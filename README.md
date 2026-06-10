# ♻️ GarbageP2P — Static (GitHub Pages) Edition

A **100% static** build of the GarbageP2P peer-to-peer scrap & recycling marketplace, designed to run on **GitHub Pages** (or any static host) with **no server, no PHP, no database**.

It keeps the look and the headline features of the full app — browsing the marketplace, live scrap rates, recency-weighted average prices, Leaflet maps with **live + pickup locations**, browser geolocation, posting requests, booking pickups, and an **inDrive-style price negotiation** — by replacing the backend with:

- a static **JSON dataset** (`data/*.json`) for the seed catalog, listings and past deals, and
- the visitor's **browser `localStorage`** for anything they create (posts, deals, bookings, chat, profile).

> ⚠️ Because there's no server, data is **per-browser and not shared between visitors**. This is a faithful interactive demo / portfolio build, not a multi-user production system. (The full PHP + MySQL version in `Garbage_P2P` provides real accounts, shared data, multi-user chat and an admin panel.)

---

## ✅ What works on GitHub Pages

| Feature | How |
|--------|-----|
| Home, Marketplace, Rates, Deals, About | Rendered in JS from `data/*.json` |
| **Recency-weighted average prices** | Computed client-side (`2^(−ageDays/30)`, 90-day window) |
| **Leaflet maps** (live + pickup pins) | OpenStreetMap tiles — no API key |
| **Browser geolocation** | `navigator.geolocation` (HTTPS — GitHub Pages qualifies) |
| **Post a request** (with image) | Saved to `localStorage`; image downscaled to a data-URL |
| **Negotiation chat + close deal** | Simulated counterpart in JS; closed deals appear in history |
| **Book a pickup** | Saved to `localStorage` (see *My Activity*) |
| Demo profile | Name/role kept in `localStorage` (no passwords) |

## ❌ Removed vs. the PHP version (needs a server)

Real user accounts & login · MySQL/shared data · real-time multi-user chat · the admin panel · server-side contact/booking storage & email (the contact form opens `mailto:` instead) · server file uploads.

---

## 🚀 Deploy to GitHub Pages

### Option A — straight from a repo (simplest)

1. Create a new GitHub repo, e.g. `garbage-p2p`.
2. Put **the contents of this folder at the repo root** (so `index.html` is at the top level — **not** inside a subfolder).
3. Commit & push:
   ```bash
   cd Garbage_P2P_Github
   git init
   git add .
   git commit -m "GarbageP2P static site"
   git branch -M main
   git remote add origin https://github.com/<your-username>/garbage-p2p.git
   git push -u origin main
   ```
4. On GitHub: **Settings → Pages**. Under *Build and deployment*, set **Source = Deploy from a branch**, **Branch = `main`**, **Folder = `/ (root)`**, then **Save**.
5. Wait ~1 minute. Your site is live at:
   ```
   https://<your-username>.github.io/garbage-p2p/
   ```

### Option B — drag-and-drop (no command line)

1. Create the repo on github.com → **Add file → Upload files**.
2. Drag **all files and folders from this directory** in (keep the structure: `assets/`, `data/`, the `.html` files, `.nojekyll`). Commit.
3. Enable **Settings → Pages** as in step 4 above.

### Notes
- The included **`.nojekyll`** file tells GitHub Pages to skip Jekyll and serve every file as-is.
- **`404.html`** is served automatically for unknown URLs.
- All links and asset/data paths are **relative**, so the site works correctly under the `/<repo>/` sub-path of a project page. Keep every file at the repo root.
- To use a custom domain, add it under Settings → Pages (a `CNAME` file is created for you).

---

## 🖥️ Preview locally first

GitHub Pages serves over HTTPS, but `fetch()` of the JSON files is blocked if you open the HTML by **double-clicking** (`file://`). Use any tiny static server:

```bash
# from inside Garbage_P2P_Github/
python -m http.server 8080
#  → open http://localhost:8080
```
…or, since you have XAMPP, just start **Apache** and open:
```
http://localhost/Garbage_P2P_Github/
```

---

## 📁 Structure

```
Garbage_P2P_Github/
├── index.html  marketplace.html  request.html  deals.html  rates.html
├── post-request.html  book-pickup.html  dashboard.html  profile.html
├── about.html  contact.html  404.html
├── .nojekyll
├── data/      categories.json · users.json · requests.json · deals.json
└── assets/
    ├── css/style.css
    ├── img/favicon.svg · placeholder.svg
    └── js/  util.js · store.js · maps.js · layout.js
```

### Editing the seed data
Just edit the JSON in `data/`. Listings use `hours_ago` and deals use `days_ago` (relative to load time) so the demo always looks "fresh" and the average-price charts never go empty over time.

### Resetting the demo
Any visitor can wipe their browser-local data via **Profile → Reset demo data** (or the user menu).
