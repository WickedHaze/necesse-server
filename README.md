# Necesse Dedicated Server — SteamCMD (Linux VPS)

Deploy a Necesse dedicated server on a $5 Linux VPS (2GB RAM is plenty) using
SteamCMD and systemd. No Docker, no game-panel lock-in; you own the box and can
run a Discord bot or backup cron alongside it.

Runs the dedicated server app (Steam app id **1169370**) with the stock
`StartServer-nogui.sh` launcher, managed by systemd so it auto-starts on boot
and restarts on crash.

---

## What's in here

| File | Purpose |
|------|---------|
| `setup.sh` | One-shot root installer. Installs SteamCMD + Java + the server app, writes `cfg/server.cfg`, creates a `necesse` user, and registers a systemd service. |
| `README.md` | This file. |

Default config: port `14159/udp`, 10 slots, world named `world`, no password.
Override via env vars when running `setup.sh`, e.g.
`WORLD=myserver SLOTS=6 PORT=25000 PASSWORD=secret sudo bash setup.sh`.

---

## The 5-step plan (your end)

1. **Rent a VPS** — Hetzner CX11 (2GB / 1 vCPU / 20GB) ≈ $4.85/mo, or a
   LowEndBox flash deal. Pick **Debian 12** (or Ubuntu 22.04/24.04).
2. **Get the IP + root password/SSH key** from your provider's panel.
3. **Copy these files to the server.** From your PC:
   ```
   scp setup.sh root@<SERVER_IP>:~/
   ssh root@<SERVER_IP>
   ```
4. **Run the installer:**
   ```
   sudo bash setup.sh
   ```
   It downloads ~a few hundred MB (SteamCMD + game), so give it a couple
   minutes the first time.
5. **Open the firewall port** (UDP 14159):
   ```
   sudo ufw allow 14159/udp
   # or, if no ufw:
   sudo iptables -A INPUT -p udp --dport 14159 -j ACCEPT
   ```

Then join in game via **Join Game → server `<SERVER_IP>:14159`**.

---

## Control

| Action | Command |
|--------|---------|
| Status | `sudo systemctl status necesse` |
| Restart | `sudo systemctl restart necesse` |
| Stop | `sudo systemctl stop necesse` |
| Start on boot | already enabled |
| Watch logs | `ls ${INSTALL_DIR:-/opt/necesse-server}/logs/` then `tail -f .../latest.log` |
| Update server app | re-run `sudo bash setup.sh` (SteamCMD `validate` re-fetches) |

---

## Editing config

Config lives at `/opt/necesse-server/cfg/server.cfg` (a Lua-style table).
The game reads it on start. After editing, `sudo systemctl restart necesse`.

Notable options:
- `password = "..."` — set a server password (blank = public)
- `slots = N` — max players
- `pauseWhenEmpty = true` — pause simulation when nobody's online (saves CPU)

---

## Tuning for 2GB RAM

The server is Java-based. systemd unit intentionally uses the default heap so
it stays under your 2GB. If you run other services too and see memory pressure,
add to the `[Service]` section:
```
Environment=JAVA_OPTS=-Xmx900M -Xms512M
```
then restart. StartServer-nogui.sh honors `JAVA_OPTS` in most builds.

---

## Notes / caveats

- **SteamCMD needs 32-bit libs** — `setup.sh` installs them automatically
  (`lib32gcc`, `lib32stdc++`, 32-bit curl).
- The install dir is **`/opt/necesse-server`** via SteamCMD `+force_install_dir`.
  Your client PC never needs Steam running for this to work.
- Save files live under the install dir; back them up (see below).

### Simple world backup (cron)
```
sudo crontab -e
# add:
0 3 * * * tar czf /root/necesse-backup-$(date +\%F).tar.gz /opt/necesse-server/saves
```
Keep the last several: `ls -t /root/necesse-backup-*.tar.gz | tail -n +8 | xargs -r rm --`