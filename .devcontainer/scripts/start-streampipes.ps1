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
    [switch]$SkipBuild,
    [switch]$Status,
    [string]$Container,
    [string]$RepoDir = "/workspaces/streampipes",
    [ValidateRange(1, 7200)][int]$TimeoutSec = 1800
)
. "$PSScriptRoot/streampipes-common.ps1"

function Wait-Service([string]$Name, [int]$Port, [string]$Path) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $state = Get-ManagedStatus $Name
        if (-not $state.Running) { throw "$Name exited during startup. $($state.Text)" }
        $http = & docker exec -u vscode $Container curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 5 "http://localhost:$Port$Path"
        if ($LASTEXITCODE -eq 0 -and "$http".Trim() -match "^[23][0-9][0-9]$|^401$|^403$") {
            Write-Host "$Name is responding (HTTP $http)."
            return
        }
        # Extensions does not provide a handler at its root.
        if ($Name -eq "extensions" -and "$http".Trim() -eq "404") {
            Write-Host "$Name is responding (HTTP 404 at root)."
            return
        }
        Start-Sleep -Seconds 2
    }
    throw "$Name did not become ready within $TimeoutSec seconds. It may still be building; use -Status or stop it."
}

try {
    Resolve-Workspace
    $services = @(
        @{ Name = "core"; Port = 8030; Path = "/streampipes-backend" },
        @{ Name = "extensions"; Port = 8090; Path = "" },
        @{ Name = "ui"; Port = 8082; Path = "" }
    )
    $selected = @($services | Where-Object { $Only -eq "all" -or $Only -eq $_.Name })
    if ($Status) {
        foreach ($service in $selected) {
            Write-Host (Get-ManagedStatus $service.Name).Text
        }
        exit 0
    }
    # Finish Maven builds before Core's first-installation timer starts.
    if (-not $SkipBuild) {
        foreach ($service in $selected) {
            if ($service.Name -ne "ui") { Invoke-Service "prepare" $service.Name }
        }
    }
    # Extensions registers with Core before opening its HTTP port. Launch both
    # before waiting so neither readiness check delays the other service.
    foreach ($service in $selected) {
        Invoke-Service "start" $service.Name "skip"
    }
    foreach ($service in $selected) {
        Wait-Service $service.Name $service.Port $service.Path
        $mapping = Invoke-DockerChecked @("port", $Container, "$($service.Port)/tcp")
        Write-Host "$($service.Name) host port mapping: $mapping"
    }
    if ($Only -eq "all" -or $Only -eq "core") {
        Invoke-Service "installation-status" "core"
    }
    exit 0
} catch {
    Write-Host $_ -ForegroundColor Red
    exit 1
}
