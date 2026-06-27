# TTS MTG Table — Scryfall Image Proxy Setup Guide

Free, ~10–15 minutes, no credit card required.

## Table of contents

- [Why this exists](#why-this-exists)
- [What's in this folder](#whats-in-this-folder)
- [Step 1 — Create a free Cloudflare account](#step-1--create-a-free-cloudflare-account)
- [Step 2 — Deploy the Worker](#step-2--deploy-the-worker)
- [Step 3 — Point the save file at your Worker](#step-3--point-the-save-file-at-your-worker-one-find-and-replace)
- [Step 4 — Install the save in Tabletop Simulator](#step-4--install-the-save-in-tabletop-simulator)
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
| `scryfall-proxy-worker.js` | The Cloudflare Worker code. You'll deploy this to your own free Cloudflare account. |
| `2293586471.json` | The TTS save file. It contains one placeholder, `YOUR_WORKER_URL_HERE`, that you'll replace with your own Worker's address. |
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

   You can find the exact address on the Worker's overview page in the Cloudflare dashboard. You don't need the `https://` part for the next step.

> That's it for Cloudflare — no KV namespace, no extra bindings, and no payment info required. The Worker uses Cloudflare's free built-in edge cache.

## Step 3 — Point the save file at your Worker (one find-and-replace)

1. Open `2293586471.json` in **Notepad**.
2. Press **Ctrl+H** to open Find and Replace.
3. In **Find**, type: `YOUR_WORKER_URL_HERE`
4. In **Replace**, type your Worker's address from Step 2 (e.g. `scryfall-proxy.yourname.workers.dev`).
5. Click **Replace All**.
6. Save the file (Ctrl+S).

That's the only edit needed — `YOUR_WORKER_URL_HERE` appears throughout the file as a single placeholder, and Replace All swaps every instance in one go.

## Step 4 — Install the save in Tabletop Simulator

> **Subscribe to the original Workshop item first.** This file is a modified version of the existing Steam Workshop mod [MTG EDH 6-player (π)](https://steamcommunity.com/sharedfiles/filedetails/?id=2293586471) (Workshop ID `2293586471`). Subscribe to that item in Steam first — this lets TTS register the mod properly and creates the correct entry in `WorkshopFileInfos.json` (the file TTS uses to know which save belongs to which Workshop item and what to call it in your mods list). Skipping this step and just dropping the JSON in on its own can cause TTS to either not show the mod at all, or show it with a broken/missing name.

1. Subscribe to the original mod on Steam: [steamcommunity.com/sharedfiles/filedetails/?id=2293586471](https://steamcommunity.com/sharedfiles/filedetails/?id=2293586471). Launch TTS once and let it finish downloading the mod — this generates `Documents\My Games\Tabletop Simulator\Mods\Workshop\2293586471.json` and adds a matching entry to `WorkshopFileInfos.json` in that same folder.
2. Close Tabletop Simulator.
3. Replace that downloaded `2293586471.json` with the edited copy from this folder (same filename — **2293586471.json** — so it matches the `Directory` entry Steam already created for it in `WorkshopFileInfos.json`). Do not rename the file.
4. Launch Tabletop Simulator and load the mod from your Workshop mods list, same as before.
5. Card images should now load through your own Worker instead of failing or hitting Scryfall directly.

If the mod ever fails to appear in your Workshop list, or TTS shows an error like *"Error loading Workshop games"*, open `WorkshopFileInfos.json` in Notepad and confirm it has an entry whose `Directory` points at your `2293586471.json` file with a `Name` field filled in (e.g. `"MTG 6 player table - scripted"`). If that entry is missing, malformed, or points at the wrong file, remove the bad entry and re-launch TTS, or re-subscribe to the original Workshop item to regenerate it cleanly.

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
- Anything else returns a harmless blank image, so any unrelated leftover URLs in a mod fail safely instead of erroring.

## Limitations / things to know

> - Cloudflare's free tier allows 100,000 requests/day per Worker, which is far more than a single TTS table will ever need.
> - **This Worker is yours** — don't share its address publicly or bake it into mods you redistribute, since anyone using it will consume your free-tier quota. Each person who wants this setup should deploy their own Worker and do their own one-line replacement, the same way you just did.
> - If Scryfall changes their API or CDN structure in the future, the Worker may need updating — check api.scryfall.com docs if image loading breaks again later.
