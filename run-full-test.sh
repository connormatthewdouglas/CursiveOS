#!/usr/bin/env bash
cd /home/connor/TAO-OS
LOGFILE="logs/tao-os-full-test-$(date +%Y%m%d-%H%M%S).log"
echo "LOG=$LOGFILE"
bash tao-os-full-test-v1.3.sh > "$LOGFILE" 2>&1 &
BGPID=$!
echo "PID=$BGPID"
echo "$BGPID $LOGFILE" > /tmp/tao-fulltest-run.txt
wait $BGPID
echo "EXIT=$?"
