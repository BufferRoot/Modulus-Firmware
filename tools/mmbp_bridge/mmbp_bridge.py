#!/usr/bin/env python3
"""Modulus MMBP Telnet bridge for Mach3/Mach4.

Speaks the text protocol expected by Tab5 Mach3 client (HELLO / GET STATUS|POS|OVR / CMD …).
Default backend is an in-process mock (for bench without Mach). Optional win32com Mach3/4.

Usage:
  python mmbp_bridge.py [--port 7878] [--backend mock|mach3]
  On the pendant: MCS=Mach3/Mach4, Transport=Telnet, host=PC IP, port=7878.
"""
from __future__ import annotations

import argparse
import asyncio
import math
import time
from dataclasses import dataclass, field


@dataclass
class Machine:
    state: str = "IDLE"
    enabled: int = 1
    estop: int = 0
    x: float = 0.0
    y: float = 0.0
    z: float = 0.0
    feed_ovr: int = 100
    spindle_ovr: int = 100
    rapid_ovr: int = 100
    spindle_rpm: float = 0.0
    spindle_dir: str = "OFF"
    flood: bool = False
    mist: bool = False


class Backend:
    def status_line(self) -> str: ...
    def pos_line(self) -> str: ...
    def ovr_line(self) -> str: ...
    def handle_cmd(self, parts: list[str]) -> str: ...


class MockBackend(Backend):
    def __init__(self) -> None:
        self.m = Machine()

    def status_line(self) -> str:
        m = self.m
        dir_tok = f"SPINDLE_DIR={m.spindle_dir}"
        return (
            f"STATUS {m.state} ENABLED={m.enabled} ESTOP={m.estop} "
            f"SPINDLE_RPM={int(m.spindle_rpm)} {dir_tok}"
        )

    def pos_line(self) -> str:
        m = self.m
        return f"POS X={m.x:.4f} Y={m.y:.4f} Z={m.z:.4f}"

    def ovr_line(self) -> str:
        m = self.m
        return f"OVR FEED={m.feed_ovr} SPINDLE={m.spindle_ovr} RAPID={m.rapid_ovr}"

    def handle_cmd(self, parts: list[str]) -> str:
        if not parts:
            return "ERR EMPTY"
        op = parts[0].upper()
        m = self.m
        if op == "CYCLE_START":
            m.state = "RUN"
            return "OK"
        if op == "FEED_HOLD":
            m.state = "HOLD"
            return "OK"
        if op == "STOP":
            m.state = "IDLE"
            m.spindle_rpm = 0
            m.spindle_dir = "OFF"
            return "OK"
        if op == "RESET":
            m.state = "IDLE"
            m.estop = 1
            m.enabled = 0
            return "OK"
        if op == "UNLOCK":
            m.estop = 0
            m.enabled = 1
            m.state = "IDLE"
            return "OK"
        if op == "HOME":
            m.state = "HOME"
            m.x = m.y = m.z = 0.0
            m.state = "IDLE"
            return "OK"
        if op == "JOG" and len(parts) >= 4:
            axis = parts[1]
            dist = float(parts[2])
            sign = 1.0 if "+" in axis or axis.endswith("+") else -1.0
            letter = axis[0].upper()
            d = abs(dist) * sign
            if letter == "X":
                m.x += d
            elif letter == "Y":
                m.y += d
            elif letter == "Z":
                m.z += d
            m.state = "JOG"
            return "OK"
        if op == "JOG_CONT":
            m.state = "JOG"
            return "OK"
        if op == "JOG_STOP":
            m.state = "IDLE"
            return "OK"
        if op == "FEED_OVR" and len(parts) >= 2:
            m.feed_ovr = int(parts[1])
            return "OK"
        if op == "SPINDLE_OVR" and len(parts) >= 2:
            m.spindle_ovr = int(parts[1])
            return "OK"
        if op == "FLOOD" and len(parts) >= 2:
            m.flood = parts[1].upper() == "ON"
            return "OK"
        if op == "MIST" and len(parts) >= 2:
            m.mist = parts[1].upper() == "ON"
            return "OK"
        if op == "SPINDLE" and len(parts) >= 2 and parts[1].upper() == "STOP":
            m.spindle_rpm = 0
            m.spindle_dir = "OFF"
            return "OK"
        if op == "MDI" and len(parts) >= 2:
            line = " ".join(parts[1:])
            if "M3" in line.upper() or "M4" in line.upper():
                m.spindle_dir = "CW" if "M3" in line.upper() else "CCW"
                m.spindle_rpm = 12000
            if "M5" in line.upper():
                m.spindle_dir = "OFF"
                m.spindle_rpm = 0
            return "OK"
        return "ERR UNKNOWN"


class Mach3Backend(Backend):
    """Optional OLE automation — requires pywin32 + Mach running."""

    def __init__(self) -> None:
        try:
            import win32com.client  # type: ignore
        except ImportError as e:
            raise SystemExit("mach3 backend needs pywin32: pip install pywin32") from e
        self._com = win32com.client
        self._mach = None
        for prog in ("Mach4.Document", "Mach4CNC", "Mach3.Document"):
            try:
                self._mach = self._com.Dispatch(prog)
                break
            except Exception:
                continue
        if self._mach is None:
            raise SystemExit("Could not Dispatch Mach3/Mach4 COM object")

    def status_line(self) -> str:
        # Best-effort; COM layouts vary by install.
        return "STATUS IDLE ENABLED=1 ESTOP=0 SPINDLE_RPM=0 SPINDLE_DIR=OFF"

    def pos_line(self) -> str:
        try:
            x = float(self._mach.GetOEMDRO(800))
            y = float(self._mach.GetOEMDRO(801))
            z = float(self._mach.GetOEMDRO(802))
            return f"POS X={x:.4f} Y={y:.4f} Z={z:.4f}"
        except Exception:
            return "POS X=0 Y=0 Z=0"

    def ovr_line(self) -> str:
        return "OVR FEED=100 SPINDLE=100 RAPID=100"

    def handle_cmd(self, parts: list[str]) -> str:
        return "OK"


async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, backend: Backend) -> None:
    peer = writer.get_extra_info("peername")
    print(f"[+] client {peer}")
    try:
        while True:
            line_b = await reader.readline()
            if not line_b:
                break
            line = line_b.decode("ascii", errors="ignore").strip()
            if not line:
                continue
            parts = line.split()
            cmd = parts[0].upper()
            reply: str
            if cmd == "HELLO":
                reply = "HELLO ACK Mach3"
            elif cmd == "GET" and len(parts) >= 2:
                sub = parts[1].upper()
                if sub == "STATUS":
                    reply = backend.status_line()
                elif sub == "POS":
                    reply = backend.pos_line()
                elif sub == "OVR":
                    reply = backend.ovr_line()
                else:
                    reply = "ERR GET"
            elif cmd == "CMD":
                reply = backend.handle_cmd(parts[1:])
            else:
                reply = "ERR UNKNOWN"
            writer.write((reply + "\n").encode("ascii"))
            await writer.drain()
    finally:
        writer.close()
        await writer.wait_closed()
        print(f"[-] client {peer}")


async def main_async(port: int, backend_name: str) -> None:
    backend: Backend
    if backend_name == "mach3":
        backend = Mach3Backend()
    else:
        backend = MockBackend()
    server = await asyncio.start_server(
        lambda r, w: handle_client(r, w, backend), "0.0.0.0", port
    )
    addrs = ", ".join(str(s.getsockname()) for s in server.sockets or [])
    print(f"MMBP bridge listening on {addrs} backend={backend_name}")
    async with server:
        await server.serve_forever()


def main() -> None:
    ap = argparse.ArgumentParser(description="Modulus MMBP Telnet bridge")
    ap.add_argument("--port", type=int, default=7878)
    ap.add_argument("--backend", choices=("mock", "mach3"), default="mock")
    args = ap.parse_args()
    asyncio.run(main_async(args.port, args.backend))


if __name__ == "__main__":
    main()
