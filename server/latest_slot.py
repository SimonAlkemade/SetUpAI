"""A one-item mailbox where a newer item replaces the waiting one.

The model is slower than the 50 ms Godot sends at. A queue would grow and the
picture would fall further and further behind the camera; this keeps the lag
to at most one inference, whatever the model costs.
"""
from __future__ import annotations

import asyncio
from typing import Any


class LatestSlot:
    def __init__(self) -> None:
        self._item: Any = None
        self._full = False
        self._event = asyncio.Event()
        self.dropped = 0

    def put(self, item: Any) -> None:
        if self._full:
            self.dropped += 1
        self._item = item
        self._full = True
        self._event.set()

    async def get(self) -> Any:
        while not self._full:
            self._event.clear()
            await self._event.wait()
        item, self._item, self._full = self._item, None, False
        return item
