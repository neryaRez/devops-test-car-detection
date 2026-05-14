"""
Car-only YOLOv8 video inference with S3 I/O and evaluation vs labeled ground truth.

Configuration is driven by environment variables (and optional CLI overrides) so
the same image can run locally, in CI, or on Kubernetes with IAM/IRSA credentials.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Mapping, MutableMapping, Optional, Sequence, Tuple
from urllib.parse import urlparse

import numpy as np

LOGGER = logging.getLogger("car_detector")

# COCO class id for "car" in default YOLOv8 COCO checkpoints (Ultralytics).
COCO_CAR_CLASS_ID = 2


def configure_logging() -> None:
    level = os.environ.get("LOG_LEVEL", "INFO").upper()
    logging.basicConfig(
        level=getattr(logging, level, logging.INFO),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )


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


def iou_xyxy(a: Sequence[float], b: Sequence[float]) -> float:
    ax1, ay1, ax2, ay2 = map(float, a)
    bx1, by1, bx2, by2 = map(float, b)
    inter_x1 = max(ax1, bx1)
    inter_y1 = max(ay1, by1)
    inter_x2 = min(ax2, bx2)
    inter_y2 = min(ay2, by2)
    iw = max(0.0, inter_x2 - inter_x1)
    ih = max(0.0, inter_y2 - inter_y1)
    inter = iw * ih
    if inter <= 0.0:
        return 0.0
    area_a = max(0.0, ax2 - ax1) * max(0.0, ay2 - ay1)
    area_b = max(0.0, bx2 - bx1) * max(0.0, by2 - by1)
    union = area_a + area_b - inter
    if union <= 0.0:
        return 0.0
    return float(inter / union)


def greedy_match(
    preds: np.ndarray,
    pred_scores: np.ndarray,
    gts: np.ndarray,
    iou_threshold: float,
) -> Tuple[int, int, int]:
    """
    Greedy IoU matching (sorted by descending confidence).
    Returns (tp, fp, fn) at the bounding-box level for a single frame / image.
    """
    if preds.size == 0 and gts.size == 0:
        return 0, 0, 0
    if preds.size == 0:
        return 0, 0, int(len(gts))
    if gts.size == 0:
        return 0, int(len(preds)), 0

    order = np.argsort(-pred_scores)
    preds = preds[order]
    pred_scores = pred_scores[order]

    gt_used = np.zeros(len(gts), dtype=bool)
    tp = 0
    fp = 0

    for pb in preds:
        best_j = -1
        best_iou = 0.0
        for j, gb in enumerate(gts):
            if gt_used[j]:
                continue
            v = iou_xyxy(pb, gb)
            if v > best_iou:
                best_iou = v
                best_j = j
        if best_j >= 0 and best_iou >= iou_threshold:
            gt_used[best_j] = True
            tp += 1
        else:
            fp += 1

    fn = int(np.count_nonzero(~gt_used))
    return tp, fp, fn


def confusion_and_rates_from_counts(tp: int, fp: int, fn: int, tn: int) -> Dict[str, Any]:
    total = tp + fp + fn + tn
    precision = float(tp / (tp + fp)) if (tp + fp) > 0 else 0.0
    recall = float(tp / (tp + fn)) if (tp + fn) > 0 else 0.0
    accuracy = float((tp + tn) / total) if total > 0 else 0.0
    # sklearn-style labels: [negative, positive] -> rows actual, cols predicted
    cm = np.array([[tn, fp], [fn, tp]], dtype=np.int64)
    return {
        "confusion_matrix": cm.tolist(),
        "confusion_matrix_labels": {
            "rows": ["actual_negative", "actual_positive"],
            "cols": ["predicted_negative", "predicted_positive"],
        },
        "precision": precision,
        "recall": recall,
        "accuracy": accuracy,
        "counts": {"tp": tp, "fp": fp, "fn": fn, "tn": tn, "total": total},
    }


def load_labels_json(path: Path) -> Dict[int, np.ndarray]:
    """
    Load per-frame GT boxes (xyxy) from JSON.

    Supported shapes:
    - {"frames": {"0": [[x1,y1,x2,y2], ...], "1": [], ...}}
    - {"frames": [{"frame_index": 0, "boxes_xyxy": [...]}, ...]}
    - {"frames": [[...],[...]]}  # list index == frame index
    """
    raw = json.loads(path.read_text(encoding="utf-8"))
    frames: MutableMapping[str, Any] = {}
    if isinstance(raw.get("frames"), dict):
        frames = {str(k): v for k, v in raw["frames"].items()}  # type: ignore[assignment]
    elif isinstance(raw.get("frames"), list):
        lst = raw["frames"]
        for i, item in enumerate(lst):
            if isinstance(item, dict):
                idx = int(item.get("frame_index", item.get("index", i)))
                boxes = item.get("boxes_xyxy", item.get("boxes", item.get("xyxy", [])))
            else:
                idx = i
                boxes = item
            frames[str(idx)] = boxes
    else:
        raise ValueError("labels JSON must contain a 'frames' object or list")

    out: Dict[int, np.ndarray] = {}
    for k, boxes in frames.items():
        fi = int(k)
        if boxes is None:
            arr = np.zeros((0, 4), dtype=np.float32)
        else:
            arr = np.asarray(boxes, dtype=np.float32).reshape(-1, 4)
        out[fi] = arr
    return out


def boxes_for_frame(labels_by_frame: Mapping[int, np.ndarray], frame_index: int) -> np.ndarray:
    if frame_index in labels_by_frame:
        return np.asarray(labels_by_frame[frame_index], dtype=np.float32).reshape(-1, 4)
    return np.zeros((0, 4), dtype=np.float32)


@dataclass
class FrameEval:
    frame_index: int
    tp: int
    fp: int
    fn: int
    gt_car_present: bool
    pred_car_present: bool


def evaluate_video_frames(
    pred_boxes_by_frame: Mapping[int, Tuple[np.ndarray, np.ndarray]],
    labels_by_frame: Mapping[int, np.ndarray],
    max_frame_index: int,
    iou_threshold: float,
) -> Tuple[List[FrameEval], Dict[str, Any], Dict[str, Any]]:
    """
    pred_boxes_by_frame: frame_idx -> (xyxy Nx4, scores N)
    """
    frame_rows: List[FrameEval] = []
    tp_t = fp_t = fn_t = 0
    tp_f = fp_f = fn_f = tn_f = 0

    for fi in range(max_frame_index + 1):
        preds, scores = pred_boxes_by_frame.get(fi, (np.zeros((0, 4)), np.zeros((0,))))
        gts = boxes_for_frame(labels_by_frame, fi)
        tp, fp, fn = greedy_match(preds, scores, gts, iou_threshold=iou_threshold)
        tp_t += tp
        fp_t += fp
        fn_t += fn

        gt_present = bool(len(gts) > 0)
        pred_present = bool(len(preds) > 0)

        if gt_present and pred_present:
            tp_f += 1
        elif gt_present and not pred_present:
            fn_f += 1
        elif (not gt_present) and pred_present:
            fp_f += 1
        else:
            tn_f += 1

        frame_rows.append(
            FrameEval(
                frame_index=fi,
                tp=tp,
                fp=fp,
                fn=fn,
                gt_car_present=gt_present,
                pred_car_present=pred_present,
            )
        )

    bbox_metrics = {
        "definition": "Bounding-box TP/FP/FN via greedy IoU matching on car class predictions vs GT boxes.",
        "iou_threshold": float(iou_threshold),
        "tp": int(tp_t),
        "fp": int(fp_t),
        "fn": int(fn_t),
        "precision": float(tp_t / (tp_t + fp_t)) if (tp_t + fp_t) > 0 else 0.0,
        "recall": float(tp_t / (tp_t + fn_t)) if (tp_t + fn_t) > 0 else 0.0,
    }
    bbox_metrics["f1"] = (
        float(2 * bbox_metrics["precision"] * bbox_metrics["recall"] / (bbox_metrics["precision"] + bbox_metrics["recall"]))
        if (bbox_metrics["precision"] + bbox_metrics["recall"]) > 0
        else 0.0
    )

    frame_rates = confusion_and_rates_from_counts(tp_f, fp_f, fn_f, tn_f)
    frame_rates["definition"] = (
        "Frame-level confusion for car presence: actual_positive means >=1 GT car box; "
        "predicted_positive means >=1 predicted car box after confidence filtering."
    )

    bbox_metrics["micro_accuracy"] = (
        float(tp_t / (tp_t + fp_t + fn_t)) if (tp_t + fp_t + fn_t) > 0 else 0.0
    )

    return frame_rows, bbox_metrics, frame_rates


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

        # Ensure we evaluate frames up to max index even if video ended earlier / labels longer
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

        # Human-readable matrix to stdout for Jenkins logs
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


if __name__ == "__main__":
    main()
