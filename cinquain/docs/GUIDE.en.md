# Cinquain Beginner's Deployment Guide (English)

This guide is written for people with no server administration experience.
Follow it step by step and you will have your own Matrix chat server in about
15 minutes — able to talk to Matrix users anywhere in the world.

---

## Step 0: What you need

| Item | Details | Approx. cost |
|---|---|---|
| A cloud server (VPS) | Freshly installed Debian 12 / Ubuntu 22.04+ or Fedora/RHEL, at least 2 GB RAM and 10 GB disk | from a few $/month |
| A domain name | e.g. `example.com`; your user ID will look like `@you:matrix.example.com` | ~$10/year |
| Your own computer | Windows / macOS / Linux with a terminal | — |

> **Important**: the Matrix domain **cannot be changed** after deployment
> (this is how the Matrix protocol works). Changing it means starting over
> with an empty server. Choose carefully.

### Do this first: point DNS at your server

In your domain provider's dashboard (Cloudflare, Namecheap, etc.), add a DNS
record:

- **Type**: A
- **Host**: `matrix` (making the full name `matrix.example.com`)
- **Value**: your server's public IP address

Wait 5–10 minutes, then run `ping matrix.example.com` on your computer — if it
shows your server's IP, DNS is ready.

Also make sure your cloud provider's **firewall / security group** allows
inbound TCP ports **80 and 443** (port 22 for SSH is usually open already).

---

## Step 1: Run one command on the server

Log in to your server over SSH (on Windows, use the built-in Terminal or
PowerShell):

```bash
ssh root@YOUR_SERVER_IP
```

There are two ways to continue. Pick one.

### Option 1 (simplest): one command, fully unattended

Put your domain and email straight into the command and nothing else is needed:

```bash
curl -fsSL https://raw.githubusercontent.com/Mcxiaocaibug/Cinquain/cinquain-v0.0.1/cinquain/bootstrap.sh \
  | sudo sh -s -- matrix.example.com admin@example.com
```

Replace `matrix.example.com` with your Matrix domain and `admin@example.com` with
your email (used for certificate expiry notices).

It installs the dependencies, checks DNS and ports, obtains the HTTPS
certificate, starts the services, and finally prints the **first registration
token**. Once you see the token you are done — skip ahead to "Create your
account".

If the domain does not point at this server yet, or another program already holds
port 80/443, the command stops immediately and tells you exactly why, instead of
failing at the very end.

### Option 2: step-by-step in the web panel

Leave out the domain and email to install only the panel and fill things in from a
browser:

```bash
curl -fsSL https://raw.githubusercontent.com/Mcxiaocaibug/Cinquain/cinquain-v0.0.1/cinquain/bootstrap.sh | sudo sh
```

It installs Docker and everything else automatically, then starts a web
deployment panel that **only you can reach**. When it finishes, it prints two
key lines, similar to:

```
On your computer, run: ssh -N -L 7080:127.0.0.1:7080 root@203.0.113.10
Then open: http://127.0.0.1:7080/#token=a-long-random-string
```

**Copy and save both lines.**

---

## Step 2: Open the panel from your own computer

For security, the panel is not exposed to the internet. You reach it through
an "SSH tunnel" — think of it as an encrypted private line from your computer
to the server:

1. Open a **new terminal window on your own computer** and run the
   `ssh -N -L 7080:...` command printed in Step 1.
2. It will **appear to hang — that is normal**. The tunnel is working.
   Keep this window open.
3. Open your browser and visit the full `http://127.0.0.1:7080/#token=...`
   URL from Step 1.

You should now see the Cinquain deployment panel.

---

## Step 3: Deploy from the web page

1. Enter your **Matrix domain** (e.g. `matrix.example.com` — the one from
   Step 0).
2. Enter an **operator email** (used for the free HTTPS certificate; your
   normal email is fine).
3. Click **Verify and deploy**.

The panel streams live progress: pulling images → writing configuration →
starting services → automatic HTTPS certificate → health checks. It takes
2–5 minutes and needs no input from you.

When everything is green, the panel shows a **single-use registration
token**. Copy it — it is the key to creating the administrator account and
works exactly once.

---

## Step 4: Register your admin account

1. Open the registration page shown by the panel:
   `https://matrix.example.com/_continuwuity/account/register/`
2. Choose a username and password, and paste the registration token.
3. Done — **the first registered account automatically becomes the server
   administrator**.

---

## Step 5: Start chatting

1. Download the **Element** client
   ([element.io](https://element.io/download), available for phone and
   desktop).
2. At login, choose **"Other / custom homeserver"** and enter
   `https://matrix.example.com`.
3. Sign in with the account you just created.

Your full Matrix ID is `@username:matrix.example.com`. You can chat with any
Matrix user, including people on `matrix.org`.

---

## Day-to-day operations (optional but recommended)

Run all commands on the **server**, inside `/opt/cinquain`:

```bash
cd /opt/cinquain

./cinquain status     # are the services running?
./cinquain doctor     # full health check
./cinquain logs       # view logs
./cinquain backup     # manual backup (archives land in backups/)
./cinquain restore backups/SOME-ARCHIVE.tar.gz   # restore from a backup
./cinquain upgrade    # upgrade (backs up first, rolls back on failure)
```

Recommendations:

- **Back up regularly** and copy the files in `backups/` somewhere off the
  server. Backups contain all chat data — treat them as secrets.
- If you no longer need the panel after deployment, turn it off:
  ```bash
  sudo systemctl disable --now cinquain-panel
  ```
  You can bring it back any time with `sudo systemctl start cinquain-panel`.

---

## Troubleshooting

**Q: The panel says the token is invalid.**
The URL must include the full `#token=...` fragment. Re-copy the complete URL
from Step 1. The token is also stored on the server in
`/etc/cinquain/panel.env` (readable with `sudo cat`).

**Q: Deployment is stuck on the HTTPS certificate.**
Almost always DNS not propagated yet, or ports 80/443 blocked. Re-check both
items in Step 0, then click deploy again in the panel (the command is
idempotent — re-running it is safe).

**Q: The registration token is empty.**
The admin account has already been registered (the token works once), or the
homeserver is not ready yet. On the server run
`cd /opt/cinquain && ./cinquain token`.

**Q: Can I change the domain?**
No. The only path is to start fresh: back up anything you need, remove the
Docker volumes, and deploy again.

**Q: Do the services come back after a server reboot?**
Yes. All containers restart automatically; no action needed.
