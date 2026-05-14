# Project background

Read these in order when onboarding or handing work between agents.

| Doc | Purpose |
|-----|---------|
| [dataset-and-s3.md](dataset-and-s3.md) | Where the labeled video and GT labels live (S3, not git) and which env vars point at them |
| [repo-layout.md](repo-layout.md) | Directory map: Python package, tests, Docker, Helm, Terraform |
| [terraform-layout.md](terraform-layout.md) | Three Terraform stacks and shared `modules/` |
| [workstreams.md](workstreams.md) | Suggested order: app → container → CI → cluster → Jenkins |
| [aws-region-and-bootstrap.md](aws-region-and-bootstrap.md) | Default `us-east-1`, region overrides, `scripts/bootstrap.sh`, Jenkins trigger |
| [submission-and-aws-accounts.md](submission-and-aws-accounts.md) | Who supplies the AWS test account (candidate vs employer) |
