#!/usr/bin/env python3
"""Repository entry point for the published game shader compiler."""
from pathlib import Path
import runpy
import sys

TOOLS = Path(__file__).resolve().parents[2] / "platform/shader-tools"
sys.path.insert(0, str(TOOLS))
runpy.run_path(str(TOOLS / "build.py"), run_name="__main__")
