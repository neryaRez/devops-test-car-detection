# Car Detector Service — YOLOv8, Docker, Jenkins, Helm, EKS

A DevOps-oriented car detection service that runs YOLOv8 inference on a labeled video stored in S3, calculates detection metrics, and writes the results back to S3.

This project demonstrates a complete cloud CI/CD flow with Docker Compose, Jenkins, ECR, Helm, EKS, S3, SSM Parameter Store, SSM port forwarding, and IRSA.

---

## Quick Start

### 1. Main cloud setup path — build the infrastructure

Use this path when you want to provision the AWS infrastructure and prepare Jenkins for the full CI/CD flow.

```bash
chmod +x scripts/start_build_infra.sh
./scripts/start_build_infra.sh --yes
```

For a safer first run, omit `--yes` so Terraform shows the plan before applying:

```bash
./scripts/start_build_infra.sh
```

The script provisions or reuses:

- Terraform remote state: S3 bucket + DynamoDB lock table
- VPC, public/private subnets, NAT Gateway, and VPC endpoints
- S3 app bucket for videos, labels, metrics, and logs
- ECR repository for the detector image
- Private EKS cluster and worker nodes
- Private Jenkins EC2 instance
- Jenkins IAM permissions and EKS access
- Detector IRSA role for secure pod-level S3 access
- SSM parameters used by Jenkins

At the end, the script prints the SSM port-forwarding command for opening Jenkins securely.

### 2. Simple local test path — Docker Compose against S3

Use this path when you only want to validate the detector locally without provisioning the full cloud infrastructure.

```bash
chmod +x scripts/run_local_test.sh
./scripts/run_local_test.sh
```

This builds the Docker image with Docker Compose, verifies or uploads the sample video and labels to S3, runs the detector container, and writes `metrics.json` and `run.log` back to S3.

This is useful for fast home testing, but the main submission flow is the full Jenkins + EKS pipeline.

---

## What the Python Detector Does

The Python application is a batch job. It is not a web server.

Entrypoint:

```bash
python -m detector.app
```

Runtime flow:

1. Reads `S3_VIDEO_URI`, `S3_LABELS_URI`, and output S3 paths from environment variables.
2. Downloads the input video and label JSON from S3.
3. Loads YOLOv8.
4. Filters inference to the COCO `car` class only.
5. Compares predictions to ground-truth labels using IoU matching.
6. Calculates:
   - bounding-box precision
   - bounding-box recall
   - bounding-box micro accuracy
   - frame-level confusion matrix
   - frame-level accuracy
7. Uploads:
   - `metrics.json`
   - `run.log`

The important code is organized under:

```text
detector/
  app.py
  cli.py
  evaluation.py
  labels.py
  s3_io.py
```

---

## CI/CD Pipeline

The Jenkins pipeline performs the complete validation and deployment flow:

1. Checkout source code from GitHub.
2. Check required tools: AWS CLI, Docker, Docker Compose, Python, Helm, kubectl.
3. Read environment configuration from AWS SSM Parameter Store.
4. Run Python unit tests.
5. Verify the S3 bucket, input video, and labels.
6. Build the Docker image with Docker Compose.
7. Run the detector through Docker Compose.
8. Download and validate metrics against thresholds.
9. Push the image to Amazon ECR.
10. Lint the Helm chart.
11. Deploy the detector to EKS with Helm.
12. Run the detector as a Kubernetes Job.
13. Print Kubernetes Job logs.
14. Verify that final `metrics.json` and `run.log` exist in S3.

A successful pipeline ends with:

```text
CAR DETECTOR CI/CD PIPELINE COMPLETED SUCCESSFULLY
Docker Compose test: PASSED
Metrics validation:  PASSED
Image pushed to ECR: <ecr-image>
Helm deployment:     PASSED
EKS metrics path:    <s3-metrics-path>
EKS run log path:    <s3-log-path>
```

---

## Jenkins Access Through AWS SSM Tunnel

Jenkins is intentionally private.

There is no public Jenkins UI and no public SSH requirement. Access is done through AWS Systems Manager Session Manager port forwarding.

After running `scripts/start_build_infra.sh`, use the command printed by the script. It will look like this:

```bash
aws ssm start-session \
  --target <jenkins-instance-id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}'
```

Then open:

```text
http://localhost:8080
```

This keeps Jenkins inside the VPC and avoids exposing port `8080` to the internet.

---

## Creating the Jenkins Pipeline Job

After Jenkins is open:

1. Click `New Item`.
2. Choose `Pipeline`.
3. Use `Pipeline script from SCM`.
4. Select `Git`.
5. Set the repository URL to this GitHub repository.
6. Set branch to:

```text
*/main
```

7. Set script path to:

```text
Jenkinsfile
```

8. Click `Build Now`.

---

## IRSA and AWS Security

The EKS detector pod does not use static AWS access keys.

Instead, the Helm chart uses a Kubernetes ServiceAccount annotated with an IAM role ARN:

```yaml
eks.amazonaws.com/role-arn: <detector-irsa-role-arn>
```

The IAM role trust policy is scoped to:

- the EKS OIDC provider
- the expected namespace
- the expected ServiceAccount

The detector pod receives only the permissions it needs:

- read the input video and labels from S3
- write metrics and logs back to S3

This follows least privilege and avoids long-lived credentials inside the container or Kubernetes manifests.

---

## Generic Configuration with SSM Parameter Store

The infrastructure writes important values to SSM Parameter Store:

```text
/car-detector/test/app-bucket-name
/car-detector/test/ecr-repository-url
/car-detector/test/eks-cluster-name
/car-detector/test/helm-namespace
/car-detector/test/detector-service-account-name
/car-detector/test/detector-irsa-role-arn
```

Jenkins reads these values dynamically during the pipeline.

This keeps the Jenkinsfile generic and avoids hardcoding AWS account IDs, bucket names, cluster names, or role ARNs.

---

## Terraform Structure

Terraform is split into clear layers:

```text
terraform/state-backend   # S3 remote state bucket + DynamoDB lock table
terraform/platform        # VPC, S3, ECR, EKS, SSM parameters
terraform/jenkins         # private Jenkins EC2, IAM, EKS access, IRSA
terraform/modules         # reusable infrastructure modules
```

Generated backend files are created locally under:

```text
terraform/.generated-backends/
```

These files are ignored by Git and should not be committed.

---

## Helm Chart

The Helm chart is located at:

```text
helm/car-detector
```

The pipeline deploys it automatically as a Kubernetes Job.

Manual deployment example:

```bash
helm upgrade --install car-detector helm/car-detector \
  --namespace car-detector \
  --create-namespace \
  --set image.repository=<ecr-repository-url> \
  --set image.tag=<image-tag> \
  --set aws.region=us-east-1 \
  --set s3.videoUri=s3://<bucket>/testing/input/car-sample.mp4 \
  --set s3.labelsUri=s3://<bucket>/testing/input/labels.json \
  --set s3.outputPrefixUri=s3://<bucket>/testing/runs/manual/ \
  --set serviceAccount.iamRoleArn=<detector-irsa-role-arn>
```

---

## Verification Commands

From a machine that has access to the private EKS API, such as the Jenkins EC2 instance:

```bash
kubectl get nodes
kubectl get jobs -n car-detector
kubectl logs -n car-detector job/<job-name>
```

Check S3 outputs:

```bash
aws s3 ls s3://<bucket>/testing/runs/
```

Expected files per run:

```text
metrics.json
run.log
```

---

## Cleanup

Destroy Jenkins first, then the platform stack:

```bash
terraform -chdir=terraform/jenkins destroy
terraform -chdir=terraform/platform destroy
```

The Terraform backend stack can be kept for future runs or removed manually when no longer needed.

> Note: EKS, NAT Gateway, and EC2 resources may create AWS costs. Clean up resources when finished.