#!/bin/bash
set -euo pipefail

# Quick health and access test for RustFS
echo "RustFS console: http://localhost:9001"
echo "Credentials: dev-access-key / dev-secret-key"

echo
echo "Checking RustFS HTTP health endpoint..."
if curl -sS http://localhost:9000/health >/dev/null 2>&1; then
  echo "RustFS health: READY"
else
  echo "RustFS health: NOT READY or not reachable"
  echo "Check 'docker compose logs rustfs --tail=100' for details"
fi

echo
# Quick attempt to list buckets using AWS CLI inside a transient container
echo "Listing buckets via AWS CLI..."
docker run --rm --network $(basename $(pwd))_default \
  -e AWS_ACCESS_KEY_ID=dev-access-key \
  -e AWS_SECRET_ACCESS_KEY=dev-secret-key \
  amazon/aws-cli:2.27.41 \
  --endpoint-url http://rustfs:9000 s3api list-buckets || echo "Failed to list buckets via AWS CLI"
