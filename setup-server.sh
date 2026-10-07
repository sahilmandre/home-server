#!/usr/bin/env bash
# Turns a spare Ubuntu laptop into a VPS-style server that runs Coolify.
#
#   sudo bash setup-server.sh [--admin-email EMAIL] [--domain DOMAIN] [--tailscale] [--headless]
#                             [--no-coolify] [--hostname NAME] [--timezone ZONE]
#
#   --admin-email   create the Coolify admin account during the install (password saved to
#                   /root/coolify-admin.txt), instead of whoever opens the dashboard first
#   --domain        serve apps on the internet at https://<name>.DOMAIN through a Cloudflare Tunnel
#                   (the domain's DNS must be on Cloudflare; you approve one sign-in link)
#   --tailscale     install Tailscale, to reach the server from anywhere without opening ports
#   --headless      boot to the text console instead of the desktop (frees ~1 GB of RAM)
#   --no-coolify    do everything except install Coolify
#   --hostname      rename the machine
#   --timezone      default Asia/Kolkata
#
# Who can connect: devices on the home network, on Tailscale and in Docker reach every port; the
# internet reaches none, over IPv4 or IPv6, ports published by Docker included. Public websites go
# out through a Cloudflare Tunnel instead (see README).
#
# Safe to run again: each step checks the current state before changing it.
set -euo pipefail

ADMIN_EMAIL=""
DOMAIN=""
TAILSCALE=0
HEADLESS=0
INSTALL_COOLIFY=1
NEW_HOSTNAME=""
TIMEZONE="Asia/Kolkata"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --admin-email) ADMIN_EMAIL="${2:?--admin-email needs an email address}"; shift ;;
    --domain) DOMAIN="${2:?--domain needs a domain, e.g. example.com}"; shift ;;
    --tailscale) TAILSCALE=1 ;;
    --headless) HEADLESS=1 ;;
    --no-coolify) INSTALL_COOLIFY=0 ;;
    --hostname) NEW_HOSTNAME="${2:?--hostname needs a name}"; shift ;;
    --timezone) TIMEZONE="${2:?--timezone needs a zone}"; shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

# Addresses that can't come from the internet: private IPv4 (home network, Docker), Tailscale
# (100.64.0.0/10 and fd7a:115c:a1e0::/48), and IPv6 link-local and unique-local.
TRUSTED_V4=(10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10)
TRUSTED_V6=(fe80::/10 fc00::/7)

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!   %s\033[0m\n' "$*"; }

[[ $EUID -eq 0 ]] || { echo "Run it with sudo: sudo bash $0" >&2; exit 1; }
ADMIN_USER="${SUDO_USER:-}"
[[ -n "$ADMIN_USER" && "$ADMIN_USER" != root ]] || { echo "Run it as your normal user with sudo, not as root." >&2; exit 1; }
ADMIN_HOME="$(getent passwd "$ADMIN_USER" | cut -d: -f6)"

# shellcheck source=/dev/null
. /etc/os-release
[[ "$ID" == ubuntu ]] || { echo "This script is for Ubuntu (found $PRETTY_NAME)." >&2; exit 1; }

export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

step "This machine"
CPUS="$(nproc)"
MEM_GB="$(awk '/MemTotal/ {printf "%.1f", $2 / 1048576}' /proc/meminfo)"
DISK_GB="$(df -BG --output=avail / | tail -1 | tr -dc '0-9')"
# The home network address: the one used to reach the internet (not Docker's or Tailscale's).
IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "src") print $(i + 1)}')"
IP="${IP:-$(hostname -I | awk '{print $1}')}"
echo "$PRETTY_NAME · $CPUS CPU(s) · ${MEM_GB} GB RAM · ${DISK_GB} GB free on / · $IP"
(( CPUS >= 2 )) || warn "Coolify wants at least 2 CPUs."
awk "BEGIN { exit !($MEM_GB < 1.9) }" && warn "Coolify wants at least 2 GB of RAM (consider --headless)."
(( DISK_GB >= 30 )) || warn "Coolify wants at least 30 GB of free disk."

step "Updating packages"
apt-get update -q
# --with-new-pkgs also takes updates that need an extra package (a new kernel, a new driver), which a
# plain upgrade holds back. Unlike full-upgrade it never removes anything.
apt-get "${APT_OPTS[@]}" upgrade --with-new-pkgs
apt-get "${APT_OPTS[@]}" install openssh-server curl ca-certificates git jq htop btop ufw fail2ban python3-systemd unattended-upgrades

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

# The battery covers short power cuts. In a long one, shut down cleanly instead of running until the
# battery dies mid-write, and let the laptop's clock switch it back on to check whether power is back.
if grep -qx Battery /sys/class/power_supply/*/type 2>/dev/null; then
  step "Power cuts: shut down before the battery runs out, start again when power is back"
  cat >/usr/local/sbin/power-guard <<'EOF'
#!/bin/sh
# Written by setup-server.sh. Gets the server through power cuts without anyone pressing a button:
# on battery at SHUTDOWN_AT% or less, it sets the laptop's clock to switch it on in WAKE_EVERY
# minutes and shuts down cleanly. Each time it starts it checks again: still no power, off for
# another WAKE_EVERY minutes; power back, a normal start. To change the numbers, put them in
# /etc/default/power-guard.
#   power-guard status   is it on the charger, and how full is the battery
SHUTDOWN_AT=25
WAKE_EVERY=15
# shellcheck source=/dev/null
[ -r /etc/default/power-guard ] && . /etc/default/power-guard

# The laptop's battery charge, in percent. (Batteries with scope Device are a mouse's or a phone's.)
charge() {
  for s in /sys/class/power_supply/*; do
    [ "$(cat "$s/type" 2>/dev/null)" = Battery ] && [ "$(cat "$s/scope" 2>/dev/null)" != Device ] &&
      cat "$s/capacity" 2>/dev/null && return
  done
}

# True when the battery is all that powers the laptop.
on_battery() {
  discharging=0
  for s in /sys/class/power_supply/*; do
    [ "$(cat "$s/scope" 2>/dev/null)" = Device ] && continue
    case "$(cat "$s/type" 2>/dev/null)" in
      Mains | USB) [ "$(cat "$s/online" 2>/dev/null)" = 1 ] && return 1 ;;
      Battery) [ "$(cat "$s/status" 2>/dev/null)" = Discharging ] && discharging=1 ;;
    esac
  done
  [ "$discharging" = 1 ]
}

low() { on_battery && pct="$(charge)" && [ "$pct" -le "$SHUTDOWN_AT" ] 2>/dev/null; }

off_for_now() {
  echo "$1: shutting down, switching on again in $WAKE_EVERY minutes to check for power"
  rtcwake -m no -s $((WAKE_EVERY * 60)) >/dev/null ||
    echo "Couldn't set the wake-up time: once power is back, press the power button"
  systemctl --no-block poweroff
}

case "$1" in
  boot)
    # Runs at every start, before the apps.
    if low; then off_for_now "Still no power, battery at $pct%"; else rtcwake -m disable >/dev/null 2>&1; fi ;;
  watch)
    while sleep 60; do
      if low; then off_for_now "Power cut, battery down to $pct%"; exit 0; fi
    done ;;
  status)
    if on_battery; then
      echo "On battery: $(charge)% left. At $SHUTDOWN_AT% it shuts down, then checks for power every $WAKE_EVERY minutes."
    else
      echo "On the charger. Battery: $(charge)%."
    fi ;;
  *) echo "Usage: power-guard status" >&2; exit 2 ;;
esac
EOF
  chmod 755 /usr/local/sbin/power-guard
  cat >/etc/systemd/system/power-guard.service <<'EOF'
# Written by setup-server.sh: see /usr/local/sbin/power-guard.
[Unit]
Description=Shut down before the battery runs out, start again when power is back
# The check at start finishes before the apps start, so a start during a power cut ends quickly.
Before=docker.service

[Service]
ExecStartPre=/usr/local/sbin/power-guard boot
ExecStart=/usr/local/sbin/power-guard watch
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  # A backstop if the battery gets this low anyway: UPower's default, hybrid sleep, is disabled
  # above, so at critically low battery nothing would happen.
  mkdir -p /etc/UPower/UPower.conf.d
  cat >/etc/UPower/UPower.conf.d/server.conf <<'EOF'
# Written by setup-server.sh.
[UPower]
CriticalPowerAction=PowerOff
EOF
  systemctl try-restart upower
  systemctl daemon-reload
  systemctl enable power-guard >/dev/null 2>&1
  systemctl restart power-guard
  /usr/local/sbin/power-guard status
fi

if command -v nmcli >/dev/null; then
  step "Wi-Fi: no power saving, connected at boot"
  mkdir -p /etc/NetworkManager/conf.d
  # Files are read in alphabetical order and the last one wins, so the name has to sort after
  # Ubuntu's default-wifi-powersave-on.conf.
  cat >/etc/NetworkManager/conf.d/server-wifi-powersave-off.conf <<'EOF'
# Written by setup-server.sh: Wi-Fi power saving makes SSH laggy and can drop idle connections.
[connection]
wifi.powersave = 2
EOF
  echo "Wi-Fi power saving is off from the next boot."
  # A Wi-Fi password kept in the desktop keyring is only available once someone signs in, so after
  # a reboot the server would stay offline.
  while IFS=: read -r name type; do
    [[ "$type" == 802-11-wireless ]] || continue
    flags="$(nmcli -g 802-11-wireless-security.psk-flags connection show "$name" 2>/dev/null || true)"
    perms="$(nmcli -g connection.permissions connection show "$name" 2>/dev/null || true)"
    if [[ "${flags:-0}" != 0 || -n "$perms" ]]; then
      warn "Wi-Fi '$name' only connects after you sign in to the desktop. To connect it at boot:"
      warn "  sudo nmcli connection modify '$name' connection.permissions '' wifi-sec.psk-flags 0 wifi-sec.psk 'YOUR-WIFI-PASSWORD'"
    else
      echo "Wi-Fi '$name' connects at boot, before anyone signs in."
    fi
  done < <(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null)
fi

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

step "Firewall: open to the home network and Tailscale, closed to the internet"
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
# The trusted rules go in before the old ones come out, so an open SSH session is never cut off.
for range in "${TRUSTED_V4[@]}" "${TRUSTED_V6[@]}"; do
  ufw allow from "$range" comment "home network, Tailscale, Docker" >/dev/null
done
# Earlier versions of this script opened these to the whole internet.
for rule in OpenSSH 80/tcp 443/tcp 8000/tcp 6001/tcp 6002/tcp; do
  ufw delete allow "$rule" >/dev/null 2>&1 || true
done
# Docker publishes container ports with its own firewall rules, which run before ufw's, so ufw alone
# can't close them. DOCKER-USER is the chain Docker leaves to us: let replies and trusted addresses
# through, drop the rest.
docker_rules() {
  local file="/etc/ufw/$1" range
  shift
  sed -i '/^# BEGIN setup-server.sh docker/,/^# END setup-server.sh docker/d' "$file"
  {
    echo "# BEGIN setup-server.sh docker"
    echo "*filter"
    echo ":DOCKER-USER - [0:0]"
    echo "-A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN"
    for range in "$@"; do echo "-A DOCKER-USER -s $range -j RETURN"; done
    echo "-A DOCKER-USER -j DROP"
    echo "COMMIT"
    echo "# END setup-server.sh docker"
  } >>"$file"
}
docker_rules after.rules "${TRUSTED_V4[@]}"
docker_rules after6.rules "${TRUSTED_V6[@]}"
if ufw status | grep -q '^Status: active'; then ufw reload >/dev/null; else ufw --force enable >/dev/null; fi
ufw status | sed -n '1,30p'

step "Brute-force protection (fail2ban)"
cat >/etc/fail2ban/jail.d/sshd.local <<EOF
# Written by setup-server.sh. Addresses the firewall trusts are never banned.
[sshd]
enabled = true
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
ignoreip = 127.0.0.1/8 ::1 ${TRUSTED_V4[*]} ${TRUSTED_V6[*]}
EOF
systemctl enable fail2ban >/dev/null 2>&1
systemctl restart fail2ban
# The restart returns before fail2ban has opened its control socket.
for _ in {1..15}; do fail2ban-client ping >/dev/null 2>&1 && break; sleep 1; done
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

if (( TAILSCALE )); then
  step "Tailscale (reach the server from anywhere, no open ports)"
  command -v tailscale >/dev/null || curl -fsSL https://tailscale.com/install.sh | sh
  if tailscale status >/dev/null 2>&1; then
    echo "Connected to Tailscale as $(hostname) · $(tailscale ip -4 | head -1)"
  else
    warn "Not signed in yet: run 'sudo tailscale up' and open the link it prints."
  fi
fi

if (( INSTALL_COOLIFY )); then
  step "Coolify (installs Docker too — takes a few minutes)"
  if [[ -f /data/coolify/source/.env ]]; then
    echo "Coolify is already installed (update it from its dashboard)."
  else
    ADMIN_PASSWORD=""
    if [[ -n "$ADMIN_EMAIL" ]]; then
      ADMIN_PASSWORD="Cf-$(openssl rand -hex 12)"
      (umask 077 && printf 'email:    %s\npassword: %s\n' "$ADMIN_EMAIL" "$ADMIN_PASSWORD" >/root/coolify-admin.txt)
    fi
    # The installer only uses the ROOT_* account when all three are set.
    curl -fsSL https://cdn.coollabs.io/coolify/install.sh |
      ROOT_USERNAME="$ADMIN_USER" ROOT_USER_EMAIL="$ADMIN_EMAIL" ROOT_USER_PASSWORD="$ADMIN_PASSWORD" bash
    # Two settings the dashboard would otherwise ask for, set once on a fresh install: every app gets
    # an address like http://<name>.<ip>.sslip.io, and the API is on (it still needs a token), so
    # apps can be deployed from any PC with curl. The API has no endpoint for the first one.
    for _ in {1..30}; do
      docker exec coolify-db psql -U coolify -d coolify -tAc "select 1 from server_settings where server_id = 0" 2>/dev/null | grep -q 1 && break
      sleep 2
    done
    docker exec coolify-db psql -U coolify -d coolify -qc \
      "update server_settings set wildcard_domain = 'http://$IP.sslip.io' where server_id = 0; update instance_settings set is_api_enabled = true;" ||
      warn "Couldn't preset Coolify's settings: set Servers → localhost → Wildcard Domain to http://$IP.sslip.io yourself."
  fi
  # CPU and memory graphs for the server and each app (kept 7 days), off by default. Like the
  # dashboard's switch: save the setting, then restart Sentinel, Coolify's monitoring agent.
  if [[ "$(docker exec coolify-db psql -U coolify -d coolify -tAc "select is_metrics_enabled from server_settings where server_id = 0" 2>/dev/null)" == f ]]; then
    docker exec coolify php artisan tinker --execute '
      $server = App\Models\Server::find(0);
      $server->settings->is_metrics_enabled = true;
      $server->settings->save();
      App\Actions\Server\StartSentinel::run($server->refresh(), true);' >/dev/null 2>&1 ||
      warn "Couldn't turn on Coolify's graphs: Servers → localhost → Metrics."
  fi
  echo "CPU and memory graphs: Servers → localhost → Metrics, and each app's Metrics."
  getent group docker >/dev/null && usermod -aG docker "$ADMIN_USER"
fi

if [[ -n "$DOMAIN" ]]; then
  step "Cloudflare Tunnel: apps on the internet at https://<name>.$DOMAIN"
  if ! command -v cloudflared >/dev/null; then
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" \
      >/etc/apt/sources.list.d/cloudflared.list
    apt-get update -q
    apt-get "${APT_OPTS[@]}" install cloudflared
  fi
  CF=(cloudflared --origincert /root/.cloudflared/cert.pem)
  if [[ ! -s /root/.cloudflared/cert.pem ]]; then
    echo "Open the link below, pick $DOMAIN and click Authorize. It lets this server manage its tunnel."
    cloudflared tunnel login
  fi
  tunnel_id() { "${CF[@]}" tunnel list -o json 2>/dev/null | jq -r --arg n "$(hostname)" '.[]? | select(.name == $n) | .id'; }
  TUNNEL_ID="$(tunnel_id)"
  if [[ -z "$TUNNEL_ID" ]]; then
    "${CF[@]}" tunnel create "$(hostname)" >/dev/null
    TUNNEL_ID="$(tunnel_id)"
    rm -f "/root/.cloudflared/$TUNNEL_ID.json"
  fi
  # The tunnel's key, readable only by root. It can be fetched again, e.g. after reinstalling Ubuntu.
  mkdir -p /etc/cloudflared
  CRED="/etc/cloudflared/$TUNNEL_ID.json"
  [[ -s "$CRED" ]] || "${CF[@]}" tunnel token --cred-file "$CRED" "$TUNNEL_ID" >/dev/null
  chmod 600 "$CRED"
  cat >/etc/cloudflared/config.yml <<EOF
# Written by setup-server.sh. Every *.$DOMAIN name without a DNS record of its own arrives here and
# goes to Coolify's proxy, which picks the app by name.
tunnel: $TUNNEL_ID
credentials-file: $CRED
ingress:
  # hooks.$DOMAIN lets GitHub reach Coolify's webhooks (each signed with a secret) to deploy on
  # git push. Nothing else of Coolify is public: the dashboard stays on the home network and Tailscale.
  - hostname: hooks.$DOMAIN
    path: ^/webhooks/
    service: http://localhost:8000
  - hostname: hooks.$DOMAIN
    service: http_status:404
  - hostname: "*.$DOMAIN"
    service: http://localhost:80
  - service: http_status:404
EOF
  cloudflared tunnel --config /etc/cloudflared/config.yml ingress validate >/dev/null
  # One DNS record, *.DOMAIN → the tunnel. Names with a record of their own ($DOMAIN, www...) keep it.
  "${CF[@]}" tunnel route dns "$TUNNEL_ID" "*.$DOMAIN" >/dev/null 2>&1 ||
    warn "Couldn't add the *.$DOMAIN DNS record: if one already exists, point it at $TUNNEL_ID.cfargotunnel.com."
  [[ -f /etc/systemd/system/cloudflared.service ]] || cloudflared service install >/dev/null 2>&1
  systemctl enable cloudflared >/dev/null 2>&1
  systemctl restart cloudflared
  for _ in {1..20}; do "${CF[@]}" tunnel info "$TUNNEL_ID" 2>/dev/null | grep -q 'CONNECTOR ID' && break; sleep 1; done
  if "${CF[@]}" tunnel info "$TUNNEL_ID" 2>/dev/null | grep -q 'CONNECTOR ID'; then
    echo "Tunnel $(hostname) is connected; *.$DOMAIN reaches Coolify."
  else
    warn "The tunnel isn't connected yet: check with 'journalctl -u cloudflared'."
  fi

  if [[ -f /data/coolify/source/.env ]]; then
    # New apps get https://<name>.DOMAIN, unless you've set a wildcard domain of your own.
    docker exec coolify-db psql -U coolify -d coolify -qc \
      "update server_settings set wildcard_domain = 'https://$DOMAIN' where server_id = 0 and coalesce(wildcard_domain, '') in ('', 'http://$IP.sslip.io')" ||
      warn "Couldn't set Coolify's wildcard domain: set it to https://$DOMAIN in Servers → localhost."
    # The tunnel sends each request with the visitor's address and https scheme in X-Forwarded-*
    # headers; the proxy drops them unless it trusts the sender. Without them apps believe every
    # visit is plain http from a Docker address, and https:// domains redirect forever.
    PROXY=/data/coolify/proxy/docker-compose.yml
    for _ in {1..30}; do [[ -f "$PROXY" ]] && break; sleep 2; done
    if [[ ! -f "$PROXY" ]]; then
      warn "Coolify hasn't started its proxy yet; run this script again in a minute."
    elif ! grep -q 'forwardedHeaders.trustedIPs' "$PROXY"; then
      trusted="$(IFS=,; echo "127.0.0.1/32,::1/128,${TRUSTED_V4[*]},${TRUSTED_V6[*]}")"
      sed -i -E "s|^( *)- '--entrypoints.https.address=:443'$|&\n\1- '--entrypoints.http.forwardedHeaders.trustedIPs=$trusted'\n\1- '--entrypoints.https.forwardedHeaders.trustedIPs=$trusted'|" "$PROXY"
      if grep -q 'forwardedHeaders.trustedIPs' "$PROXY"; then
        docker compose -f "$PROXY" up -d --wait >/dev/null 2>&1 ||
          warn "Restart the proxy from Coolify: Servers → localhost → Proxy → Restart."
      else
        warn "Couldn't add forwardedHeaders.trustedIPs to $PROXY: apps may see http instead of https."
      fi
    fi
  fi
fi

step "Done"
echo "SSH:      ssh $ADMIN_USER@$IP"
if (( INSTALL_COOLIFY )); then
  if [[ -f /root/coolify-admin.txt ]]; then
    echo "Coolify:  http://$IP:8000  ← sign in with the account in /root/coolify-admin.txt (sudo cat it), then change the password"
  else
    echo "Coolify:  http://$IP:8000  ← open it now and create the admin account (the first visitor becomes admin)"
  fi
  echo "Apps:     http://<name>.$IP.sslip.io  (home network and Tailscale)"
  [[ -z "$DOMAIN" ]] || echo "          https://<name>.$DOMAIN  (anywhere)"
  [[ -z "$DOMAIN" ]] || echo "Webhooks: https://hooks.$DOMAIN  (for GitHub: deploy on git push, see README)"
fi
echo "Reboot once so every setting applies:  sudo reboot"
