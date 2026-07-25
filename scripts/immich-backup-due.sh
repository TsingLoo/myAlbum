#!/usr/bin/env bash
set -Eeuo pipefail

# Run on even ISO week numbers. The timer invokes this every Tuesday, producing
# a stable two-week cadence while still using a calendar-based 04:00 schedule.
week=$(date +%V)
((10#${week} % 2 == 0))
