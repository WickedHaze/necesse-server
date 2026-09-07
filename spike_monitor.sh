#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Necesse CPU spike monitor - spike_monitor.sh
# Watches the server's total CPU and java-process CPU; whenever utilization
# jumps above a threshold, appends a snapshot (top consumers + game log tail)
# to a log so you can see what caused the spike. Runs as a loop; stop with
# systemd or kill. Deployed to /opt/necesse-spike-monitor.sh.
#
#   SPIKE_THRESH  java %%CPU threshold that counts as a spike (default 80)
#   MONITOR_LOG   where snapshots append (default /root/cpu-spikes.log)
# ---------------------------------------------------------------------------
set -u
SPIKE_THRESH="${SPIKE_THRESH:-80}"
MONITOR_LOG="${MONITOR_LOG:-/root/cpu-spikes.log}"
GAME_DIR="/opt/necesse-server"

log(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$MONITOR_LOG"; }

log "=== spike monitor started (threshold ${SPIKE_THRESH}% CPU) ==="

while true; do
  # Idle % = number preceding "id," in the Cpu(s) line (robust across field changes)
  IDLE=$(top -bn1 | grep 'Cpu(s)' | grep -oE '[0-9.]+ id' | grep -oE '[0-9.]+' | head -1)
  # Java process CPU% = the value in the %CPU column. Use ps for a stable parse.
  JAVA=$(ps -eo pcpu,comm | awk '/java/ && !/awk/ && !/grep/ {print $1; exit}')
  IDLE_N=$(echo "$IDLE" | tr -d '%')
  JAVA_N=$(echo "$JAVA" | tr -d '%')
  BUSY=$(python3 -c "print(round(100-float('${IDLE_N:-100}'),1))" 2>/dev/null || echo 0)

  if [ "${BUSY%.*}" -ge "$SPIKE_THRESH" ] || [ "${JAVA_N%.*}" -ge "$SPIKE_THRESH" ]; then
    log "SPIKE (busy%=${BUSY}, java%=${JAVA_N})"
    log "--- top consumers ---"
    ps -eo pcpu,pmem,comm --sort=-pcpu | head -6 >> "$MONITOR_LOG"
    log "--- load ---"
    cat /proc/loadavg >> "$MONITOR_LOG"
    log "--- game log tail ---"
    LG=$(ls -t "$GAME_DIR"/*.txt 2>/dev/null | head -1)
    if [ -n "$LG" ]; then
      tail -n 20 "$LG" >> "$MONITOR_LOG"
    fi
    log "----------------------------"
  fi
  sleep 5
done