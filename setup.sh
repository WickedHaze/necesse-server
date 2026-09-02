#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Necesse dedicated server - setup.sh
# Runs as root on a Debian/Ubuntu VPS. Installs SteamCMD + the dedicated
# server app (Steam app id 1169370) under /opt/necesse-server and creates
# the config + systemd unit.
#
# Usage:  sudo bash setup.sh
# ---------------------------------------------------------------------------
set -euo pipefail

STEAMAPPID="1169370"                 # Necesse dedicated server
INSTALL_DIR="/opt/necesse-server"    # force_install_dir target
RUN_USER="${RUN_USER:-necesse}"      # dedicated service account

SERVICE_FILE="/etc/systemd/system/necesse.service"
CFG_FILE="${INSTALL_DIR}/cfg/server.cfg"

PORT="${PORT:-14159}"
SLOTS="${SLOTS:-10}"
WORLD="${WORLD:-world}"
PASSWORD="${PASSWORD:-}"            # blank = no password
MOTD="${MOTD:-Necesse via SteamCMD (2GB VPS)}"

log() { echo -e "\033[1;32m[setup]\033[0m $*"; }
die() { echo -e "\033[1;31m[error]\033[0m $*"; exit 1; }

# --- root check -----------------------------------------------------------
[[ $EUID -eq 0 ]] || die "Run as root:  sudo bash setup.sh"

# --- distro detection -----------------------------------------------------
if command -v apt-get >/dev/null 2>&1; then
    PKG="apt-get"
elif command -v dnf >/dev/null 2>&1; then
    PKG="dnf"
elif command -v yum >/dev/null 2>&1; then
    PKG="yum"
else
    die "Unsupported package manager (need apt/dnf/yum)."
fi

# --- 32-bit libs needed by steamcmd --------------------------------------
log "Installing system dependencies (package manager: ${PKG})..."
if [[ "$PKG" == "apt-get" ]]; then
    dpkg --add-architecture i386
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        lib32gcc-s1 lib32stdc++6 libcurl4-gnutls-dev:i386 \
        wget curl tar \
        || apt-get install -y lib32gcc1 libstdc++6 libcurl4-openssl-dev:i386 wget curl tar
elif [[ "$PKG" == "dnf" ]]; then
    dnf install -y glibc.i686 libstdc++.i686 libcurl.i686 wget curl tar
else
    yum install -y glibc.i686 libstdc++.i686 libcurl.i686 wget curl tar
fi

# --- Java (Necesse server is Java-based) ----------------------------------
log "Ensuring a JRE is present..."
if command -v java >/dev/null 2>&1; then
    log "Java already installed: $(java -version 2>&1 | head -1)"
else
    if [[ "$PKG" == "apt-get" ]]; then
        apt-get install -y openjdk-17-jre-headless
    elif [[ "$PKG" == "dnf" ]]; then
        dnf install -y java-17-openjdk-headless
    else
        yum install -y java-17-openjdk-headless
    fi
fi

# --- steamcmd -------------------------------------------------------------
log "Installing SteamCMD to /usr/games/steamcmd ..."
if [[ ! -f "/usr/games/steamcmd" ]]; then
    if [[ "$PKG" == "apt-get" ]]; then
        echo steam steam/question select "I AGREE" | debconf-set-selections
        echo steam steam/license note '' | debconf-set-selections
        DEBIAN_FRONTEND=noninteractive apt-get install -y steamcmd || {
            log "steamcmd package not available; installing manually."
            mkdir -p /opt/steamcmd
            cd /opt/steamcmd
            wget -q https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
            tar xzf steamcmd_linux.tar.gz
            ln -sf /opt/steamcmd/steamcmd.sh /usr/local/bin/steamcmd
        }
    else
        mkdir -p /opt/steamcmd
        cd /opt/steamcmd
        wget -q https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
        tar xzf steamcmd_linux.tar.gz
        ln -sf /opt/steamcmd/steamcmd.sh /usr/local/bin/steamcmd
    fi
fi

# --- dedicated user -------------------------------------------------------
if ! id "$RUN_USER" >/dev/null 2>&1; then
    log "Creating user ${RUN_USER} ..."
    useradd --system --shell /usr/sbin/nologin --home /nonexistent "$RUN_USER"
fi

# --- install the server app ----------------------------------------------
ST=$(command -v steamcmd || command -v /usr/games/steamcmd || echo /usr/local/bin/steamcmd)
log "Installing Necesse dedicated server (app ${STEAMAPPID}) to ${INSTALL_DIR} ..."
mkdir -p "${INSTALL_DIR}"
chown -R "$RUN_USER":"$RUN_USER" "${INSTALL_DIR}"
STEAMCMD_CMD=""
[[ -f /usr/games/steamcmd ]] && STEAMCMD_CMD="/usr/games/steamcmd"
[[ -z "$STEAMCMD_CMD" && -f /usr/local/bin/steamcmd ]] && STEAMCMD_CMD="/usr/local/bin/steamcmd"
sudo -u "$RUN_USER" "$STEAMCMD_CMD" \
    +force_install_dir "$INSTALL_DIR" \
    +login anonymous \
    +app_update "$STEAMAPPID" validate \
    +quit

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

# Optional hardening
NoNewPrivileges=true
ProtectSystem=full
ReadWritePaths=${INSTALL_DIR}
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable necesse
systemctl start necesse

log "Done. Status:"
systemctl status necesse --no-pager || true

cat <<INFO

--------------------------------------------------------------------------
Necesse server installed and started.
  App ID      : ${STEAMAPPID}
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
  tail -f ${INSTALL_DIR}/logs/  (latest log)

Joining: in Necesse use "Join Game" -> server <PUBLIC_IP>:${PORT}
--------------------------------------------------------------------------
INFO