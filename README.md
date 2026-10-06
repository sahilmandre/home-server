# Home server: an Ubuntu laptop that works like a VPS

Manage it over SSH (`ssh homeserver`) and host apps straight from your Git repos with **Coolify**, just like a cloud VPS (Oracle, AWS, DigitalOcean...).

**New to this? Read [GUIDE.md](GUIDE.md):** a step-by-step guide to deploying apps, connecting from other computers (at home and away) and rebuilding everything from scratch. This README is the short reference.

| File | Runs on | What it does |
|---|---|---|
| `setup-server.sh` | the Ubuntu laptop | updates the system, keeps the laptop awake with the lid closed and the Wi-Fi up, sets up the firewall, fail2ban and automatic security updates, installs Coolify (and Docker), switches SSH to keys only once your key is on the laptop, and with `--domain` puts your apps on the internet through a Cloudflare Tunnel |
| `connect.ps1` | each Windows PC you manage it from, once | creates an SSH key, copies it to the laptop, gives your Ubuntu user password-free `sudo` (like a cloud VPS), adds the `ssh homeserver` shortcut |

## Who can reach the server

- **Your home network and your Tailscale devices:** everything (SSH, the Coolify dashboard, your apps).
- **The internet:** nothing, over IPv4 or IPv6. Docker normally lets the ports it publishes bypass `ufw`; the script closes that gap too.
- **Your apps** can still be public, at `https://<name>.<your-domain>`: they're served through a Cloudflare Tunnel, which the server opens from the inside, so no port is open (see [Your own domain](#put-your-apps-on-the-internet-with-your-own-domain)).

## 1. On the Ubuntu laptop: get the files and run the setup

Plug in the charger, and if you can, an Ethernet cable. Then open a terminal:

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/sahilmandre/home-server.git
cd home-server
sudo bash setup-server.sh --tailscale --admin-email you@example.com
```

Options: `--admin-email EMAIL` (creates the Coolify admin account during the install, recommended), `--domain DOMAIN` (apps on the internet on your own domain, [see below](#put-your-apps-on-the-internet-with-your-own-domain)), `--tailscale` (reach it from anywhere, recommended), `--headless` (no desktop: frees about 1 GB of RAM), `--no-coolify`, `--hostname NAME`, `--timezone Asia/Kolkata`.

When it finishes:

1. **Sign in to Coolify at `http://<laptop-ip>:8000`** with the email and password in `/root/coolify-admin.txt` (`sudo cat /root/coolify-admin.txt`), then change the password under your profile. Without `--admin-email`, open the dashboard straight away and create the account: the first person to open it becomes the admin.
2. In your router's settings, reserve the laptop's IP ("DHCP reservation" / "static lease"), so it never changes.
3. If you used `--tailscale` and it says you're not signed in: run `sudo tailscale up` and open the link it prints.

Every app gets its own address, like `http://myapp.192.168.29.66.sslip.io`, with no DNS setup: sslip.io answers any such name with the IP inside it. (The setup presets this as the server's **Wildcard Domain** in Coolify.)

SSH still accepts your password at this point, because the laptop doesn't have your key yet.

## 2. On your Windows PC: connect once

```powershell
git clone https://github.com/sahilmandre/home-server.git
cd home-server
powershell -ExecutionPolicy Bypass -File .\connect.ps1
```

Enter the IP and username the setup printed. It asks for your Ubuntu password twice; after that you never need it again. Check with `ssh homeserver`.

If a company VPN is connected, it may block your home network. Disconnect it for this.

**Another PC later:** run `connect.ps1` there too. The server no longer accepts passwords by then, so the script prints one line to run on a PC that's already connected; after that, run `connect.ps1` again.

## 3. Switch SSH to keys only, and reboot

Run the setup once more, now that your key is on the laptop. It's safe to re-run, and this time it turns password sign-in off:

```powershell
ssh -t homeserver "cd ~/home-server && git pull && sudo bash setup-server.sh --tailscale"
ssh homeserver sudo reboot
```

To update the scripts later, run the first line again.

## Deploying an app

In Coolify: **Projects → New project**, open it, open **production**, then **New resource → Public Git Repository** (or **Git Repository (with GitHub App)** once you have a [GitHub App](#deploy-automatically-on-git-push)), pick the repo and branch, and **Deploy**. [GUIDE.md](GUIDE.md#4-deploy-an-app) has every step. Coolify detects Node, Python, static sites and more (Nixpacks), or uses your `Dockerfile` / `docker-compose.yml`. Each app gets an address automatically: `https://<random>.<your-domain>` with `--domain`, otherwise `http://<random>.<laptop-ip>.sslip.io`. Change it under the app's **Domains**. You can list several, separated by commas, e.g. `https://myapp.example.com,http://myapp.192.168.29.66.sslip.io`.

- **Redeploy:** the **Deploy** button, or from any PC on your network with the app's deploy webhook (app → **Webhooks**). It needs an API token: **Keys & Tokens → API Tokens**, with the *deploy* permission.
  `curl -X POST -H "Authorization: Bearer <token>" "http://<laptop-ip>:8000/api/v1/deploy?uuid=<app-uuid>"`
- **Automatic deploy on `git push`**, like Vercel: see [below](#deploy-automatically-on-git-push) (needs `--domain`).
- **Databases:** **New resource → PostgreSQL / MongoDB / Redis**, then paste its **URL (internal)** into the app's environment variables.

## Put your apps on the internet with your own domain

The domain can stay with any registrar (Hostinger, GoDaddy...); only its DNS moves to Cloudflare, on the free plan.

1. In Cloudflare, **Add a domain**, pick the **Free** plan and check the records it copies over (especially email/MX records). At your registrar, replace the nameservers with the two Cloudflare shows (Hostinger: **Domains → your domain → DNS / Nameservers → Edit**). Wait for Cloudflare's "active" email.
2. Run the setup with your domain, open the link it prints, pick the domain and click **Authorize**:
   ```powershell
   ssh -t homeserver "cd ~/home-server && git pull && sudo bash setup-server.sh --tailscale --domain example.com"
   ```
3. In Coolify, give an app a domain such as `https://myapp.example.com` (new apps get one automatically) and deploy. It's live within a minute, with HTTPS, from anywhere.

How it works: the script adds one DNS record, `*.example.com`, that sends every name without a record of its own to the tunnel, and from there to Coolify, which picks the app by name. Records you already have, like `example.com` or `www`, keep pointing where they did. Write app domains with `https://`: visitors who type `http://` are then sent to the secure address.

## Deploy automatically on git push

GitHub tells Coolify about each push through `https://hooks.example.com`. That address only lets through Coolify's webhooks, each checked against a secret; the dashboard itself stays on your home network and Tailscale.

**For all your repos at once (recommended): a GitHub App.** It also covers private repos and can deploy a preview of each pull request.

1. Open the Coolify dashboard the way you usually do, e.g. `http://192.168.29.66:8000`, and sign in.
2. **Sources → + Add → GitHub App**, give it a name, and continue.
3. Under **Webhook endpoint** pick **Use a custom endpoint**, and as the **Custom endpoint** enter exactly the address in your browser's address bar, e.g. `http://192.168.29.66:8000`. GitHub sends your browser back to that address, and Coolify only finishes the setup for a signed-in visitor, so it must be the dashboard's own address (not `hooks.example.com`). Click **Register with GitHub**, then **Create GitHub App** on GitHub; you land back in Coolify.
4. Click **Install repositories**, pick all repos or some, and **Install**; you land back in Coolify again.
5. Now point the webhooks at the public address. On GitHub: **Settings → Developer settings → GitHub Apps →** your app **→ Edit**, set **Webhook URL** to `https://hooks.example.com/webhooks/source/github/events`, and **Save changes** (leave the secret as it is).
6. Add apps with **New resource → Git Repository (with GitHub App)**. Every push to the app's branch now deploys it.

**For a single repo: a webhook.**

1. In Coolify: the app → **Webhooks** → **GitHub Webhook Secret**: enter a long random value and save.
2. On GitHub: the repo → **Settings → Webhooks → Add webhook**. Payload URL `https://hooks.example.com/webhooks/source/github/events/manual`, content type `application/json`, the same secret, **Just the push event**.

GitHub's **Recent Deliveries** tab (on the webhook or the GitHub App's settings) shows each push it sent and Coolify's answer, which is the first place to look if a push doesn't deploy.

## Reaching it from outside your home

- **SSH and the dashboard from anywhere: Tailscale.** A private network between your devices. With Tailscale on your phone or PC, use the laptop's Tailscale name: `ssh <user>@<hostname>`, `http://<hostname>:8000`. No open ports.
- **Public websites: Cloudflare Tunnel** (`--domain`, [above](#put-your-apps-on-the-internet-with-your-own-domain)). Works even if your ISP gives you no public IP (common with Jio and Airtel fibre).

Both are set up by the script over SSH; you only approve a sign-in link in your browser.

## Differences from a real VPS

- If your power or internet goes down, so do your apps. The battery covers short power cuts; keep the charger plugged in.
- Home upload speed limits how fast your sites serve.
- In the BIOS, turn on *"Power on after AC loss"* / *"Restore on AC power"*, if available, so it comes back by itself after a long outage.
- Keep the laptop somewhere ventilated, lid closed or open.
- Every device on your home network can reach every port on the server. Fine at home; don't connect it to a network you don't trust.

## Undo

- Allow password sign-in again: `sudo rm /etc/ssh/sshd_config.d/01-server.conf && sudo systemctl reload ssh`
- Get the desktop back after `--headless`: `sudo systemctl set-default graphical.target`
- Allow sleep again: `sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target && sudo rm /etc/systemd/logind.conf.d/10-server.conf`
- Wi-Fi power saving back on: `sudo rm /etc/NetworkManager/conf.d/server-wifi-powersave-off.conf` (applies after a reboot)
- Take the apps off the internet: `sudo systemctl disable --now cloudflared`, then delete the `*` record on Cloudflare's DNS page.
