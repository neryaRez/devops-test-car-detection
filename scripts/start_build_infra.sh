#!/usr/bin/env bash
set -euo pipefail

# Car Detector one-shot infrastructure bootstrap.
#
# What this script does:
# 1. Checks/install basic local prerequisites where possible.
# 2. Detects AWS account and region.
# 3. Creates Terraform remote backend: S3 state bucket + DynamoDB lock table.
# 4. Initializes and applies the platform stack:
#    VPC, private/public subnets, NAT, VPC endpoints, S3 app bucket, ECR, EKS, SSM parameters.
# 5. Initializes and applies the Jenkins stack:
#    Private Jenkins EC2, IAM role, SSM access, Docker/AWS/kubectl/Helm/Jenkins tools,
#    Jenkins EKS access, detector IRSA role.
# 6. Prints Jenkins access instructions through SSM port forwarding.
#
# Usage:
#   chmod +x scripts/start_build_infra.sh
#   ./scripts/start_build_infra.sh --yes
#
# Optional env vars:
#   AWS_REGION=us-east-1
#   PROJECT_NAME=car-detector
#   ENVIRONMENT=test
#   TERRAFORM_VERSION=1.14.0

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROJECT_NAME="${PROJECT_NAME:-car-detector}"
ENVIRONMENT="${ENVIRONMENT:-test}"
TERRAFORM_VERSION="${TERRAFORM_VERSION:-1.14.0}"

AUTO_APPROVE_FLAG=()
if [[ "${1:-}" == "--yes" ]] || [[ "${AUTO_APPROVE:-}" == "1" ]]; then
  AUTO_APPROVE_FLAG=(-auto-approve)
fi

log() {
  echo
  echo "==> $*"
}

warn() {
  echo "WARNING: $*" >&2
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

install_terraform_if_missing() {
  if command -v terraform >/dev/null 2>&1; then
    return 0
  fi

  log "Terraform not found. Installing Terraform ${TERRAFORM_VERSION}"

  if [[ "$(uname -s)" != "Linux" ]]; then
    fail "Automatic Terraform install is supported only on Linux. Please install Terraform manually."
  fi

  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64|amd64)
      TF_ARCH="amd64"
      ;;
    aarch64|arm64)
      TF_ARCH="arm64"
      ;;
    *)
      fail "Unsupported CPU architecture for automatic Terraform install: $ARCH"
      ;;
  esac

  need_cmd curl
  need_cmd unzip
  need_cmd sudo

  TMP_DIR="$(mktemp -d)"
  ZIP_PATH="${TMP_DIR}/terraform.zip"

  curl -fsSL \
    "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TF_ARCH}.zip" \
    -o "$ZIP_PATH"

  unzip -q "$ZIP_PATH" -d "$TMP_DIR"
  sudo install -m 0755 "${TMP_DIR}/terraform" /usr/local/bin/terraform
  rm -rf "$TMP_DIR"

  terraform version
}

install_session_manager_plugin_if_possible() {
  if command -v session-manager-plugin >/dev/null 2>&1; then
    echo "Session Manager plugin already installed"
    session-manager-plugin --version || true
    return 0
  fi

  log "Session Manager plugin not found. Trying to install it."

  if [[ "$(uname -s)" != "Linux" ]]; then
    warn "Automatic Session Manager Plugin install is supported only on Linux."
    warn "Install it manually before using SSM port forwarding."
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    warn "curl is missing. Cannot auto-install Session Manager Plugin."
    return 0
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    warn "sudo is missing. Cannot auto-install Session Manager Plugin."
    return 0
  fi

  ARCH="$(uname -m)"

  case "$ARCH" in
    x86_64|amd64)
      PLUGIN_URL="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb"
      ;;
    aarch64|arm64)
      PLUGIN_URL="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_arm64/session-manager-plugin.deb"
      ;;
    *)
      warn "Unsupported architecture for automatic Session Manager Plugin install: $ARCH"
      warn "Install Session Manager Plugin manually before using SSM port forwarding."
      return 0
      ;;
  esac

  TMP_DEB="$(mktemp /tmp/session-manager-plugin.XXXXXX.deb)"

  curl -fsSL "$PLUGIN_URL" -o "$TMP_DEB"
  sudo dpkg -i "$TMP_DEB"
  rm -f "$TMP_DEB"

  if command -v session-manager-plugin >/dev/null 2>&1; then
    echo "Session Manager plugin installed successfully"
    session-manager-plugin --version || true
  else
    warn "Session Manager plugin installation may have failed."
    warn "Install it manually before using SSM port forwarding."
  fi
}

write_backend_hcl() {
  local path="$1"
  local bucket="$2"
  local key="$3"
  local table="$4"
  local region="$5"

  mkdir -p "$(dirname "$path")"

  cat > "$path" <<BACKEND
bucket         = "${bucket}"
key            = "${key}"
region         = "${region}"
dynamodb_table = "${table}"
encrypt        = true
BACKEND
}

get_jenkins_initial_password() {
  local instance_id="$1"

  log "Trying to read Jenkins initial admin password through SSM"

  local command_id
  command_id="$(aws ssm send-command \
    --instance-ids "$instance_id" \
    --document-name "AWS-RunShellScript" \
    --comment "Read Jenkins initial admin password" \
    --parameters 'commands=["sudo cat /var/lib/jenkins/secrets/initialAdminPassword 2>/dev/null || true"]' \
    --query 'Command.CommandId' \
    --output text 2>/dev/null || true)"

  if [[ -z "$command_id" || "$command_id" == "None" ]]; then
    warn "Could not start SSM command to read Jenkins password."
    return 0
  fi

  for _ in {1..20}; do
    status="$(aws ssm get-command-invocation \
      --command-id "$command_id" \
      --instance-id "$instance_id" \
      --query 'Status' \
      --output text 2>/dev/null || true)"

    if [[ "$status" == "Success" ]]; then
      password="$(aws ssm get-command-invocation \
        --command-id "$command_id" \
        --instance-id "$instance_id" \
        --query 'StandardOutputContent' \
        --output text 2>/dev/null | tr -d '\r' | xargs || true)"

      if [[ -n "$password" && "$password" != "None" ]]; then
        echo
        echo "Jenkins initial admin password:"
        echo "$password"
        return 0
      fi
    fi

    if [[ "$status" == "Failed" || "$status" == "Cancelled" || "$status" == "TimedOut" ]]; then
      warn "SSM command finished with status: $status"
      return 0
    fi

    sleep 3
  done

  warn "Timed out waiting for Jenkins initial password."
}

log "Checking local prerequisites"
install_terraform_if_missing
need_cmd terraform
need_cmd aws
need_cmd curl
need_cmd unzip
install_session_manager_plugin_if_possible

AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null || true)}}"
AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

log "Detecting AWS identity"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
echo "AWS account : $ACCOUNT_ID"
echo "AWS region  : $AWS_REGION"
echo "Project     : $PROJECT_NAME"
echo "Environment : $ENVIRONMENT"

BACKEND_DIR="${ROOT}/terraform/.generated-backends"
PLATFORM_BACKEND_FILE="${BACKEND_DIR}/platform.hcl"
JENKINS_BACKEND_FILE="${BACKEND_DIR}/jenkins.hcl"

log "Step 1/3: Creating Terraform remote backend"
terraform -chdir="${ROOT}/terraform/state-backend" init -input=false

terraform -chdir="${ROOT}/terraform/state-backend" apply \
  "${AUTO_APPROVE_FLAG[@]}" \
  -input=false \
  -var="name_prefix=${PROJECT_NAME}" \
  -var="aws_region=${AWS_REGION}"

STATE_BUCKET="$(terraform -chdir="${ROOT}/terraform/state-backend" output -raw state_bucket_name)"
LOCK_TABLE="$(terraform -chdir="${ROOT}/terraform/state-backend" output -raw lock_table_name)"

echo "Terraform state bucket: $STATE_BUCKET"
echo "Terraform lock table  : $LOCK_TABLE"

log "Writing generated backend configs"
write_backend_hcl \
  "$PLATFORM_BACKEND_FILE" \
  "$STATE_BUCKET" \
  "platform/${ENVIRONMENT}/terraform.tfstate" \
  "$LOCK_TABLE" \
  "$AWS_REGION"

write_backend_hcl \
  "$JENKINS_BACKEND_FILE" \
  "$STATE_BUCKET" \
  "jenkins/${ENVIRONMENT}/terraform.tfstate" \
  "$LOCK_TABLE" \
  "$AWS_REGION"

log "Step 2/3: Applying platform Terraform stack"
terraform -chdir="${ROOT}/terraform/platform" init \
  -input=false \
  -reconfigure \
  -backend-config="$PLATFORM_BACKEND_FILE"

terraform -chdir="${ROOT}/terraform/platform" apply \
  "${AUTO_APPROVE_FLAG[@]}" \
  -input=false \
  -var="name_prefix=${PROJECT_NAME}" \
  -var="environment=${ENVIRONMENT}" \
  -var="aws_region=${AWS_REGION}" \
  -var="enable_eks=true"

log "Step 3/3: Applying Jenkins Terraform stack"
terraform -chdir="${ROOT}/terraform/jenkins" init \
  -input=false \
  -reconfigure \
  -backend-config="$JENKINS_BACKEND_FILE"

terraform -chdir="${ROOT}/terraform/jenkins" apply \
  "${AUTO_APPROVE_FLAG[@]}" \
  -input=false \
  -var="name_prefix=${PROJECT_NAME}" \
  -var="environment=${ENVIRONMENT}" \
  -var="aws_region=${AWS_REGION}"

JENKINS_INSTANCE_ID="$(terraform -chdir="${ROOT}/terraform/jenkins" output -raw jenkins_instance_id)"
JENKINS_PRIVATE_IP="$(terraform -chdir="${ROOT}/terraform/jenkins" output -raw jenkins_private_ip 2>/dev/null || true)"

log "Verifying generated SSM configuration"
aws ssm get-parameters-by-path \
  --path "/${PROJECT_NAME}/${ENVIRONMENT}" \
  --recursive \
  --query 'Parameters[*].[Name,Value]' \
  --output table || true

get_jenkins_initial_password "$JENKINS_INSTANCE_ID"

echo
echo "============================================================"
echo "✅ CAR DETECTOR INFRASTRUCTURE BOOTSTRAP COMPLETED"
echo "============================================================"
echo "AWS account:              ${ACCOUNT_ID}"
echo "AWS region:               ${AWS_REGION}"
echo "Terraform state bucket:   ${STATE_BUCKET}"
echo "Terraform lock table:     ${LOCK_TABLE}"
echo "Jenkins instance ID:      ${JENKINS_INSTANCE_ID}"
if [[ -n "$JENKINS_PRIVATE_IP" ]]; then
  echo "Jenkins private IP:       ${JENKINS_PRIVATE_IP}"
fi
echo
echo "Open Jenkins through SSM port forwarding:"
echo
echo "aws ssm start-session \\"
echo "  --target ${JENKINS_INSTANCE_ID} \\"
echo "  --document-name AWS-StartPortForwardingSession \\"
echo "  --parameters '{\"portNumber\":[\"8080\"],\"localPortNumber\":[\"8080\"]}'"
echo
echo "Then open:"
echo "http://localhost:8080"
echo
echo "After Jenkins opens:"
echo "1. Unlock Jenkins with the initial password printed above."
echo "2. Install suggested plugins."
echo "3. Create a Pipeline job from SCM."
echo "4. Repository URL: your GitHub repository URL."
echo "5. Branch: */main"
echo "6. Script Path: Jenkinsfile"
echo "============================================================"