#!/usr/bin/env python3
"""Entrada operacional do simulador da oficina."""

import pathlib
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from scripts.simulator.oficina_simulator import main  # noqa: E402


if __name__ == "__main__":
    raise SystemExit(main())
