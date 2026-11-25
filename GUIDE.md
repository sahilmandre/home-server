# Home server guide

Everything about your home server in one place: what it is, how to use it, how to deploy an app, how to reach it from any computer (at home or away), and how to rebuild it if everything breaks. No experience needed: every command is written out in full, with where to type it.

> This repo is public, so the guide contains no passwords or keys. It tells you where they're kept.

> **Just need the steps?** [EASY-GUIDE.md](EASY-GUIDE.md) has every everyday task as a short recipe. This guide has the details and the reasons.

**Contents**

1. [Your setup at a glance](#1-your-setup-at-a-glance)
2. [How it fits together](#2-how-it-fits-together)
3. [Everyday use](#3-everyday-use)
4. [Deploy an app](#4-deploy-an-app)
5. [Connect from another computer](#5-connect-from-another-computer)
6. [Keep it healthy](#6-keep-it-healthy)
7. [When something goes wrong](#7-when-something-goes-wrong)
8. [Rebuild from scratch](#8-rebuild-from-scratch)
9. [What we built, and why](#9-what-we-built-and-why)
10. [Words you'll see](#10-words-youll-see)

## 1. Your setup at a glance

| What | Value |
|---|---|
| The server | The spare Ubuntu laptop, named **samserver**. Your user on it: **sam** |
| Its home network address | `192.168.29.66` (keep it fixed, see [section 6](#6-keep-it-healthy)) |
| Its Tailscale address | `100.103.7.25`, or just the name `samserver` (reachable from anywhere, once Tailscale is on your device) |
| SSH | `ssh homeserver`. On the office laptop that shortcut is the home address, so it works at home only. On the Honor laptop it's the Tailscale address, so it works anywhere with Tailscale on |
| Coolify dashboard | `http://192.168.29.66:8000` at home; `http://samserver:8000` (or `http://100.103.7.25:8000`) from anywhere with Tailscale on |
| Coolify sign-in | `sahilmandre@gmail.com`, your password and the 6-digit code from your phone's authenticator app (2FA). Password and recovery codes: in your password manager. Forgot them? See [section 7](#forgot-the-coolify-password-or-lost-your-2fa-phone) |
| Your devices | **Honor laptop:** dashboard and SSH, from anywhere. **Office laptop:** dashboard and SSH, at home only (no Tailscale). **Phone:** dashboard, from anywhere |
| Your apps on the internet | `https://<name>.tradelogy.in` |
| Deploy on `git push` | GitHub App **job-mailer** (covers all your repos), webhooks arrive at `hooks.tradelogy.in` |
| Domain | `tradelogy.in`: bought at Hostinger, DNS run by Cloudflare. `tradelogy.in` and `www` are your Tradelogy site, which lives elsewhere and isn't touched by this server |
| Setup kit | This repo: `setup-server.sh` runs on the server, `connect.ps1` on your PCs |

Who can reach what:

- **Your home Wi-Fi and your Tailscale devices:** everything (SSH, the dashboard, your apps).
- **The internet:** only your apps, at `https://<name>.tradelogy.in`. Nothing is open on your router or the laptop. The dashboard is kept off the internet on purpose ([why](#9-what-we-built-and-why)).

## 2. How it fits together

```
You  ── home Wi-Fi or Tailscale ──►  samserver: SSH, Coolify dashboard
Visitors ──► https://myapp.tradelogy.in ──► Cloudflare ──tunnel──► samserver ──► your app
git push ──► GitHub ──► hooks.tradelogy.in ──► Cloudflare ──tunnel──► Coolify ──► rebuilds the app
```

The pieces, one line each:

- **samserver** (the Ubuntu laptop): the computer that runs everything. It stays on day and night, lid closed, and never sleeps.
- **SSH:** a command line to the server from your PC. It signs you in with a key file instead of a password.
- **Coolify:** the dashboard that turns a GitHub repo into a running app, like Vercel or Heroku but on your own machine. Each app runs in its own Docker container.
- **Firewall:** blocks everything coming from the internet.
- **Tailscale:** a private network of your own devices, so the server is reachable from anywhere, but only by you.
- **Cloudflare Tunnel:** how the public reaches your apps without opening the firewall. The server keeps a connection open *to* Cloudflare, and Cloudflare sends visitors down it.
- **GitHub App:** lets Coolify read your repos and hear about every push.

## 3. Everyday use

### Open the dashboard

In a browser: `http://192.168.29.66:8000` at home, or `http://samserver:8000` (the same as `http://100.103.7.25:8000`) from anywhere with Tailscale on. Type the `http://` yourself. Sign in with your email, password, and the 6-digit code from your authenticator app.

The browser calls the page "Not secure" because it's `http`. That's fine: at home it never leaves your Wi-Fi, and through Tailscale everything is encrypted anyway.

### Run commands on the server (SSH)

On this PC, open **PowerShell** (Start menu → type "PowerShell") and type:

```powershell
ssh homeserver
```

The prompt changes to `sam@samserver:~$`: what you type now runs on the server. Type `exit` to come back to your PC. To run a single command without staying: `ssh homeserver uptime`.

Handy commands, after `ssh homeserver`:

| To... | Type |
|---|---|
| See what's running | `docker ps` |
| Check free disk space | `df -h /` (look at "Avail") |
| Check memory | `free -h` |
| Check the public tunnel | `systemctl status cloudflared` (press `q` to leave) |
| Restart the server | `sudo reboot` (it's back in about a minute) |
| Install updates now | `sudo apt update && sudo apt upgrade -y` |

**After `sudo reboot`:** the server is back in about a minute (measured: off at 0:11 seconds, Coolify running again at 0:46). But the SSH window you typed it in doesn't close: it freezes, and stays frozen for up to 2 minutes, so it looks as if the server never came back. Close that window (or press Enter, then type `~.`), wait a minute, and run `ssh homeserver` in a new one. In the browser, reload the dashboard.

### See how busy it is (memory, CPU, disk, power)

- **Graphs, in the dashboard:** **Servers** → **localhost** → **Metrics** shows the server's CPU and memory use, for up to the last 7 days. Each app has its own: the app → **Metrics**.
- **Live, everything on one screen:** `ssh -t homeserver btop`. It shows each CPU core, memory, disk, network, temperatures, the battery, and which programs use the most. Press `q` to leave.
- **Memory per app:** after `ssh homeserver`, type `docker stats` (Ctrl+C to leave). Apps are listed by their Coolify ID: the last code in the app's address when you open it in the dashboard.
- **Power:** `ssh homeserver power-guard status` says whether it's on the charger and how full the battery is.

For scale: Coolify itself and the current apps use about 2 GB of the 7 GB of memory, which leaves room for several more apps. Each time job-mailer runs a browser, it briefly uses a few hundred MB more. The laptop draws about 6 watts (measured on battery), which comes to roughly 4 to 5 units (kWh) of electricity a month.

### Edit files on the server with VS Code

1. In VS Code, open **Extensions** and install **Remote - SSH** (by Microsoft).
2. Press **F1**, choose **Remote-SSH: Connect to Host...**, then **homeserver**.
3. A new window opens on the server. **File → Open Folder** → `/home/sam`.

### Copy files

```powershell
scp .\notes.txt homeserver:~/        # from this PC to the server
scp homeserver:~/notes.txt .\        # from the server to this PC
```

## 4. Deploy an app

### Before you start

The app must be in a GitHub repo; the GitHub App can see all of yours. Find out three things, usually from the repo's `package.json` or README:

1. **The port** it listens on. Look for `PORT` or `listen(3000)` in the code. Many Node apps use 3000. Ignore the development ports: Vite's 5173, for example, only exists while you code. A deployed React or Vite frontend is built into plain files, and either Coolify serves them itself (a static site), or your backend serves them (then use the backend's port, and deploy one app, not two).
2. **How it builds and starts.** The `"build"` and `"start"` scripts in `package.json`; Coolify runs them by itself.
3. **Its settings (environment variables):** database URLs, API keys and so on. The names are usually in `.env.example`.

A server app must listen on `0.0.0.0` (every address), not `localhost`. Otherwise Coolify can't reach it, and you'll see "Bad Gateway".

### Step by step

1. Open the dashboard → **Projects** → **New project**. Name it (for example `apps`) and create it. One project can hold many apps.
2. Open the project, then its **production** environment, and click **New resource**.
3. Choose **Git Repository (with GitHub App)**. If it asks for a server, pick **localhost**.
4. Pick the GitHub App **job-mailer**, then fill in:
   - **Repository:** your repo.
   - **Branch:** usually `main`.
   - **Build pack:** see [Which build pack?](#which-build-pack) below. When unsure, **Nixpacks**.
   - **Port:** the port from "Before you start".

   Click **Continue**.
5. You're on the app's page. Coolify has already given it a random address like `https://abc123.tradelogy.in`. To choose your own, on the **General** tab click **Manage application domains** (or **Add an application domain**) and enter `https://myapp.tradelogy.in`. Any name before `.tradelogy.in` works; always start it with `https://`.
6. Add its settings under **Environment variables**: **New Environment Variable** for each one. To paste many at once, switch to **Developer view** and paste lines like `KEY=value`.
7. Click **Deploy** (top right) and watch the log. The first build takes 1 to 5 minutes.
8. Open `https://myapp.tradelogy.in`.

From now on, every `git push` to that branch rebuilds and redeploys the app within about a minute. (That's the **Auto deploy** switch under **Advanced**, on by default.) After changing environment variables, click **Deploy** again so the app picks them up.

### Which build pack?

| Your app | Build pack | Also set |
|---|---|---|
| Node.js API (Express, NestJS...) | Nixpacks | **Port** = your app's port |
| Next.js, Nuxt, Remix | Nixpacks | **Port** 3000 |
| React, Vite or Angular site with no server of its own | Nixpacks | **Output type**: Static site, **Publish directory**: `/dist` (Vite) or `/build` (Create React App). Afterwards, on **General**, set **Site type** to **SPA (single-page application)** if the app has its own page routing (React Router), or refreshing a sub-page gives "404" |
| Plain HTML/CSS/JS files | Static | **Port** 80 |
| The repo has a `Dockerfile` | Dockerfile | **Port** = the one the Dockerfile uses |
| The repo has a `docker-compose.yml` | Docker Compose | a domain for each service that needs one |
| Python (FastAPI, Flask, Django) | Nixpacks | **Port** (often 8000) |

### Add a database

1. In the same project: **New resource** → **MongoDB** (or PostgreSQL, MySQL, Redis...), then **Start**.
2. Copy its **Mongo URL (internal)** (or **Postgres URL (internal)**...).
3. In your app: **Environment variables** → add the setting your app reads (for example `MONGODB_URI`) with the copied URL → **Deploy**.

The "internal" URL only works for apps on the same server, which is what you want: the database itself is never on the internet.

### Example: job-mailer

- It's one repo with `client`, `server` and `shared` folders. `npm run build` builds both halves, and `npm start` runs the server, which also serves the built frontend. So it's **one app, port 5000**. (5173 is only Vite's development server.)
- Settings it needs: `MONGODB_URI` (from a MongoDB resource, as above), `JWT_SECRET` and `ENCRYPTION_KEY` (each from `ssh homeserver openssl rand -hex 32`; keep `ENCRYPTION_KEY` safe, because data saved with one key can't be read with another), `NODE_ENV=production`, `FRONTEND_URL=https://<its-address>` and `TRUST_PROXY=true`.
- It drives a Chrome browser with **Puppeteer** (for LinkedIn and Naukri). No `Dockerfile` is needed: `npm install` downloads Chrome, and Nixpacks adds the system libraries it needs. But apps in Docker run as the `root` user, and Chrome refuses to start as root unless it's given `--no-sandbox` ("Running as root without --no-sandbox is not supported"). job-mailer adds that flag itself when it runs as root (`server/src/lib/browser.ts`).
- It keeps its LinkedIn and Naukri sign-ins in `/app/server/data`, so that folder needs [persistent storage](#keep-files-across-deploys), or every redeploy signs you out. (Done for job-mailer, along with `/app/server/logs`, where it saves debug screenshots.)

### Keep files across deploys

Every deploy starts the app from a fresh copy, so anything it saved in its own folders is gone. Store data in a database, or give each folder the app writes to a volume: the app → **Persistent Storage** → **+ Add** → **Volume mount**, any **Name**, and as **Destination Path** the folder inside the container (the repo's files are under `/app`). Then **Deploy**. Files in that folder now stay on the server's disk.

### When a deploy doesn't work

| What you see | Likely cause | Fix |
|---|---|---|
| The deploy log ends in red | The build failed | Read the last red lines. Common causes: a missing environment variable, or a Node version mismatch (add `"engines": { "node": ">=20" }` to `package.json`) |
| "Bad Gateway" | Wrong port, or the app listens on `localhost` | Fix **Ports exposes** on **General**; make the app listen on `0.0.0.0` |
| "404 page not found" | The address doesn't match the app's domain | Check the domain's spelling on **General** |
| "no available server" | The app crashed while starting | Open the app's **Logs** to see the error |
| Uploads, sign-ins or other files disappear after a deploy | The app saves them in its own folder | [Keep files across deploys](#keep-files-across-deploys) |
| "Running as root without --no-sandbox is not supported" | A Puppeteer/Chrome app running as root, the default in Docker | Start Chrome with `--no-sandbox` (job-mailer does this) |
| A push didn't redeploy | GitHub's message didn't arrive, or a different branch | On GitHub: **Settings → Developer settings → GitHub Apps → job-mailer → Edit → Advanced → Recent Deliveries**. Each push should show a green 200. Also check the branch matches the app's |

## 5. Connect from another computer

How access works: SSH on the server doesn't accept passwords, only keys. A key is a pair of files made on your computer: a private one that never leaves it, and a public one that you give the server. Each computer gets its own key, added once. Today two have one: the office laptop and the Honor laptop.

**Personal laptop: use B (Tailscale), even at home.** Its `ssh homeserver` then works the same in every city. A is for a computer that can't run Tailscale, like the office laptop.

### A. Another Windows laptop, at home

1. On the new laptop, get this repo: open <https://github.com/sahilmandre/home-server>, click **Code → Download ZIP**, and unzip it.
2. Open PowerShell in that folder: in File Explorer, click the address bar, type `powershell`, press Enter. Then run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\connect.ps1 -HostAddress 192.168.29.66 -User sam
   ```
3. It makes a key, then says it couldn't sign in. That's expected, because the server doesn't take passwords. It prints a line that starts with `echo 'ssh-ed25519 ...`.
4. Copy that line and run it in PowerShell on a computer that already connects (like this PC).
5. Back on the new laptop, run the command from step 2 again. It ends with "Connected", and `ssh homeserver` now works there too.

### B. Away from home (Tailscale)

Tailscale joins your devices into one private network, wherever each of them is. This is how the Honor laptop was set up (26 November).

1. Install Tailscale on the laptop (<https://tailscale.com/download>) and sign in with **the same account as the server** (`sahilmandre@`). If Tailscale is already installed but hasn't been used for months, install the latest version over it first: an old one may say "Connected" without really connecting.
2. Check it: at <https://login.tailscale.com/admin/machines>, both **samserver** and this laptop should be listed as connected.
3. Test it: open `http://100.103.7.25:8000`. The Coolify dashboard should appear. If it doesn't, see [If Tailscale is on but nothing opens](#if-tailscale-is-on-but-nothing-opens).
4. For SSH: get this repo (section A, step 1), open PowerShell in its folder, and run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\connect.ps1 -HostAddress 100.103.7.25 -User sam
   ```
5. It makes a key, then says "Couldn't sign in" in red. That's expected. It prints a line starting with `echo 'ssh-ed25519 ...`. Run that line on a computer that already connects:
   - **the Honor laptop**, with Tailscale on, from anywhere: run the line as printed;
   - **the office laptop**, at home only: run the line as printed.
6. Back on the new laptop, run the command from step 4 again. It ends with a green "Connected". `ssh homeserver` now works there, at home and away, as long as Tailscale is on.

   If the laptop already has a `homeserver` shortcut for the home address, add a second one instead. Open `C:\Users\<you>\.ssh\config` in Notepad and add at the end:
   ```
   Host homeserver-ts
     HostName 100.103.7.25
     User sam
     IdentityFile ~/.ssh/id_ed25519_homeserver
     IdentitiesOnly yes
   ```
   Then use `ssh homeserver-ts` when you're away.

Company laptops may not be allowed to run Tailscale. Without it, away from home they can only open your public apps.

**Away from home, the home address leads somewhere else.** Most Jio routers hand out the same `192.168.29.x` addresses, so on a Jio Wi-Fi in another city, `192.168.29.66` is some other home's device, or nothing at all. A shortcut with the home address (like the office laptop's `ssh homeserver`) then times out. Or it warns "REMOTE HOST IDENTIFICATION HAS CHANGED": that's a stranger's computer, so answer **no**. Away from home, only the Tailscale address reaches your server.

### If Tailscale is on but nothing opens

"This site can't be reached", or `ssh homeserver` times out, while Tailscale says it's on. Go down this list:

1. **Is this device really connected?** Open <https://login.tailscale.com/admin/machines>. If this device shows as offline there, its Tailscale isn't really connected, whatever the app says.
2. **Reconnect.** Click the Tailscale icon near the clock (it may be under the **^** arrow), click **Disconnect**, then **Connect**. If it asks you to log in, log in.
3. **Update it.** Install the latest version from <https://tailscale.com/download> over the old one. Your sign-in is kept. (This fixed the Honor laptop, whose Tailscale hadn't been used since July.)
4. **Switch off other VPNs:** Cloudflare WARP, an office VPN, free VPN apps. Two VPNs on one device often block each other.
5. **Test** in PowerShell: `tailscale status` should list samserver, and `ping 100.103.7.25` should get replies. If so, open `http://100.103.7.25:8000`.
6. **The number works but `samserver` doesn't:** Tailscale icon → **Preferences** → turn on **Use Tailscale DNS settings**.
7. **samserver shows as offline** on the machines page: the server is off, or its Tailscale has stopped. That needs someone at the server: check it has power, and if it does, open a terminal on it (Ctrl+Alt+T) and run `sudo tailscale up`.

### C. A Mac or Linux laptop

In its Terminal:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_homeserver -N ""
cat ~/.ssh/id_ed25519_homeserver.pub
```

On a computer that already connects, add that printed line to the server:

```powershell
echo 'PASTE-THE-LINE-HERE' | ssh homeserver "tr -d '\r' >> ~/.ssh/authorized_keys"
```

Then add the `Host` block from section B to `~/.ssh/config` on the Mac, with `Host homeserver` and the address you want (`192.168.29.66` at home, `100.103.7.25` with Tailscale).

### D. Your phone

- **Dashboard:** install the Tailscale app, sign in with the same account, then open `http://100.103.7.25:8000` in the browser.
- **SSH:** use an app such as Termius. Create a key in the app, add its public key with the `echo` line from section C, and connect to `100.103.7.25` as user `sam`.

### Lost a laptop, or stopped using one?

Take its access away, from another laptop that connects:

1. At <https://login.tailscale.com/admin/machines>: click **⋯** next to it → **Remove**.
2. See which keys the server accepts: `ssh homeserver ssh-keygen -lf .ssh/authorized_keys`. Each line ends with the computer's name, like `sahil@SAHIL to homeserver` for the Honor laptop.
3. Remove that computer's key: `ssh -t homeserver nano .ssh/authorized_keys`. Move to its line with the arrow keys, press **Ctrl+K** to delete the line, then **Ctrl+O**, **Enter** to save and **Ctrl+X** to leave. Be careful not to delete the line of the laptop you're using.

### Locked out?

If no computer can connect any more (for example, you lost the only PC with a key):

1. At the server laptop itself, sign in to the desktop with your Ubuntu password and open **Terminal** (Ctrl+Alt+T).
2. Turn password sign-in back on for a moment:
   ```bash
   sudo rm /etc/ssh/sshd_config.d/01-server.conf && sudo systemctl reload ssh
   ```
3. On your PC, run `connect.ps1` as in section A. This time it asks for your Ubuntu password.
4. Turn password sign-in off again, from your PC:
   ```powershell
   ssh -t homeserver "cd ~/home-server && sudo bash setup-server.sh --tailscale --domain tradelogy.in"
   ```

## 6. Keep it healthy

- **Leave it plugged in**, somewhere with airflow. Closing the lid is fine.
- **Keep its home address fixed.** In your Jio router (usually `http://192.168.29.1`), reserve `192.168.29.66` for the laptop. The setting is called "DHCP reservation" or "static lease", under LAN or DHCP settings. If the address ever changes, `ssh homeserver` stops working at home.
- **Updates:** security updates install by themselves every day. About once a month, install everything else and restart:
  ```powershell
  ssh -t homeserver "cd ~/home-server && git pull && sudo bash setup-server.sh --tailscale --domain tradelogy.in"
  ssh homeserver sudo reboot
  ```
  Re-running the setup is always safe: it installs updates and re-checks every setting.
- **Coolify** updates itself.
- **Tailscale key expiry is off for samserver** (turned off on 26 November). Tailscale signs every device out after 180 days unless you turn this off. For the server, that would mean no access from outside home until someone at the laptop signs it in again (it was due on 6 January 2027). After a rebuild, turn it off again: <https://login.tailscale.com/admin/machines> → **⋯** next to samserver → **Disable key expiry**. Your phone and laptops can keep expiry on: when theirs runs out, the app just asks you to sign in again.
- **Disk space:** check with `ssh homeserver df -h /`. Every deploy keeps a copy of the app's image. If free space drops below about 20 GB, `ssh homeserver docker image prune -a -f` removes the images no app is using; running apps are not affected.
- **Power cuts** are handled by themselves, in three stages:
  1. The battery keeps the server running. This battery is worn: it holds about 15 Wh where a new one holds 41 Wh, so it reaches 40% after about 1¼ hours.
  2. At 40% the server shuts down cleanly, rather than running until the battery dies in the middle of writing something.
  3. Every 10 minutes, the laptop's clock switches it on to check for power. If the charger is still dead, it switches off again within about 35 seconds. Once power is back, it starts normally. Your apps are back about 10 minutes after the power is.

  The remaining 40% lasts about 3½ hours of these checks, so a cut of up to about 4½ hours is covered, about as long as the router's UPS lasts. To see what happened during a cut: `ssh homeserver journalctl -t power-guard`.

  **Why 40%, and not lower:** a worn battery's percentage can't be trusted near the end. On 7 October, at 15%, the server stopped as planned and checked twice, reading 14% and then 12%. By then the battery was really almost empty (10.4 V, where 12.6 V is full). The burst of power at the next start cut it out completely, and the server stayed off.

  **If the battery does run completely flat** (a cut longer than about 4½ hours), the laptop stays off when power returns, and only its power button starts it. The clock's wake-up time is lost along with the power. This HP's BIOS also has no "power on when the charger connects" setting, and the chip setting that does this can't be changed while Secure Boot is on.

  **With a new battery** (HP part TF03XL; check the number printed on your old one), it runs about 4 hours before reaching 40%, and then has many hours of checks left. Most cuts then cause no downtime at all. You can also let it run longer: put `SHUTDOWN_AT=25` in `/etc/default/power-guard` on the server.
- **Your router needs power too.** During a cut the Jio router would go off as well, and your apps with it. Yours is on a mini UPS that lasts about 4.5 hours, longer than the usual cut.
- **Battery health:** a battery kept full all the time ages faster, and old batteries can swell. If the laptop's case or touchpad starts to bulge, unplug it and replace the battery.
- **Back up what GitHub can't:** your code is safe on GitHub, but each app's environment variables and database contents live only on the server. Keep the variables in a password manager. For databases with data you care about, Coolify can make scheduled backups (the database's **Backups** page) to S3 storage such as Cloudflare R2, which is free up to 10 GB. This isn't set up yet.

## 7. When something goes wrong

| Problem | Check | Fix |
|---|---|---|
| `ssh homeserver` hangs or times out | Is the laptop on? Are you on the home Wi-Fi? Is a company VPN connected? | Disconnect the VPN, or use Tailscale (section 5B). Check the laptop has power |
| `ssh homeserver` times out away from home | Does this laptop's shortcut use the home address (`192.168.29.66`)? | That only works at home ([why](#b-away-from-home-tailscale)). Use Tailscale and its address `100.103.7.25` |
| Tailscale is on, but "This site can't be reached" | <https://login.tailscale.com/admin/machines>: are this device and samserver connected? | [If Tailscale is on but nothing opens](#if-tailscale-is-on-but-nothing-opens) |
| The SSH window froze after `sudo reboot` | Normal: it doesn't notice the server went away | Close it, wait a minute, open a new one ([details](#3-everyday-use)) |
| Forgot the Coolify password, or lost the 2FA phone | | [See below](#forgot-the-coolify-password-or-lost-your-2fa-phone) |
| "REMOTE HOST IDENTIFICATION HAS CHANGED" | The server was reinstalled | `ssh-keygen -R 192.168.29.66` (and `ssh-keygen -R 100.103.7.25`), then connect again |
| "Permission denied (publickey)" | This computer's key isn't on the server | Section 5A |
| The dashboard won't open | `ssh homeserver docker ps`: does `coolify` say "healthy"? | `ssh homeserver sudo reboot`, then wait 2 minutes |
| Apps work at home but not on the internet | `ssh homeserver systemctl is-active cloudflared` | `ssh homeserver sudo systemctl restart cloudflared` |
| Every `https://` app says "redirected you too many times" (`ERR_TOO_MANY_REDIRECTS`), or never finishes loading | The proxy lost its "trust the tunnel" setting ([what happened on 26 November](#9-what-we-built-and-why)) | Re-run the setup: `ssh -t homeserver "cd ~/home-server && git pull && sudo bash setup-server.sh --tailscale --domain tradelogy.in"`. It puts the setting back |
| Nothing works after a power cut | It switches itself on within 10 minutes of the power coming back, then needs about 2 minutes to start everything | Still off after 15 minutes? The battery ran completely flat: press the power button. `ssh homeserver journalctl -t power-guard` then shows how far it got (see "Power cuts" in [section 6](#6-keep-it-healthy)) |
| The laptop switches itself off right after you switch it on | No charger, and the battery is below 40%: the power-cut protection at work | Plug in the charger, then switch it on |
| A deploy fails | | [When a deploy doesn't work](#when-a-deploy-doesnt-work) |
| `ssh homeserver` fails at home, but Tailscale works | The laptop's home address changed | Reserve the address in the router (section 6), or put the new address in `HostName` in `C:\Users\<you>\.ssh\config` |

### Forgot the Coolify password, or lost your 2FA phone

There's no "Forgot password?" email: Coolify can only send one if email sending is set up, and it isn't on this server. Reset it from a laptop that has SSH (the Honor laptop with Tailscale on, or the office laptop at home).

**Forgot the password.** In PowerShell:

```powershell
ssh -t homeserver "sudo docker exec -ti coolify php artisan root:reset-password"
```

It asks "Give me a new password for root user", then "Again". Nothing appears while you type, which is normal. Then sign in with the new password (2FA stays on) and save it in your password manager.

**Lost the phone with the authenticator app.** On the sign-in page, enter one of the recovery codes Coolify showed when you turned on 2FA, instead of the 6-digit code. No recovery codes either? Turn 2FA off from a laptop with SSH:

1. Run `ssh homeserver`, then on the server: `sudo docker exec -it coolify php artisan tinker`
2. At its `>` prompt, paste this line and press Enter. It answers `true`:
   ```php
   App\Models\User::find(0)->forceFill(['two_factor_secret' => null, 'two_factor_recovery_codes' => null, 'two_factor_confirmed_at' => null])->save();
   ```
3. Type `exit` twice.
4. Sign in with just the password, then turn 2FA on again in your **Profile**, with the new phone. Save the new recovery codes in your password manager.

(User 0 is the admin account, `sahilmandre@gmail.com`. Both commands only change that account.)

## 8. Rebuild from scratch

Use this if the laptop dies, its disk is wiped, or you move to another machine.

- **Safe elsewhere:** your code (GitHub), the domain and the tunnel (Cloudflare), your Tailscale account, and this setup kit (GitHub).
- **Lost:** Coolify's settings and list of apps, the apps' environment variables, database contents (unless backed up), and the server's keys.
- **Time:** about an hour, mostly waiting. The kit does nearly everything: you type about five commands and approve three sign-in links.

### Step 1: Install Ubuntu

1. On any PC, download **Ubuntu Desktop 26.04 LTS** from <https://ubuntu.com/download/desktop>. Write it to a USB stick (8 GB or more) with **balenaEtcher** or **Rufus**.
2. Plug the stick into the laptop and switch it on, pressing the boot-menu key (often F12, F2 or Esc) to start from the USB.
3. Choose **Erase disk and install Ubuntu**. Use: your name, computer name **samserver**, username **sam**, and a password you'll remember. Connect to your Wi-Fi when asked.
4. When it's installed, plug in the charger, and an Ethernet cable if you can.

### Step 2: Run the setup on the laptop

On the laptop, open **Terminal** (Ctrl+Alt+T) and type:

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/sahilmandre/home-server.git
cd home-server
sudo bash setup-server.sh --tailscale --admin-email sahilmandre@gmail.com
```

It takes 10 to 20 minutes. When it's done:

1. **Tailscale:** first remove the old **samserver** at <https://login.tailscale.com/admin/machines>, so the new laptop gets the same name. Then run `sudo tailscale up`, open the link it prints and sign in. Back on the machines page, click **⋯** next to the new samserver → **Disable key expiry** ([why](#6-keep-it-healthy)). Note the new Tailscale address (`tailscale ip -4`); it replaces `100.103.7.25` everywhere in this guide. On the Honor laptop, put it in `HostName` in `C:\Users\<you>\.ssh\config`, and run `ssh-keygen -R 100.103.7.25` there.
2. **Home address:** run `hostname -I`. The first address is the laptop's home address. If it isn't `192.168.29.66`, use the new one below and in your router reservation.

### Step 3: Connect your PC

On your PC, in PowerShell, in this repo's folder:

```powershell
ssh-keygen -R 192.168.29.66
powershell -ExecutionPolicy Bypass -File .\connect.ps1 -HostAddress 192.168.29.66 -User sam
```

The first line makes your PC forget the old server's fingerprint. The script then asks for your Ubuntu password twice.

### Step 4: Lock SSH, connect the domain, restart

```powershell
ssh -t homeserver "cd ~/home-server && sudo bash setup-server.sh --tailscale --domain tradelogy.in"
```

It prints a Cloudflare link: open it, click **tradelogy.in**, then **Authorize**. Because the new laptop is also called samserver, the script finds the existing tunnel and DNS record and reconnects them. (With a different name it would make a new tunnel. Then, in Cloudflare, delete the old tunnel and the `*` DNS record, and run the command again.) Finally:

```powershell
ssh homeserver sudo reboot
```

### Step 5: Set up Coolify again

1. **Sign in** at `http://192.168.29.66:8000` with the email and password from `ssh homeserver sudo cat /root/coolify-admin.txt`. In your **Profile**, change the password and turn on 2FA. Save the password and the recovery codes in your password manager, then delete the file: `ssh homeserver sudo rm /root/coolify-admin.txt`.
2. **GitHub App:** the old app's keys were on the old server, so make a new one. On GitHub: **Settings → Developer settings → GitHub Apps → job-mailer → Edit → Advanced → Delete GitHub App**. Then follow [README → Deploy automatically on git push](README.md#deploy-automatically-on-git-push), all six steps.
3. **Apps:** add each one again with [section 4](#4-deploy-an-app), pasting its environment variables from your password manager. Create the databases again, and restore their backups if you have them.

### Step 6: Check

- `https://<app>.tradelogy.in` opens, and a `git push` redeploys it.
- On your phone, with Wi-Fi off (mobile data only), the app still opens.

### Faster next time (optional)

- **Disk image:** a tool like Clonezilla copies the whole disk to a USB drive. Restoring it brings back everything exactly as it was when you made the copy, but only onto the same or a very similar laptop.
- **Coolify backups:** Coolify can back up its own settings and your databases to S3 storage. With those, step 5 is mostly a restore instead of re-entering everything. This isn't set up yet.

## 9. What we built, and why

1. **We started clean.** The laptop had collected three tools doing the same job (Coolify, Portainer, Dockge), a background script rewriting the proxy's settings, databases open to the whole home network, and a public Tailscale Funnel. We deleted all of it (no data was needed) and reinstalled from this kit.
2. **One setup script**, `setup-server.sh`, that's safe to run again and makes a laptop behave like a cloud server. It:
   - installs all updates, including the ones Ubuntu holds back (new kernel, NVIDIA driver);
   - stops it sleeping with the lid closed, turns off Wi-Fi power saving, and checks that the Wi-Fi reconnects with nobody signed in;
   - gets it through power cuts: it shuts down cleanly at 40% battery and switches itself back on once power returns (`power-guard`);
   - makes SSH key-only, and adds fail2ban against password guessers;
   - sets up the firewall: home network and Tailscale in, internet out. That includes the ports Docker publishes, which normally slip past Ubuntu's firewall;
   - turns on daily security updates;
   - installs Tailscale, Coolify (with your admin account created during the install, and its CPU and memory graphs on) and the Cloudflare Tunnel.
3. **The domain:** tradelogy.in's DNS moved from Hostinger to Cloudflare (Hostinger still holds the registration). One DNS record, `*.tradelogy.in`, sends every subdomain without a record of its own to the tunnel. Your Tradelogy site at `tradelogy.in` and `www` is untouched.
4. **Problems that testing found, and their fixes:**
   - Apps saw every visitor as plain `http` coming from a Docker address. That breaks logins, cookies and `https://` redirects. Now the proxy trusts the tunnel's forwarded headers.
   - Wi-Fi power saving stayed on, because Ubuntu's own setting overrode ours. Renaming our file fixed it.
   - Coolify's API was off, and the API can't set the default app domain. The script now sets both on a fresh install.
   - Setting Coolify's "Instance's Domain" would have locked the dashboard to that one name. It's left empty; instead, webhooks get their own address, `hooks.tradelogy.in`, which only lets `/webhooks/...` through.
   - GitHub App registration only finishes when GitHub returns your browser to the address where you're signed in. So you register with the dashboard address, then point the webhook at `hooks.tradelogy.in`.
   - **26 November: all apps stopped loading after "Restart Proxy" was clicked in the dashboard.** Coolify keeps its own copy of the proxy settings in its database, and writes that copy back whenever the proxy is restarted from the dashboard. The setup had only changed the file, so the "trust the tunnel" setting disappeared and every `https://` app redirected to itself forever. The fix: the settings are now also saved in Coolify's copy (the setup script does this too). A dashboard restart was tested afterwards and keeps them. **Restart Proxy is safe to click now.**
5. **The dashboard stays private** (decided on 26 November). It could live at `https://coolify.tradelogy.in`, through the tunnel, behind a Cloudflare Access login. Then any browser could open it without Tailscale. We chose not to, because whoever gets into Coolify controls the whole server and every app's passwords, and serious security holes have been found in Coolify before. Tailscale already gives the phone and the Honor laptop access from anywhere. If it's ever needed: set up the Cloudflare Access login first, then the tunnel route, and keep Coolify's Instance's Domain empty.
6. **What was tested:**
   - A simulated internet computer couldn't reach any port, over IPv4 or IPv6, while home addresses could.
   - Apps deployed from GitHub and opened over HTTPS from outside.
   - A push went live in under a minute.
   - Re-running the setup changed nothing.
   - After each reboot, everything came back by itself.
   - A power cut, simulated with the charger unplugged: the server shut down, switched itself on every 2 minutes (for the test) and back off while the charger was out, and started normally once it was plugged in. It also wakes on time when the charger is plugged in while it's off.
   - A real 4-hour run on battery, with the limit then at 15%, showed that a worn battery can't be run that low (see "Power cuts" in [section 6](#6-keep-it-healthy)), so the limit is now 40%.

Test leftovers you can delete whenever you like: the Coolify project **samples** (sample-node, sample-vite, sample-db, autodeploy-ghapp), and the private GitHub repo **homeserver-autodeploy-test**.

## 10. Words you'll see

| Word | Meaning |
|---|---|
| Server | A computer that stays on to do work for other computers |
| SSH | Typing commands into another computer over the network |
| SSH key | A pair of files that proves who you are, instead of a password. The private half never leaves your computer |
| Terminal / PowerShell | The window where you type commands |
| Docker, container | A sealed box holding one app and everything it needs, so apps don't get in each other's way |
| Coolify | The dashboard that builds your GitHub repos into containers and runs them |
| Deploy | Build the latest code and start it |
| Port | A numbered door on a computer. Each app listens on one, such as 3000 |
| Firewall | The rules for who may knock on which door |
| Environment variable | A setting handed to an app from outside its code, such as a password or a database URL |
| Build pack | Coolify's recipe for turning your code into a container |
| Domain, subdomain | `tradelogy.in`, and `myapp.tradelogy.in` |
| DNS | The internet's phone book: turns names into addresses |
| Nameservers | Whoever runs a domain's phone book. For tradelogy.in, that's Cloudflare |
| Cloudflare Tunnel | A connection the server opens to Cloudflare, so visitors reach your apps without any open door |
| Tailscale | A private network of your own devices that works from anywhere |
| Webhook | A message one service sends another when something happens ("new push!") |
| GitHub App | What lets Coolify read your repos and receive webhooks from GitHub |
