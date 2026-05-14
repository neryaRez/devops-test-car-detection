# Submission: whose AWS account?

## What the Neuronics-style brief usually means

Many hiring tests say they provide an **AWS test account** (EKS, ECR, S3, Jenkins) **to you**, the candidate. In that model, **you** apply Terraform and run pipelines **inside their** account using credentials **they** issued. You normally **do not** give them *your* root keys.

## Can you supply *your own* test account to them?

- **As the official submission surface:** only if the employer explicitly allows it (e.g. “record a demo in your own sandbox”). Otherwise, assume they want artifacts from **their** environment or a **shared** account they control.
- **As a portfolio / open-source fork:** using **your** account is normal. Forkers run `scripts/bootstrap.sh` with **their** `aws configure` profile; you are not handing out your keys—you publish **code + docs** only.

## Practical guidance

1. **Read their email / portal:** do they send IAM user, SSO, or “use this account ID”?  
2. **If they give you an account:** use it for submission; do not commit credentials; use `AUTO_APPROVE` only in disposable sandboxes.  
3. **If they do not give you an account:** ask whether a **screen recording + logs + fork URL** is acceptable, or whether they will provision access.  
4. **Never** commit access keys or long-lived tokens; use IAM roles (EKS IRSA, instance profiles) where possible.

This repo stays **account-agnostic**: only `AWS_REGION` and standard AWS credential env vars / profiles matter.
