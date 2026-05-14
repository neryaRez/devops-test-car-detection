"""S3 URI parsing and object upload/download helpers."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Mapping, Tuple
from urllib.parse import urlparse

from detector.logging_utils import LOGGER


def parse_s3_uri(uri: str) -> Tuple[str, str]:
    parsed = urlparse(uri)
    if parsed.scheme != "s3" or not parsed.netloc or not parsed.path:
        raise ValueError(f"Invalid S3 URI: {uri!r}")
    bucket = parsed.netloc
    key = parsed.path.lstrip("/")
    if not key:
        raise ValueError(f"S3 URI must include object key: {uri!r}")
    return bucket, key


def ensure_s3_prefix_uri(uri: str) -> Tuple[str, str]:
    """Return (bucket, prefix) where prefix ends with '/' if non-empty."""
    bucket, key = parse_s3_uri(uri)
    if key and not key.endswith("/"):
        key = key + "/"
    return bucket, key


def download_s3_object(uri: str, dest_path: Path, s3_client: Any) -> None:
    bucket, key = parse_s3_uri(uri)
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    LOGGER.info("Downloading s3://%s/%s -> %s", bucket, key, dest_path)
    s3_client.download_file(bucket, key, str(dest_path))


def put_s3_json(uri: str, payload: Mapping[str, Any], s3_client: Any) -> None:
    bucket, key = parse_s3_uri(uri)
    body = json.dumps(payload, indent=2, sort_keys=True).encode("utf-8")
    LOGGER.info("Uploading metrics to s3://%s/%s (%d bytes)", bucket, key, len(body))
    s3_client.put_object(Bucket=bucket, Key=key, Body=body, ContentType="application/json")


def put_s3_text(uri: str, text: str, s3_client: Any, content_type: str = "text/plain") -> None:
    bucket, key = parse_s3_uri(uri)
    body = text.encode("utf-8")
    LOGGER.info("Uploading text artifact to s3://%s/%s (%d bytes)", bucket, key, len(body))
    s3_client.put_object(Bucket=bucket, Key=key, Body=body, ContentType=content_type)
