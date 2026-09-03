# Necesse Dedicated Server — Direct Linux64 download (Linux VPS)

Deploy a Necesse dedicated server on a Linux VPS (2GB RAM is plenty) using the
official direct-download Linux64 server zip and systemd. No SteamCMD, no
Docker, no game-panel lock-in; you own the box and can run a Discord bot or
other services alongside it.

The server ships a **bundled JRE** (no system Java needed) and is driven by the
stock `StartServer-nogui.sh -localdir -world <name>` launcher, managed by
systemd so it auto-starts on boot and restarts on crash.

> **Why direct download instead of SteamCMD?** During deployment SteamCMD's own
> client bootstrap repeatedly failed to self-update (`steamcmd_bins_linux`
> download error). The official direct-download zip from use of the same
> `necessegame.com/server` page is simpler and avoids that entirely.

---

## What's in here

| File | Purpose |
|------|---------|
| `setup.sh` | One-shot root installer. Downloads the latest Linux64 server zip from `necessegame.com/server`, extracts it to `/opt/necesse-server`, writes `cfg/server.cfg`, creates a `necesse` user, registers a systemd service, and sets up the daily backup timer. |
| `backup.sh` | World backup script: tars `<install>/saves`, keeps the newest `KEEP` (7) archives. Wired into a systemd timer by `setup.sh`, runnable standalone. |
| `config-reference.cfg` | Documented template of every server + world setting (MOTD/name, password, pauseWhenEmpty, death penalty, day/night length, PvP, raids, etc.) with all valid options. |
| `README.md` | This file. |

Default config: port `14159/udp`, 10 slots, world named `world`, no password.
Override via env vars when running `setup.sh`, e.g.
`WORLD=myserver SLOTS=6 PORT=25000 PASSWORD=secret sudo bash setup.sh`.

`setup.sh` also installs a **daily world backup** (systemd timer, 03:00, keeps
the last 7, script at `/opt/necesse-backup.sh`). Set `BACKUP_DIR` (default
`/root/necesse-backups`) / `KEEP` (default 7) inside `backup.sh`.

---

## The 5-step plan (your end)

1. **Rent a VPS** — e.g. Kainode Singapore **VPS Pro** (2 vCPU / 4GB / 60GB,
   $6.99/mo; coupon `SGLEB30` may apply). Pick **Debian 12** (or Ubuntu
   22.04/24.04). 60GB of disk recommended: a 3GB scratch root cannot hold the
   game + world (we hit that exact issue).
2. **Get the IP + root password/SSH key** from your provider's panel.
3. **Copy these files to the server.** From your PC:
   ```
   scp setup.sh backup.sh root@<SERVER_IP>:~/
   ssh root@<SERVER_IP>
   ```
4. **Run the installer:**
   ```
   sudo bash setup.sh
   ```
   It downloads ~85MB (the server zip), so give it a minute the first time.
5. **Open the firewall port** (UDP 14159):
   ```
   sudo ufw allow 14159/udp
   # or, if no ufw:
   sudo iptables -A INPUT -p udp --dport 14159 -j ACCEPT
   ```

Then join in game via **Join Game → server `<SERVER_IP>:14159`** (enter the
password if you set one).

---

## Control

| Action | Command |
|--------|---------|
| Status | `sudo systemctl status necesse` |
| Restart | `sudo systemctl restart necesse` |
| Stop | `sudo systemctl stop necesse` |
| Start on boot | already enabled |
| Watch logs | `tail -f /opt/necesse-server/latest-server-log.txt` |
| Update server app | re-run `sudo bash setup.sh` (re-downloads latest build) |

---

## Editing config

Config lives at `/opt/necesse-server/cfg/server.cfg` (a Lua-style table).
The game reads it on start. After editing, `sudo systemctl restart necesse`.

Notable options:
- `password = "..."` — set a server password (blank = public). NOTE: this is
  the in-game join password; keep it free of quotes.
- `slots = N` — max players
- `pauseWhenEmpty = true` — pause simulation when nobody's online (saves CPU)

---

## Death penalty / other world settings

The server has no `cfg` key for death penalty; it's a **console command** that
persists into the world save. Connect to the server console and run:

```
deathpenalty <penalty>
```

Valid values (from `deathpenalty list`):
`none`, `drop_mats`, `drop_main_inventory`, `drop_full_inventory`, `hardcore`.
The value to drop everything except equipped/hotbar is `drop_main_inventory`.

---

## Tuning for RAM

The server is Java-based and ships its own JRE. The default heap is fine on a
4GB box for 10-20 players. If it shares the box with other services and you see
memory pressure, cap it by adding to the `[Service]` section:
```
Environment=JAVA_OPTS=-Xmx1600M -Xms800M
```
then restart. `StartServer-nogui.sh` honors `JAVA_OPTS` in most builds.

---

## Notes / caveats

- **Needs `unzip`** — `setup.sh` installs it (plus curl/wget) via apt.
- The install dir is **`/opt/necesse-server`**, owned by the `necesse` service
  account. The bundle includes its own `jre/`.
- The world save is a zip at `<install>/saves/worlds/<world>.zip`.
- **Backups are automatic**: a systemd timer runs `/opt/necesse-backup.sh`
  daily at 03:00, keeping the last 7 archives in `/root/necesse-backups`.
- World loss hurts: confirm backups actually exist
  (`ls /root/necesse-backups`) after the first day before trusting it.

### Manual backup (if you disabled the timer)
Run the script directly:
```
sudo /opt/necesse-backup.sh
```