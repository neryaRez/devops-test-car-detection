#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROJECT_NAME="${PROJECT_NAME:-car-detector}"
ENVIRONMENT="${ENVIRONMENT:-test}"
AWS_REGION="${AWS_REGION:-$(aws configure get region || true)}"

if [[ -z "$AWS_REGION" ]]; then
  AWS_REGION="us-east-1"
fi

export AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

aws sts get-caller-identity >/dev/null

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

STATE_BUCKET="${PROJECT_NAME}-tfstate-${ACCOUNT_ID}-${AWS_REGION}"
LOCK_TABLE="${PROJECT_NAME}-tf-locks"
STATE_KEY="jenkins/${ENVIRONMENT}/terraform.tfstate"

echo "Initializing Jenkins backend:"
echo "  Project:      ${PROJECT_NAME}"
echo "  Environment:  ${ENVIRONMENT}"
echo "  Account:      ${ACCOUNT_ID}"
echo "  Region:       ${AWS_REGION}"
echo "  Bucket:       ${STATE_BUCKET}"
echo "  Lock table:   ${LOCK_TABLE}"
echo "  State key:    ${STATE_KEY}"

BACKEND_DIR="$ROOT/terraform/.generated-backends"
BACKEND_FILE="$BACKEND_DIR/jenkins.hcl"

mkdir -p "$BACKEND_DIR"

cat > "$BACKEND_FILE" <<EOF
bucket         = "${STATE_BUCKET}"
key            = "${STATE_KEY}"
region         = "${AWS_REGION}"
dynamodb_table = "${LOCK_TABLE}"
encrypt        = true
EOF

cd "$ROOT/terraform/jenkins"

terraform init \
  -reconfigure \
  -input=false \
  -backend-config="$BACKEND_FILE"

echo "Jenkins backend initialized successfully."