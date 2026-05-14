# Dataset and S3

## Where are the video and labels?

They are **not stored in this repository**. The practical test assumes a **small labeled video** and **ground-truth labels** are already placed in **S3 inside your AWS test account** (or whatever bucket URIs Neuronics / your instructor gave you).

You reference them at run time with:

- **`S3_VIDEO_URI`** — `s3://bucket/key.mp4` (or similar)
- **`S3_LABELS_URI`** — `s3://bucket/key.json` (per-frame car boxes; formats supported by `detector.labels.load_labels_json`)

Outputs go to either:

- **`S3_OUTPUT_PREFIX_URI`** — `s3://bucket/prefix/` (service writes `metrics.json` and `run.log` under that prefix), or  
- **`S3_METRICS_URI`** / **`S3_RUN_LOG_URI`** — explicit object keys.

## How to find the real URIs

1. Check email / brief / shared doc from the company running the test.  
2. In the AWS console: **S3** → open the test bucket → copy object URLs and convert to `s3://bucket/key` form.  
3. Keep secrets out of git: use **`.env`** (gitignored), **IAM roles** on EKS, or Jenkins credentials — see `config/.env.example`.

## Local vs cloud credentials

- **Locally:** short-lived keys or SSO profile (only on your machine).  
- **EKS:** prefer **IRSA** (IAM Roles for Service Accounts) so the pod does not use long-lived keys.
