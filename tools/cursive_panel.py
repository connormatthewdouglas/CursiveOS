#!/usr/bin/env python3
"""Client-side CursiveOS window: status, progress, update, stop. Not the public app."""
from __future__ import annotations

import os
import sys
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402

ROOT = Path("/home/elizabeth/CursiveOS")
sys.path.insert(0, str(ROOT / "tools"))

from cursive_status import (  # noqa: E402
    git_info,
    git_update,
    next_from_ledger,
    next_from_library,
    read_status,
    write_status,
)

PID_PATH = ROOT / ".cursiveos" / "closed-loop" / "panel.pid"

CSS = b"""
window { background-color: #10141b; }
label { color: #e8eef6; font-family: Cantarell, sans-serif; }
.label-muted { color: #8b98ab; font-size: 13px; }
.label-title { font-size: 13px; color: #8b98ab; }
.label-status { font-size: 22px; font-weight: 600; }
.label-busy { color: #c4a574; }
.label-free { color: #6fb68a; }
.label-body { font-size: 14px; }
progressbar trough { min-height: 12px; background-color: #1c2330; border: none; border-radius: 6px; }
progressbar progress { background-color: #8aa4c1; border-radius: 6px; }
button.stop {
  background-image: none; background-color: #c97a80; color: #090b0f;
  font-weight: 600; font-size: 15px; min-height: 48px; border-radius: 10px; border: none;
}
button.stop:disabled { background-color: #1c2330; color: #667385; }
button.quiet {
  background-image: none; background-color: #1c2330; color: #e8eef6;
  min-height: 40px; border-radius: 10px; border: none;
}
"""


def _next_line() -> str:
    nxt = next_from_ledger() or next_from_library()
    if not nxt:
        return "Nothing lined up."
    src = "from the notebook" if nxt.get("source") == "ledger" else "next leftover on this machine"
    return f"{nxt.get('candidate')} vs {nxt.get('parent')} · {src}"


class Panel(Gtk.Window):
    def __init__(self) -> None:
        super().__init__(title="CursiveOS")
        self.set_default_size(420, 360)
        self.set_resizable(False)
        self.connect("destroy", Gtk.main_quit)
        self._updating = False

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=16)
        self.add(box)

        top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        kicker = Gtk.Label(label="CursiveOS", xalign=0)
        kicker.get_style_context().add_class("label-title")
        top.pack_start(kicker, True, True, 0)
        self.ver = Gtk.Label(label="", xalign=1)
        self.ver.get_style_context().add_class("label-muted")
        top.pack_start(self.ver, False, False, 0)
        box.pack_start(top, False, False, 0)

        self.status = Gtk.Label(label="…", xalign=0)
        self.status.get_style_context().add_class("label-status")
        box.pack_start(self.status, False, False, 0)

        self.now = Gtk.Label(label="", xalign=0, wrap=True)
        self.now.get_style_context().add_class("label-body")
        self.now.set_line_wrap(True)
        box.pack_start(self.now, False, False, 0)

        self.nxt = Gtk.Label(label="", xalign=0, wrap=True)
        self.nxt.get_style_context().add_class("label-muted")
        self.nxt.set_line_wrap(True)
        box.pack_start(self.nxt, False, False, 0)

        self.bar = Gtk.ProgressBar()
        self.bar.set_show_text(True)
        box.pack_start(self.bar, False, False, 4)

        self.stop_btn = Gtk.Button(label="Stop — give me this computer")
        self.stop_btn.get_style_context().add_class("stop")
        self.stop_btn.connect("clicked", self.on_stop)
        box.pack_start(self.stop_btn, False, False, 4)

        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.upd = Gtk.Button(label="Update from GitHub")
        self.upd.get_style_context().add_class("quiet")
        self.upd.connect("clicked", self.on_update)
        row.pack_start(self.upd, True, True, 0)
        hide = Gtk.Button(label="Hide")
        hide.get_style_context().add_class("quiet")
        hide.connect("clicked", lambda *_: self.iconify())
        row.pack_start(hide, False, False, 0)
        box.pack_start(row, False, False, 0)

        self.msg = Gtk.Label(label="", xalign=0, wrap=True)
        self.msg.get_style_context().add_class("label-muted")
        self.msg.set_line_wrap(True)
        box.pack_start(self.msg, False, False, 0)

        self.refresh()
        GLib.timeout_add(900, self.refresh)

    def refresh(self):
        if self._updating:
            return True
        st = read_status()
        busy = bool(st.get("busy"))
        self.set_keep_above(busy)
        ctx = self.status.get_style_context()
        ctx.remove_class("label-busy")
        ctx.remove_class("label-free")
        if busy:
            self.status.set_text("BUSY")
            ctx.add_class("label-busy")
            parent, cand = st.get("parent") or "parent", st.get("candidate") or "candidate"
            self.now.set_text(f"Now: {cand} vs {parent}")
            self.stop_btn.set_sensitive(True)
            self.stop_btn.set_label("Stop — give me this computer")
            self.upd.set_sensitive(False)
            self.present()
            step = int(st.get("step") or 0)
            total = int(st.get("total") or 10) or 10
            label = st.get("label") or "Measuring"
            self.bar.set_fraction(min(1.0, step / total))
            self.bar.set_text(f"{label}  ·  {step}/{total}")
        else:
            self.status.set_text("FREE")
            ctx.add_class("label-free")
            self.now.set_text("Now: nothing running. You can use this computer.")
            self.stop_btn.set_sensitive(False)
            self.stop_btn.set_label("Nothing to stop")
            self.upd.set_sensitive(True)
            self.bar.set_fraction(0)
            self.bar.set_text("Idle")
        self.nxt.set_text("Next: " + _next_line())
        g = st.get("git") or {}
        if not g.get("head"):
            g = git_info()
            write_status(git=g)
        extra = ""
        if g.get("behind"):
            extra = f" · {g['behind']} behind"
        elif g.get("dirty"):
            extra = " · local edits"
        self.ver.set_text(f"{g.get('head', '')}{extra}")
        return True

    def on_stop(self, _btn) -> None:
        self.stop_btn.set_sensitive(False)
        self.stop_btn.set_label("Stopping…")
        from cursive_desk import panic_stop

        panic_stop()
        self.refresh()

    def on_update(self, _btn) -> None:
        self._updating = True
        self.upd.set_sensitive(False)
        self.msg.set_text("Checking GitHub…")

        def work():
            note = git_update()
            write_status(git=git_info(), note=note)

            def done():
                self._updating = False
                self.msg.set_text(note)
                self.upd.set_sensitive(True)
                self.refresh()
                return False

            GLib.idle_add(done)
            return False

        GLib.timeout_add(50, work)


def main() -> int:
    PID_PATH.parent.mkdir(parents=True, exist_ok=True)
    PID_PATH.write_text(str(os.getpid()), encoding="utf-8")
    provider = Gtk.CssProvider()
    provider.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
    )
    win = Panel()
    win.show_all()
    Gtk.main()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
