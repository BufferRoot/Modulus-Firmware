#!/usr/bin/env python3
"""Capture serial monitor output for N seconds after RTS reset."""
import sys
import time

import serial


def main() -> int:
    if len(sys.argv) != 4:
        print(f"usage: {sys.argv[0]} PORT OUTFILE SECONDS", file=sys.stderr)
        return 2

    port = sys.argv[1]
    out_path = sys.argv[2]
    duration = float(sys.argv[3])

    ser = serial.Serial(port, 115200, timeout=0.5)
    ser.dtr = False
    ser.rts = True
    time.sleep(0.05)
    ser.rts = False
    time.sleep(0.05)
    ser.dtr = True
    time.sleep(0.05)
    ser.dtr = False

    chunks: list[str] = []
    start = time.time()
    while time.time() - start < duration:
        data = ser.read(4096)
        if data:
            text = data.decode("utf-8", errors="replace")
            chunks.append(text)
            print(text, end="", flush=True)
    ser.close()

    with open(out_path, "w", encoding="utf-8") as f:
        f.write("".join(chunks))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
