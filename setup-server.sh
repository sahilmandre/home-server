#!/usr/bin/env bash
# Turns a spare Ubuntu laptop into a VPS-style server that runs Coolify.
#
#   sudo bash setup-server.sh [--headless] [--no-coolify] [--hostname NAME] [--timezone ZONE]
#
#   --headless      boot to the text console instead of the desktop (frees ~1 GB of RAM)
#   --no-coolify    do everything except install Coolify
#   --hostname      rename the machine (e.g. homeserver)
#   --timezone      default Asia/Kolkata
#
# Safe to run again: each step checks the current state before changing it.
set -euo pipefail

HEADLESS=0
INSTALL_COOLIFY=1
NEW_HOSTNAME=""
TIMEZONE="Asia/Kolkata"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --headless) HEADLESS=1 ;;
    --no-coolify) INSTALL_COOLIFY=0 ;;
    --hostname) NEW_HOSTNAME="${2:?--hostname needs a name}"; shift ;;
    --timezone) TIMEZONE="${2:?--timezone needs a zone}"; shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!   %s\033[0m\n' "$*"; }

[[ $EUID -eq 0 ]] || { echo "Run it with sudo: sudo bash $0" >&2; exit 1; }
ADMIN_USER="${SUDO_USER:-}"
[[ -n "$ADMIN_USER" && "$ADMIN_USER" != root ]] || { echo "Run it as your normal user with sudo, not as root." >&2; exit 1; }
ADMIN_HOME="$(getent passwd "$ADMIN_USER" | cut -d: -f6)"

. /etc/os-release
[[ "$ID" == ubuntu ]] || { echo "This script is for Ubuntu (found $PRETTY_NAME)." >&2; exit 1; }

export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

step "This machine"
CPUS="$(nproc)"
MEM_GB="$(awk '/MemTotal/ {printf "%.1f", $2 / 1048576}' /proc/meminfo)"
DISK_GB="$(df -BG --output=avail / | tail -1 | tr -dc '0-9')"
echo "$PRETTY_NAME · $CPUS CPU(s) · ${MEM_GB} GB RAM · ${DISK_GB} GB free on /"
(( CPUS >= 2 )) || warn "Coolify wants at least 2 CPUs."
awk "BEGIN { exit !($MEM_GB < 1.9) }" && warn "Coolify wants at least 2 GB of RAM (consider --headless)."
(( DISK_GB >= 30 )) || warn "Coolify wants at least 30 GB of free disk."

step "Updating packages"
apt-get update -q
apt-get "${APT_OPTS[@]}" upgrade
apt-get "${APT_OPTS[@]}" install openssh-server curl ca-certificates git jq htop ufw fail2ban python3-systemd unattended-upgrades

step "Time zone and name"
timedatectl set-timezone "$TIMEZONE"
if [[ -n "$NEW_HOSTNAME" && "$(hostname)" != "$NEW_HOSTNAME" ]]; then
  hostnamectl set-hostname "$NEW_HOSTNAME"
  if grep -q '^127\.0\.1\.1' /etc/hosts; then
    sed -i "s/^127\.0\.1\.1.*/127.0.1.1 $NEW_HOSTNAME/" /etc/hosts
  else
    echo "127.0.1.1 $NEW_HOSTNAME" >>/etc/hosts
  fi
fi
echo "$(hostname) · $(timedatectl show -p Timezone --value)"

step "Keeping the laptop awake (lid closed, idle, on battery)"
mkdir -p /etc/systemd/logind.conf.d
cat >/etc/systemd/logind.conf.d/10-server.conf <<'EOF'
# Written by setup-server.sh: this laptop is a server — closing the lid or idling must not suspend it.
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
IdleAction=ignore
EOF
# Masking the sleep targets takes effect now; the logind file above applies from the next boot
# (restarting logind would end the desktop session).
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null
echo "Sleep and hibernate are disabled."

step "SSH: sign-in with keys only"
systemctl enable --now ssh >/dev/null 2>&1 || systemctl enable --now ssh.socket >/dev/null
if [[ -s "$ADMIN_HOME/.ssh/authorized_keys" ]]; then
  cat >/etc/ssh/sshd_config.d/01-server.conf <<'EOF'
# Written by setup-server.sh. Keys only. Root may sign in with a key (never a password)
# because Coolify manages this machine over SSH as root with its own key.
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
PubkeyAuthentication yes
X11Forwarding no
MaxAuthTries 4
EOF
  mkdir -p /run/sshd
  sshd -t
  systemctl reload ssh 2>/dev/null || systemctl restart ssh
  echo "Password sign-in is off; $ADMIN_USER signs in with their key."
else
  warn "$ADMIN_USER has no SSH key yet, so password sign-in stays on (otherwise you'd be locked out)."
fi

step "Firewall (ufw)"
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow OpenSSH >/dev/null
ufw allow 80/tcp comment "web" >/dev/null
ufw allow 443/tcp comment "web (https)" >/dev/null
ufw allow 8000/tcp comment "Coolify dashboard" >/dev/null
ufw allow 6001/tcp comment "Coolify realtime" >/dev/null
ufw allow 6002/tcp comment "Coolify terminal" >/dev/null
ufw --force enable >/dev/null
ufw status | sed -n '1,20p'

step "Brute-force protection (fail2ban)"
cat >/etc/fail2ban/jail.d/sshd.local <<'EOF'
# Written by setup-server.sh. Devices on the home network are never banned.
[sshd]
enabled = true
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
ignoreip = 127.0.0.1/8 ::1 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10
EOF
systemctl enable fail2ban >/dev/null 2>&1
systemctl restart fail2ban
fail2ban-client status sshd | sed -n '1,4p' || true

step "Automatic security updates"
cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
systemctl enable --now unattended-upgrades >/dev/null 2>&1
echo "Security updates install daily (no automatic reboots)."

if (( HEADLESS )); then
  step "Headless: boot to the text console"
  systemctl set-default multi-user.target >/dev/null
  echo "From the next boot the desktop won't start (undo: sudo systemctl set-default graphical.target)."
fi

if (( INSTALL_COOLIFY )); then
  step "Coolify (installs Docker too — takes a few minutes)"
  if command -v docker >/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx coolify; then
    echo "Coolify is already running."
  else
    curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash
  fi
  getent group docker >/dev/null && usermod -aG docker "$ADMIN_USER"
fi

IP="$(hostname -I | awk '{print $1}')"
step "Done"
echo "SSH:      ssh $ADMIN_USER@$IP"
(( INSTALL_COOLIFY )) && echo "Coolify:  http://$IP:8000  ← open it now and create the admin account (the first visitor becomes admin)"
echo "Reboot once so every setting applies:  sudo reboot"
