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

param(
    [ValidateSet("all", "core", "extensions", "ui")][string]$Only = "all",
    [switch]$Down,
    [string]$Container,
    [string]$RepoDir = "/workspaces/streampipes"
)
. "$PSScriptRoot/streampipes-common.ps1"

try {
    Resolve-Workspace
    foreach ($service in @("core", "extensions", "ui")) {
        if ($Only -eq "all" -or $Only -eq $service) {
            Invoke-Service "stop" $service
        }
    }
    if ($Down) {
        $inspection = (Invoke-DockerChecked @("inspect", $Container) | Out-String | ConvertFrom-Json)
        $project = $inspection[0].Config.Labels.'com.docker.compose.project'
        if (-not "$project".Trim()) { throw "Workspace has no Compose project label." }
        Invoke-DockerChecked ($ComposeArgs + @("-p", "$project".Trim(), "stop"))
    }
    exit 0
} catch {
    Write-Host $_ -ForegroundColor Red
    exit 1
}
