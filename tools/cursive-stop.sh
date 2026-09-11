#!/usr/bin/env bash
set -u
export DISPLAY="${DISPLAY:-:0}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/1000/bus}"
python3 /home/elizabeth/CursiveOS/tools/cursive_desk.py stop
