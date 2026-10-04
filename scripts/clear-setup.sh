#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/functions.sh"

init_script_paths "${BASH_SOURCE[0]}"
resolve_compose_cmd || exit 1
build_compose_files

if question "Remove this devstack's containers, volumes, and images? This deletes local data."; then
    echo_warning "Removing this devstack's containers, volumes, and images..."
    compose down --volumes --rmi all --remove-orphans
    echo_ok "Devstack containers, volumes, and images removed."
    echo_info "Only resources managed by this docker-compose.yml were removed."
    echo_info "The next './devstack -up' will pull the current service images from Docker Hub."
    echo "Done. Run './devstack -up' when you want to start again."
    exit 0
fi

echo_info "Teardown cancelled. No changes made."
