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
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_dir/streampipes-service-core"
export SP_INITIAL_SERVICE_USER_SECRET="${SP_INITIAL_SERVICE_USER_SECRET:-streampipes-development-only-service-secret}"
export SP_CLIENT_SECRET="${SP_CLIENT_SECRET:-streampipes-development-only-service-secret}"
# Allow development extensions time to register during initial setup only.
export SP_INITIAL_WAIT_BEFORE_INSTALLATION_MS="${SP_INITIAL_WAIT_BEFORE_INSTALLATION_MS:-120000}"
exec bash "$repo_dir/.devcontainer/scripts/run-java.sh" streampipes-service-core org.apache.streampipes.service.core.StreamPipesCoreApplication
