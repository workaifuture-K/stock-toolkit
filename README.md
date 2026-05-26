# StockHero Toolkit

A domain-aware KOL content quantification toolkit. Scrapes Threads / Instagram / Facebook public posts via browser bookmarklets, runs a PowerShell pipeline to produce a structured database + 3 analyst-style reports per KOL.

**Per-KOL independent analysis** — no cross-KOL aggregation, no cross-domain mixing.

---

## What you get

```
For each KOL you onboard:
├─ database/                   ← machine-readable JSON for future App/Web
│   ├─ kol_db.json
│   ├─ threads_metrics.json
│   ├─ instagram_metrics.json
│   └─ facebook_metrics.json
└─ reports/                    ← 3 HTML reports (one per platform)
    ├─ index.html              KOL platform index
    ├─ threads_report.html
    ├─ instagram_report.html
    └─ facebook_report.html
```

Each report has 8 sections with data-derived conclusion paragraphs:
overview, posting cadence, theme distribution, temporal momentum, length structure, platform-specific patterns, hashtag usage, disclaimer/compliance.

---

## Requirements

- **Windows 10/11** with **PowerShell 5.1+**
- **Chromium-based browser** (Chrome / Edge / Brave / Arc) to install bookmarks
- **Active login** on Instagram / Facebook / Threads (bookmarks scrape what your logged-in session can see)

---

## Quick start

See **[QUICKSTART.md](QUICKSTART.md)** for the 5-minute setup walkthrough.

TL;DR:
```powershell
# 1. Install bookmarks (one-time)
#    Open install-bookmarklets.html in browser → drag 3 bookmarks to bookmark bar

# 2. Edit domains/tw_stock_kol/domain.json → add your KOL to "kols" array

# 3. Scrape (per platform): visit KOL profile → click bookmark → wait → click 複製 → run:
.\save_clipboard.ps1 -Author <kol_id>

# 4. After all 3 platforms done, run full pipeline:
.\run_kol.ps1 -Author <kol_id> -Discover
#    ↑ pauses for you to review/edit kol_profile.json, then generates reports
```

---

## File map

| File | Role |
|------|------|
| `install-bookmarklets.html` | Browser bookmarklet install page (drag bookmarks to bookmark bar) |
| `instagram-bookmarklet-v8.js` | IG scraper source (v8.1: Phase 1 URL collection + Phase 2 fetch caption) |
| `facebook-bookmarklet-v2.js` | FB scraper source |
| `threads-bookmarklet-v2.js` | Threads scraper source |
| `pack_ig_v8.ps1` | Rebuild IG bookmark URL after modifying .js |
| `save_clipboard.ps1` | Clipboard JSON → `domains/<d>/kols/<a>/raw/<platform>.json` |
| `recover_dates.ps1` | Decode HTML entities + fill missing dates (canonical lookup + web fetch) |
| `merge_ig.ps1` `merge_threads.ps1` `merge_fb.ps1` | Merge raw into canonical (URL shortcode + content hash dedup) |
| `discover_kol_profile.ps1` | TF-IDF + era detection → profile draft (KOL-specific config) |
| `build_kol_db.ps1` | Canonical → structured Database (App-ready JSON) |
| `generate_kol_reports.ps1` | Database → 3 platform reports + KOL index + domain index |
| `cleanup_canonical.ps1` | Maintenance: URL-aware + no-URL prefix dedup |
| `run_kol.ps1` | One-shot pipeline wrapper (recover → merge → [discover →] build → generate) |
| `domains/tw_stock_kol/domain.json` | Domain template (preserves 12 financial themes; empty kols array) |

---

## Design principles

- **Any KOL works** — all KOL-specific bias lives in profile JSON, not in scripts
- **Each KOL fully independent** — own raw / canonical / database / reports; no aggregation
- **Data > narrative** — section conclusions are data-derived (thresholds & labels), not hardcoded prose
- **Failure isolation** — six independent pipeline stages; breaking one doesn't break the others
- **Human-in-the-loop** — discover proposes, USER confirms via editing profile JSON, analyzer executes
- **Dedup protection** — merge uses URL shortcode primary + content hash secondary; comment/caption pollution can't recur

---

## Responsible use

This toolkit scrapes **public** posts via authenticated browser sessions. You are responsible for:
- Respecting target users' Terms of Service of Instagram / Facebook / Threads
- Not republishing scraped content without permission
- Following local data protection law (GDPR / CCPA / etc.)
- Not using this for harassment, doxxing, or commercial exploitation without consent

---

## Limitations

- IG modal-click style scrapers (v7.x and earlier) hit rate limits ~100 posts; v8 uses URL-collect + fetch and gets ~300+ in one run
- IG public embed page (used as date fallback) requires `facebookexternalhit` UA — if Meta changes this, web fetch may degrade
- Threads/FB bookmark sessions depend on platform's DOM structure; UI changes may require bookmark rev
- PowerShell scripts assume UTF-8 with BOM (PS 5.1 quirk); when adding new scripts, save with BOM
- Bookmarklet `navigator.clipboard.writeText` 寫入有時會被剪貼簿管理工具（PowerToys / Ditto / Win+V 歷史）攔截或在大量資料時失敗 → install-bookmarklets.html 提供「📥 備用：下載書籤」(IG / Threads / FB) 直接從 localStorage 下載 JSON 檔，繞開剪貼簿

---

## License

MIT (or your choice — replace this section with your preferred license).
