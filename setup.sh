#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Necesse dedicated server - setup.sh
# Runs as root on a Debian/Ubuntu VPS. Downloads the official Linux64 server
# zip directly from necessegame.com/server (no SteamCMD), extracts it to
# /opt/necesse-server, writes cfg/server.cfg, creates a service account, and
# registers a systemd unit + daily world-backup timer.
#
# Usage:  sudo bash setup.sh
#   Env:   PORT  SLOTS  WORLD  PASSWORD  MOTD   (optional overrides)
# ---------------------------------------------------------------------------
set -euo pipefail

INSTALL_DIR="/opt/necesse-server"
RUN_USER="${RUN_USER:-necesse}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SH="${SCRIPT_DIR}/backup.sh"
BACKUP_DIR="/root/necesse-backups"

SERVICE_FILE="/etc/systemd/system/necesse.service"
CFG_FILE="${INSTALL_DIR}/cfg/server.cfg"

PORT="${PORT:-14159}"
SLOTS="${SLOTS:-10}"
WORLD="${WORLD:-world}"
PASSWORD="${PASSWORD:-}"                 # blank = no password
MOTD="${MOTD:-WickedHaze Necesse server}"

log() { echo -e "\033[1;32m[setup]\033[0m $*"; }
die() { echo -e "\033[1;31m[error]\033[0m $*"; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root:  sudo bash setup.sh"
command -v unzip >/dev/null 2>&1 || { apt-get update -y; apt-get install -y unzip; }
command -v file >/dev/null 2>&1 || apt-get install -y file
command -v python3 >/dev/null 2>&1 || apt-get install -y python3
command -v wget >/dev/null 2>&1 || apt-get install -y wget tar unzip

# --- dedicated service account -------------------------------------------
if ! id "$RUN_USER" >/dev/null 2>&1; then
    log "Creating user ${RUN_USER} ..."
    useradd --system --shell /usr/sbin/nologin --home /var/lib/necesse "$RUN_USER"
    mkdir -p /var/lib/necesse && chown "$RUN_USER":"$RUN_USER" /var/lib/necesse
fi

# --- download + extract the server ---------------------------------------
log "Fetching latest Linux64 server build from necessegame.com/server ..."
mkdir -p /tmp/necesse-dl
# Reuse an existing, already-valid zip to avoid re-downloading (network can be
# flaky). Otherwise fetch page+URL+download all in Python so the S3 presigned
# URL is preserved byte-for-byte (shell quoting mangles &, /, + -> 400 errors).
if [[ ! -s /tmp/necesse-dl/server.zip ]]; then
    python3 - <<'PYD'
import re, urllib.request, os
UA = {"User-Agent": "Mozilla/5.0"}
req = urllib.request.Request("https://necessegame.com/server", headers=UA)
page = urllib.request.urlopen(req, timeout=60).read().decode("utf-8", "replace")
# Pin to the newest version's URL. A bare wildcard can match an OLD version
# link whose S3 presigned signature has expired -> SignatureDoesNotMatch/400.
# Find ALL linux64 hrefs and take the first (page lists newest first).
matches = re.findall(r'href="([^"]*necesse-server-linux64-\d[^"]*)"', page)
if not matches:
    raise SystemExit("could not locate linux64 URL")
url = matches[0].replace("&amp;", "&")
req2 = urllib.request.Request(url, headers=UA)
data = urllib.request.urlopen(req2, timeout=180).read()
os.makedirs("/tmp/necesse-dl", exist_ok=True)
with open("/tmp/necesse-dl/server.zip", "wb") as f:
    f.write(data)
print("downloaded", len(data), "bytes")
PYD
fi
[[ -s /tmp/necesse-dl/server.zip ]] || die "Download produced an empty file"
[[ "$(file -b /tmp/necesse-dl/server.zip)" == Zip* ]] || die "Download was not a valid zip (got: $(file -b /tmp/necesse-dl/server.zip))"

rm -rf "$INSTALL_DIR"
mkdir -p "$(dirname "$INSTALL_DIR")"
log "Extracting to ${INSTALL_DIR} ..."
unzip -q /tmp/necesse-dl/server.zip -d /tmp/necesse-dl
SRC="$(find /tmp/necesse-dl -maxdepth 2 -type d -name 'necesse-server-*' | head -1)"
[[ -n "$SRC" ]] || die "Could not locate extracted server directory"
mv "$SRC" "$INSTALL_DIR"
rm -rf /tmp/necesse-dl

# server binary must be executable; ship bundled JRE at jre/ (no system Java needed)
chmod +x "${INSTALL_DIR}"/StartServer*.sh "${INSTALL_DIR}"/jre/bin/java
chown -R "$RUN_USER":"$RUN_USER" "$INSTALL_DIR"

# --- config ---------------------------------------------------------------
log "Writing ${CFG_FILE} ..."
mkdir -p "$(dirname "$CFG_FILE")"
cat > "$CFG_FILE" <<CFG
SERVER = {
    port = ${PORT}, // [0 - 65535] Server default port
    slots = ${SLOTS}, // [1 - 250] Server default slots
    password = "${PASSWORD}", // Leave blank for no password
    maxClientLatencySeconds = 30,
    pauseWhenEmpty = true,
    giveClientsPower = true,
    logging = true,
    language = en,
    zipSaves = true,
    MOTD = "${MOTD}"
}
CFG
chown -R "$RUN_USER":"$RUN_USER" "${INSTALL_DIR}"

# --- systemd unit ---------------------------------------------------------
log "Installing systemd unit ${SERVICE_FILE} ..."
cat > "$SERVICE_FILE" <<UNIT
[Unit]
Description=Necesse Dedicated Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_USER}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/StartServer-nogui.sh -localdir -world ${WORLD}
Restart=on-failure
RestartSec=5
KillSignal=SIGINT
TimeoutStopSec=60
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
UNIT

# --- backup unit + timer (daily world backups, keep 7) --------------------
log "Installing backup service + timer..."
BACKUP_BIN="/opt/necesse-backup.sh"
install -m 0755 "${BACKUP_SH}" "${BACKUP_BIN}" || \
    log "WARN: could not copy backup.sh. Copy manually to ${BACKUP_BIN}."
cat > /etc/systemd/system/necesse-backup.service <<UNIT
[Unit]
Description=Necesse world backup

[Service]
Type=oneshot
ExecStart=/bin/bash ${BACKUP_BIN}
User=root
UNIT
cat > /etc/systemd/system/necesse-backup.timer <<UNIT
[Unit]
Description=Daily Necesse world backup

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable necesse necesse-backup.timer
systemctl start necesse
systemctl start necesse-backup.timer

log "Done. Status:"
systemctl status necesse --no-pager || true

cat <<INFO

--------------------------------------------------------------------------
Necesse server installed and started.
  Install dir : ${INSTALL_DIR}
  World name  : ${WORLD}
  Port        : ${PORT}/udp   (open this in your firewall)
  MOTD        : "${MOTD}"

Open the UDP port (default 14159):
  sudo ufw allow ${PORT}/udp                          # if using ufw
  sudo iptables -A INPUT -p udp --dport ${PORT} -j ACCEPT

Control:
  sudo systemctl stop/start/restart necesse
  sudo systemctl status necesse
  tail -f ${INSTALL_DIR}/logs/   (latest log)

Joining: in Necesse "Join Game" -> <PUBLIC_IP>:${PORT}
Backups: daily 03:00 UTC -> ${BACKUP_DIR}  (keep newest 7)
--------------------------------------------------------------------------
INFO