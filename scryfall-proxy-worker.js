// Scryfall Full Proxy Worker - Cloudflare Worker
// Proxies ALL Scryfall calls so TTS/Unity Player never contacts Scryfall directly,
// and actually caches responses at the edge so repeat card loads never hit Scryfall again.
//
// Routes:
//   /api/*       → proxies to api.scryfall.com/*  (card search, named, collection, etc.)
//                  JSON responses are rewritten so any embedded cards.scryfall.io image
//                  URLs point back through this worker's /img/ route.
//   /img/*       → proxies to cards.scryfall.io/* (direct CDN image passthrough), cached.
//                  Falls back to /normal/ if /large/ 404s (Scryfall occasionally hasn't
//                  finished generating the large size for a newly-added card/printing).
//   anything else → 1x1 transparent PNG. Some bundled TTS mods reference a third-party
//                  asset host (importer-static.rikrassen.xyz) for UI icons that has since
//                  started redirecting through a malware-warning page; those icon URLs were
//                  repointed at this worker so they fail safe instead of erroring or risking
//                  a request to a flagged domain.

const BLANK_PNG_BASE64 =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=";

function blankPng() {
  const bytes = Uint8Array.from(atob(BLANK_PNG_BASE64), (c) => c.charCodeAt(0));
  return new Response(bytes, {
    status: 200,
    headers: {
      "Content-Type": "image/png",
      "Cache-Control": "public, max-age=2592000",
      "Access-Control-Allow-Origin": "*"
    }
  });
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const cache = caches.default;

    // ── Route 1: Proxy Scryfall API calls ──────────────────────────────────
    if (url.pathname.startsWith("/api/")) {
      const cacheKey = new Request(url.toString(), request);

      if (request.method === "GET") {
        const hit = await cache.match(cacheKey);
        if (hit) return hit;
      }

      const scryfallPath = url.pathname.replace(/^\/api/, "");
      const scryfallUrl = "https://api.scryfall.com" + scryfallPath + url.search;

      const apiResp = await fetch(scryfallUrl, {
        method: request.method,
        headers: {
          "User-Agent": "TTSProxyWorker/1.0",
          "Accept": "application/json",
          "Content-Type": request.headers.get("Content-Type") || "application/json"
        },
        body: request.method === "POST" ? await request.text() : undefined
      });

      let body = await apiResp.text();

      // Rewrite any embedded image CDN URLs so TTS never fetches Scryfall directly,
      // even from data buried inside search/collection results.
      body = body.split("https://cards.scryfall.io/").join(`${url.origin}/img/`);
      body = body.split("https:\\/\\/cards.scryfall.io\\/").join(`${url.origin.replace(/\//g, "\\/")}\\/img\\/`);

      // Also rewrite API self-links (uri, rulings_uri, prints_search_uri, all_parts,
      // etc.) - mod scripts fetch these fields straight out of responses, e.g. for
      // rulings chat commands and emblem/token imports.
      body = body.split("https://api.scryfall.com/").join(`${url.origin}/api/`);
      body = body.split("https:\\/\\/api.scryfall.com\\/").join(`${url.origin.replace(/\//g, "\\/")}\\/api\\/`);

      const response = new Response(body, {
        status: apiResp.status,
        headers: {
          "Content-Type": "application/json",
          "Cache-Control": "public, max-age=21600",
          "Access-Control-Allow-Origin": "*"
        }
      });

      if (request.method === "GET" && apiResp.ok) {
        ctx.waitUntil(cache.put(cacheKey, response.clone()));
      }

      return response;
    }

    // ── Route 2: Direct CDN image passthrough (cached) ─────────────────────
    if (url.pathname.startsWith("/img/")) {
      // Strip cache-busting query strings before using as the cache key, since
      // TTS's stripScryfallImageURI already removes them on its end too.
      const imgPath = url.pathname.replace(/^\/img/, "");
      const cacheKeyUrl = `${url.origin}/img${imgPath}`;
      const cacheKey = new Request(cacheKeyUrl, request);

      const hit = await cache.match(cacheKey);
      if (hit) return hit;

      const imgUrl = "https://cards.scryfall.io" + imgPath + url.search;

      let imgResp = await fetch(imgUrl, {
        headers: { "User-Agent": "TTSProxyWorker/1.0" }
      });

      // Scryfall sometimes hasn't generated the /large/ size yet for a brand-new
      // card/printing even though the API reports it. Fall back to /normal/ rather
      // than surfacing a broken card image to players.
      if (!imgResp.ok && imgPath.startsWith("/large/")) {
        const fallbackUrl = "https://cards.scryfall.io" + imgPath.replace("/large/", "/normal/") + url.search;
        imgResp = await fetch(fallbackUrl, { headers: { "User-Agent": "TTSProxyWorker/1.0" } });
      }

      if (!imgResp.ok) {
        return blankPng();
      }

      const response = new Response(imgResp.body, {
        status: imgResp.status,
        headers: {
          "Content-Type": imgResp.headers.get("Content-Type") || "image/jpeg",
          "Cache-Control": "public, max-age=2592000",
          "Access-Control-Allow-Origin": "*"
        }
      });

      ctx.waitUntil(cache.put(cacheKey, response.clone()));
      return response;
    }

    // ── Route: Proxy the Moxfield deck API ─────────────────────────────────
    // Moxfield's API sits behind bot protection that rejects Unity/TTS
    // clients outright. Requests from the worker (with browser-like headers)
    // have a better chance, and failures still come back as clean HTTP
    // errors the mod can handle gracefully.
    if (url.pathname.startsWith("/moxfield/")) {
      const moxPath = url.pathname.replace(/^\/moxfield/, "");
      const moxResp = await fetch("https://api2.moxfield.com" + moxPath + url.search, {
        headers: {
          "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
          "Accept": "application/json"
        }
      });
      const body = await moxResp.text();
      return new Response(body, {
        status: moxResp.status,
        headers: {
          "Content-Type": moxResp.headers.get("Content-Type") || "application/json",
          "Access-Control-Allow-Origin": "*"
        }
      });
    }

    // ── Route 3: Proxy importer.rikrassen.xyz backend ─────────────────────
    // TTS/Unity Player can't make SSL connections to importer.rikrassen.xyz
    // for the same reason it can't reach Scryfall — Unity's HTTP stack blocks
    // certain domains. This route passes the request through the worker, which
    // has no such restrictions.
    if (url.pathname.startsWith("/importer")) {
      const importerPath = url.pathname.replace(/^\/importer/, "") || "/";
      const importerUrl = "https://importer.rikrassen.xyz" + importerPath + url.search;

      const body = request.method !== "GET" && request.method !== "HEAD"
        ? await request.arrayBuffer()
        : undefined;

      const importerResp = await fetch(importerUrl, {
        method: request.method,
        headers: {
          "Content-Type": request.headers.get("Content-Type") || "application/json",
          "Accept": request.headers.get("Accept") || "application/json",
          "User-Agent": request.headers.get("User-Agent") || "TTSProxyWorker/1.0",
          "X-Client-Version": request.headers.get("X-Client-Version") || ""
        },
        body
      });

      const respBody = await importerResp.arrayBuffer();
      return new Response(respBody, {
        status: importerResp.status,
        headers: {
          "Content-Type": importerResp.headers.get("Content-Type") || "application/json",
          "Access-Control-Allow-Origin": "*"
        }
      });
    }

    if (url.pathname === "/") {
      return new Response(
        "Scryfall Proxy\n\nRoutes:\n  /api/<path>    Proxy + cache Scryfall API\n  /img/<path>    Proxy + cache Scryfall image CDN",
        { status: 200 }
      );
    }

    // Anything else (e.g. former importer-static.rikrassen.xyz icon paths) gets a
    // harmless blank image instead of an error.
    return blankPng();
  }
};
