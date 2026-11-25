# Easy guide

Short recipes for everything you do with the home server. Copy the commands exactly as they are. Type PowerShell commands on your laptop (Start menu → type "PowerShell"). More detail and the reasons: [GUIDE.md](GUIDE.md).

## Remember these 4 things

1. **Turn Tailscale on first** on your phone or laptop. Outside home, nothing except your public apps works without it.
2. **Dashboard (Coolify):** `http://samserver:8000` (or `http://100.103.7.25:8000`). At home, `http://192.168.29.66:8000` works too.
3. **Command line on the server:** `ssh homeserver` in PowerShell.
4. **Your apps, for everyone:** `https://<name>.tradelogy.in`. They don't need Tailscale.

Keep in your password manager: the Coolify password and its 2FA recovery codes, each app's environment variables, and the server laptop's Ubuntu password.

## Your devices

| Device | Dashboard | Server commands (SSH) |
|---|---|---|
| Honor laptop | anywhere, Tailscale on | anywhere, Tailscale on |
| Office laptop | at home only | at home only |
| Phone | anywhere, Tailscale on | not set up |

## Open Coolify

1. Tailscale on.
2. In the browser, type `http://samserver:8000`.
3. Enter your email, password, and the 6-digit code from your authenticator app.

Doesn't open? See [Tailscale is on but nothing opens](#tailscale-is-on-but-nothing-opens).

## Run commands on the server

1. Honor laptop: Tailscale on. Office laptop: be at home.
2. In PowerShell: `ssh homeserver`. The prompt changes to `sam@samserver:~$`.
3. Type your commands. Type `exit` to come back to your laptop.

| To... | Type (after `ssh homeserver`) |
|---|---|
| Restart the server | `sudo reboot` (see below) |
| See what's running | `docker ps` |
| Check free disk space | `df -h /` (look at "Avail") |
| Check memory | `free -h` |
| See everything live | `btop` (press `q` to leave) |
| Check charger and battery | `power-guard status` |
| Install updates | `sudo apt update && sudo apt upgrade -y` |

**After `sudo reboot`:** the server is back in about 1 minute, but your PowerShell window freezes. That's normal. Close the window, wait a minute, open a new one and run `ssh homeserver` again. Reload the dashboard page in the browser.

## Deploy a new app

1. Dashboard → **Projects** → your project → **production** → **New resource**.
2. **Git Repository (with GitHub App)** → GitHub App **job-mailer** → pick the repo and the branch.
3. **Build pack:** Nixpacks (or Dockerfile, if the repo has one). **Port:** the port the app listens on. Many Node apps use 3000. Never use Vite's 5173.
4. **Continue**. On **General**, set the domain, like `https://myapp.tradelogy.in`.
5. **Environment variables:** add the app's settings (database URL, keys...).
6. Click **Deploy** and wait 1 to 5 minutes. Then open the address.

Does the app save files (logins, uploads)? Go to **Persistent Storage** → **+ Add** → **Volume mount**, enter the folder, then **Deploy** again. Otherwise those files are lost on every deploy.

Help with the build pack or errors: [GUIDE.md section 4](GUIDE.md#4-deploy-an-app).

## Update an app

`git push` to the app's branch. It's live in about a minute.

Changed an environment variable? Click **Deploy** again.

## Add a database

1. In the project: **New resource** → **MongoDB** (or PostgreSQL...) → **Start**.
2. Copy its **URL (internal)**.
3. In your app: **Environment variables** → paste it (for example as `MONGODB_URI`) → **Deploy**.

## Forgot the Coolify password

From the Honor laptop (Tailscale on) or the office laptop (at home), in PowerShell:

```powershell
ssh -t homeserver "sudo docker exec -ti coolify php artisan root:reset-password"
```

Type the new password twice. Nothing appears while you type. Then sign in, and save the new password in your password manager.

## Lost the phone with the 2FA app

1. On the sign-in page, enter one of your **recovery codes** instead of the 6-digit code.
2. No recovery codes? [GUIDE.md section 7](GUIDE.md#forgot-the-coolify-password-or-lost-your-2fa-phone) shows how to turn 2FA off.

## Add a new device

**Phone (dashboard only):**

1. Install the Tailscale app and sign in with `sahilmandre@`.
2. Open `http://samserver:8000` in the browser.

**Laptop (dashboard and server commands):**

1. Install Tailscale from <https://tailscale.com/download>, sign in with `sahilmandre@`, and turn it on.
2. Open <https://github.com/sahilmandre/home-server> → **Code** → **Download ZIP**, then unzip it.
3. Open the unzipped folder, click the address bar, type `powershell` and press Enter. Then run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\connect.ps1 -HostAddress 100.103.7.25 -User sam
   ```
4. It says "Couldn't sign in" in red. That's normal. It also prints a line starting with `echo 'ssh-ed25519 ...`.
5. On the **Honor laptop** (Tailscale on), paste that whole line into PowerShell and press Enter.
6. On the new laptop, run the command from step 3 again. It ends with a green **Connected**.

## Lost a laptop

1. <https://login.tailscale.com/admin/machines> → **⋯** next to it → **Remove**.
2. Remove its key from the server: follow [GUIDE.md: Lost a laptop](GUIDE.md#lost-a-laptop-or-stopped-using-one).

## Once a month

```powershell
ssh -t homeserver "cd ~/home-server && git pull && sudo bash setup-server.sh --tailscale --domain tradelogy.in"
ssh homeserver sudo reboot
```

Then check the disk: `ssh homeserver df -h /`. If "Avail" is below 20G, run `ssh homeserver docker image prune -a -f`. Your running apps are not affected.

## After a power cut

Nothing to do. The server switches itself back on within about 10 minutes of the power returning.

Still off after 15 minutes? Press the server laptop's power button. To see what happened: `ssh homeserver journalctl -t power-guard`.

## Something's wrong

| Problem | Do this |
|---|---|
| Nothing opens from outside home | Is Tailscale on? Then see [below](#tailscale-is-on-but-nothing-opens) |
| The PowerShell window froze after `sudo reboot` | Close it, wait a minute, open a new one |
| `ssh homeserver` times out on the office laptop | It only works at home. Also switch off any company VPN |
| "REMOTE HOST IDENTIFICATION HAS CHANGED" away from home | Answer **no**: you're on another Jio network, not yours. Use the Honor laptop with Tailscale |
| The dashboard won't open, but Tailscale is fine | `ssh homeserver sudo reboot`, then wait 2 minutes |
| Apps don't open on the internet | `ssh homeserver sudo systemctl restart cloudflared` |
| Every app says "redirected you too many times", or never finishes loading | Run the first command from [Once a month](#once-a-month). It puts the proxy's setting back |
| A deploy fails | Read the last red lines of the deploy log, then the table in [GUIDE.md section 4](GUIDE.md#when-a-deploy-doesnt-work) |

### Tailscale is on but nothing opens

1. Click the Tailscale icon near the clock (it may be under **^**). Does it say **Connected**, with your `sahilmandre@` account?
2. Click **Disconnect**, then **Connect**. If it asks you to log in, log in.
3. Haven't used Tailscale on this device for months? Install the latest version from <https://tailscale.com/download>.
4. Switch off any other VPN (Cloudflare WARP, office VPN, free VPN apps).
5. In PowerShell: `ping 100.103.7.25`. If you get replies, open `http://100.103.7.25:8000`.
6. The number works but `samserver` doesn't? Tailscale icon → **Preferences** → turn on **Use Tailscale DNS settings**.
7. Check <https://login.tailscale.com/admin/machines>. If **samserver** shows as offline, the server is off or its Tailscale stopped. That needs someone at home: check the laptop has power.

## Where things are kept

| What | Where |
|---|---|
| Your code | GitHub |
| This setup kit | this repo, `github.com/sahilmandre/home-server` |
| Coolify password, 2FA recovery codes, apps' environment variables | your password manager |
| Domain registration | Hostinger |
| Domain DNS and the tunnel | Cloudflare |
| Your Tailscale devices | <https://login.tailscale.com/admin/machines> |
