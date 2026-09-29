#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/functions.sh"

init_script_paths "${BASH_SOURCE[0]}"
resolve_compose_cmd || exit 1
build_compose_files

echo_info "Starting RustFS (detached)..."
compose up -d rustfs

echo "Waiting for RustFS to be ready..."
until curl -fsS http://localhost:9000/health >/dev/null 2>&1; do
    sleep 2
done

if [ "$#" -gt 0 ]; then
    BUCKETS=("$@")
elif [ -n "${RUSTFS_BUCKETS:-}" ]; then
    IFS=',' read -r -a BUCKETS <<< "${RUSTFS_BUCKETS}"
else
    BUCKETS=("cafedebug-uploads" "cafedebug-images")
fi

RUSTFS_ACCESS_KEY="$(get_env_value "RUSTFS_ACCESS_KEY" || echo "minioadmin")"
RUSTFS_SECRET_KEY="$(get_env_value "RUSTFS_SECRET_KEY" || echo "minioadmin")"

AWS_CMDS=("aws --endpoint-url http://rustfs:9000 s3api list-buckets >/dev/null")
for b in "${BUCKETS[@]}"; do
    AWS_CMDS+=("aws --endpoint-url http://rustfs:9000 s3api head-bucket --bucket ${b} >/dev/null 2>&1 || aws --endpoint-url http://rustfs:9000 s3api create-bucket --bucket ${b}")
    AWS_CMDS+=("aws --endpoint-url http://rustfs:9000 s3api put-bucket-policy --bucket ${b} --policy '{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::${b}/*\"}]}'")
done
AWS_CMDS+=("aws --endpoint-url http://rustfs:9000 s3api list-buckets")

CMD=""
for aws_cmd in "${AWS_CMDS[@]}"; do
    if [ -n "${CMD}" ]; then
        CMD+=" && "
    fi
    CMD+="${aws_cmd}"
done

echo_info "Running rustfs-init to create buckets: ${BUCKETS[*]}"
compose run --rm --entrypoint sh rustfs-init -c "${CMD}"

echo_info "Buckets ensured. You can open RustFS Console at http://localhost:9001 (user: ${RUSTFS_ACCESS_KEY} / pass: ${RUSTFS_SECRET_KEY})"
