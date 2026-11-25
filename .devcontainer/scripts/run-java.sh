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
module="${1:?Expected module path}"
main_class="${2:?Expected main class}"
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${SP_DEV_BUILD_ROOT:-$repo_dir}/$module"
runtime_dir=$(mktemp -d /tmp/streampipes-java.XXXXXX)
child=
cleanup() {
  if [[ -n "$child" ]]; then
    kill -TERM "$child" 2>/dev/null || true
    wait "$child" 2>/dev/null || true
  fi
  rm -rf -- "$runtime_dir"
}
trap cleanup EXIT
trap 'exit 143' TERM INT
mvn -B dependency:build-classpath "-Dmdep.outputFile=$runtime_dir/classpath" -Dmdep.regenerateFile=true -DincludeScope=runtime
# Keep runtime classes on Linux to avoid Windows bind-mount metadata lookups.
cp -a target/classes "$runtime_dir/classes"
classpath="$runtime_dir/classes:$(cat "$runtime_dir/classpath")"
java -cp "$classpath" "$main_class" &
child=$!
wait "$child"

