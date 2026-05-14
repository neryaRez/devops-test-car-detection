"""Shared logger configuration for the detector process."""

from __future__ import annotations

import logging
import os

LOGGER = logging.getLogger("car_detector")


def configure_logging() -> None:
    level = os.environ.get("LOG_LEVEL", "INFO").upper()
    logging.basicConfig(
        level=getattr(logging, level, logging.INFO),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
