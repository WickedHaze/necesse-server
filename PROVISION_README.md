# Kainode blank-state provisioning

Run this on a **fresh Debian 12 / Ubuntu Kainode VPS** to bring it to a
known-good baseline: up-to-date packages, a non-root `admin` user with sudo,
SSH hardened to key-only, UFW with only SSH open, fail2ban, and time sync.
Apps (like the Necesse server) are meant to be deployed *on top* of this
baseline afterward.

## Status: PARKED

Reference script. It documents how we baseline a blank Kainode box so anyone
can reproduce the same secure starting state later. Not part of any active
deploy flow on `main`.

## Usage

```bash
# on the fresh box
scp provision-kainode.sh root@<IP>:~/
ssh root@<IP>
sudo bash provision-kainode.sh

# with your SSH key inline:
sudo SSH_PUBKEY='ssh-ed25519 AAAA...you@host' ADMIN_USER=admin bash provision-kainode.sh
```

> After it runs, SSH password auth and root password-login are OFF. **You must
> have a reachable SSH key on the box** or you'll lock yourself out. The script
> installs the key you provide BEFORE touching sshd_config, so it's safe as
> long as you pass a valid `SSH_PUBKEY`.

## What it does

| Step | Action |
|------|--------|
| System | `apt update` + `upgrade`, installs `curl wget git vim htop fail2ban ufw` |
| Admin user | creates `admin` (default), adds sudo (passwordless), installs your SSH key |
| SSH | `PasswordAuthentication no`, `PermitRootLogin prohibit-password`, `PubkeyAuthentication yes` |
| Firewall | `ufw allow OpenSSH; ufw enable` (only port 22) |
| fail2ban | enabled on boot |
| Time | chrony enabled if available |

## Idempotent
Re-runs are safe: packages are already installed, the key is only appended if
absent, user/sudo are only created once.

## Options (env vars)
- `ADMIN_USER` — admin account name (default `admin`)
- `SSH_PUBKEY` — your public key, **required**