# 用 Claude 上線一位新作者 — 範例與指令範本

這份文件示範**如何搭配 Claude（Claude Code）用 stock-toolkit 跑一位全新的 KOL 作者**。
如果你只想純手動操作不透過 Claude，請看 [QUICKSTART.md](QUICKSTART.md)。

---

## 核心觀念：每位作者 = 一份獨立的 toolkit 複本

stock-toolkit 本身是**乾淨範本**。上線新作者時，不要直接在範本裡爬資料，而是**複製一份**出來，每位作者自成一包：

```
CMoney_claude\
├── stock-toolkit\          ← 乾淨範本（只拿來複製，kols 永遠空的）
├── <作者A>\                 ← 作者 A 的獨立複本（完整腳本 + 自己的 domains 資料）
│   └── domains\<domain>\kols\<作者A>\   ← 爬的資料、報告都在這
├── <作者A>-app\             ← （之後）作者 A 的下游 Web / App
├── <作者B>\                 ← 作者 B 的獨立複本
└── ...
```

這樣每位作者的資料、報告、下游應用完全隔離，互不影響，刪除或搬移都很乾淨。

---

## 分工：哪些 Claude 做、哪些你手動做

| 工作 | 誰做 |
|------|------|
| 複製範本成獨立資料夾、移除繼承的 `.git` | ✅ Claude |
| 在新複本的 `domain.json` 註冊作者、依題材調整 `domain_themes` | ✅ Claude |
| 跑 pipeline 腳本（recover_dates / merge / discover / build / report） | ✅ Claude |
| REVIEW CHECKPOINT 審 `kol_profile.json`（確認 persona、整理 eras、清雜詞） | ✅ Claude |
| 產報告、打開 `index.html` | ✅ Claude |
| 之後做下游 Web / App / 課程規劃 | ✅ Claude |
| **開瀏覽器登入、點擷取書籤、按「複製」** | 🙋 **只能你手動做**（需要你登入的瀏覽器 session） |

爬資料這段 Claude 代勞不了，所以指令分**兩個階段**：先請 Claude 建好環境 → 你手動爬完 → 再請 Claude 跑 pipeline。

---

## 階段一：請 Claude 建環境（爬之前）

把下面這段貼給 Claude，填入你的作者資訊：

```
我要用 stock-toolkit 跑一位新作者。請幫我：
- 作者 handle：<例如 alpha_kitev>
- 公開暱稱 persona：<暱稱>
- 題材領域：<台股 / ETF / 美股 / 加密貨幣 / 其他，描述一下>
- 三平台網址：
    IG：<url>
    Threads：<url>
    FB：<url>

請複製 stock-toolkit 範本成一個獨立資料夾、移除繼承的 .git，
在它自己的 domain.json 註冊作者並依題材調整 domain_themes，
最後把我接下來要手動爬哪些頁面的清單列給我。
```

Claude 會：
1. `Copy-Item` 範本 → `<作者>\`（完整腳本 + domains 結構）
2. 移除複製過來的 `.git`（避免綁到範本的 GitHub 遠端）
3. 編輯 `<作者>\domains\<domain>\domain.json`：註冊 `kols` 條目（`id` / `persona` / `platforms_covered` / `profile_urls`），必要時依題材改 `domain_themes`
4. 列出你要手動爬的頁面清單

---

## 中間：你手動爬資料

依 Claude 給的清單，在已登入的瀏覽器逐平台操作：

1. 開作者該平台頁面 → 點對應擷取書籤（IG / Threads / FB）→ 等面板跑完 → 按「複製」
2. 回 PowerShell（在 `<作者>\` 資料夾）執行：
   ```powershell
   .\save_clipboard.ps1 -Author <作者>
   ```
3. **IG 要跑兩個頁面**：`instagram.com/<作者>/`（主頁）和 `/reels/`，各擷取 + save 一次
4. Threads、FB 各一次

> 書籤還沒裝？雙擊 `<作者>\install-bookmarklets.html`，把擷取書籤拖到瀏覽器書籤列（一台瀏覽器只需裝一次）。
> 複製失敗（資料量大或被剪貼簿管理器攔截）？改用安裝頁下方的「📥 下載書籤」直接下 JSON 檔。

---

## 階段二：請 Claude 跑 pipeline（爬完後）

四個平台檔案都進 `raw\` 之後，貼這段給 Claude：

```
<作者> 三平台都爬好了，raw 資料夾有檔案了。
請幫我跑 run_kol.ps1 -Discover，到 REVIEW CHECKPOINT 時
幫我審 kol_profile.json（確認 persona、整理 eras 標籤、清掉樣板雜詞），
然後 build DB、產報告，並打開 reports\index.html。
```

Claude 會跑：`recover_dates` → `merge_*` → `discover_kol_profile` → 代審 profile → `build_kol_db` → `generate_kol_reports`，最後打開報告。

需要變現分析報告的話，加一句「**也跑 -Monetization**」即可（多產一份 `monetization_report.html`；Section 5 競品表是 Taiwan finance KOL 模板，跨域要人工微調）。

---

## 最精簡版

懶得填欄位也行，Claude 會反問缺的資訊：

```
用 stock-toolkit 幫我上線新作者 <handle>，題材是 <…>
```

---

## 後續：做下游應用

報告與結構化資料產生後，下游 Web / App / 課程都從這包讀：

- 結構化資料：`<作者>\domains\<domain>\kols\<作者>\database\`
- 乾淨貼文：`<作者>\domains\<domain>\kols\<作者>\canonical\`

要做網站時跟 Claude 說：

```
依 <作者> 的 database/ 資料，幫我做一個下游 Web App，
放在 <作者>-app 資料夾（對照現有的 -app 慣例）。
```

---

## 日常更新（作者發新內容後）

```
<作者> 又有新貼文了，我重新爬好 raw 了。
請幫我跑 run_kol.ps1（不要 -Discover，保留我審過的 profile）並更新報告。
```
