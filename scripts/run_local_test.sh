#!/usr/bin/env bash
set -euo pipefail

# Local Docker Compose integration test for the car detector.
#
# Flow:
# 1. Detect AWS account + region.
# 2. Prefer the official app bucket from SSM if platform Terraform already exists.
# 3. Otherwise create/use a generic local testing bucket.
# 4. Upload sample video + labels if they are missing.
# 5. Run docker compose build + docker compose run against S3.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROJECT_NAME="${PROJECT_NAME:-car-detector}"
ENVIRONMENT="${ENVIRONMENT:-test}"

SAMPLE_VIDEO_PATH="${SAMPLE_VIDEO_PATH:-data/input/car-sample.mp4}"
SAMPLE_LABELS_PATH="${SAMPLE_LABELS_PATH:-data/labels/labels.json}"

S3_INPUT_PREFIX="${S3_INPUT_PREFIX:-testing/input}"
S3_RUNS_PREFIX="${S3_RUNS_PREFIX:-testing/runs}"

YOLO_MODEL="${YOLO_MODEL:-yolov8n.pt}"
YOLO_DEVICE="${YOLO_DEVICE:-cpu}"
CONF_THRESHOLD="${CONF_THRESHOLD:-0.25}"
IOU_THRESHOLD="${IOU_THRESHOLD:-0.5}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: Missing required command: $1" >&2
    exit 1
  }
}

echo "==> Checking required commands"
need_cmd aws
need_cmd docker

if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: docker compose is not available." >&2
  exit 1
fi

echo "==> Checking sample files"
if [[ ! -f "$SAMPLE_VIDEO_PATH" ]]; then
  echo "ERROR: Missing sample video: $SAMPLE_VIDEO_PATH" >&2
  echo "Place the test video at this path or set SAMPLE_VIDEO_PATH." >&2
  exit 1
fi

if [[ ! -f "$SAMPLE_LABELS_PATH" ]]; then
  echo "ERROR: Missing labels file: $SAMPLE_LABELS_PATH" >&2
  echo "Place the labels file at this path or set SAMPLE_LABELS_PATH." >&2
  exit 1
fi

echo "==> Detecting AWS identity"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null || true)}}"
AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

echo "AWS account: $ACCOUNT_ID"
echo "AWS region : $AWS_REGION"

SSM_BUCKET_PARAM="/${PROJECT_NAME}/${ENVIRONMENT}/app-bucket-name"
APP_BUCKET=""

echo "==> Looking for official app bucket in SSM: $SSM_BUCKET_PARAM"
if APP_BUCKET_FROM_SSM="$(aws ssm get-parameter \
  --name "$SSM_BUCKET_PARAM" \
  --query 'Parameter.Value' \
  --output text 2>/dev/null)"; then

  if [[ -n "$APP_BUCKET_FROM_SSM" && "$APP_BUCKET_FROM_SSM" != "None" ]]; then
    APP_BUCKET="$APP_BUCKET_FROM_SSM"
    echo "Using official app bucket from SSM: $APP_BUCKET"
  fi
fi

if [[ -z "$APP_BUCKET" ]]; then
  APP_BUCKET="${PROJECT_NAME}-local-${ACCOUNT_ID}-${AWS_REGION}"
  echo "SSM bucket parameter not found."
  echo "Using local testing bucket: $APP_BUCKET"
fi

ensure_bucket_exists() {
  local bucket="$1"

  if aws s3api head-bucket --bucket "$bucket" >/dev/null 2>&1; then
    echo "Bucket exists: s3://$bucket"
    return 0
  fi

  echo "Bucket does not exist. Creating: s3://$bucket"

  if [[ "$AWS_REGION" == "us-east-1" ]]; then
    aws s3api create-bucket \
      --bucket "$bucket"
  else
    aws s3api create-bucket \
      --bucket "$bucket" \
      --create-bucket-configuration LocationConstraint="$AWS_REGION"
  fi

  echo "Applying basic secure bucket settings"

  aws s3api put-public-access-block \
    --bucket "$bucket" \
    --public-access-block-configuration \
      BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

  aws s3api put-bucket-encryption \
    --bucket "$bucket" \
    --server-side-encryption-configuration \
      '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

  aws s3api put-bucket-versioning \
    --bucket "$bucket" \
    --versioning-configuration Status=Enabled
}

object_exists() {
  local bucket="$1"
  local key="$2"

  aws s3api head-object \
    --bucket "$bucket" \
    --key "$key" >/dev/null 2>&1
}

upload_if_missing() {
  local local_path="$1"
  local bucket="$2"
  local key="$3"

  if object_exists "$bucket" "$key"; then
    echo "S3 object exists: s3://$bucket/$key"
  else
    echo "Uploading: $local_path -> s3://$bucket/$key"
    aws s3 cp "$local_path" "s3://$bucket/$key"
  fi
}

ensure_bucket_exists "$APP_BUCKET"

VIDEO_KEY="${S3_INPUT_PREFIX}/car-sample.mp4"
LABELS_KEY="${S3_INPUT_PREFIX}/labels.json"

echo "==> Ensuring sample data exists in S3"
upload_if_missing "$SAMPLE_VIDEO_PATH" "$APP_BUCKET" "$VIDEO_KEY"
upload_if_missing "$SAMPLE_LABELS_PATH" "$APP_BUCKET" "$LABELS_KEY"

RUN_ID="local-$(date +%Y%m%d-%H%M%S)"
S3_VIDEO_URI="s3://${APP_BUCKET}/${VIDEO_KEY}"
S3_LABELS_URI="s3://${APP_BUCKET}/${LABELS_KEY}"
S3_OUTPUT_PREFIX_URI="s3://${APP_BUCKET}/${S3_RUNS_PREFIX}/${RUN_ID}/"

echo "==> Local test configuration"
echo "S3_VIDEO_URI        = $S3_VIDEO_URI"
echo "S3_LABELS_URI       = $S3_LABELS_URI"
echo "S3_OUTPUT_PREFIX_URI= $S3_OUTPUT_PREFIX_URI"
echo "YOLO_MODEL          = $YOLO_MODEL"
echo "YOLO_DEVICE         = $YOLO_DEVICE"

echo "==> Building container with docker compose"
docker compose build

echo "==> Running detector with docker compose"

COMPOSE_RUN_ARGS=(
  run
  --rm
  -e "AWS_REGION=$AWS_REGION"
  -e "AWS_DEFAULT_REGION=$AWS_REGION"
  -e "S3_VIDEO_URI=$S3_VIDEO_URI"
  -e "S3_LABELS_URI=$S3_LABELS_URI"
  -e "S3_OUTPUT_PREFIX_URI=$S3_OUTPUT_PREFIX_URI"
  -e "YOLO_MODEL=$YOLO_MODEL"
  -e "YOLO_DEVICE=$YOLO_DEVICE"
  -e "CONF_THRESHOLD=$CONF_THRESHOLD"
  -e "IOU_THRESHOLD=$IOU_THRESHOLD"
  -e "LOG_LEVEL=$LOG_LEVEL"
)

# If the user uses AWS_PROFILE / SSO, mount ~/.aws into the container.
# If the user uses env keys, pass them through.
if [[ -d "$HOME/.aws" ]]; then
  COMPOSE_RUN_ARGS+=(
    -v "$HOME/.aws:/root/.aws:ro"
    -e "AWS_PROFILE=${AWS_PROFILE:-default}"
  )
fi

if [[ -n "${AWS_ACCESS_KEY_ID:-}" ]]; then
  COMPOSE_RUN_ARGS+=(-e "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID")
fi

if [[ -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
  COMPOSE_RUN_ARGS+=(-e "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY")
fi

if [[ -n "${AWS_SESSION_TOKEN:-}" ]]; then
  COMPOSE_RUN_ARGS+=(-e "AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN")
fi

COMPOSE_RUN_ARGS+=(detector)

docker compose "${COMPOSE_RUN_ARGS[@]}"

echo
echo "==> Local test finished"
echo "Metrics expected at:"
echo "s3://${APP_BUCKET}/${S3_RUNS_PREFIX}/${RUN_ID}/metrics.json"
echo
echo "Run log expected at:"
echo "s3://${APP_BUCKET}/${S3_RUNS_PREFIX}/${RUN_ID}/run.log"