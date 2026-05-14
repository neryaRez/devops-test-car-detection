# Repository layout

```text
devops-test-car-detection/
├── config/                 # Example env only (.env.example); real .env stays gitignored
├── detector/               # Python application
│   ├── app.py              # Thin entry for `python -m detector.app`
│   ├── cli.py              # Argparse + full S3 → YOLO → metrics → S3 run
│   ├── constants.py        # COCO car class id, etc.
│   ├── evaluation.py       # IoU, matching, confusion matrix / rates
│   ├── labels.py           # GT JSON → per-frame boxes
│   ├── logging_utils.py    # Shared logger setup
│   └── s3_io.py            # S3 URI helpers + get/put objects
├── docs/                   # Onboarding and architecture notes (this folder)
├── helm/car-detector/      # Kubernetes packaging (fill templates + values)
├── tests/                  # pytest: pure logic (no S3 / no GPU required)
├── terraform/              # IaC split into 3 stacks + modules (see terraform-layout.md)
├── Dockerfile
├── docker-compose.yml
├── Jenkinsfile             # CI/CD (to be implemented)
├── pyproject.toml          # pytest / ruff settings
├── requirements.txt
└── README.md               # Top-level quick links
```

**Docker** expects `PYTHONPATH=/app` and `CMD ["python", "-m", "detector.app"]` (see `Dockerfile`).
