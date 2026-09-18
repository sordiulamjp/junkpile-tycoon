# Data safety 申報草稿（Play Console → App content → Data safety）

**呢份係草稿**，跟現時 code 實際行為（`ads/ad_manager.gd`、`systems/remote_constants_loader.gd`、
`systems/event_log.gd`）填。用戶登入 Play Console 正式填表前應該覆核一次，尤其係「去廣告 IAP」
（ALTA-154／ALTA-285 商業化實作完成後）呢部分——依家淨係測試 ad unit ID，未有真帳戶。

## 1. 你嘅 App 有冇收集或者分享 Play 要求申報嘅用戶資料類型？

**答：有**（透過內嵌嘅 Google AdMob SDK）。

## 2. 逐項資料類型

| 類別 | 資料類型 | 收集？ | 分享？ | 用途 | 是否必要 | 理由 |
|---|---|---|---|---|---|---|
| 裝置或其他 ID | Device or other IDs（廣告 ID） | 有 | 有（同 Google／AdMob 廣告網絡） | 廣告 | 用戶可選擇（可拒絕個人化，但 SDK 本身仍會存取） | AdMob SDK 內嵌行為，`ads/ad_manager.gd` 已行 UMP 同意流程先至初始化廣告 |
| 位置 | 大約位置（Approximate location） | 有 | 有 | 廣告 | 選擇性 | AdMob 由 IP 推算大約位置嚟投放廣告，屬 SDK 標準行為 |
| App 活動 | App 互動／廣告曝光量度 | 有 | 有 | 廣告、分析廣告成效 | 選擇性 | rewarded 廣告曝光／完成率由 AdMob 記錄 |
| App 資訊及表現 | 崩潰紀錄／診斷 | 有 | 冇（淨係 Google Play 平台內部） | 分析、App 效能 | 必要 | Google Play Console 自動收集，非本 App 主動送出 |
| 財務資料 | 購買紀錄（去廣告 IAP） | **視乎版本** | 冇 | App 功能 | 必要（如果用咗呢個購買） | 用 Google Play Billing 處理；本 App 見唔到卡資料，只收到「已購買」狀態。**現時 code 未實作 Billing（ALTA-154/285 進行中）；一旦上線，呢格應改做「有」+「App 功能」，暫時可以填「無」或者留返實作完成後先送出呢張表** |
| 個人資料 | 姓名／電郵／電話／地址 | 冇 | — | — | — | App 冇登入、冇表單收集呢啲資料 |
| 相片／影片／音訊／檔案／聯絡人／日曆／健康 | 全部 | 冇 | — | — | — | App 唔要求任何裝置權限存取呢類資料 |
| 網頁瀏覽紀錄 | — | 冇 | — | — | — | 冇內置瀏覽器／追蹤 |
| 其他 | 本機事件 log（`user://events.jsonl`） | **淨係本機，唔算「收集」（冇離開裝置）** | 冇 | — | — | 屬於裝置內部日誌，用戶主動匯出分享先會離開裝置，Play 表格通常唔要求申報純本機、唔上傳嘅日誌 |

## 3. 保安做法（Security practices）

- **資料喺傳輸中有冇加密？** 有——AdMob／Google Play Billing／Play 服務全部行 HTTPS；
  日後部署嘅 Cloudflare Worker 遠端設定 endpoint 都應該用 HTTPS。
- **用戶可唔可以要求刪除資料？** 我哋冇集中式伺服器存住用戶資料，冇資料庫可刪；用戶可以
  透過裝置設定重置廣告 ID，或者解除安裝 App 徹底移除本機存檔／log。呢點喺 PRIVACY.md
  已講明。
- **有冇承諾遵守 Play Families Policy？** 冇——本 App 冇加入 Designed for Families 計劃
  （見 TARGET-AUDIENCE.md）。
- **資料有冇獨立安全審查／第三方認證？** 冇（獨立開發者項目，冇呢類審查）。

## 4. 交表前必做

- [ ] 確認去廣告 IAP（ALTA-285）上線狀態，決定「購買紀錄」呢格點答
- [ ] 用戶登入 Play Console 時逐項對返呢份草稿，用 Play 表單嘅實際措辭揀選項
- [ ] 如果日後加真 Firebase／其他分析 SDK，記得返嚟加返對應資料類型
