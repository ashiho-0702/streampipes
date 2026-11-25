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
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/../.." && pwd)"
cd "$repo_dir"
case "${1:-all}" in
  core) services=(core) ;;
  extensions) services=(core extensions) ;;
  ui|all) services=(core extensions ui) ;;
  *) echo "Expected core, extensions, ui or all" >&2; exit 2 ;;
esac
state_dir="/tmp/streampipes-dev-$(id -u)-$(printf %s "$repo_dir" | sha256sum | cut -c1-16)"
mkdir -p "$state_dir"
export SP_DEV_BUILD_ROOT="$state_dir/build-workspace"
owned=()
tail_pid=
cleanup() {
  local service
  [[ -z "$tail_pid" ]] || kill "$tail_pid" 2>/dev/null || true
  for ((i=${#owned[@]}-1; i>=0; i--)); do
    service=${owned[i]}
    bash "$script_dir/manage-services.sh" stop "$service" || true
  done
}
trap cleanup EXIT
trap 'exit 143' TERM INT
exec 9>"$state_dir/idea-launch.lock"
flock -x 9
# Dependencies must be running before compilation and service launch.
for endpoint in "http://${SP_COUCHDB_HOST:-couchdb}:${SP_COUCHDB_PORT:-5984}/_up" "http://${SP_NATS_HOST:-nats}:8222/healthz" "http://${SP_INFLUX_HOST:-influxdb}:${SP_INFLUX_PORT:-8086}/health"; do
  if ! curl -fsS --connect-timeout 3 --max-time 5 "$endpoint" >/dev/null; then
    echo "Development dependency unavailable: $endpoint. Start the Dev Container Compose services." >&2
    exit 1
  fi
done
for service in "${services[@]}"; do
  [[ "$service" == ui ]] || bash "$script_dir/manage-services.sh" prepare "$service"
done
for service in "${services[@]}"; do
  if bash "$script_dir/manage-services.sh" status "$service" >/dev/null; then
    echo "Reusing running $service"
  else
    code=$?
    [[ "$code" == 3 ]] || exit "$code"
    owned+=("$service")
    bash "$script_dir/manage-services.sh" start "$service" skip
  fi
  case "$service" in
    core) url=http://127.0.0.1:8030/streampipes-backend/api/v2/setup/configured ;;
    extensions) url=http://127.0.0.1:8090/ ;;
    ui) url=http://127.0.0.1:8082/ ;;
  esac
  ready=false
  for ((attempt=0; attempt<900; attempt++)); do
    if ! bash "$script_dir/manage-services.sh" status "$service" >/dev/null; then
      tail -60 "$state_dir/$service.log" >&2
      exit 1
    fi
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$url" || true)
    if [[ "$code" =~ ^[23][0-9][0-9]$ || ( "$service" == extensions && "$code" == 404 ) ]]; then ready=true; break; fi
    sleep 2
  done
  if [[ "$ready" != true ]]; then echo "$service readiness timed out" >&2; exit 1; fi
  echo "$service ready"
done
flock -u 9
exec 9>&-
logs=()
for service in "${services[@]}"; do
  [[ ! -f "$state_dir/$service.log" ]] || logs+=("$state_dir/$service.log")
done
if (( ${#logs[@]} )); then tail -n 10 -F "${logs[@]}" & tail_pid=$!; fi
echo "Services ready. Open http://localhost:8082 when UI is selected. Stop this run configuration to stop services it started."
while sleep 3; do
  for service in "${services[@]}"; do
    bash "$script_dir/manage-services.sh" status "$service" >/dev/null || exit 1
  done
done

