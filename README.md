# Car detector (YOLOv8) — DevOps test repo

Fork-friendly layout: Python detector, Docker, Helm skeleton, Terraform (3 stacks), optional one-shot `scripts/bootstrap.sh`.

## Defaults

- **AWS region:** `us-east-1` everywhere unless you set `AWS_REGION` / `TF_VAR_aws_region` / Terraform `-var=aws_region=...`.
- **AWS CLI + profile:** configure credentials as usual (`aws configure` or env vars); nothing account-specific is committed.

## Quick paths

| Goal | Where |
|------|--------|
| Run detector locally / in Docker | `docker compose` + env from `config/.env.example` |
| Unit tests | `python3 -m pytest` (repo root; see `pyproject.toml`) |
| Infra one-shot | `chmod +x scripts/*.sh` then `./scripts/bootstrap.sh` (see `docs/aws-region-and-bootstrap.md`) |
| Trigger Jenkins only | `./scripts/trigger-jenkins.sh` |
| Background docs | `docs/README.md` |

## Fork and bootstrap (generic)

```bash
git clone https://github.com/YOUR_USER/devops-test-car-detection.git
cd devops-test-car-detection
chmod +x scripts/bootstrap.sh scripts/trigger-jenkins.sh

# Optional: another region
# export AWS_REGION=eu-central-1

# Creates: remote state bucket → VPC + ECR + app S3 (+ optional EKS / Jenkins / job trigger via env vars)
AUTO_APPROVE=1 ./scripts/bootstrap.sh --yes
```

Prerequisites: **Terraform ≥ 1.5**, **aws-cli**, **jq**, **openssl**.

## Submission / test account (FAQ)

See **`docs/submission-and-aws-accounts.md`**. Short version: many employers **give you** their test account; supplying **your own** account to **them** is only OK if they say so—otherwise use their access or ask.
