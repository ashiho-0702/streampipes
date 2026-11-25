<!--
  ~ Licensed to the Apache Software Foundation (ASF) under one or more
  ~ contributor license agreements.  See the NOTICE file distributed with
  ~ this work for additional information regarding copyright ownership.
  ~ The ASF licenses this file to You under the Apache License, Version 2.0
  ~ (the "License"); you may not use this file except in compliance with
  ~ the License.  You may obtain a copy of the License at
  ~
  ~    http://www.apache.org/licenses/LICENSE-2.0
  ~
  ~ Unless required by applicable law or agreed to in writing, software
  ~ distributed under the License is distributed on an "AS IS" BASIS,
  ~ WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  ~ See the License for the specific language governing permissions and
  ~ limitations under the License.
  ~
  -->

# Development Containers

This setup runs third-party services in Docker Compose and provides a container
for running StreamPipes from source with VS Code, IntelliJ IDEA, or the helper
scripts in `scripts/`.

## Services

- CouchDB
- InfluxDB
- NATS
- One workspace container for Maven, Java and Node.js tooling

Core, IIoT extensions and the UI are started from source with IDE run
configurations or the helper scripts, not as prebuilt application images.

## First Start with VS Code

1. Open the repository in VS Code.
2. Run `Dev Containers: Reopen in Container`.
3. Start the app with either:
   - `Run and Debug: Full StreamPipes Dev` for core, IIoT extensions and UI
   - `Tasks: Run Task: dev: start ui` if you only need the Angular dev server

## First Start with IntelliJ IDEA

1. Open IntelliJ IDEA and select `Dev Containers` under `Remote Development`.
2. Click `New Dev Container`.
3. Select `.devcontainer/idea/devcontainer.json` as the configuration file.
4. Select `Full StreamPipes Dev` in the run configuration selector and click
   `Run` to start Core, IIoT extensions and the UI.
5. Once the services are ready, open <http://localhost:8082>. Use IDEA's `Stop`
   actions to stop the running configurations.

The shared configurations are in `.run/StreamPipes Dev Container.run.xml` and
require the Shell Script plugin. They build with Maven inside the container,
then wait for Core and IIoT extensions before starting the UI. Individual
configurations also start their required application services. Services already
running are reused; stopping a configuration stops the services it started.

These are Run configurations. Java breakpoint debugging requires a separate
Java or remote debug configuration.

The IDEA launchers synchronize source changes into a private Linux build cache
before compiling, which avoids slow class loading from Windows bind mounts.

### IDEA Troubleshooting

In IntelliJ IDEA 2025.1 and earlier, the Docker plugin may report
`client version 1.24 is too old` if your Docker Engine requires a newer API
version than the plugin supports. If you see this error, upgrade IntelliJ IDEA
to a release newer than 2025.2.

If opening an existing Dev Container does nothing, check `idea.log` for a 404
indicating that `/.jbdevcontainer/config/JetBrains/host-config.json` is missing.
IDEA generates that file per connection and it contains the local backend path
and build number, so it is neither committed nor shareable.

If IDEA uses `/root/.m2/repository` and cannot resolve Maven dependencies already
cached in `/home/vscode/.m2/repository`, move any existing root repository aside
inside the container, symlink `/root/.m2/repository` to
`/home/vscode/.m2/repository`, and reload the Maven project. This workaround may
need to be reapplied after recreating the container.

## Start and Stop with Helper Scripts

Start the Dev Container using one of the IDEs above. Run the commands on the
host from the repository root. The UI is available at <http://localhost:8082>
by default once the services are ready.

### Windows

1. Run [start-streampipes-build.cmd](scripts/start-streampipes-build.cmd)
   for the first run or after backend code changes. To reuse the existing Maven
   build outputs, run [start-streampipes.cmd](scripts/start-streampipes.cmd).
2. Run [stop-streampipes.cmd](scripts/stop-streampipes.cmd) to stop Core, IIoT
   extensions and the UI.

### macOS and Linux

Use PowerShell 7 (`pwsh`) on the host to run the same helper scripts.

1. Run `pwsh -NoProfile -File .devcontainer/scripts/start-streampipes.ps1` for
   the first run or after backend code changes. Add `-SkipBuild` to reuse the
   existing Maven build outputs.
2. Run `pwsh -NoProfile -File .devcontainer/scripts/stop-streampipes.ps1` to stop
   the application services.

### First Installation

On a fresh database, the scripts give Core a 120-second delay before initial setup. To
override the delay, set `SP_INITIAL_WAIT_BEFORE_INSTALLATION_MS` in the workspace
container's environment.

If the startup log reports that initial setup found no extensions, or if pipeline
elements are missing after startup, wait until IIoT extensions is ready and use
`Install pipeline elements` under `Configuration` in the UI.

## Services and Ports

The default URLs are:

- UI: <http://localhost:8082>
- Core: <http://localhost:8030>
- IIoT extensions: <http://localhost:8090>
- CouchDB: <http://localhost:5984>
- InfluxDB: <http://localhost:8086>
- NATS monitoring: <http://localhost:8222>

The default development stack uses NATS for pipeline transport and for
core-to-extension communication.

`SP_DEBUG` is intentionally set to `false` in the devcontainer and VS Code
launch settings. VS Code Java debugging still works through JDWP, but
StreamPipes debug mode rewrites broker hostnames to `localhost`; that breaks
NATS because the broker runs as the sibling Compose service `nats`.

## Isolated Checkouts

For a second checkout or PR worktree, copy `.devcontainer/.env.example` to
`.devcontainer/.env` and change at least `COMPOSE_PROJECT_NAME`.

If two environments should run at the same time, also change the exposed host
ports in `.devcontainer/.env`.

Example:

```bash
COMPOSE_PROJECT_NAME=streampipes-pr-123
SP_CORE_PORT=8130
SP_EXTENSIONS_IIOT_PORT=8190
SP_UI_PORT=8182
SP_COUCHDB_PORT=6984
SP_TS_STORAGE_PORT=9086
SP_NATS_PORT=5222
SP_NATS_MONITORING_PORT=9222
SP_CORE_DEBUG_PORT=5105
SP_EXTENSIONS_IIOT_DEBUG_PORT=5106
```

There is also a helper for GitHub pull requests:

```bash
tools/dev/create-pr-worktree.sh 123
```

It creates `../streampipes-pr-123`, fetches the PR into a local `pr/123`
branch, and writes an isolated `.devcontainer/.env` into that worktree.

## Reset Data

To remove only the data for the current devcontainer project:

```bash
docker compose --env-file .devcontainer/.env -f .devcontainer/docker-compose.yml down -v
```

If no `.devcontainer/.env` exists, omit `--env-file`; Compose uses the default
project name `streampipes-dev`.
