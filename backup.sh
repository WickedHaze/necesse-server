#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Necesse world backup - backup.sh
# Tars the world/save directory, keeps the newest N backups, prunes the rest.
# Run standalone (sudo ./backup.sh) or via systemd timer (see setup.sh).
#
#   BACKUP_DIR  where archives land (default /root/necesse-backups)
#   KEEP        number of archives to retain (default 7)
# ---------------------------------------------------------------------------
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/necesse-server}"
BACKUP_DIR="${BACKUP_DIR:-/root/necesse-backups}"
KEEP="${KEEP:-7}"

# Layout: saves live under <install>/saves. If it doesn't exist, bail with a
# helpful message instead of silently tarring an empty dir.
if [[ ! -d "${INSTALL_DIR}/saves" ]]; then
    echo "[backup] ERROR: ${INSTALL_DIR}/saves not found. Is Necesse configured with -localdir? Aborting." >&2
    exit 1
fi

mkdir -p "$BACKUP_DIR"
STAMP="$(date +%Y-%m-%d_%H%M%S)"
AR="${BACKUP_DIR}/necesse-world-${STAMP}.tar.gz"

echo "[backup] Archiving ${INSTALL_DIR}/saves -> ${AR}"
tar czf "$AR" -C "$INSTALL_DIR" saves
echo "[backup] Done. Size: $(du -h "$AR" | cut -f1)"

# Retention: keep newest KEEP, remove older ones.
mapfile -t OLD < <(ls -1t "${BACKUP_DIR}"/necesse-world-*.tar.gz 2>/dev/null | tail -n +$((KEEP + 1)))
if [[ ${#OLD[@]} -gt 0 ]]; then
    for f in "${OLD[@]}"; do
        echo "[backup] Pruning $f"
        rm -f "$f"
    done
fi
echo "[backup] Retention: keeping newest $KEEP backup(s)."