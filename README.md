 _                    _   ____             _             _
| |    ___   ___ __ _| | |  _ \  _____   __| |_ __ _  ___| | __
| |   / _ \ / __/ _` | | | | | |/ _ \ \ / /| __/ _` |/ __| |/ /
| |__| (_) | (_| (_| | | | |_| |  __/\ V /| || (_| | (__|   <
|_____\___/ \___\__,_|_| |____/ \___| \_/ \__\__,_|\___|_|\_\

The Local devstack is a project is for automation, allowing you to run various projects in localy containers. You can configure any APIs and databases using shell scripts that run within the containers.

## Project information 📑

- 📂 **Applications** - each application should have a folder and contain its own separate informations

- 📂 **Databases** - database scripts for create tables and insert

- 📂 **Scripts** - applications scripts shell to configure database and APis in container, called docker-compose file

- 🐋 **Docker-compose** - to configure services, containers and ports of database 


## Setup 🔧
To configure the database in a local environment, follow these steps. Note that for each project script you run, you must grant permission using chmod.

- Before running the project, configure access permission for this script. Enter the command in terminal (WSL, PowerShell, CMD, etc)

```bash
chmod +x scripts/run.sh
chmod +x devstack
```

## Container Management 🐳

### Starting Containers
To start all containers and set up the environment:

```bash
./devstack -up
```

This command will:
- Start all Docker containers defined in the docker-compose.yml
- Execute database setup scripts
- Configure APIs and services

### Stopping Containers  
To stop all containers and clean up the environment:

```bash
./devstack -d
```

This command will:
- Stop all running containers
- Remove containers and associated resources
- Clean up the environment

### Environment Status
To inspect current container/service status:

```bash
./devstack status
```

This command will:
- Show Docker daemon availability
- Show compose service status
- Run quick MySQL and MinIO checks

### Environment Doctor
To run a full diagnostic suite:

```bash
./devstack doctor
```

This command will:
- Validate Docker and Compose availability
- Validate compose configuration
- Verify core services are running
- Execute MySQL and MinIO health checks

### Devstack Version
To show current `devstack` version from `.env`:

```bash
./devstack version
```

This command reads one of these keys from `.env`:
- `DEVSTACK_VERSION`
- `LOCAL_DEVSTACK_VERSION`
- `VERSION`

## Use `devstack` Without `./`

The repository path is different for each user. Run the commands below from inside the repo root, so the current path is captured automatically.

### zsh (macOS/Linux)

```bash
echo "alias devstack=\"$(pwd)/devstack\"" >> ~/.zshrc
source ~/.zshrc
```

### bash (Linux/macOS)

```bash
echo "alias devstack=\"$(pwd)/devstack\"" >> ~/.bashrc
source ~/.bashrc
```

If your system uses `~/.bash_profile` instead of `~/.bashrc`, add the same alias there.

### PowerShell (Windows)

This requires `bash` available in PowerShell (Git Bash or WSL in PATH).

```powershell
$repo = (Get-Location).Path
if (!(Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force | Out-Null }
Add-Content $PROFILE "`nfunction devstack { bash '$repo/devstack' @args }"
. $PROFILE
```

### Verify

```bash
devstack -h
```


For generate users data

```bash
  chmod +x data-generator.sh
```

- To generate users data

```bash
 ./data-generator.sh
```

## Tests and Run 🧪
For test you connection database in DBaver following this steps:

![alt text](dbeaver.png)

- Server Host: localhost
- Port: 3307  (the door mapped in your docker-compose.yml)
- Username: root (the door mapped in your docker-compose.yml)
- Password: root (the door mapped in your docker-compose.yml)
