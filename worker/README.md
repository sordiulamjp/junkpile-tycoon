# 遠端 constants worker（Cloudflare Worker + KV）

VR-08（ALTA-155）：俾開發者調 `GameConstants` 標 `# TUNE` 嘅純量欄位（價錢／
倍率／時長／上限，見 [`../data/constants.gd`](../data/constants.gd) 嘅
`REMOTE_TUNABLE_FIELDS` 白名單），唔使重新出／交 APK。搬
[yaing](https://github.com/sordiulamjp/yaing) 嘅 `meta/` + Worker + KV 模式，
但跟呢個 issue 縮細咗嘅範圍剪到淨返一個 endpoint——唔接 Firebase、唔做
公告／強制更新。

**呢次改動未部署。** 開 KV namespace、設 `ADMIN_KEY` secret 呢兩步淨係
喺 Cloudflare dashboard 度先做得到（同 yaing 自己個商店 worker 一樣嘅
限制）——冇任何嘢可以自動化呢部分。喺有人完成以下部署步驟並填返 worker
網址之前，App 嘅 `RemoteConstantsLoader.CONSTANTS_URL` 會維持空白，遊戲
淨係用本機預設（見
[`../systems/remote_constants_loader.gd`](../systems/remote_constants_loader.gd)）。

## 做咩

- `GET /constants`（公開）→ `{ overrides: {...}, updatedAt: <ISO8601 或 null> }`
  ——App 開機 GET 一次，將 `overrides` 疊喺本機 `GameConstants` 預設之上。
- `POST /constants`（要帶 `x-admin-key: <ADMIN_KEY>` header）→ body
  `{ overrides: {...} }`，用 [`worker.js`](worker.js) 嘅 `FIELD_TYPES` 白名單
  洗一次（唔喺白名單／型別唔啱／NaN／Infinity 一律靜靜哋忽略，唔會令
  request 400），存落 KV，回傳實際存低（洗好）嘅值。

淨係 `FIELD_TYPES`／`REMOTE_TUNABLE_FIELDS` 入面列嘅純量（`float`／`int`）
TUNE 欄位先可以咁樣覆寫——`Dictionary`／`Array`／`Vector`／`Color` 嘅
TUNE 欄位（例如 `offline_bands`、`car_upgrade_tiers`、`yard_x_range`）呢期
未支援，維持本機預設（見 `constants.gd` `REMOTE_TUNABLE_FIELDS` 上面嘅
註解）。

## 部署（~10 分鐘，喺 Cloudflare dashboard 撳幾下）

1. [dash.cloudflare.com](https://dash.cloudflare.com) → **Workers & Pages** →
   Create → Worker（名例如 `junkpile-tycoon-constants`）→ 貼
   [`worker.js`](worker.js) 入去 → Deploy。
2. **Storage & Databases → KV** → Create namespace（名例如
   `junkpile-tycoon-constants`）。
3. 返去個 Worker → **Settings → Bindings** → Add → **KV namespace**：
   變數名 `CONSTANTS`，揀第 2 步個 namespace。
4. 同一頁 → **Add → Secret**：名 `ADMIN_KEY`，值 = 你自訂嘅一串夠長夠亂
   嘅字（呢個係 `POST /constants` 嘅認證密鑰；唔可以 commit——淨係存喺
   dashboard）。
5. 抄低個 Worker 網址（Worker overview 頁見到，例如
   `https://junkpile-tycoon-constants.<你嘅子網域>.workers.dev`）。
6. 將呢個網址填入
   [`../systems/remote_constants_loader.gd`](../systems/remote_constants_loader.gd)
   嘅 `RemoteConstantsLoader.CONSTANTS_URL` → commit → 重新出 APK。

### 想用 Git 接駁自動部署（代替手動貼 code）

接咗落 **Workers Builds** 嘅話，push 落 `main` 就自動部署，唔使自己手動貼
code。將 Workers Builds 個 project 嘅 root directory 設做 `worker/`，佢會
讀到 [`wrangler.jsonc`](wrangler.jsonc)；記得先將第 2 步個 KV namespace id
填入 `wrangler.jsonc` 嘅 `kv_namespaces[0].id`。同 yaing 自己個 worker 一樣：
**改 `worker.js` 一定經 PR，唔好直接 push 落 main**——Workers Builds 一見
main 有新 commit 即刻部署，唔會等任何 CI 跑綠先部署。

## 推一次調數（唔使出 APK）

```bash
curl -X POST https://<你嘅worker網址>/constants \
  -H "x-admin-key: <ADMIN_KEY>" \
  -H "content-type: application/json" \
  -d '{"overrides": {"miner_cost_base": 20, "frenzy_mult": 6}}'
```

查而家派緊嘅值：

```bash
curl https://<你嘅worker網址>/constants
```

App 開機喺背景 GET 一次（見 `RemoteConstantsLoader`），成功就即刻套用（升
級價／狂熱數值等即場生效）並存落本機 cache；request 失敗或者回應格式壞
咗都會 fallback 用本機 cache／預設，唔會因為 worker 冧咗／連唔到而擋住
遊戲入口。**部分欄位（例如 `starting_cash`）喺遊戲初始化嗰刻就已經讀
走，今次 session 改極都唔會即場生效**——呢類欄位一定要玩家**重開多次
App**（背景 fetch 存落本機 cache → 下次開機 `main.gd` 構造遊戲物件之前
先讀 cache 套用），先會用到新值。

## 私隱

呢個 worker 完全唔碰任何 cookie／帳戶／玩家資料——淨係回返開發者最後一次
`POST` 落嘅內容。`GET` endpoint 設計上公開、唯讀（App 要攞得到，唔可以帶
任何密鑰）。
