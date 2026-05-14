# AWS region and one-shot bootstrap

## Default region

- **Default:** `us-east-1` for Terraform variables, `docker-compose.yml`, and `config/.env.example`.
- **Override:** export `AWS_REGION` (and usually `AWS_DEFAULT_REGION`) before running Terraform, Docker, or `scripts/bootstrap.sh`.

## One-shot infrastructure (`scripts/bootstrap.sh`)

From repo root (after `chmod +x scripts/bootstrap.sh scripts/trigger-jenkins.sh`):

```bash
# Interactive applies (you type "yes" when prompted)
./scripts/bootstrap.sh

# Non-interactive (CI / automation)
AUTO_APPROVE=1 ./scripts/bootstrap.sh --yes
```

Optional:

```bash
AWS_REGION=us-west-2 AUTO_APPROVE=1 ./scripts/bootstrap.sh --yes
ENABLE_EKS=1 BOOTSTRAP_JENKINS=1 TRIGGER_JENKINS=1 \
  JENKINS_URL=https://jenkins.example.com JENKINS_JOB=car-detector \
  JENKINS_USER=you JENKINS_TOKEN=your-api-token \
  AUTO_APPROVE=1 ./scripts/bootstrap.sh --yes
```

`terraform/**/backend.generated.hcl` is written by the script and is **gitignored** (contains your state bucket name).

## Jenkins only

```bash
./scripts/trigger-jenkins.sh
```

Requires `JENKINS_URL` and `JENKINS_JOB` (use path segments, e.g. `folderA/myJob`).

## Local Terraform without remote state

To experiment without the S3 backend:

```bash
cd terraform/platform && terraform init -backend=false
```

Same idea for `terraform/jenkins` if you add a `backend "s3" {}` block there (already present): use `terraform init -backend=false` for purely local state.
