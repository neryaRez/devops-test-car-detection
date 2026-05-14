"""Ground-truth label JSON loading (per-frame car boxes, xyxy)."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, Mapping, MutableMapping

import numpy as np


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
