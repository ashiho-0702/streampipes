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

$ErrorActionPreference = "Stop"
$DevContainerDir = Split-Path -Parent $PSScriptRoot
$ComposeFile = Join-Path $DevContainerDir "docker-compose.yml"
$ComposeArgs = @("compose", "-f", $ComposeFile)
$EnvFile = Join-Path $DevContainerDir ".env"
if (Test-Path -LiteralPath $EnvFile) { $ComposeArgs += @("--env-file", $EnvFile) }

function Invoke-DockerChecked([string[]]$Arguments) {
    & docker @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Docker command failed (exit $LASTEXITCODE)." }
}

function Resolve-Workspace {
    if (-not $Container) {
        $ids = @(Invoke-DockerChecked ($ComposeArgs + @("ps", "-q", "workspace")))
        if ($ids.Count -ne 1 -or -not $ids[0]) {
            throw "Start the Dev Container first, or specify -Container."
        }
        $script:Container = "$($ids[0])".Trim()
    }
    $state = Invoke-DockerChecked @("inspect", "-f", "{{.State.Running}}", $Container)
    if ("$state".Trim() -ne "true") { throw "Workspace container is not running." }
}

function Invoke-Service([string]$Action, [string]$Name, [string]$Build = "skip") {
    Invoke-DockerChecked @("exec", "-u", "vscode", $Container, "bash",
        "$RepoDir/.devcontainer/scripts/manage-services.sh", $Action, $Name, $Build)
}

function Get-ManagedStatus([string]$Name) {
    $output = & docker exec -u vscode $Container bash "$RepoDir/.devcontainer/scripts/manage-services.sh" status $Name
    $code = $LASTEXITCODE
    if ($code -ne 0 -and $code -ne 3) { throw "Cannot read $Name status (exit $code)." }
    return @{ Running = ($code -eq 0); Text = "$output" }
}

