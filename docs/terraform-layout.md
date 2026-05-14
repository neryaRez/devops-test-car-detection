# Terraform layout

Infrastructure is split into **three stacks** under `terraform/`. Apply order: **1 → 2 → (optional 3)**. **Default AWS region** for variables is **`us-east-1`**; set `AWS_REGION` / `-var=aws_region=...` to change it.

For a generic one-shot flow (AWS CLI + Terraform + jq), use **`scripts/bootstrap.sh`** (see `docs/aws-region-and-bootstrap.md`).

## 1. `terraform/state-backend/`

Creates the **remote state** backend: S3 bucket + DynamoDB table for state locking.

- Uses **local** Terraform state (this stack is the bootstrap; do not store its state only in the bucket it creates without a one-time bootstrap flow).
- After apply, copy `outputs` into `platform/backend.tf` (or use the generated `backend.tf.example` pattern).

## 2. `terraform/platform/`

Shared **platform**: **VPC**, **EKS** (optional toggle), **ECR**, **S3 buckets** for app datasets / run outputs.

- Composes **reusable modules** under `terraform/modules/`.
- Intended for **EC2-backed EKS** and supporting services per the test brief.

## 3. `terraform/jenkins/`

A **Jenkins controller** (EC2 pattern in scaffold — adjust AMI, sizing, and plugins to match your org).

- Takes **VPC + subnet** inputs (from `platform` outputs or variables).

## Modules (`terraform/modules/`)

| Module | Role |
|--------|------|
| `remote_state_backend` | S3 + DynamoDB for Terraform state |
| `network` | VPC, public subnets, IGW (dev/test style) |
| `ecr` | Container registry for the detector image |
| `s3_app_data` | Buckets/prefixes for video, labels, metrics (tighten policies per environment) |
| `eks` | EKS cluster + managed node group (uses public subnets in scaffold — **harden for production**) |

## Commands (after filling variables)

```bash
cd terraform/state-backend && terraform init && terraform plan
cd ../platform && terraform init && terraform plan
cd ../jenkins && terraform init && terraform plan
```

Add `-var-file=...` or `TF_VAR_*` as you standardize per environment.
