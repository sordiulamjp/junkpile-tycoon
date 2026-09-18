# Junkpile Tycoon — 私隱政策 / Privacy Policy

生效日期 / Effective date: 2026-09-18（正式上架時請改為實際發佈日 / update to the actual
publish date at launch）

呢份係**上架前草稿**，用戶／開發者發佈前應該核實聯絡方式、公司／個人身份等細節。
This is a **pre-launch draft** — verify the contact details and developer identity below
before publishing.

---

## 中文版

### 概覽

Junkpile Tycoon（下稱「本 App」）係一隻放置／大亨風格嘅單機手機遊戲。本 App 冇帳戶登
入、冇雲端存檔、冇聊天或社交功能。本政策講清楚本 App 同佢用嘅第三方服務（Google
AdMob／Google Play）會處理咩資料。

### 我們（開發者）直接收集嘅資料

- **冇**。本 App 唔要求登入、唔收集姓名／電郵／電話等個人身份資料，亦冇自己嘅後台
  伺服器儲存玩家資料。
- 遊戲內建一個**純本機**事件記錄（`user://events.jsonl`，例如「開始新一節遊戲」
  「觸發狂熱」「領取離線收入」等玩法事件），淨係存喺你部裝置度，上限 500 行自動
  滾動覆蓋舊記錄，唔會自動上傳。你可以喺遊戲內 debug 畫面隨時查看／匯出／清除；
  如果你主動匯出並傳畀我哋作支援用途，先會離開你部裝置。

### 第三方服務收集嘅資料

本 App 用以下 Google 服務嚟提供廣告同付款功能，呢啲服務會按照 Google 自己嘅私隱政
策獨立處理資料：

1. **Google AdMob（含 Google 使用者訊息平台 UMP 同意表格）**
   為咗顯示獎勵廣告（rewarded video，例如「睇廣告 ×2 離線收入」「睇廣告免費開多次
   狂熱」），Google AdMob 可能收集廣告 ID、大約位置（由 IP 推算）、裝置資訊等資
   料，用嚟投放同量度廣告成效。歐洲經濟區／英國／類似地區嘅用戶開 App 會見到 UMP
   同意表格，可以選擇係咪接受個人化廣告；App 已設定 `child-directed = false`（唔
   針對兒童）。詳見 Google 私隱政策：https://policies.google.com/privacy 同
   AdMob 資料揭露：https://support.google.com/admob/answer/6128543
2. **Google Play Billing**（去廣告付費項目）
   購買由 Google Play 全程處理，我哋見唔到你嘅信用卡／付款方式資料，只會由 Google
   Play 通知本 App「呢個裝置已購買去廣告」嚟解鎖功能。
3. **Google Play 服務（自動診斷）**
   Google Play Console 會自動收集崩潰／ANR 報告等技術診斷資料，呢個係 Google Play
   平台本身嘅機制，唔屬於我哋主動收集，但為咗透明特意列出。
4. **遠端遊戲設定（Cloudflare Workers，未部署時停用）**
   App 開機時可能會發一個公開 `GET` request 攞遊戲數值設定（例如加成倍率），呢個
   request **唔帶任何個人資料**，純粹讀取一份公開設定檔；未部署呢個服務前，App 一
   律用內建預設值。

### 本機存檔

所有遊戲進度（金幣、升級、威望等）存喺你部裝置本機檔案（`user://save-v1.json`），冇
雲端同步。解除安裝 App 或者清除 App 資料就會一併刪除呢啲存檔。

### 兒童

本 App 唔係專為兒童設計，亦冇參加 Google Play「Designed for Families」計劃。如果你
係家長／監護人，發現子女喺未經同意下使用本 App 並想查詢或刪除相關資料，請用下面
聯絡方式聯絡我哋。

### 你嘅選擇同權利

因為我哋冇集中式伺服器儲存你嘅個人身份資料：

- 想停用個人化廣告／重置廣告 ID：請喺你部裝置嘅 Google 設定入面調整（Android：設
  定 → Google → 廣告）。
- 想刪除本機存檔／玩法記錄：解除安裝 App 即可完全刪除（本機檔案，冇備份喺我哋度）。
- 其他查詢／根據個人資料（私隱）條例（PDPO）或者你所在地區私隱法例要求查閱／更正／
  刪除：請電郵聯絡我哋，我哋會喺合理時間內回覆。

### 政策更新

如果本政策有重大改動，我哋會更新呢頁同上面嘅生效日期。

### 聯絡方式

開發者：sordiulamjp
電郵：sordiulamjp@gmail.com

---

## English

### Overview

Junkpile Tycoon ("the App") is a single-player idle/tycoon mobile game. The App has no
account login, no cloud save, and no chat or social features. This policy explains what
data the App and the third-party services it uses (Google AdMob / Google Play) process.

### Data we (the developer) collect directly

- **None.** The App does not require sign-in and does not collect personally identifying
  information such as name, email, or phone number. We do not operate our own backend
  server that stores player data.
- The App keeps a **local-only** gameplay event log (`user://events.jsonl`, e.g. "session
  started", "frenzy triggered", "offline earnings claimed") on your device only, capped
  at 500 lines with automatic rolling deletion of the oldest entries, and never uploaded
  automatically. You can view, export, or clear it any time from the in-game debug
  screen; it only leaves your device if you choose to export and send it to us for
  support purposes.

### Data collected by third-party services

The App uses the following Google services to provide ads and payments; each processes
data under its own privacy policy:

1. **Google AdMob (including the Google User Messaging Platform / UMP consent form)**
   To show rewarded video ads (e.g. "watch an ad for 2× offline earnings" or "watch an ad
   for a free extra Frenzy"), Google AdMob may collect the advertising ID, approximate
   (IP-derived) location, and device information to serve and measure ads. Users in the
   EEA/UK and similar regions see a UMP consent form on first launch and can choose
   whether to allow personalized ads. The App sets `child-directed = false`. See Google's
   Privacy Policy: https://policies.google.com/privacy and AdMob's data disclosure:
   https://support.google.com/admob/answer/6128543
2. **Google Play Billing** (ad-removal purchase)
   Purchases are handled entirely by Google Play; we never see your payment details.
   Google Play simply informs the App that a device has purchased ad removal.
3. **Google Play services (automatic diagnostics)**
   Google Play Console automatically collects crash/ANR diagnostics as part of the
   platform itself; this is not data we actively collect, but we list it for
   transparency.
4. **Remote game-balance configuration (Cloudflare Workers, disabled until deployed)**
   On launch the App may make a public `GET` request to fetch gameplay-balance settings
   (e.g. multipliers). This request carries **no personal data** — it only reads a public
   config file. Until this service is deployed, the App always uses its built-in
   defaults.

### Local save data

All game progress (cash, upgrades, prestige, etc.) is stored in a local file on your
device (`user://save-v1.json`) with no cloud sync. Uninstalling the App or clearing its
data removes this save permanently.

### Children

The App is not designed for children and is not enrolled in Google Play's "Designed for
Families" program. If you are a parent/guardian and believe your child has used the App
without consent and you would like data reviewed or deleted, please contact us below.

### Your choices and rights

Because we do not operate a central server holding your personal data:

- To opt out of personalized ads / reset your advertising ID: use your device's Google
  settings (Android: Settings → Google → Ads).
- To delete local save data / gameplay history: uninstalling the App fully removes it
  (it is local-only; we hold no backup).
- For other requests, including access/correction/deletion requests under Hong Kong's
  Personal Data (Privacy) Ordinance (PDPO) or your local privacy law: email us and we
  will respond within a reasonable time.

### Changes to this policy

If we make material changes to this policy, we will update this page and the effective
date above.

### Contact

Developer: sordiulamjp
Email: sordiulamjp@gmail.com
