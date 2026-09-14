# Redeploy Runbook — Necesse server on Kainode (from blank)

Purpose: take a **blank Debian 12 Kainode VPS** and rebuild the exact Necesse
server that was running, using the backup + this repo. Written so the box can
be wiped/reset and restored later without re-debugging everything.

> Status: PARKED. This is a reference runbook, not merged into main's active
> flow. Follow it when redeploying after a blank reset.

---

## How this repo + backup fit together

| Artifact | Where | What it is |
|----------|-------|------------|
| `setup.sh` | this repo | Fresh-install script: pulls Linux64 server zip, creates `necesse` user, writes `cfg/server.cfg`, systemd service + backup timer |
| `backup.sh` | this repo | World backup (keeps newest 7, daily timer) |
| `config-reference.cfg` | this repo | Documented server + world settings with valid values |
| `spike_monitor.sh` | this repo | Captures CPU spikes to `/root/cpu-spikes.log` |
| `necesse-backup.tar.gz` | **local PC** (`~/necesse-server/`) | The saved world + config from before the reset. NOT in the repo (contains password + world data) |

---

## Step 0 — you need before starting

1. A **blank Debian 12** Kainode VPS (from the reinstall/blank in their panel).
2. The **public IP + root password** Kainode gives you after reinstall.
3. This repo (already on `main`).
4. `necesse-backup.tar.gz` (already on your PC).

> SSH host-key gotcha: reinstalling Kainode **regenerates the server's SSH host
> key**. After blanking, `ssh` will error `REMOTE HOST IDENTIFICATION HAS
> CHANGED`. Fix once:
> ```
> ssh-keygen -R <IP>
> ```

---

## Step 1 — connect + transfer scripts + backup

```bash
scp setup.sh backup.sh root@<IP>:~/
scp necesse-backup.tar.gz root@<IP>:/tmp/
ssh root@<IP>
```

## Step 2 — install the server (blank → running)

```bash
sudo bash setup.sh
```

This installs the Linux64 server to `/opt/necesse-server`, creates the
`necesse` user, writes `cfg/server.cfg` with defaults, enables the systemd
service + backup timer, and opens nothing (firewall is below). Give it ~1 min
(the ~85MB server zip download).

## Step 3 — restore the world + config from backup

The backup layout is:
```
saves/worlds/world.zip
cfg/server.cfg  cfg/settings.cfg  cfg/banned.cfg  cfg/auth
```

```bash
sudo systemctl stop necesse
sudo tar xzf /tmp/necesse-backup.tar.gz -C /opt/necesse-server
sudo chown -R necesse:necesse /opt/necesse-server
sudo systemctl start necesse
```

This puts back your world, the passwordized config, and the saved player UUID
(`cfg/auth`), so returning players keep their slot without re-entering the
password.

## Step 4 — firewall (open UDP 14159)

```bash
sudo ufw allow 14159/udp
# or without ufw:
sudo iptables -A INPUT -p udp --dport 14159 -j ACCEPT
```

Reboot persistence for iptables: `apt install -y iptables-persistent` and
`netfilter-persistent save` (or just use ufw).

## Step 5 — SSH key hardening (optional but recommended)

```bash
install -d -m700 /root/.ssh
echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFl8y61GeINkDm2TF3FAqoGWU9GtF1+YnO5JBZjxRn3g ACER-machine' \
  >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
```
Then disable password auth:
```bash
sed -i 's/^[# ]*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^[# ]*PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
systemctl reload ssh
```

## Step 6 — verify

```bash
sudo systemctl is-active necesse          # expect: active
ss -lunp | grep 14159                     # expect: bound
sudo ls -la /opt/necesse-server/saves/worlds/   # world.zip + LATEST_BACKUP* present
cat /opt/necesse-server/cfg/server.cfg    # port 14159, slots 10, password set
```

Then join from the client: `Join Game → <IP>:14159`, password
`absolutegaming`. Confirm a returning character loads straight in (world + auth
restored).

---

## Config knobs (see config-reference.cfg for details)

- **MOTD / server name** — `cfg/server.cfg` → `MOTD = "Welcome to Kivotos!"`
- **Slots / port / password** — `cfg/server.cfg`
- **Death penalty** — console command `deathpenalty <drop_main_inventory|...>`
- **Allow outside characters** — world's `worldSettings.cfg` (inside `world.zip`),
  set `false` to block imported/cheated characters
- **pauseWhenEmpty** — `cfg/server.cfg`, `true` = world freezes with 0 players

## Backups

`setup.sh` installs `necesse-backup.sh` + a daily 03:00 UTC systemd timer that
keeps the newest 7 archives in `/root/necesse-backups`. After a fresh install,
confirm one exists with:
```bash
sudo systemctl list-timers | grep necesse-backup
ls /root/necesse-backups
```

---

## Gotchas encountered on the original deploy (recap)

- **SteamCMD was flaky** — its self-update kept failing (`steamcmd_bins_linux`
  error). The **direct Linux64 zip** from `necessegame.com/server` is used
  instead and is reliable.
- **60GB disk needed** — the first box was provisioned at 3GB (a Kainode
  provisioning error); Necesse won't fit. Ensure the plan ships the listed disk.
- **CPU "spiking during idle" = the world autosave** — every few minutes an
  autosave + backup copy briefly pins the 2-core box to 100% busy. Normal, not a
  fault. The spike_monitor (`/root/cpu-spikes.log`) caught it at
  `SPIKE busy%=100%` right after `Starting world save`.
- **`cfg/auth`** is a Java-serialized player UUID; it's why a returning client
  skips the password prompt. Restoring it preserves that.
- **allowOutsideCharacters lives inside `world.zip`**, not `server.cfg` —
  editing the world requires stopping the server, editing the file inside the
  zip, re-zipping, restarting (Python `zipfile` handles it cleanly).