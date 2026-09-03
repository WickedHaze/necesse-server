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
| `setup.sh` | One-shot root installer. Installs SteamCMD + Java + the server app, writes `cfg/server.cfg`, creates a `necesse` user, registers a systemd service, and sets up the daily backup timer. |
| `backup.sh` | World backup script: tars `<install>/saves`, keeps the newest `KEEP` (7) archives. Wired into a systemd timer by `setup.sh`, runnable standalone. |
| `README.md` | This file. |

Default config: port `14159/udp`, 10 slots, world named `world`, no password.
Override via env vars when running `setup.sh`, e.g.
`WORLD=myserver SLOTS=6 PORT=25000 PASSWORD=secret sudo bash setup.sh`.

`setup.sh` also installs a **daily world backup** (systemd timer, 03:00, keeps
the last 7, script at `/opt/necesse-backup.sh`). Config via env vars on the
backup run: `BACKUP_DIR` (default `/root/necesse-backups`), `KEEP` (default 7).

---

## The 5-step plan (your end)

1. **Rent a VPS** — Kainode Singapore **VPS Pro** (2 vCPU / 4GB / 60GB,
   $6.99/mo; try coupon `SGLEB30` for ~$4.89). Pick **Debian 12** (or Ubuntu
   22.04/24.04).
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

## Tuning for RAM

The server is Java-based. The systemd unit intentionally leaves the heap
unset so the JVM picks a sensible default. On the VPS Pro (4GB), the default
is fine for 10-20 players. Only cap it if you run other services on the same
box and see memory pressure. Add to the `[Service]` section:
```
Environment=JAVA_OPTS=-Xmx1600M -Xms800M
```
then restart. `StartServer-nogui.sh` honors `JAVA_OPTS` in most builds.

---

## Notes / caveats

- **SteamCMD needs 32-bit libs** — `setup.sh` installs them automatically
  (`lib32gcc`, `lib32stdc++`, 32-bit curl).
- The install dir is **`/opt/necesse-server`** via SteamCMD `+force_install_dir`.
  Your client PC never needs Steam running for this to work.
- **Backups are automatic**: a systemd timer runs `/opt/necesse-backup.sh`
  daily at 03:00, keeping the last 7 archives in `/root/necesse-backups`.
  The archives cover `<install>/saves`. Change retention via `KEEP` in the
  backup script. If you move install dirs, update `INSTALL_DIR` in both
  `setup.sh` and `backup.sh`.
- World loss hurts: confirm backups actually exist
  (`ls /root/necesse-backups`) after the first day before trusting it.

### Manual backup (if you disabled the timer)
Run the script directly:
```
sudo /opt/necesse-backup.sh
```