#!/bin/bash
set -euo pipefail

# Script to manage bootstrap, diagnostics, and teardown of the environment.
# Usage:
#   ./scripts/run.sh -up
#   ./scripts/run.sh -d
#   ./scripts/run.sh status
#   ./scripts/run.sh doctor
#   ./scripts/run.sh version

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT_DIR}/docker-compose.yml"
ENV_FILE="${PROJECT_ROOT_DIR}/.env"
COMPOSE_CMD=()

source "${SCRIPT_DIR}/functions.sh"

show_help() {
    local usage_cmd="${RUN_ALIAS:-$0}"
    echo_info "Usage: ${usage_cmd} [OPTION]"
    echo ""
    echo "Options:"
    echo "  -up               Execute environment bootstrap (cafedebug-setup.sh)"
    echo "  -d                Execute environment teardown (clear-setup.sh)"
    echo "  status            Show container and service status"
    echo "  doctor            Run full environment diagnostics"
    echo "  version           Show devstack version from .env"
    echo "  -v, --version     Show devstack version from .env"
    echo "  -h, --help        Show this help"
    echo ""
}

get_env_value() {
    local key="$1"
    local line value

    if [ ! -f "${ENV_FILE}" ]; then
        return 1
    fi

    line="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "${ENV_FILE}" | tail -n 1 || true)"
    if [ -z "${line}" ]; then
        return 1
    fi

    value="${line#*=}"
    value="$(printf '%s' "${value}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"

    if [ -z "${value}" ]; then
        return 1
    fi

    printf '%s\n' "${value}"
}

resolve_compose_cmd() {
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD=(docker compose)
        return 0
    fi

    if command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_CMD=(docker-compose)
        return 0
    fi

    echo_error "Error: Docker Compose is not available (docker compose / docker-compose)."
    return 1
}

compose() {
    "${COMPOSE_CMD[@]}" -f "${COMPOSE_FILE}" "$@"
}

bootstrap() {
    echo_info "Executing environment bootstrap..."
    if [ -f "${SCRIPT_DIR}/cafedebug-setup.sh" ]; then
        bash "${SCRIPT_DIR}/cafedebug-setup.sh"
    else
        echo_error "Error: Script cafedebug-setup.sh not found in ${SCRIPT_DIR}"
        exit 1
    fi
}

teardown() {
    echo_info "Executing environment teardown..."
    if [ -f "${SCRIPT_DIR}/clear-setup.sh" ]; then
        bash "${SCRIPT_DIR}/clear-setup.sh"
    else
        echo_error "Error: Script clear-setup.sh not found in ${SCRIPT_DIR}"
        exit 1
    fi
}

is_service_running() {
    local service="$1"
    local cid status

    cid="$(compose ps -q "${service}" 2>/dev/null | head -n 1 || true)"
    if [ -z "${cid}" ]; then
        return 1
    fi

    status="$(docker inspect -f '{{.State.Status}}' "${cid}" 2>/dev/null || true)"
    [ "${status}" = "running" ]
}

# Report long-running services as running; rustfs-init is a one-shot job (exited 0 = OK).
check_core_service() {
    local service="$1"
    local strict="${2:-0}"
    local cid status exit_code

    cid="$(compose ps -aq "${service}" 2>/dev/null | head -n 1 || true)"
    if [ -z "${cid}" ]; then
        if [ "${strict}" -eq 1 ]; then
            echo_error "${service}: not started"
            return 1
        fi
        echo_warning "${service}: not running"
        return 1
    fi

    status="$(docker inspect -f '{{.State.Status}}' "${cid}" 2>/dev/null || true)"

    if [ "${status}" = "running" ]; then
        echo_ok "${service}: running"
        return 0
    fi

    if [ "${service}" = "rustfs-init" ] && [ "${status}" = "exited" ]; then
        exit_code="$(docker inspect -f '{{.State.ExitCode}}' "${cid}" 2>/dev/null || echo 1)"
        if [ "${exit_code}" = "0" ]; then
            echo_ok "${service}: completed (one-shot)"
            return 0
        fi
        if [ "${strict}" -eq 1 ]; then
            echo_error "${service}: exited with code ${exit_code}"
            return 1
        fi
        echo_warning "${service}: exited with code ${exit_code}"
        return 1
    fi

    if [ "${strict}" -eq 1 ]; then
        echo_error "${service}: ${status}"
        return 1
    fi
    echo_warning "${service}: ${status}"
    return 1
}

detect_mysql_auth() {
    local mysql_root_password
    mysql_root_password="$(get_env_value "MYSQL_ROOT_PASSWORD" || echo "root")"
    echo "-uroot -p${mysql_root_password}"
}

status_cmd() {
    local mysql_auth mysql_cid

    resolve_compose_cmd || exit 1

    title "Environment Status"

    subtitle "Docker daemon"
    if docker info >/dev/null 2>&1; then
        echo_ok "Docker daemon is running."
    else
        echo_error "Docker daemon is not running."
        return 1
    fi

    subtitle "Compose services"
    compose ps || true

    subtitle "Core services"
    for service in cafedebugdb rustfs rustfs-init cafedebug-api; do
        check_core_service "${service}" 0 || true
    done

    subtitle "Quick checks"
    if curl -fsS --max-time 3 "http://localhost:9000/health" >/dev/null 2>&1; then
        echo_ok "RustFS health endpoint is reachable."
    else
        echo_warning "RustFS health endpoint is not reachable (http://localhost:9000/health)."
    fi

    local api_port
    api_port="$(get_env_value "CAFEDEBUG_API_PORT" || echo "8080")"
    if curl -fsS --max-time 3 "http://localhost:${api_port}/health" >/dev/null 2>&1; then
        echo_ok "CafeDebug API health endpoint is reachable (http://localhost:${api_port}/health)."
    else
        echo_warning "CafeDebug API health endpoint is not reachable (http://localhost:${api_port}/health)."
    fi

    if is_service_running "cafedebugdb"; then
        mysql_auth="$(detect_mysql_auth)"
        mysql_cid="$(compose ps -q cafedebugdb | head -n 1)"
        if docker exec "${mysql_cid}" mysql ${mysql_auth} -e "SELECT 1" >/dev/null 2>&1; then
            echo_ok "MySQL query check passed."
        else
            echo_warning "MySQL query check failed."
        fi
    else
        echo_warning "Skipping MySQL query check because cafedebugdb is not running."
    fi
}

doctor_cmd() {
    local failed=0 mysql_auth mysql_cid

    resolve_compose_cmd || exit 1

    title "Environment Doctor"

    subtitle "Pre-flight"
    if command -v docker >/dev/null 2>&1; then
        echo_ok "docker command found."
    else
        echo_error "docker command not found."
        failed=1
    fi

    if docker info >/dev/null 2>&1; then
        echo_ok "Docker daemon is running."
    else
        echo_error "Docker daemon is not running."
        failed=1
    fi

    if compose version >/dev/null 2>&1; then
        echo_ok "Docker Compose is available."
    else
        echo_error "Docker Compose command failed."
        failed=1
    fi

    subtitle "Compose file integrity"
    if compose config >/dev/null 2>&1; then
        echo_ok "docker-compose.yml parsed successfully."
    else
        echo_error "docker-compose.yml has parsing/validation issues."
        failed=1
    fi

    subtitle "Service runtime"
    for service in cafedebugdb rustfs rustfs-init cafedebug-api; do
        if ! check_core_service "${service}" 1; then
            failed=1
        fi
    done

    subtitle "Service health checks"
    if is_service_running "cafedebugdb"; then
        mysql_auth="$(detect_mysql_auth)"
        mysql_cid="$(compose ps -q cafedebugdb | head -n 1)"
        if docker exec "${mysql_cid}" mysql ${mysql_auth} -e "SELECT 1" >/dev/null 2>&1; then
            echo_ok "MySQL connectivity check passed."
        else
            echo_error "MySQL connectivity check failed."
            failed=1
        fi
    else
        echo_error "MySQL connectivity check skipped because cafedebugdb is not running."
        failed=1
    fi

    if curl -fsS --max-time 5 "http://localhost:9000/health" >/dev/null 2>&1; then
        echo_ok "RustFS readiness check passed."
    else
        echo_error "RustFS readiness check failed (http://localhost:9000/health)."
        failed=1
    fi

    local api_port
    api_port="$(get_env_value "CAFEDEBUG_API_PORT" || echo "8080")"
    if curl -fsS --max-time 5 "http://localhost:${api_port}/health" >/dev/null 2>&1; then
        echo_ok "CafeDebug API readiness check passed (http://localhost:${api_port}/health)."
    else
        echo_error "CafeDebug API readiness check failed (http://localhost:${api_port}/health)."
        failed=1
    fi

    subtitle "Doctor result"
    if [ "${failed}" -eq 0 ]; then
        echo_ok "All checks passed."
        return 0
    fi

    echo_error "One or more checks failed."
    return 1
}

version_cmd() {
    local key version
    local keys=("DEVSTACK_VERSION" "LOCAL_DEVSTACK_VERSION" "VERSION")

    for key in "${keys[@]}"; do
        if version="$(get_env_value "${key}")"; then
            echo_info "devstack version: ${version}"
            echo_info "source: .env (${key})"
            return 0
        fi
    done

    echo_error "Version not found in ${ENV_FILE}."
    echo_info "Add one of: DEVSTACK_VERSION=<value>, LOCAL_DEVSTACK_VERSION=<value>, VERSION=<value>"
    return 1
}

main() {
    local option="${1:-}"

    case "${option}" in
        -up)
            bootstrap
            ;;
        -d)
            teardown
            ;;
        status|-status|-s)
            status_cmd
            ;;
        doctor|-doctor)
            doctor_cmd
            ;;
        version|-version|-v|--version)
            version_cmd
            ;;
        -h|--help)
            show_help
            ;;
        "")
            echo_error "Error: No option provided."
            show_help
            exit 1
            ;;
        *)
            echo_error "Error: Option '${option}' not recognized."
            show_help
            exit 1
            ;;
    esac
}

main "$@"
