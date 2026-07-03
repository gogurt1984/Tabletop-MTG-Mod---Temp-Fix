# Gogurt's 6 Player MTG Table — Setup Guide

A fixed version of the [MTG EDH 6-player (π)](https://steamcommunity.com/sharedfiles/filedetails/?id=2293586471) Tabletop Simulator table that works around Scryfall's block on Unity Player by routing all card images and data through your own free Cloudflare Worker.

Free, ~10–15 minutes, no credit card required.

## Table of contents

- [Why this exists](#why-this-exists)
- [What's in this folder](#whats-in-this-folder)
- [Step 1 — Create a free Cloudflare account](#step-1--create-a-free-cloudflare-account)
- [Step 2 — Deploy the Worker](#step-2--deploy-the-worker)
- [Step 3 — Run the installer](#step-3--run-the-installer)
- [Updating to the latest version](#updating-to-the-latest-version)
- [Manual install (without the installer)](#manual-install-without-the-installer)
- [Verifying it worked](#verifying-it-worked)
- [How it works, briefly](#how-it-works-briefly)
- [Limitations / things to know](#limitations--things-to-know)

## Why this exists

Scryfall blocked Unity Player (the engine Tabletop Simulator runs on) because too many
TTS users were hammering their servers — every card load was re-downloading full-size
images directly from Scryfall with zero caching. This package fixes that by routing all
Scryfall traffic from this table through your own free Cloudflare Worker, which:

- Caches every card image and API response at Cloudflare's edge, so repeat loads never touch Scryfall again.
- Lets TTS keep working even though Scryfall blocks direct requests from Unity Player.

## What's in this folder

| File | Purpose |
|---|---|
| `Install.zip` / `Install.bat` | **The installer.** Double-click `Install.bat` to install or update the mod. It always fetches the latest version from this GitHub repo. The zip is just a download-friendly wrapper for the same file. |
| `installer.ps1` | The PowerShell script `Install.bat` runs. You don't need to touch it. |
| `scryfall-proxy-worker.js` | The Cloudflare Worker code. You'll deploy this to your own free Cloudflare account (Steps 1–2). |
| `2293586471.json` | The TTS save file the installer downloads and patches. Only needed directly if you do a [manual install](#manual-install-without-the-installer). |
| `2293586471.png` | The mod thumbnail. |
| `README.md` | This guide. |

## Step 1 — Create a free Cloudflare account

1. Go to [dash.cloudflare.com/sign-up](https://dash.cloudflare.com/sign-up) and create a free account.
2. Once logged in, go to **Workers & Pages** in the left sidebar.

## Step 2 — Deploy the Worker

1. In **Workers & Pages**, click **Create** → **Workers** → **Create Worker**.
2. Give it any name you like (e.g. `scryfall-proxy`). Click **Deploy** to create it with the default "Hello World" code first.
3. Once created, click **Edit code** (or open the online editor).
4. Select all the existing code and delete it.
5. Open `scryfall-proxy-worker.js` from this folder, copy its entire contents, and paste it into the editor.
6. Click **Save and Deploy**.
7. Note your Worker's address — it will look like:

   ```
   <your-worker-name>.<your-subdomain>.workers.dev
   ```

   You can find the exact address on the Worker's overview page in the Cloudflare dashboard.

> That's it for Cloudflare — no KV namespace, no extra bindings, and no payment info required. The Worker uses Cloudflare's free built-in edge cache.

## Step 3 — Run the installer

1. Download [`Install.zip`](https://raw.githubusercontent.com/gogurt1984/Tabletop-MTG-Mod---Temp-Fix/main/Install.zip) (clicking the link downloads it).
2. Open the zip and double-click `Install.bat`. (Windows SmartScreen may warn about an unrecognized app — click **More info** → **Run anyway**.)
3. When prompted, paste your Worker address from Step 2 and press Enter.

The installer downloads the latest save file from this repo, patches in your Worker URL, installs it into your TTS Workshop folder, and registers it with Tabletop Simulator — the same way a Steam Workshop subscription would.

Then in Tabletop Simulator: **Create → Games → Workshop → "Gogurt's 6 Player MTG Table"**.

## Updating to the latest version

Run the same `Install.bat` again. It detects your existing install, pulls the latest save file from this repo, and keeps the Worker URL you already entered — no prompts, no re-pasting.

## Manual install (without the installer)

<details>
<summary>Click to expand if you'd rather do it by hand</summary>

1. Open `2293586471.json` in **Notepad**.
2. Press **Ctrl+H** to open Find and Replace.
3. In **Find**, type: `YOUR_WORKER_URL_HERE`
4. In **Replace**, type your Worker's address (e.g. `scryfall-proxy.yourname.workers.dev` — no `https://`).
5. Click **Replace All** and save the file.
6. Subscribe to the original mod on Steam: [steamcommunity.com/sharedfiles/filedetails/?id=2293586471](https://steamcommunity.com/sharedfiles/filedetails/?id=2293586471). Launch TTS once and let it finish downloading — this generates `Documents\My Games\Tabletop Simulator\Mods\Workshop\2293586471.json` and adds a matching entry to `WorkshopFileInfos.json` in that same folder.
7. Close Tabletop Simulator.
8. Replace the downloaded `2293586471.json` with your edited copy (same filename — do not rename it, so it matches the `Directory` entry Steam created in `WorkshopFileInfos.json`).
9. Launch Tabletop Simulator and load the mod from your Workshop mods list.

If the mod ever fails to appear in your Workshop list, or TTS shows an error like *"Error loading Workshop games"*, open `WorkshopFileInfos.json` in Notepad and confirm it has an entry whose `Directory` points at your mod's `.json` file with a `Name` field filled in. If that entry is missing, malformed, or points at the wrong file, remove the bad entry and re-launch TTS.

</details>

## Verifying it worked

Once your Worker is deployed, you can sanity-check it from a browser before loading TTS. Replace `YOUR-WORKER-URL` below with your actual Worker address:

```
https://YOUR-WORKER-URL/img/large/front/4/2/42ecb371-53aa-4368-8ddd-88ae8e90ae0c.jpg
```

This should display a Magic card image (Chaotic Aether Phenomenon). If you get an error, double check the Worker deployed successfully and that you copied the *entire* script.

```
https://YOUR-WORKER-URL/api/cards/named?fuzzy=lightning+bolt
```

This should return JSON card data for Lightning Bolt, with any image URLs inside it already rewritten to point at your Worker's `/img/` route rather than Scryfall directly.

## How it works, briefly

- `/api/*` on your Worker proxies requests to `api.scryfall.com`, caches the JSON response at Cloudflare's edge, and rewrites any embedded Scryfall image URLs in the response so they point back at your Worker instead of Scryfall's CDN.
- `/img/*` proxies and caches actual card images from `cards.scryfall.io`, with a fallback to a smaller image size if the originally requested size isn't available yet (this happens occasionally for newly added cards), and a transparent placeholder image as a last resort so a missing image never produces a hard error in TTS.
- `/importer/*` proxies the deck/token import backend (`importer.rikrassen.xyz`), which Unity Player also can't reach directly — this is what makes the Card Importer's deck build and token import buttons work.
- Anything else returns a harmless blank image, so any unrelated leftover URLs in a mod fail safely instead of erroring.

## Limitations / things to know

> - Cloudflare's free tier allows 100,000 requests/day per Worker, which is far more than a single TTS table will ever need.
> - **This Worker is yours** — don't share its address publicly or bake it into mods you redistribute, since anyone using it will consume your free-tier quota. Each person who wants this setup should deploy their own Worker and do their own one-line replacement, the same way you just did.
> - If Scryfall changes their API or CDN structure in the future, the Worker may need updating — check api.scryfall.com docs if image loading breaks again later.
