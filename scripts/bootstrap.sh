#!/usr/bin/env bash
# One-shot bootstrap: state-backend (S3 + DynamoDB for TF state) → platform (VPC, ECR, S3, optional EKS) → optional Jenkins.
#
# Prerequisites: aws-cli (configured), terraform >= 1.5, jq, openssl
#
# Defaults: AWS_REGION=us-east-1, TF_NAME_PREFIX=car-detector
#
# Common env vars:
#   AWS_REGION              Override region (default us-east-1)
#   TF_NAME_PREFIX          Resource name prefix (default car-detector)
#   TF_STATE_BUCKET_SUFFIX  Fixed suffix for state bucket (random if unset)
#   APP_BUCKET_SUFFIX       Suffix for app data bucket (defaults to same as state suffix)
#   ENABLE_EKS              1 to create EKS (default 0)
#   BOOTSTRAP_JENKINS       1 to apply terraform/jenkins (default 0)
#   TRIGGER_JENKINS         1 to run scripts/trigger-jenkins.sh (default 0)
#   AUTO_APPROVE            1 for non-interactive apply, or pass --yes
#
# Jenkins (when TRIGGER_JENKINS=1): JENKINS_URL, JENKINS_JOB, optional JENKINS_USER, JENKINS_TOKEN

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

AUTO_APPROVE_FLAG=()
if [[ "${AUTO_APPROVE:-}" == "1" ]] || [[ "${1:-}" == "--yes" ]]; then
  AUTO_APPROVE_FLAG=(-auto-approve)
fi

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

need_cmd terraform
need_cmd aws
need_cmd jq
need_cmd openssl

export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"

echo "==> AWS region: ${AWS_REGION} (set AWS_REGION to override)"
aws sts get-caller-identity >/dev/null

NAME_PREFIX="${TF_NAME_PREFIX:-car-detector}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
APP_SFX="${APP_BUCKET_SUFFIX:-${ACCOUNT_ID}-${AWS_REGION}}"
ENABLE_EKS="${ENABLE_EKS:-0}"
BOOTSTRAP_JENKINS="${BOOTSTRAP_JENKINS:-0}"
TRIGGER_JENKINS="${TRIGGER_JENKINS:-0}"

if [[ "$ENABLE_EKS" == "1" ]]; then
  EKS_TF_BOOL="true"
else
  EKS_TF_BOOL="false"
fi

write_backend_hcl() {
  local path="$1"
  local bucket="$2"
  local key="$3"
  local table="$4"
  local region="$5"
  cat >"$path" <<EOF
bucket         = "${bucket}"
key            = "${key}"
region         = "${region}"
dynamodb_table = "${table}"
encrypt        = true
EOF
}

echo "==> [1/3] terraform/state-backend (remote state bucket + lock table; uses local .tfstate in this folder)"
pushd "$ROOT/terraform/state-backend" >/dev/null
terraform init -input=false
terraform apply "${AUTO_APPROVE_FLAG[@]}" -input=false \
  -var="name_prefix=${NAME_PREFIX}" \
  -var="aws_region=${AWS_REGION}"

STATE_BUCKET="$(terraform output -raw state_bucket_name)"
LOCK_TABLE="$(terraform output -raw lock_table_name)"
popd >/dev/null

echo "==> [2/3] terraform/platform (VPC + ECR + app S3; EKS if ENABLE_EKS=1)"
write_backend_hcl "$ROOT/terraform/platform/backend.generated.hcl" "$STATE_BUCKET" "platform/terraform.tfstate" "$LOCK_TABLE" "$AWS_REGION"

pushd "$ROOT/terraform/platform" >/dev/null
terraform init -input=false -reconfigure -backend-config="$ROOT/terraform/platform/backend.generated.hcl"
terraform apply "${AUTO_APPROVE_FLAG[@]}" -input=false \
  -var="name_prefix=${NAME_PREFIX}" \
  -var="aws_region=${AWS_REGION}" \
  -var="app_bucket_suffix=${APP_SFX}" \
  -var="enable_eks=${EKS_TF_BOOL}"

VPC_ID="$(terraform output -raw vpc_id)"
FIRST_SUBNET="$(terraform output -json public_subnet_ids | jq -r '.[0]')"
popd >/dev/null

if [[ "$BOOTSTRAP_JENKINS" == "1" ]]; then
  echo "==> [3/3] terraform/jenkins (EC2 controller scaffold)"
  write_backend_hcl "$ROOT/terraform/jenkins/backend.generated.hcl" "$STATE_BUCKET" "jenkins/terraform.tfstate" "$LOCK_TABLE" "$AWS_REGION"
  pushd "$ROOT/terraform/jenkins" >/dev/null
  terraform init -input=false -reconfigure -backend-config="$ROOT/terraform/jenkins/backend.generated.hcl"
  terraform apply "${AUTO_APPROVE_FLAG[@]}" -input=false \
    -var="vpc_id=${VPC_ID}" \
    -var="subnet_id=${FIRST_SUBNET}" \
    -var="aws_region=${AWS_REGION}" \
    -var="name_prefix=${NAME_PREFIX}"
  popd >/dev/null
else
  echo "==> Skipping Jenkins (set BOOTSTRAP_JENKINS=1 to apply terraform/jenkins)"
fi

if [[ "$TRIGGER_JENKINS" == "1" ]]; then
  echo "==> Triggering Jenkins job"
  "$ROOT/scripts/trigger-jenkins.sh"
fi

echo "==> Bootstrap finished."
echo "    State bucket: ${STATE_BUCKET}"
echo "    Platform VPC: ${VPC_ID}"
echo "    First public subnet: ${FIRST_SUBNET}"
