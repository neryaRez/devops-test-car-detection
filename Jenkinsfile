pipeline {
  agent any

  options {
    timestamps()
    ansiColor('xterm')
    disableConcurrentBuilds()
  }

  environment {
    PROJECT_NAME = 'car-detector'
    ENVIRONMENT_NAME = 'test'

    AWS_REGION = "${env.AWS_REGION ?: 'us-east-1'}"
    AWS_DEFAULT_REGION = "${env.AWS_REGION ?: 'us-east-1'}"

    SAMPLE_VIDEO_PATH = 'data/input/car-sample.mp4'
    SAMPLE_LABELS_PATH = 'data/labels/labels.json'

    S3_INPUT_PREFIX = 'testing/input'
    S3_RUNS_PREFIX = 'testing/runs'

    YOLO_MODEL = 'yolov8n.pt'
    YOLO_DEVICE = 'cpu'
    CONF_THRESHOLD = '0.25'
    IOU_THRESHOLD = '0.5'
    LOG_LEVEL = 'INFO'

    PRECISION_THRESHOLD = '0.90'
    RECALL_THRESHOLD = '0.90'
    ACCURACY_THRESHOLD = '0.90'

    HELM_RELEASE = 'car-detector'
    HELM_CHART_PATH = 'helm/car-detector'

    LOCAL_IMAGE = 'car-detector:local'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Check tools') {
      steps {
        sh '''
          set -euo pipefail

          echo "==> Checking tools"
          command -v aws
          command -v docker
          docker compose version
          command -v python3
          command -v helm
          command -v kubectl

          echo "==> Tool versions"
          aws --version
          docker --version
          docker compose version
          python3 --version
          helm version --short
          kubectl version --client=true
        '''
      }
    }

    stage('Prepare config from AWS') {
      steps {
        sh '''
          set -euo pipefail

          echo "==> Detecting AWS identity"
          ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
          AWS_REGION="${AWS_REGION:-us-east-1}"
          SSM_PREFIX="/${PROJECT_NAME}/${ENVIRONMENT_NAME}"

          echo "AWS account: ${ACCOUNT_ID}"
          echo "AWS region : ${AWS_REGION}"
          echo "SSM prefix : ${SSM_PREFIX}"

          get_ssm_or_empty() {
            local name="$1"
            aws ssm get-parameter \
              --name "${SSM_PREFIX}/${name}" \
              --query 'Parameter.Value' \
              --output text 2>/dev/null || true
          }

          APP_BUCKET="$(get_ssm_or_empty app-bucket-name)"
          if [ -z "$APP_BUCKET" ] || [ "$APP_BUCKET" = "None" ]; then
            APP_BUCKET="${PROJECT_NAME}-local-${ACCOUNT_ID}-${AWS_REGION}"
            echo "SSM app bucket not found. Using fallback bucket: ${APP_BUCKET}"
          else
            echo "Using app bucket from SSM: ${APP_BUCKET}"
          fi

          ECR_REPOSITORY_URL="$(get_ssm_or_empty ecr-repository-url)"
          if [ -z "$ECR_REPOSITORY_URL" ] || [ "$ECR_REPOSITORY_URL" = "None" ]; then
            ECR_REPOSITORY_URL="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}"
            echo "SSM ECR URL not found. Using fallback ECR URL: ${ECR_REPOSITORY_URL}"
          else
            echo "Using ECR URL from SSM: ${ECR_REPOSITORY_URL}"
          fi

          EKS_CLUSTER_NAME="$(get_ssm_or_empty eks-cluster-name)"
          if [ -z "$EKS_CLUSTER_NAME" ] || [ "$EKS_CLUSTER_NAME" = "None" ]; then
            EKS_CLUSTER_NAME="${PROJECT_NAME}-eks"
            echo "SSM EKS cluster name not found. Using fallback: ${EKS_CLUSTER_NAME}"
          else
            echo "Using EKS cluster from SSM: ${EKS_CLUSTER_NAME}"
          fi

          HELM_NAMESPACE="$(get_ssm_or_empty helm-namespace)"
          if [ -z "$HELM_NAMESPACE" ] || [ "$HELM_NAMESPACE" = "None" ]; then
            HELM_NAMESPACE="${PROJECT_NAME}"
          fi

          SERVICE_ACCOUNT_NAME="$(get_ssm_or_empty detector-service-account-name)"
          if [ -z "$SERVICE_ACCOUNT_NAME" ] || [ "$SERVICE_ACCOUNT_NAME" = "None" ]; then
            SERVICE_ACCOUNT_NAME="car-detector"
          fi

          DETECTOR_IRSA_ROLE_ARN="$(get_ssm_or_empty detector-irsa-role-arn)"

          IMAGE_TAG="${BUILD_NUMBER}-${GIT_COMMIT:-manual}"
          IMAGE_TAG="$(echo "$IMAGE_TAG" | cut -c1-40 | tr -c 'a-zA-Z0-9_.-' '-')"

          LOCAL_RUN_ID="jenkins-compose-${BUILD_NUMBER}"
          EKS_RUN_ID="jenkins-eks-${BUILD_NUMBER}"

          S3_VIDEO_URI="s3://${APP_BUCKET}/${S3_INPUT_PREFIX}/car-sample.mp4"
          S3_LABELS_URI="s3://${APP_BUCKET}/${S3_INPUT_PREFIX}/labels.json"
          LOCAL_OUTPUT_PREFIX_URI="s3://${APP_BUCKET}/${S3_RUNS_PREFIX}/${LOCAL_RUN_ID}/"
          EKS_OUTPUT_PREFIX_URI="s3://${APP_BUCKET}/${S3_RUNS_PREFIX}/${EKS_RUN_ID}/"

          cat > ci.env <<EOF
export ACCOUNT_ID="${ACCOUNT_ID}"
export AWS_REGION="${AWS_REGION}"
export AWS_DEFAULT_REGION="${AWS_REGION}"
export APP_BUCKET="${APP_BUCKET}"
export ECR_REPOSITORY_URL="${ECR_REPOSITORY_URL}"
export ECR_REPOSITORY_NAME="${PROJECT_NAME}"
export EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME}"
export HELM_NAMESPACE="${HELM_NAMESPACE}"
export SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME}"
export DETECTOR_IRSA_ROLE_ARN="${DETECTOR_IRSA_ROLE_ARN}"
export IMAGE_TAG="${IMAGE_TAG}"
export S3_VIDEO_URI="${S3_VIDEO_URI}"
export S3_LABELS_URI="${S3_LABELS_URI}"
export LOCAL_OUTPUT_PREFIX_URI="${LOCAL_OUTPUT_PREFIX_URI}"
export EKS_OUTPUT_PREFIX_URI="${EKS_OUTPUT_PREFIX_URI}"
EOF

          echo "==> Generated CI config"
          cat ci.env
        '''
      }
    }

    stage('Run unit tests') {
      steps {
        sh '''
          set -euo pipefail

          echo "==> Running lightweight unit tests"
          python3 -m venv .venv-test
          . .venv-test/bin/activate

          python -m pip install --upgrade pip
          python -m pip install pytest numpy

          python -m pytest tests/ -q
        '''
      }
    }

    stage('Ensure S3 bucket and sample data') {
      steps {
        sh '''
          set -euo pipefail
          . ./ci.env

          echo "==> Checking sample files"
          test -f "${SAMPLE_VIDEO_PATH}"
          test -f "${SAMPLE_LABELS_PATH}"

          echo "==> Ensuring bucket exists: s3://${APP_BUCKET}"
          if aws s3api head-bucket --bucket "${APP_BUCKET}" >/dev/null 2>&1; then
            echo "Bucket exists"
          else
            echo "Bucket missing. Creating bucket: ${APP_BUCKET}"

            if [ "${AWS_REGION}" = "us-east-1" ]; then
              aws s3api create-bucket --bucket "${APP_BUCKET}"
            else
              aws s3api create-bucket \
                --bucket "${APP_BUCKET}" \
                --create-bucket-configuration LocationConstraint="${AWS_REGION}"
            fi

            aws s3api put-public-access-block \
              --bucket "${APP_BUCKET}" \
              --public-access-block-configuration \
                BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

            aws s3api put-bucket-encryption \
              --bucket "${APP_BUCKET}" \
              --server-side-encryption-configuration \
                '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

            aws s3api put-bucket-versioning \
              --bucket "${APP_BUCKET}" \
              --versioning-configuration Status=Enabled
          fi

          upload_if_missing() {
            local local_path="$1"
            local bucket="$2"
            local key="$3"

            if aws s3api head-object --bucket "$bucket" --key "$key" >/dev/null 2>&1; then
              echo "S3 object exists: s3://${bucket}/${key}"
            else
              echo "Uploading: ${local_path} -> s3://${bucket}/${key}"
              aws s3 cp "${local_path}" "s3://${bucket}/${key}"
            fi
          }

          upload_if_missing "${SAMPLE_VIDEO_PATH}" "${APP_BUCKET}" "${S3_INPUT_PREFIX}/car-sample.mp4"
          upload_if_missing "${SAMPLE_LABELS_PATH}" "${APP_BUCKET}" "${S3_INPUT_PREFIX}/labels.json"
        '''
      }
    }

    stage('Docker Compose build') {
      steps {
        sh '''
          set -euo pipefail

          echo "==> Building image with docker compose"
          CAR_DETECTOR_IMAGE="${LOCAL_IMAGE}" docker compose build
        '''
      }
    }

    stage('Docker Compose run detector') {
      steps {
        sh '''
          set -euo pipefail
          . ./ci.env

          echo "==> Exporting temporary AWS credentials for container runtime"
          aws configure export-credentials --format env > aws-runtime.env
          . ./aws-runtime.env

          echo "==> Running detector with docker compose"
          set +e
          CAR_DETECTOR_IMAGE="${LOCAL_IMAGE}" \
          AWS_REGION="${AWS_REGION}" \
          AWS_DEFAULT_REGION="${AWS_REGION}" \
          AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
          AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
          AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN:-}" \
          S3_VIDEO_URI="${S3_VIDEO_URI}" \
          S3_LABELS_URI="${S3_LABELS_URI}" \
          S3_OUTPUT_PREFIX_URI="${LOCAL_OUTPUT_PREFIX_URI}" \
          YOLO_MODEL="${YOLO_MODEL}" \
          YOLO_DEVICE="${YOLO_DEVICE}" \
          CONF_THRESHOLD="${CONF_THRESHOLD}" \
          IOU_THRESHOLD="${IOU_THRESHOLD}" \
          LOG_LEVEL="${LOG_LEVEL}" \
          docker compose run --rm detector | tee compose-run.log
          COMPOSE_EXIT="${PIPESTATUS[0]}"
          set -e

          if [ "${COMPOSE_EXIT}" -ne 0 ]; then
            echo "Detector compose run failed"
            exit "${COMPOSE_EXIT}"
          fi

          METRICS_URI="$(grep '^METRICS_URI:' compose-run.log | awk '{print $2}' | tail -n 1)"
          if [ -z "${METRICS_URI}" ]; then
            echo "ERROR: Could not find METRICS_URI in detector output"
            exit 1
          fi

          echo "COMPOSE_METRICS_URI=${METRICS_URI}" > compose-metrics.env
          echo "Compose metrics URI: ${METRICS_URI}"
        '''
      }
    }

    stage('Verify metrics thresholds') {
      steps {
        sh '''
          set -euo pipefail
          . ./ci.env
          . ./compose-metrics.env

          echo "==> Downloading metrics"
          aws s3 cp "${COMPOSE_METRICS_URI}" metrics.json

          echo "==> Validating metrics thresholds"
          python3 - <<'PY'
import json
import os
import sys

with open("metrics.json", "r", encoding="utf-8") as f:
    data = json.load(f)

bbox = data.get("bbox_metrics", {})
frame = data.get("frame_presence_metrics", {})

precision = float(bbox.get("precision", 0.0))
recall = float(bbox.get("recall", 0.0))
accuracy = float(frame.get("accuracy", 0.0))

precision_threshold = float(os.environ.get("PRECISION_THRESHOLD", "0.90"))
recall_threshold = float(os.environ.get("RECALL_THRESHOLD", "0.90"))
accuracy_threshold = float(os.environ.get("ACCURACY_THRESHOLD", "0.90"))

print(f"bbox_precision={precision:.6f}")
print(f"bbox_recall={recall:.6f}")
print(f"frame_presence_accuracy={accuracy:.6f}")

failed = False

if precision < precision_threshold:
    print(f"ERROR: precision {precision:.6f} < threshold {precision_threshold:.6f}")
    failed = True

if recall < recall_threshold:
    print(f"ERROR: recall {recall:.6f} < threshold {recall_threshold:.6f}")
    failed = True

if accuracy < accuracy_threshold:
    print(f"ERROR: accuracy {accuracy:.6f} < threshold {accuracy_threshold:.6f}")
    failed = True

if failed:
    sys.exit(1)

print("Metrics thresholds passed.")
PY
        '''
      }
    }

    stage('Ensure ECR repository') {
      steps {
        sh '''
          set -euo pipefail
          . ./ci.env

          echo "==> Ensuring ECR repository exists: ${ECR_REPOSITORY_NAME}"
          if aws ecr describe-repositories \
            --repository-names "${ECR_REPOSITORY_NAME}" \
            --region "${AWS_REGION}" >/dev/null 2>&1; then

            echo "ECR repository exists"
          else
            echo "ECR repository missing. Creating: ${ECR_REPOSITORY_NAME}"

            aws ecr create-repository \
              --repository-name "${ECR_REPOSITORY_NAME}" \
              --image-scanning-configuration scanOnPush=true \
              --encryption-configuration encryptionType=AES256 \
              --region "${AWS_REGION}" >/dev/null
          fi
        '''
      }
    }

    stage('Tag and push image to ECR') {
      steps {
        sh '''
          set -euo pipefail
          . ./ci.env

          echo "==> Logging in to ECR"
          aws ecr get-login-password --region "${AWS_REGION}" | \
            docker login \
              --username AWS \
              --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

          echo "==> Tagging image"
          docker tag "${LOCAL_IMAGE}" "${ECR_REPOSITORY_URL}:${IMAGE_TAG}"

          echo "==> Pushing image"
          docker push "${ECR_REPOSITORY_URL}:${IMAGE_TAG}"

          echo "Pushed image: ${ECR_REPOSITORY_URL}:${IMAGE_TAG}"
        '''
      }
    }

    stage('Helm lint') {
      steps {
        sh '''
          set -euo pipefail

          echo "==> Helm lint"
          helm lint "${HELM_CHART_PATH}" -f "${HELM_CHART_PATH}/lint-values.yaml"
        '''
      }
    }

    stage('Deploy to EKS with Helm') {
      steps {
        sh '''
          set -euo pipefail
          . ./ci.env

          if [ -z "${DETECTOR_IRSA_ROLE_ARN}" ] || [ "${DETECTOR_IRSA_ROLE_ARN}" = "None" ]; then
            echo "ERROR: Missing detector IRSA role ARN."
            echo "Expected SSM parameter:"
            echo "/${PROJECT_NAME}/${ENVIRONMENT_NAME}/detector-irsa-role-arn"
            echo
            echo "Create the detector pod IAM role before deploying to EKS."
            exit 1
          fi

          echo "==> Updating kubeconfig"
          aws eks update-kubeconfig \
            --name "${EKS_CLUSTER_NAME}" \
            --region "${AWS_REGION}"

          echo "==> Verifying cluster access"
          kubectl get nodes

          echo "==> Deploying Helm chart"
          helm upgrade --install "${HELM_RELEASE}" "${HELM_CHART_PATH}" \
            --namespace "${HELM_NAMESPACE}" \
            --create-namespace \
            --set image.repository="${ECR_REPOSITORY_URL}" \
            --set image.tag="${IMAGE_TAG}" \
            --set image.pullPolicy="IfNotPresent" \
            --set aws.region="${AWS_REGION}" \
            --set s3.videoUri="${S3_VIDEO_URI}" \
            --set s3.labelsUri="${S3_LABELS_URI}" \
            --set s3.outputPrefixUri="${EKS_OUTPUT_PREFIX_URI}" \
            --set detector.yoloModel="${YOLO_MODEL}" \
            --set detector.yoloDevice="${YOLO_DEVICE}" \
            --set detector.confThreshold="${CONF_THRESHOLD}" \
            --set detector.iouThreshold="${IOU_THRESHOLD}" \
            --set detector.logLevel="${LOG_LEVEL}" \
            --set serviceAccount.name="${SERVICE_ACCOUNT_NAME}" \
            --set serviceAccount.iamRoleArn="${DETECTOR_IRSA_ROLE_ARN}"
        '''
      }
    }

    stage('Wait for EKS job and print logs') {
      steps {
        sh '''
          set -euo pipefail
          . ./ci.env

          echo "==> Waiting for Kubernetes Job to complete"
          kubectl wait \
            --for=condition=complete \
            job \
            -l app.kubernetes.io/instance="${HELM_RELEASE}" \
            -n "${HELM_NAMESPACE}" \
            --timeout=30m

          JOB_NAME="$(kubectl get jobs \
            -n "${HELM_NAMESPACE}" \
            -l app.kubernetes.io/instance="${HELM_RELEASE}" \
            --sort-by=.metadata.creationTimestamp \
            -o jsonpath='{.items[-1].metadata.name}')"

          echo "Job name: ${JOB_NAME}"

          echo "==> Kubernetes Job logs"
          kubectl logs -n "${HELM_NAMESPACE}" "job/${JOB_NAME}" | tee eks-job.log
        '''
      }
    }

    stage('Verify final S3 output') {
      steps {
        sh '''
          set -euo pipefail
          . ./ci.env

          METRICS_URI="${EKS_OUTPUT_PREFIX_URI}metrics.json"
          RUN_LOG_URI="${EKS_OUTPUT_PREFIX_URI}run.log"

          echo "==> Verifying final S3 outputs"
          echo "Metrics: ${METRICS_URI}"
          echo "Run log: ${RUN_LOG_URI}"

          aws s3 ls "${METRICS_URI}"
          aws s3 ls "${RUN_LOG_URI}"

          echo "Final EKS metrics location:"
          echo "${METRICS_URI}"
        '''
      }
    }
  }

  post {
    success {
      sh '''
        set -e

        if [ -f ./ci.env ]; then
          . ./ci.env
        fi

        echo
        echo "============================================================"
        echo "✅ CAR DETECTOR CI/CD PIPELINE COMPLETED SUCCESSFULLY"
        echo "============================================================"
        echo "Docker Compose test: PASSED"
        echo "Metrics validation:  PASSED"
        echo "Image pushed to ECR: ${ECR_REPOSITORY_URL}:${IMAGE_TAG}"
        echo "Helm deployment:     PASSED"
        echo "EKS metrics path:    ${EKS_OUTPUT_PREFIX_URI}metrics.json"
        echo "EKS run log path:    ${EKS_OUTPUT_PREFIX_URI}run.log"
        echo "============================================================"
        echo
      '''
    }

    failure {
      echo '❌ Pipeline failed. Check the failed stage logs above.'
    }

    always {
      archiveArtifacts artifacts: '*.log,*.json,*.env', allowEmptyArchive: true
    }
  }
}