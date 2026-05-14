import json
from pathlib import Path

import numpy as np

from detector.app import (
    evaluate_video_frames,
    greedy_match,
    iou_xyxy,
    load_labels_json,
    confusion_and_rates_from_counts,
)


def test_iou_xyxy_perfect_overlap():
    a = [0.0, 0.0, 10.0, 10.0]
    b = [0.0, 0.0, 10.0, 10.0]
    assert abs(iou_xyxy(a, b) - 1.0) < 1e-6


def test_iou_xyxy_no_overlap():
    a = [0.0, 0.0, 10.0, 10.0]
    b = [20.0, 20.0, 30.0, 30.0]
    assert iou_xyxy(a, b) == 0.0


def test_greedy_match_simple_tp_fp_fn():
    gts = np.array([[0.0, 0.0, 10.0, 10.0]], dtype=np.float32)
    preds = np.array([[0.0, 0.0, 10.0, 10.0], [50.0, 50.0, 60.0, 60.0]], dtype=np.float32)
    scores = np.array([0.9, 0.8], dtype=np.float32)
    tp, fp, fn = greedy_match(preds, scores, gts, iou_threshold=0.5)
    assert (tp, fp, fn) == (1, 1, 0)


def test_greedy_match_two_gt_one_pred():
    gts = np.array([[0.0, 0.0, 10.0, 10.0], [20.0, 0.0, 30.0, 10.0]], dtype=np.float32)
    preds = np.array([[0.0, 0.0, 10.0, 10.0]], dtype=np.float32)
    scores = np.array([0.9], dtype=np.float32)
    tp, fp, fn = greedy_match(preds, scores, gts, iou_threshold=0.5)
    assert (tp, fp, fn) == (1, 0, 1)


def test_load_labels_dict_and_list(tmp_path: Path):
    p1 = tmp_path / "l1.json"
    p1.write_text(
        json.dumps({"frames": {"0": [[0, 0, 1, 1]], "1": []}}),
        encoding="utf-8",
    )
    m1 = load_labels_json(p1)
    assert 0 in m1 and 1 in m1
    assert m1[0].shape == (1, 4)
    assert m1[1].shape == (0, 4)

    p2 = tmp_path / "l2.json"
    p2.write_text(
        json.dumps(
            {
                "frames": [
                    {"frame_index": 0, "boxes_xyxy": [[0, 0, 2, 2]]},
                    {"frame_index": 2, "boxes_xyxy": []},
                ]
            }
        ),
        encoding="utf-8",
    )
    m2 = load_labels_json(p2)
    assert 0 in m2 and 2 in m2
    assert 1 not in m2


def test_evaluate_video_frames_counts():
    labels = {0: np.array([[0, 0, 10, 10]], dtype=np.float32), 1: np.zeros((0, 4), dtype=np.float32)}
    preds = {
        0: (np.array([[0, 0, 10, 10]], dtype=np.float32), np.array([0.9], dtype=np.float32)),
        1: (np.zeros((0, 4), dtype=np.float32), np.zeros((0,), dtype=np.float32)),
    }
    rows, bbox_m, frame_m = evaluate_video_frames(preds, labels, max_frame_index=1, iou_threshold=0.5)
    assert len(rows) == 2
    assert bbox_m["tp"] == 1
    assert bbox_m["fp"] == 0
    assert bbox_m["fn"] == 0
    assert frame_m["counts"]["tp"] == 1  # frame0 both present
    assert frame_m["counts"]["tn"] == 1  # frame1 both absent


def test_confusion_and_rates_from_counts():
    out = confusion_and_rates_from_counts(tp=2, fp=1, fn=1, tn=4)
    assert out["confusion_matrix"] == [[4, 1], [1, 2]]
    assert abs(out["precision"] - (2 / 3)) < 1e-9
    assert abs(out["recall"] - (2 / 3)) < 1e-9
    assert abs(out["accuracy"] - (6 / 8)) < 1e-9
