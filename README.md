# Home server: an Ubuntu laptop that works like a VPS

SSH in from anywhere on your network (`ssh homeserver`), and host apps with **Coolify**, just like a cloud VPS (Oracle, AWS, DigitalOcean...).

| File | Runs on | What it does |
|---|---|---|
| `setup-server.sh` | the Ubuntu laptop | installs SSH, keeps the laptop awake with the lid closed, sets up the firewall, fail2ban and automatic security updates, installs Coolify (and Docker), and switches SSH to keys only once your key is on the laptop |
| `connect.ps1` | your Windows PC, once | creates an SSH key, copies it to the laptop, gives your Ubuntu user password-free `sudo` (like a cloud VPS), adds the `ssh homeserver` shortcut |

## 1. On the Ubuntu laptop: get the files and run the setup

Plug in the charger, and if you can, an Ethernet cable. Then open a terminal:

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/sahilmandre/home-server.git
cd home-server
sudo bash setup-server.sh --hostname homeserver
```

Options: `--headless` (no desktop: frees about 1 GB of RAM, good for a server laptop), `--no-coolify`, `--timezone Asia/Kolkata`.

When it finishes:

1. **Open `http://<laptop-ip>:8000` straight away and create your Coolify admin account.** The first person to open it becomes the admin. You can do this from the laptop's own browser too: `http://localhost:8000`.
2. Note the laptop's address and your username: `hostname -I && whoami`. In your router's settings, reserve that IP for the laptop ("DHCP reservation" / "static lease"), so it never changes.

SSH still accepts your password at this point, because the laptop doesn't have your key yet.

## 2. On your Windows PC: connect once

```powershell
git clone https://github.com/sahilmandre/home-server.git
cd home-server
powershell -ExecutionPolicy Bypass -File .\connect.ps1
```

Enter the IP and username from step 1. It asks for your Ubuntu password twice; after that you never need it again. Check with `ssh homeserver`.

If a company VPN is connected, it may block your home network. Disconnect it for this.

## 3. Switch SSH to keys only, and reboot

Run the setup once more, now that your key is on the laptop. It's safe to re-run, and this time it turns password sign-in off:

```powershell
ssh -t homeserver "cd ~/home-server && git pull && sudo bash setup-server.sh --hostname homeserver"
ssh homeserver sudo reboot
```

To update the scripts later, run `git pull` in `~/home-server` on the laptop.

## Reaching it from outside your home

The laptop sits behind your home router, so out of the box it's only reachable on your home network. Two free options, and you can use both:

- **SSH from anywhere: Tailscale.** A private network between your devices. Install it on the laptop and on your phone or PC, then `ssh homeserver` works from anywhere, with no open ports.
- **Public websites: Cloudflare Tunnel.** Serves your Coolify apps on your own domain, even if your ISP gives you no public IP (common with Jio and Airtel fibre). You need a domain on Cloudflare (free plan). Coolify has a built-in guide: *Coolify docs → Knowledge base → Cloudflare Tunnels*.
- **Port forwarding** (router: 80/443 → laptop) only works if your connection has a real public IP.

Both can be set up over SSH; you only approve a sign-in link in your browser.

## Differences from a real VPS

- If your power or internet goes down, so do your apps. The battery covers short power cuts; keep the charger plugged in.
- Home upload speed limits how fast your sites serve.
- In the BIOS, turn on *"Power on after AC loss"* / *"Restore on AC power"*, if available, so it comes back by itself after a long outage.
- Keep the laptop somewhere ventilated, lid closed or open.
- Docker publishes container ports past `ufw`. Only expose apps through Coolify's proxy (80/443), not by publishing raw ports.

## Undo

- Allow password sign-in again: `sudo rm /etc/ssh/sshd_config.d/01-server.conf && sudo systemctl reload ssh`
- Get the desktop back after `--headless`: `sudo systemctl set-default graphical.target`
- Allow sleep again: `sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target && sudo rm /etc/systemd/logind.conf.d/10-server.conf`
