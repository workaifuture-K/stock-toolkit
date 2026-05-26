# Quick Start — 5 minutes to first KOL report

## Prerequisites check

```powershell
# In PowerShell, verify you have Windows PowerShell 5.1+
$PSVersionTable.PSVersion
# Should show Major 5 or higher
```

You also need:
- A Chromium-based browser (Chrome, Edge, Brave, Arc)
- Active logins on Instagram, Facebook, and Threads

---

## Step 1 — Install bookmarklets (one-time)

1. Open `install-bookmarklets.html` in your browser (double-click the file).
2. Make sure your **bookmarks bar is visible** (Chrome: Ctrl+Shift+B).
3. Drag the three bookmarks onto your bookmarks bar:
   - 📸 **IG 擷取 v8.1**
   - 🧵 **Threads 擷取 v3.5**
   - 📘 **FB 擷取 v5.4**
   - 📥 **IG / Threads / FB 下載**（備用，剪貼簿失敗時用）

You only do this once per browser.

---

## Step 2 — Set up your first KOL

Edit `domains/tw_stock_kol/domain.json`. Add a KOL entry under `"kols"`:

```json
"kols": [
  {
    "id": "kol_handle_on_instagram",
    "persona": "Their Public Nickname",
    "platforms_covered": ["threads", "instagram", "facebook"]
  }
]
```

**Tip**: If your target KOL isn't in the financial domain (e.g., beauty, sports, fitness), copy the `tw_stock_kol` folder to a new domain name and edit `domain_themes` to reflect your topic categories.

---

## Step 3 — Scrape each platform

For each platform (Instagram, Threads, Facebook):

1. **Open the KOL's profile** in your browser while logged in
2. **Click the corresponding bookmark** (e.g., 📸 IG 擷取 v8.1 on instagram.com/<kol_handle>/)
3. A panel appears top-right. Wait for it to finish (it shows progress).
4. Click the **複製** button on the panel to copy the data.
5. In PowerShell, run:
   ```powershell
   .\save_clipboard.ps1 -Author <kol_handle>
   # auto-detects domain + platform; saves to domains/<d>/kols/<kol>/raw/<platform>.json
   ```

Repeat for each platform.

**IG note**: IG has two pages — `instagram.com/<kol>/` (main feed) and `instagram.com/<kol>/reels/`. Run the bookmark on **both** and `save_clipboard` after each. They produce `instagram_main.json` and `instagram_reels.json` separately.

**Time per scrape**:
- IG: 5–10 minutes (auto-scrolls + fetches captions)
- Threads: 1–2 minutes
- Facebook: 3–5 minutes

---

## Step 4 — Run the pipeline

After all platforms scraped:

```powershell
.\run_kol.ps1 -Author <kol_handle> -Discover
```

This runs:
1. `recover_dates` — decode HTML entities + fill missing dates (web fetch)
2. `merge_ig` / `merge_threads` / `merge_fb` — dedup + merge raw into canonical
3. `discover_kol_profile` — auto-detect top terms, era transitions, persona patterns

The pipeline **pauses** at a review checkpoint:

```
>>> REVIEW CHECKPOINT <<<
Edit: domains/<d>/kols/<kol>/kol_profile.json
  1) Confirm 'persona' (公開暱稱)
  2) Rename 'eras' labels (前期/後期 → 真實階段名)
  3) Remove boilerplate from 'discovered_terms'
  4) Non-financial KOL: set philosophy_keywords / anti_scam_patterns / type_rules / themes = []

Press Enter when profile is ready to analyze
```

**Open the profile JSON** in your editor (Notepad, VS Code, etc.), apply the above tweaks, save. Then press Enter in PowerShell.

The pipeline then runs:
4. `build_kol_db` — generate the structured Database
5. `generate_kol_reports` — generate 3 platform reports + KOL index + domain index
6. **(opt-in)** `analyze_monetization` — generate `monetization_report.html` if you passed `-Monetization`

---

## Step 5 — View reports

```powershell
# Open the KOL's report index
Start-Process "domains\tw_stock_kol\kols\<kol_handle>\reports\index.html"

# Or the domain-level index (lists all KOLs in the domain)
Start-Process "domains\tw_stock_kol\index.html"
```

### 變現分析報告（opt-in）

預設 pipeline 只生成 3 個平台報告。若要 +1 變現分析報告：

```powershell
.\run_kol.ps1 -Author <kol_handle> -Discover -Monetization
# 或 daily refresh 也可以加：
.\run_kol.ps1 -Author <kol_handle> -Monetization
```

產出 `reports\monetization_report.html` 含 5 區段：
1. **業配掃描** — 按 `$sponsors` 列表抓 Taiwan 券商/投信/平台品牌 mention（Tier A/B/C/D）
2. **內容強項與缺口** — 12 個主題分布 → 哪些可包裝商品 / 哪些是缺口
3. **產文節奏可持續性** — 月度趨勢、近 3 個月成長率、燃燒風險評估
4. **平台分工** — IG vs FB vs Threads 風格對比 → 各自變現定位
5. **競品定位** — Taiwan ETF KOL 競品表 + 護城河/弱點/變現建議（placeholder 待填寫）

⚠️ **客製化提示**：腳本目前以 Taiwan finance KOL 為基準範本。
- **Section 1 `$sponsors`** 是 Taiwan 券商/投信/平台名單，跨域請改 `analyze_monetization.ps1` 的 `$sponsors` 區塊。
- **Section 5 競品表 + placeholder** 預設為 Taiwan ETF KOL 競品。其他細分（美股 / Crypto / 非財經）請編輯競品表 + 填寫各 `[請填寫]` 區塊。

---

## Daily refresh (later, after first onboarding)

When the KOL posts new content and you want to update reports:

```powershell
# 1. Re-scrape each platform (same bookmark workflow)
.\save_clipboard.ps1 -Author <kol_handle>

# 2. Run pipeline WITHOUT -Discover (keep your edited profile)
.\run_kol.ps1 -Author <kol_handle>
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Auto-detected domain" errors | Make sure exactly one folder exists under `domains/` |
| Bookmark does nothing on IG | Confirm you installed **v8.1** (label shows "v8.1"); old v7.x bookmarks broke after IG updates |
| `save_clipboard` says clipboard empty | Click 複製 on the panel before running the script |
| 複製按鈕看似成功（彈出「已複製 X 筆！」）但 `save_clipboard` 抓到別的內容 | 剪貼簿管理器（PowerToys / Ditto / Win+V 歷史 pin）攔截了寫入。改用 install-bookmarklets.html 下方的「📥 備用：下載書籤」直接下載 JSON 檔，繞開剪貼簿 |
| 大量資料時 `navigator.clipboard.writeText` 失敗（特別是 FB 數百篇以上） | 同上，用「📥 下載書籤」直接從 localStorage 下載成檔案 |
| `recover_dates` web fetch slow | Default fetches up to 200 URLs at 1.5–3s each. Use `-MaxFetch 50` to cap; use `-NoFetch` to skip entirely |
| Chinese mojibake in PowerShell output | Run `chcp 65001` in PowerShell, or save your .ps1 files as UTF-8 with BOM |
| Reports show 0 posts for one platform | That platform wasn't scraped yet (no raw/<platform>.json); run the bookmark + save_clipboard |
| `discover` complains active profile exists | It's protecting your edits — wrote to `kol_profile_draft.json`. Diff/merge manually, or add `-Force` to overwrite |

---

## Adding a second/third KOL

Each KOL is fully independent. Repeat **Step 2 → Step 4** for the next one. The domain index page auto-updates to list both.

```powershell
# Edit domain.json — append another entry under "kols"
# Scrape with: .\save_clipboard.ps1 -Author <kol2>
# Pipeline:    .\run_kol.ps1 -Author <kol2> -Discover
```

zhao1945's reports and data are completely separate from kol2's.

---

## Adding a different domain (e.g., US stocks, beauty)

```powershell
# 1. Copy the template
Copy-Item -Recurse domains\tw_stock_kol domains\us_stock_kol

# 2. Edit domains\us_stock_kol\domain.json:
#    - Change domain_id, domain_name, description
#    - Replace 'domain_themes' with US-stock-relevant themes (e.g., SPY, QQQ, Fed, sectors)
#    - Empty 'kols' array
#    - Delete the `kols/.gitkeep` placeholder if present, replace with your actual KOLs
```

Now you have two parallel domains. Each `run_kol.ps1` call will need `-Domain <name>` since auto-detect requires exactly one domain.
