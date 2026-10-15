import asyncio

from latest_slot import LatestSlot


async def test_get_returns_what_was_put():
    slot = LatestSlot()
    slot.put("a")
    assert await slot.get() == "a"


async def test_newer_item_replaces_waiting_one():
    slot = LatestSlot()
    slot.put(1)
    slot.put(2)
    slot.put(3)
    assert await slot.get() == 3
    assert slot.dropped == 2


async def test_get_waits_for_put():
    slot = LatestSlot()
    task = asyncio.create_task(slot.get())
    await asyncio.sleep(0.01)
    assert not task.done()
    slot.put("late")
    assert await asyncio.wait_for(task, 1) == "late"


async def test_slot_is_empty_after_get():
    slot = LatestSlot()
    slot.put(1)
    await slot.get()
    task = asyncio.create_task(slot.get())
    await asyncio.sleep(0.01)
    assert not task.done()
    task.cancel()
