import serial
import time
import sys

PORT = "COM5"
BAUD = 115200
DURATION = 50

def hard_reset(ser):
    ser.dtr = False
    ser.rts = True
    time.sleep(0.1)
    ser.rts = False
    time.sleep(0.05)
    ser.dtr = True
    time.sleep(0.1)
    ser.dtr = False

try:
    ser = serial.Serial(PORT, BAUD, timeout=0.1)
except Exception as e:
    print(f"OPEN_FAIL: {e}", file=sys.stderr)
    sys.exit(2)

ser.reset_input_buffer()
hard_reset(ser)
print(f"--- CAPTURE {DURATION}s on {PORT} after RTS reset ---", flush=True)
deadline = time.time() + DURATION
while time.time() < deadline:
    chunk = ser.read(4096)
    if chunk:
        text = chunk.decode("utf-8", errors="replace")
        sys.stdout.write(text)
        sys.stdout.flush()
ser.close()
print("--- END CAPTURE ---", flush=True)
