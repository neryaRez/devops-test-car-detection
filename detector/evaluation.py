"""Bounding-box IoU matching, frame-level aggregation, and confusion metrics."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, List, Mapping, Sequence, Tuple

import numpy as np

from detector.labels import boxes_for_frame


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
