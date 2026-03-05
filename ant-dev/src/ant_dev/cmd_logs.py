"""``ant dev logs`` — Show antd daemon logs."""

from __future__ import annotations

import sys
import time

from .env import LOG_FILE


def run(args) -> None:
    if not LOG_FILE.exists():
        print("No log file found. Is the local environment running?")
        print("  ant dev start")
        sys.exit(1)

    if args.follow:
        _tail_follow()
    else:
        print(LOG_FILE.read_text(errors="replace"))


def _tail_follow() -> None:
    """Stream the log file, similar to ``tail -f``."""
    print(f"Following {LOG_FILE} (Ctrl+C to stop)\n")
    try:
        with open(LOG_FILE, "r", errors="replace") as f:
            # Seek to end
            f.seek(0, 2)
            while True:
                line = f.readline()
                if line:
                    print(line, end="")
                else:
                    time.sleep(0.5)
    except KeyboardInterrupt:
        print("\nStopped.")
