"""Shared test fixtures."""

from __future__ import annotations

from pathlib import Path

import pytest


@pytest.fixture
def nonexistent_path(tmp_path: Path) -> str:
    """A path inside tmp_path that does not exist."""
    return str(tmp_path / "does_not_exist.pdf")
