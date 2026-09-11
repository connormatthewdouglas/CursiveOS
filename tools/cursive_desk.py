#!/usr/bin/env python3
"""Desk control for the person sitting at the tester PC.

Popup stays. One window (status + stop) replaces the three Desktop files.
"""
from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path("/home/elizabeth/CursiveOS")
sys.path.insert(0, str(ROOT / "tools"))
from cursive_status import write_status  # noqa: E402
DESKTOP = Path("/home/elizabeth/Desktop")
STATE_DIR = ROOT / ".cursiveos" / "closed-loop"
STOP_PATH = STATE_DIR / "STOP"
PANEL_PATH = STATE_DIR / "panel.json"
PID_PATH = STATE_DIR / "panel.pid"
LAUNCHER = DESKTOP / "CursiveOS.desktop"

OLD_FILES = [
    DESKTOP / "CursiveOS status.txt",
    DESKTOP / "CURSIVOS IS MEASURING.txt",
    DESKTOP / "STOP CursiveOS.desktop",
]

LAUNCHER_BODY = """[Desktop Entry]
Type=Application
Name=CursiveOS
Comment=See if this computer is measuring, and stop it if you need it
Exec=env DISPLAY=:0 python3 /home/elizabeth/CursiveOS/tools/cursive_panel.py
Icon=utilities-system-monitor
Terminal=false
Categories=Utility;
"""


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def _notify(title: str, body: str, urgent: bool = False) -> None:
    env = os.environ.copy()
    env.setdefault("DISPLAY", ":0")
    env.setdefault("DBUS_SESSION_BUS_ADDRESS", "unix:path=/run/user/1000/bus")
    cmd = ["notify-send"]
    if urgent:
        cmd += ["-u", "critical"]
    cmd += [title, body]
    subprocess.run(cmd, env=env, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _write_panel(busy: bool, note: str) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    PANEL_PATH.write_text(
        json.dumps({"busy": busy, "note": note, "updated_at": now_iso()}, indent=2) + "\n",
        encoding="utf-8",
    )


def _clear_old_files() -> None:
    for path in OLD_FILES:
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def ensure_launcher() -> None:
    _clear_old_files()
    DESKTOP.mkdir(parents=True, exist_ok=True)
    LAUNCHER.write_text(LAUNCHER_BODY, encoding="utf-8")
    LAUNCHER.chmod(0o755)
    subprocess.run(
        ["gio", "set", str(LAUNCHER), "metadata::trusted", "true"],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def _panel_running() -> bool:
    if not PID_PATH.exists():
        return False
    try:
        pid = int(PID_PATH.read_text().strip())
        cmd = Path(f"/proc/{pid}/cmdline").read_bytes()
    except (OSError, ValueError):
        return False
    return b"cursive_panel.py" in cmd


def ensure_panel() -> None:
    ensure_launcher()
    if _panel_running():
        return
    env = os.environ.copy()
    env["DISPLAY"] = env.get("DISPLAY") or ":0"
    env["DBUS_SESSION_BUS_ADDRESS"] = env.get("DBUS_SESSION_BUS_ADDRESS") or "unix:path=/run/user/1000/bus"
    proc = subprocess.Popen(
        ["python3", str(ROOT / "tools" / "cursive_panel.py")],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
        cwd=str(ROOT),
    )
    PID_PATH.write_text(str(proc.pid), encoding="utf-8")


def mark_busy(note: str, parent: str | None = None, candidate: str | None = None) -> None:
    write_status(
        busy=True,
        note=note,
        parent=parent,
        candidate=candidate,
        step=0,
        total=10,
        label="Starting",
        counts={},
    )
    ensure_panel()
    _notify("CursiveOS is measuring", "Need this PC? Open CursiveOS and press Stop.", urgent=True)


def mark_free(note: str = "You can use this computer.") -> None:
    write_status(busy=False, note=note, candidate=None, step=0, label="Idle", counts={})
    ensure_launcher()
    _notify("CursiveOS", note, urgent=False)


def _pids(pattern: str) -> list[int]:
    me = os.getpid()
    found: list[int] = []
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        pid = int(entry.name)
        if pid == me:
            continue
        try:
            cmd = (entry / "cmdline").read_bytes().replace(b"\0", b" ").decode("utf-8", "replace")
        except (OSError, PermissionError):
            continue
        if "py_compile" in cmd or "cursive_desk.py" in cmd:
            continue
        if pattern in cmd and ("python" in cmd or "bash" in cmd):
            found.append(pid)
    return found


def _kill(pattern: str) -> None:
    for pid in _pids(pattern):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(1)
    for pid in _pids(pattern):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def undo_presets() -> None:
    presets = ROOT / "presets"
    scripts = [presets / "cursiveos-presets-v0.12.sh"]
    scripts.extend(sorted(presets.glob("cursiveos-presets-v0.13-*.sh")))
    for script in scripts:
        if script.exists():
            subprocess.run(
                ["bash", str(script), "--undo"],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )


def panic_stop() -> int:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    STOP_PATH.write_text("stop\n", encoding="utf-8")
    _kill("tools/closed_loop.py")
    _kill("seed_organism.py screen-variant")
    _kill("cursiveos-full-test")
    undo_presets()
    mark_free("Stopped. Settings put back. You can use this computer.")
    print("CursiveOS stopped. You can use this computer.")
    return 0


def is_busy() -> bool:
    panel = {}
    if PANEL_PATH.exists():
        try:
            panel = json.loads(PANEL_PATH.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            panel = {}
    return bool(panel.get("busy")) or bool(_pids("tools/closed_loop.py") or _pids("cursiveos-full-test"))


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    cmd = args[0] if args else "status"
    if cmd in {"busy", "mark-busy"}:
        mark_busy(args[1] if len(args) > 1 else "measuring")
        return 0
    if cmd in {"free", "mark-free"}:
        mark_free(args[1] if len(args) > 1 else "You can use this computer.")
        return 0
    if cmd in {"stop", "panic"}:
        return panic_stop()
    if cmd == "install":
        mark_free("CursiveOS control is on the Desktop.")
        ensure_panel()
        return 0
    if cmd == "panel":
        ensure_panel()
        return 0
    print("BUSY — open CursiveOS on the Desktop and press Stop." if is_busy() else "FREE — you can use this computer.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
