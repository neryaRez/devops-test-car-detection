# Workstreams (recommended order)

1. **Application** — Confirm `detector/` behavior and `tests/` pass (`pytest`).  
2. **Container** — `docker compose build` / `run` with env from `config/.env.example`.  
3. **Registry** — ECR repo (Terraform `platform` or manual) and push image.  
4. **CI** — Implement `Jenkinsfile`: compose build, push, run job against S3 URIs, parse metrics, gate on thresholds.  
5. **Cluster** — EKS from `terraform/platform`, IRSA for S3, deploy via `helm/car-detector`.  
6. **Jenkins host** — `terraform/jenkins` or managed Jenkins; document trigger steps in `README.md`.

Cross-cutting: **no long-lived keys in git**; document real S3 URIs only in private runbooks or Jenkins credentials.
