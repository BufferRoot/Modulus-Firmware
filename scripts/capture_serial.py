"""Raw Tab5 serial capture — writes everything (panic dumps included) to a file.

Usage: python scripts/capture_serial.py COM5 20 logs/boot.txt
"""

import sys
import time

import serial


def main() -> int:
    port = sys.argv[1] if len(sys.argv) > 1 else "COM5"
    seconds = float(sys.argv[2]) if len(sys.argv) > 2 else 20.0
    out_path = sys.argv[3] if len(sys.argv) > 3 else "serial_capture.txt"

    with serial.Serial(port, 115200, timeout=0.2) as ser:
        # Toggle DTR/RTS to reset the board so we capture from the first boot line.
        ser.setDTR(False)
        ser.setRTS(True)
        time.sleep(0.1)
        ser.setRTS(False)
        time.sleep(0.1)

        chunks = []
        deadline = time.time() + seconds
        while time.time() < deadline:
            data = ser.read(4096)
            if data:
                chunks.append(data)

    raw = b"".join(chunks)
    text = raw.decode("utf-8", errors="replace")
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write(text)
    print(f"captured {len(raw)} bytes -> {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
