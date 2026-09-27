#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/functions.sh"

init_script_paths "${BASH_SOURCE[0]}"
resolve_compose_cmd || exit 1
build_compose_files

MySQL_VERSION=$(grep -o 'mysql:[0-9]\+\.[0-9]\+' "${PROJECT_ROOT_DIR}/docker-compose.yml" | cut -d':' -f2 || echo "8.0")
echo_info "Using MySQL version ${MySQL_VERSION} from docker-compose.yml"

echo "Starting core services using compose files: ${COMPOSE_FILES[*]}"
compose down || true
echo_info "Pulling core service images from Docker Hub..."
compose pull cafedebugdb rustfs rustfs-init
compose up -d cafedebugdb rustfs rustfs-init
echo_ok "Core services started successfully"

echo_info "Waiting for MySQL to complete initialization (this may take 1-2 minutes)..."

MAX_WAIT=180
WAITED=0
echo "Checking MySQL readiness..."

MYSQL_ROOT_PASSWORD="$(get_env_value "MYSQL_ROOT_PASSWORD" || echo "root")"
MYSQL_AUTH="-uroot -p${MYSQL_ROOT_PASSWORD}"
echo_info "Using MySQL root password from .env"

while true; do
    if compose exec -T cafedebugdb mysql ${MYSQL_AUTH} -e "SELECT 1" >/dev/null 2>&1; then
        echo_ok "MySQL is ready and accessible."
        break
    fi

    if docker logs cafedebugdb 2>&1 | tail -10 | grep -q "ready for connections.*port: 3306"; then
        echo_info "MySQL reports ready, but connection test failed. Waiting a bit more..."
        sleep 5
    else
        echo_info "MySQL still initializing... (${WAITED}/${MAX_WAIT} seconds)"
    fi

    sleep 5
    WAITED=$((WAITED + 5))
    if [ "${WAITED}" -ge "${MAX_WAIT}" ]; then
        echo_error "Timed out waiting for MySQL to become ready. Logs:"
        docker logs cafedebugdb --tail=50
        echo_error "Attempted MySQL auth: ${MYSQL_AUTH}"
        exit 1
    fi
done

echo_info "MySQL is ready. Waiting additional 10 seconds for full stabilization..."
sleep 10

# Use docker compose exec (not docker exec with /usr/bin/mysql) so Git Bash on
# Windows does not rewrite container paths to C:/Program Files/Git/...
run_mysql_cmd() {
    compose exec -T cafedebugdb mysql ${MYSQL_AUTH} -e "$1"
}

run_mysql_stdin() {
    local target_db="${1:-}"
    compose exec -T cafedebugdb mysql ${MYSQL_AUTH} "${target_db}"
}

echo_info "Ensuring target database exists (cafedebug-mysql-local)..."
CREATE_DB_SQL='CREATE DATABASE IF NOT EXISTS `cafedebug-mysql-local` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;'
run_mysql_cmd "${CREATE_DB_SQL}"
echo_ok "Database ensured."

SQL_CREATE_PATH="${PROJECT_ROOT_DIR}/database/mysql/cafedebugdb/cafedebug-mysql-create-table.sql"
SQL_INSERT_PATH="${PROJECT_ROOT_DIR}/database/mysql/cafedebugdb/cafedebug-mysql-insert.sql"

echo_info "Applying SQL create script..."
if [ -f "${SQL_CREATE_PATH}" ]; then
    cat "${SQL_CREATE_PATH}" | run_mysql_stdin cafedebug-mysql-local
    echo_ok "Create script applied successfully"
else
    echo_error "Create script not found at ${SQL_CREATE_PATH}"
    exit 1
fi

echo_info "Applying SQL insert script..."
if [ -f "${SQL_INSERT_PATH}" ]; then
    cat "${SQL_INSERT_PATH}" | run_mysql_stdin cafedebug-mysql-local
    echo_ok "Insert script applied successfully"
else
    echo_error "Insert script not found at ${SQL_INSERT_PATH}"
    exit 1
fi

DEFAULT_BUCKETS=("cafedebug-uploads" "cafedebug-images")
echo_info "Ensuring RustFS buckets..."
RUSTFS_BUCKETS_SCRIPT="${PROJECT_ROOT_DIR}/scripts/create-rustfs-buckets.sh"
if [ -f "${RUSTFS_BUCKETS_SCRIPT}" ]; then
    if [ -n "${RUSTFS_BUCKETS:-}" ]; then
        IFS=',' read -r -a _buckets <<< "${RUSTFS_BUCKETS}"
        bash "${RUSTFS_BUCKETS_SCRIPT}" "${_buckets[@]}"
    else
        bash "${RUSTFS_BUCKETS_SCRIPT}" "${DEFAULT_BUCKETS[@]}"
    fi
else
    echo_warning "Warning: create-rustfs-buckets.sh not found at ${RUSTFS_BUCKETS_SCRIPT}; skipping bucket creation"
fi

API_ENABLED="$(get_env_value "CAFEDEBUG_API_ENABLED" || echo "true")"
API_ENABLED_LOWER="$(printf '%s' "${API_ENABLED}" | tr '[:upper:]' '[:lower:]')"

if [ "${API_ENABLED_LOWER}" = "false" ]; then
    echo_info "CAFEDEBUG_API_ENABLED=false — skipping API startup."
    exit 0
fi

echo_info "Starting CafeDebug API after DB seed..."
echo_info "Pulling CafeDebug API image from Docker Hub..."
compose pull cafedebug-api
compose up -d cafedebug-api

API_PORT="$(get_env_value "CAFEDEBUG_API_PORT" || echo "8080")"
echo_info "Waiting for cafedebug-backend.api API on port ${API_PORT}..."
API_MAX_WAIT=120
API_WAITED=0
until curl -fsS --max-time 3 "http://localhost:${API_PORT}/health" >/dev/null 2>&1; do
    sleep 5
    API_WAITED=$((API_WAITED + 5))
    if [ "${API_WAITED}" -ge "${API_MAX_WAIT}" ]; then
        echo_warning "CafeDebug API did not become healthy within ${API_MAX_WAIT}s — check logs: docker logs cafedebug-backend.api"
        break
    fi
    echo_info "API not ready yet... (${API_WAITED}/${API_MAX_WAIT}s)"
done
if curl -fsS --max-time 3 "http://localhost:${API_PORT}/health" >/dev/null 2>&1; then
    echo_ok "CafeDebug API is healthy at http://localhost:${API_PORT}"
fi
