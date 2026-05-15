#!/usr/bin/env bash
set -euo pipefail

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

echo "Project:     $PROJECT_NAME"
echo "Environment: $ENVIRONMENT"
echo "Account:     $ACCOUNT_ID"
echo "Region:      $AWS_REGION"
echo "State bucket: $STATE_BUCKET"
echo "Lock table:   $LOCK_TABLE"

echo "==> 1. Bootstrap Terraform backend"
cd terraform/state-backend
terraform init -input=false
terraform apply -auto-approve -input=false \
  -var="name_prefix=${PROJECT_NAME}" \
  -var="aws_region=${AWS_REGION}"

cd ../..

mkdir -p .terraform-backends

cat > .terraform-backends/platform.hcl <<EOF
bucket         = "${STATE_BUCKET}"
key            = "platform/${ENVIRONMENT}/terraform.tfstate"
region         = "${AWS_REGION}"
dynamodb_table = "${LOCK_TABLE}"
encrypt        = true
EOF

cat > .terraform-backends/jenkins.hcl <<EOF
bucket         = "${STATE_BUCKET}"
key            = "jenkins/${ENVIRONMENT}/terraform.tfstate"
region         = "${AWS_REGION}"
dynamodb_table = "${LOCK_TABLE}"
encrypt        = true
EOF

echo "==> 2. Apply platform"
cd terraform/platform
terraform init -reconfigure -input=false -backend-config="../../.terraform-backends/platform.hcl"
terraform apply -auto-approve -input=false \
  -var="name_prefix=${PROJECT_NAME}" \
  -var="environment=${ENVIRONMENT}" \
  -var="aws_region=${AWS_REGION}" \
  -var="enable_eks=true"

cd ../..

echo "==> 3. Apply Jenkins"
cd terraform/jenkins
terraform init -reconfigure -input=false -backend-config="../../.terraform-backends/jenkins.hcl"
terraform apply -auto-approve -input=false \
  -var="name_prefix=${PROJECT_NAME}" \
  -var="environment=${ENVIRONMENT}" \
  -var="aws_region=${AWS_REGION}"

cd ../..

echo "Done."
echo "Use SSM port forwarding to access Jenkins."