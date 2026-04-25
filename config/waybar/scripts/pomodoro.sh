#!/bin/bash
STATE_FILE="/tmp/pomodoro_state"

if [ ! -f "$STATE_FILE" ]; then
  echo "POMO --:--"
  exit 0
fi

source "$STATE_FILE"

if [ "$RUNNING" = "false" ]; then
  echo "POMO --:--"
  exit 0
fi

NOW=$(date +%s)
ELAPSED=$((NOW - START_TIME))
REMAINING=$((DURATION - ELAPSED))

if [ $REMAINING -le 0 ]; then
  echo "POMO 00:00"
  exit 0
fi

MIN=$((REMAINING / 60))
SEC=$((REMAINING % 60))
printf "POMO %02d:%02d\n" $MIN $SEC
