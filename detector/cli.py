"""CLI and end-to-end run: S3 download → YOLOv8 car inference → metrics → S3 upload."""

from __future__ import annotations

import argparse
import json
import os
import tempfile
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import numpy as np

from detector.constants import COCO_CAR_CLASS_ID
from detector.evaluation import evaluate_video_frames
from detector.labels import load_labels_json
from detector.logging_utils import LOGGER, configure_logging
from detector.s3_io import (
    download_s3_object,
    ensure_s3_prefix_uri,
    put_s3_json,
    put_s3_text,
)


def build_arg_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="YOLOv8 car-only video detector with S3 IO + metrics")
    p.add_argument("--s3-video-uri", default=os.environ.get("S3_VIDEO_URI"), help="s3://bucket/key.mp4")
    p.add_argument("--s3-labels-uri", default=os.environ.get("S3_LABELS_URI"), help="s3://bucket/key.json")
    p.add_argument(
        "--s3-output-prefix-uri",
        default=os.environ.get("S3_OUTPUT_PREFIX_URI"),
        help="s3://bucket/prefix/ (metrics + logs written under this prefix)",
    )
    p.add_argument("--s3-metrics-uri", default=os.environ.get("S3_METRICS_URI"), help="Optional explicit s3://bucket/key.json")
    p.add_argument("--s3-run-log-uri", default=os.environ.get("S3_RUN_LOG_URI"), help="Optional explicit s3://bucket/key.log")
    p.add_argument("--yolo-model", default=os.environ.get("YOLO_MODEL", "yolov8n.pt"))
    p.add_argument("--conf", type=float, default=float(os.environ.get("CONF_THRESHOLD", "0.25")))
    p.add_argument("--iou-threshold", type=float, default=float(os.environ.get("IOU_THRESHOLD", "0.5")))
    p.add_argument("--device", default=os.environ.get("YOLO_DEVICE", ""), help="Optional: cpu, 0, cuda:0, ...")
    return p


def require_non_empty(name: str, value: Optional[str]) -> str:
    if not value:
        raise SystemExit(f"Missing required value for {name} (env or CLI).")
    return value


def run() -> int:
    configure_logging()
    args = build_arg_parser().parse_args()

    video_uri = require_non_empty("S3_VIDEO_URI", args.s3_video_uri)
    labels_uri = require_non_empty("S3_LABELS_URI", args.s3_labels_uri)
    output_prefix = args.s3_output_prefix_uri
    metrics_uri = args.s3_metrics_uri
    run_log_uri = args.s3_run_log_uri

    if not output_prefix and not metrics_uri:
        raise SystemExit("Provide S3_OUTPUT_PREFIX_URI or S3_METRICS_URI.")

    import boto3

    s3 = boto3.client("s3")

    tmpdir = Path(tempfile.mkdtemp(prefix="car-detector-"))
    video_path = tmpdir / "input_video.mp4"
    labels_path = tmpdir / "labels.json"

    try:
        download_s3_object(video_uri, video_path, s3)
        download_s3_object(labels_uri, labels_path, s3)
        labels_by_frame = load_labels_json(labels_path)

        from ultralytics import YOLO

        device = args.device or None
        model = YOLO(args.yolo_model)
        LOGGER.info("Loaded model %s; filtering to COCO car class id=%s", args.yolo_model, COCO_CAR_CLASS_ID)

        pred_boxes_by_frame: Dict[int, Tuple[np.ndarray, np.ndarray]] = {}
        frame_indices: List[int] = []

        t0 = time.time()
        for frame_index, result in enumerate(
            model.predict(
                source=str(video_path),
                stream=True,
                verbose=False,
                conf=float(args.conf),
                classes=[COCO_CAR_CLASS_ID],
                device=device,
            )
        ):
            frame_indices.append(frame_index)
            boxes = getattr(result, "boxes", None)
            if boxes is None or boxes.xyxy is None or len(boxes) == 0:
                pred_boxes_by_frame[frame_index] = (np.zeros((0, 4), dtype=np.float32), np.zeros((0,), dtype=np.float32))
                continue
            xyxy = boxes.xyxy.cpu().numpy().astype(np.float32)
            scores = boxes.conf.cpu().numpy().astype(np.float32)
            pred_boxes_by_frame[frame_index] = (xyxy, scores)

        infer_s = max(1e-6, time.time() - t0)
        max_frame = max(frame_indices) if frame_indices else -1
        label_max_frame = max(labels_by_frame.keys()) if labels_by_frame else -1
        max_frame_index = max(max_frame, label_max_frame)
        if max_frame_index < 0:
            max_frame_index = 0

        for fi in range(max_frame_index + 1):
            pred_boxes_by_frame.setdefault(fi, (np.zeros((0, 4), dtype=np.float32), np.zeros((0,), dtype=np.float32)))

        frame_rows, bbox_metrics, frame_rates = evaluate_video_frames(
            pred_boxes_by_frame=pred_boxes_by_frame,
            labels_by_frame=labels_by_frame,
            max_frame_index=max_frame_index,
            iou_threshold=float(args.iou_threshold),
        )

        metrics_payload: Dict[str, Any] = {
            "schema_version": 1,
            "video_uri": video_uri,
            "labels_uri": labels_uri,
            "model": args.yolo_model,
            "conf_threshold": float(args.conf),
            "iou_match_threshold": float(args.iou_threshold),
            "coco_car_class_id": int(COCO_CAR_CLASS_ID),
            "frames_inferred": int(len(frame_indices)),
            "max_frame_index": int(max_frame_index),
            "inference_seconds": float(infer_s),
            "bbox_metrics": bbox_metrics,
            "frame_presence_metrics": frame_rates,
            "per_frame": [fr.__dict__ for fr in frame_rows],
        }

        log_lines = [
            "Car detector run complete",
            f"video_uri={video_uri}",
            f"labels_uri={labels_uri}",
            f"model={args.yolo_model}",
            f"bbox_precision={bbox_metrics['precision']:.6f}",
            f"bbox_recall={bbox_metrics['recall']:.6f}",
            f"bbox_f1={bbox_metrics['f1']:.6f}",
            "frame_presence_confusion_matrix=" + json.dumps(frame_rates["confusion_matrix"]),
            f"frame_presence_precision={frame_rates['precision']:.6f}",
            f"frame_presence_recall={frame_rates['recall']:.6f}",
            f"frame_presence_accuracy={frame_rates['accuracy']:.6f}",
        ]
        log_text = "\n".join(log_lines) + "\n"
        LOGGER.info("%s", log_text.strip())

        if metrics_uri:
            m_uri = metrics_uri
        else:
            out_bucket, out_prefix = ensure_s3_prefix_uri(require_non_empty("S3_OUTPUT_PREFIX_URI", output_prefix))
            m_uri = f"s3://{out_bucket}/{out_prefix}metrics.json"

        put_s3_json(m_uri, metrics_payload, s3)

        if run_log_uri:
            put_s3_text(run_log_uri, log_text, s3)
        elif output_prefix:
            out_bucket, out_prefix = ensure_s3_prefix_uri(output_prefix)
            l_uri = f"s3://{out_bucket}/{out_prefix}run.log"
            put_s3_text(l_uri, log_text, s3)

        print("CONFUSION_MATRIX_FRAME_PRESENCE:", json.dumps(frame_rates["confusion_matrix"]))
        print("PRECISION_BBOX:", f"{bbox_metrics['precision']:.6f}")
        print("RECALL_BBOX:", f"{bbox_metrics['recall']:.6f}")
        print("ACCURACY_FRAME_PRESENCE:", f"{frame_rates['accuracy']:.6f}")
        print("ACCURACY_BBOX_MICRO:", f"{bbox_metrics['micro_accuracy']:.6f}")
        print("METRICS_URI:", m_uri)
        return 0
    finally:
        try:
            for pth in tmpdir.rglob("*"):
                if pth.is_file():
                    pth.unlink(missing_ok=True)  # type: ignore[arg-type]
            tmpdir.rmdir()
        except OSError:
            LOGGER.warning("Could not fully clean temp dir: %s", tmpdir)


def main() -> None:
    raise SystemExit(run())
