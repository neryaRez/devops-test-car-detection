"""
Entry module for `python -m detector.app` (Docker CMD).

Implementation lives in focused modules: `cli`, `evaluation`, `labels`, `s3_io`, `constants`.
"""

from __future__ import annotations

from detector.cli import main, run

__all__ = ["main", "run"]

if __name__ == "__main__":
    main()
