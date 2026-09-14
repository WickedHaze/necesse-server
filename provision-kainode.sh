#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# provvision-kainode.sh — Kainode blank-state baseline provisioning
# Runs as root on a FRESH Debian 12 / Ubuntu Kainode VPS. Brings a blank box to
# a known-good, hardened baseline: updated packages, non-root admin, SSH
# hardening to key-only, a basic firewall, fail2ban, and a drop-in location for
# app installs (like the Necesse server). Idempotent: safe to re-run.
#
# Usage:  sudo bash provvision-kainode.sh
#   Env:   ADMIN_USER (default: admin)  |  SSH_PUBKEY (required, your key)
# ---------------------------------------------------------------------------
set -euo pipefail

ADMIN_USER="${ADMIN_USER:-admin}"
SSH_PUBKEY="${SSH_PUBKEY:-}"

log(){ echo -e "\033[1;32m[kainode]\033[0m $*"; }
die(){ echo -e "\033[1;31m[kainode:error]\033[0m $*"; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root: sudo bash provvision-kainode.sh"
[[ -n "$SSH_PUBKEY" ]] || die "Set SSH_PUBKEY to your public key, e.g. SSH_PUBKEY='ssh-ed25519 AAAA... user'"

HOSTNAME_FB="$(hostname)"

# --- 1. system update + base packages -------------------------------------
log "Updating system + installing base tools..."
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl wget git vim htop fail2ban ufw \
    openssh-server ca-certificates gnupg

# --- 2. admin user + SSH key ----------------------------------------------
if ! id "$ADMIN_USER" >/dev/null 2>&1; then
    log "Creating admin user ${ADMIN_USER} ..."
    useradd -m -s /bin/bash -G sudo "$ADMIN_USER"
fi
install -d -m700 /home/"$ADMIN_USER"/.ssh
touch /home/"$ADMIN_USER"/.ssh/authorized_keys
grep -qF "$SSH_PUBKEY" /home/"$ADMIN_USER"/.ssh/authorized_keys || \
    echo "$SSH_PUBKEY" >> /home/"$ADMIN_USER"/.ssh/authorized_keys
chown -R "$ADMIN_USER":"$ADMIN_USER" /home/"$ADMIN_USER"/.ssh
chmod 600 /home/"$ADMIN_USER"/.ssh/authorized_keys
# allow admin sudo without password prompt (comfortable for a single-user box)
echo "$ADMIN_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/"$ADMIN_USER"
chmod 440 /etc/sudoers.d/"$ADMIN_USER"
log "Admin user ${ADMIN_USER} configured with your SSH key."

# --- 3. SSH hardening: key-only, no root password login --------------------
log "Hardening SSH (key-only)..."
sed -i 's/^[# ]*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^[# ]*PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/^[# ]*PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sshd -t && systemctl reload ssh || log "WARN: sshd config not reloadable; check manually"

# --- 4. firewall -----------------------------------------------------------
log "Configuring UFW (allow ssh, deny rest)..."
ufw allow OpenSSH
ufw --force enable
log "Port 22 (SSH) open; everything else denied by default."

# --- 5. fail2ban -----------------------------------------------------------
log "Enabling fail2ban..."
systemctl enable --now fail2ban

# --- 6. time sync -----------------------------------------------------------
log "Ensuring chrony/ntp is present..."
if command -v chronyd >/dev/null 2>&1 || command -v chrony >/dev/null 2>&1; then
    systemctl enable --now chrony 2>/dev/null || true
else
    DEBIAN_FRONTEND=noninteractive apt-get install -y chrony >/dev/null 2>&1 && \
        systemctl enable --now chrony || true
fi

log "Done. Baseline provisioned."
cat <<INFO

--------------------------------------------------------------------------
Kainode blank-state baseline is ready.
  Hostname : ${HOSTNAME_FB}
  Admin    : ${ADMIN_USER}  (SSH key auth, password auth OFF, root pw login OFF)
  Firewall : ufw active, only SSH port 22 open
  fail2ban : enabled
  Updates  : applied

SSH in as ${ADMIN_USER}:
  ssh ${ADMIN_USER}@<IP>

You are now free to deploy apps under this baseline (e.g. run the Necesse
server, a web service, a discord bot). Drop-in `/opt` is a good install root.
--------------------------------------------------------------------------
INFO