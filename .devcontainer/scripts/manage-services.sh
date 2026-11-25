#!/usr/bin/env bash
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail

action="${1:?Expected prepare, start, stop, status, installation-status or worker}"
service="${2:?Expected core, extensions or ui}"
build="${3:-skip}"
case "$service" in
  core) port=8030 ;;
  extensions) port=8090 ;;
  ui) port=8082 ;;
  *) echo "Unknown service: $service" >&2; exit 2 ;;
esac
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(dirname "$(dirname "$script_dir")")"
state_dir="/tmp/streampipes-dev-$(id -u)-$(printf %s "$repo_dir" | sha256sum | cut -c1-16)"
mkdir -p "$state_dir"
state_file="$state_dir/$service.pid"
log_file="$state_dir/$service.log"

# Recognize servers started before PID tracking was introduced. Match both
# the working directory and argument boundaries, never a global command regex.
find_existing_processes() {
  local entry process_pid cwd executable argument matched
  local -a arguments
  for entry in /proc/[0-9]*/cmdline; do
    process_pid="${entry#/proc/}"
    process_pid="${process_pid%/cmdline}"
    [[ "$(stat -c %u "/proc/$process_pid" 2>/dev/null)" == "$(id -u)" ]] || continue
    cwd="$(readlink "/proc/$process_pid/cwd" 2>/dev/null)" || continue
    [[ "$cwd" == "$repo_dir" || "$cwd" == "$repo_dir/"* ]] || continue
    mapfile -d '' -t arguments < "$entry" 2>/dev/null || continue
    [[ "${#arguments[@]}" -gt 0 ]] || continue
    executable="${arguments[0]##*/}"
    matched=false
    if [[ "$service" == ui && "$cwd" == "$repo_dir/ui" ]]; then
      if [[ "${arguments[0]}" == "ng serve"* || "${arguments[0]}" == "npm exec ng serve"* ]]; then
        matched=true
      elif [[ "$executable" == node || "$executable" == nodejs ]]; then
        for argument in "${arguments[@]:1}"; do
          [[ "$argument" == serve ]] && matched=true
        done
        [[ "${arguments[1]:-}" == */ng || "${arguments[1]:-}" == */ng.js ]] || matched=false
      fi
    elif [[ "$executable" == java ]]; then
      for argument in "${arguments[@]:1}"; do
        if [[ "$service" == core && "$argument" == org.apache.streampipes.service.core.StreamPipesCoreApplication ]] ||
           [[ "$service" == extensions && "$argument" == org.apache.streampipes.extensions.all.iiot.AllExtensionsIIoTInit ]]; then
          matched=true
        fi
      done
    fi
    if [[ "$matched" == true ]]; then
      printf '%s\n' "$process_pid"
    fi
  done
}

stop_existing_processes() {
  local process_pid stamp current remaining
  local -a process_ids
  local -A starts=()
  mapfile -t process_ids < <(find_existing_processes)
  if [[ "${#process_ids[@]}" -eq 0 ]]; then
    if [[ -n "$(ss -H -ltn "sport = :$port")" ]]; then
      echo "Port $port is occupied by an unidentified process; $service was not stopped." >&2
      return 1
    fi
    echo "$service is already stopped"
    return
  fi
  for process_pid in "${process_ids[@]}"; do
    stamp="$(awk '{print $22}' "/proc/$process_pid/stat" 2>/dev/null)" || continue
    starts[$process_pid]="$stamp"
    echo "Stopping existing $service process $process_pid"
    kill -TERM "$process_pid" 2>/dev/null || true
  done
  for ((i=0; i<30; i++)); do
    remaining=false
    for process_pid in "${!starts[@]}"; do
      current="$(awk '{print $22}' "/proc/$process_pid/stat" 2>/dev/null)" || continue
      if [[ "$current" == "${starts[$process_pid]}" && "$(ps -o stat= -p "$process_pid")" != Z* ]]; then
        remaining=true
      fi
    done
    [[ "$remaining" == true ]] || break
    sleep 1
  done
  for process_pid in "${!starts[@]}"; do
    current="$(awk '{print $22}' "/proc/$process_pid/stat" 2>/dev/null)" || continue
    if [[ "$current" == "${starts[$process_pid]}" && "$(ps -o stat= -p "$process_pid")" != Z* ]]; then
      kill -KILL "$process_pid"
    fi
  done
  if [[ -n "$(ss -H -ltn "sport = :$port")" ]]; then
    echo "Port $port is still occupied; the remaining owner could not be safely identified." >&2
    return 1
  fi
  echo "$service stopped"
}

# PID plus kernel start time prevents signalling a recycled PID.
is_running() {
  [[ -f "$state_file" ]] || return 1
  read -r service_pid start_time < "$state_file"
  [[ "$service_pid" =~ ^[0-9]+$ && "$start_time" =~ ^[0-9]+$ ]] || return 1
  [[ -r "/proc/$service_pid/stat" ]] || return 1
  [[ "$(awk '{print $22}' "/proc/$service_pid/stat")" == "$start_time" ]] || return 1
  [[ "$(ps -o pgid= -p "$service_pid" | tr -d ' ')" == "$service_pid" ]] || return 1
  [[ "$(ps -o stat= -p "$service_pid")" != Z* ]]
}

build_backend() {
  [[ "$service" != ui ]] || return 0
  (
    cd "$repo_dir"
    exec 8>"$state_dir/build.lock"
    flock -x 8
    if [[ -n "${SP_DEV_BUILD_ROOT:-}" ]]; then
      # Only the private build cache is synchronized and pruned.
      [[ "$SP_DEV_BUILD_ROOT" == "$state_dir/build-workspace" ]] || exit 2
      [[ ! -L "$SP_DEV_BUILD_ROOT" ]] || exit 2
      mkdir -p "$SP_DEV_BUILD_ROOT"
      rsync -a --delete --exclude=.git/ --exclude=.idea/ --exclude=node_modules/ \
        --exclude=target/ --exclude=dist/ "$repo_dir/" "$SP_DEV_BUILD_ROOT/"
      cd "$SP_DEV_BUILD_ROOT"
    fi
    # Interactive startup builds artifacts; repository-wide validation runs in CI.
    options=(-DskipTests -Drat.skip=true -Dmaven.javadoc.skip=true -Dsbom.skip=true -Dassembly.skipAssembly=true)
    if [[ "$service" == core ]]; then
      mvn -B -pl streampipes-service-core -am "${options[@]}" install
    else
      mvn -B -pl streampipes-maven-plugin -am "${options[@]}" install
      mvn -B -pl streampipes-extensions/streampipes-extensions-all-iiot -am "${options[@]}" install
    fi
  )
}

if [[ "$action" == worker ]]; then
  printf '%s %s\n' "$$" "$(awk '{print $22}' /proc/$$/stat)" > "$state_file"
  # Keep the group leader alive until the build/server child exits.
  trap 'exit 143' TERM INT
  (
    cd "$repo_dir"
    if [[ "$build" == build && "$service" != ui ]]; then
      build_backend
    fi
    exec bash "$script_dir/run-$service.sh"
  ) &
  wait "$!"
  exit $?
fi

# Serialize starts/stops so a second click cannot race the PID-file creation.
exec 9>"$state_dir/$service.control"
flock -x 9
case "$action" in
  prepare)
    if is_running || [[ -n "$(find_existing_processes)" ]]; then
      echo "$service is already running; skipping its build"
    else
      build_backend
    fi
    ;;
  installation-status)
    # This reports this launch's log, not the current database contents.
    if [[ -f "$log_file" ]] && grep -q 'Found 0 extensions which we will install' "$log_file"; then
      echo "WARNING: Initial setup found no extensions. After Extensions is ready, use Configuration > Install pipeline elements."
    elif [[ -f "$log_file" ]] && grep -Eq 'Found [1-9][0-9]* extensions which we will install' "$log_file"; then
      echo "Initial setup discovered extensions; check the UI for installation completion."
    else
      echo "No initial extension discovery result in this launch's log yet (setup may be pending or already configured). If elements are missing, use Configuration > Install pipeline elements."
    fi
    ;;
  status)
    if is_running; then
      echo "$service running (PID $service_pid); log: $log_file"
    elif [[ -n "$(find_existing_processes)" ]]; then
      echo "$service running without a PID record (PIDs: $(find_existing_processes | tr '\n' ' '))"
    else
      echo "$service stopped; log: $log_file"
      exit 3
    fi
    ;;
  start)
    if is_running || [[ -n "$(find_existing_processes)" ]]; then
      echo "$service already starting/running"
      exit 0
    fi
    command -v ss >/dev/null
    if [[ -n "$(ss -H -ltn "sport = :$port")" ]]; then
      echo "Port $port is occupied. Stop its owner before starting $service." >&2
      exit 1
    fi
    rm -f -- "$state_file"
    nohup setsid bash "$script_dir/manage-services.sh" worker "$service" "$build" \
      > "$log_file" 2>&1 < /dev/null 9>&- &
    for ((i=0; i<50; i++)); do
      if is_running; then
        echo "$service started (PID $service_pid); log: $log_file"
        exit 0
      fi
      sleep 0.1
    done
    tail -n 30 "$log_file" >&2
    exit 1
    ;;
  stop)
    if ! is_running; then
      stop_existing_processes
      exit 0
    fi
    group_id="$service_pid"
    kill -TERM -- "-$group_id"
    for ((i=0; i<30; i++)); do
      if ! ps -eo pgid=,stat= | awk -v group="$group_id" '$1 == group && $2 !~ /^Z/ {found=1} END {exit !found}'; then
        rm -f -- "$state_file"
        echo "$service stopped"
        exit 0
      fi
      sleep 1
    done
    kill -KILL -- "-$group_id"
    rm -f -- "$state_file"
    echo "$service forcibly stopped after 30 seconds"
    ;;
  *) echo "Unknown action: $action" >&2; exit 2 ;;
esac

