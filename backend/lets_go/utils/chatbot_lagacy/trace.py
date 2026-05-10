import os
import time
import threading
from typing import Any


_TRACE_ENABLED = (os.getenv('LETS_GO_BOT_TRACE') or '').strip() in {'1', 'true', 'True', 'yes', 'on'}


def trace(event: str, **data: Any) -> None:
    if not _TRACE_ENABLED:
        return
    try:
        ts = time.strftime('%H:%M:%S')
        tid = threading.get_ident()
        parts = [f"{k}={data[k]!r}" for k in sorted(data.keys())]
        payload = (' ' + ' '.join(parts)) if parts else ''
        print(f"[bot-trace {ts} tid={tid}] {event}{payload}")
    except Exception:
        # Never let tracing break the bot.
        return
