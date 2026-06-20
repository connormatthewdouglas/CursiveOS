# CursiveRoot Dashboard

A single static page (`index.html`) that shows the organism's live state — current
config, lineage, latest accepted improvement, simulated reward, the fleet, and
recent measurements — in plain language for a non-technical reader.

## Design (deliberately minimal)
- **No backend, no build step, no framework.** One HTML file with inline CSS + vanilla JS.
- Reads the **already-public** CursiveRoot data directly via Supabase REST using the
  publishable (anon) key — the same key the test scripts use. Nothing secret is exposed.
- Read-only. It cannot change anything.

This is intentionally *not* the old `hub-api/` server (that was over-built scaffolding).
Start simple; expand only once a real operator has used it.

## Run it
- **Easiest:** open `index.html` in a browser. (If a browser blocks the cross-origin
  fetch from a local file, use the deploy option below.)
- **Deploy (recommended):** GitHub Pages — repo Settings → Pages → Build from branch
  `main`, folder `/dashboard` (or copy this file to `/docs`). It will be live at
  `https://connormatthewdouglas.github.io/CursiveOS/dashboard/`.
- **Any static host** works (Netlify drop, `python3 -m http.server`, etc.).

## Editing
Everything is in `index.html`. The lineage narrative (v0.8 → v0.9) is editorial text
near the top of the `<body>`; the rest is pulled live from CursiveRoot. To add a panel,
add a `q("table?select=...")` call in the `<script>` and render it.

## Honesty rules (keep these)
- Payouts are labeled **simulated, not real money** — never remove that.
- Network percentages are labeled **lab simulation** — they don't transfer to real links.
- Single-machine results are flagged as not-yet-fleet-confirmed.
