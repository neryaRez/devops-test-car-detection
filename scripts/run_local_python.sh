#!/usr/bin/env bash
set -euo pipefail

export AWS_REGION="${AWS_REGION:-us-east-1}"
export BUCKET="${BUCKET:-car-detector-demo-nerya-1778770380}"

export S3_VIDEO_URI="${S3_VIDEO_URI:-s3://$BUCKET/input/car-sample.mp4}"
export S3_LABELS_URI="${S3_LABELS_URI:-s3://$BUCKET/input/labels.json}"
export S3_OUTPUT_PREFIX_URI="${S3_OUTPUT_PREFIX_URI:-s3://$BUCKET/runs/local-python-$(date +%Y%m%d-%H%M%S)/}"

export YOLO_MODEL="${YOLO_MODEL:-yolov8n.pt}"
export YOLO_DEVICE="${YOLO_DEVICE:-cpu}"
export CONF_THRESHOLD="${CONF_THRESHOLD:-0.25}"
export IOU_THRESHOLD="${IOU_THRESHOLD:-0.5}"
export LOG_LEVEL="${LOG_LEVEL:-INFO}"

echo "Running car detector..."
echo "Video:  $S3_VIDEO_URI"
echo "Labels: $S3_LABELS_URI"
echo "Output: $S3_OUTPUT_PREFIX_URI"

python -m detector.app