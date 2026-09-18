# 上架清單 — 用戶登入 Play Console 之後逐步做

呢個 App 未開過 Play Console 項目（US$25 一次性開發者帳戶費要用戶自己畀）。以下每步
講明「貼邊份文件去邊個欄位」，全部文件喺 `store/` 資料夾。**呢張 checklist 之前嘅所有
步驟已經喺 ALTA-286 呢個 run 完成；呢張 checklist 本身要用戶登入先做到，屬於
ALTA-156 範圍。**

## 0. 開發者帳戶（如未開）

Play Console → 用戶自己嘅 Google 帳戶登入 → 畀 US$25 一次性開發者註冊費。

## 1. 建立 App

- App name: `Junkpile Tycoon`
- Default language: 中文（繁體，香港）或 English，視乎用戶想邊個做預設
- App or game: **Game**
- Free or paid: **Free**（含應用程式內購買）

## 2. Main store listing

| Play 欄位 | 貼邊份 |
|---|---|
| Short description | `STORE-LISTING.md` → 短描述（中／英各揀一個語言版位） |
| Full description | `STORE-LISTING.md` → 長描述 |
| App icon (512×512) | `store/assets/icon-512.png` |
| Feature graphic (1024×500) | `store/assets/feature-graphic-1024x500.png` |
| Phone screenshots（最少 2 張） | `store/assets/screenshots/`（**未影，見 SCREENSHOTS.md，
  要 S8+ 接通先補**） |
| Category | Games → Simulation（或 Casual，`STORE-LISTING.md` 有講） |

若要中英雙語商店頁面，Play Console 支援加多個語言版本嘅 listing——中文版貼 zh-Hant
文案，English 版貼英文文案，兩份都喺 `STORE-LISTING.md`。

## 3. Privacy policy

1. 將 `store/privacy.html` 部署上 Cloudflare Pages（同 `worker/` 果個 Cloudflare 帳戶
   一致就得，開返一個新 Pages project，靜態上傳呢個 HTML 檔案即可，唔使 build 步驟）。
2. 攞返個公開網址，貼入 Play Console → **Store settings → Privacy policy**。
3. `store/PRIVACY.md` 係同一份內容嘅 Markdown 版本，方便日後編輯／存 repo；正式對外
   連結一律用部署咗嘅 `privacy.html`。

## 4. App content

| Play 分頁 | 貼邊份 |
|---|---|
| Data safety | `store/DATA-SAFETY.md` 逐項答案（照本機 code 現況；去廣告 IAP 未上線嗰格見文件備註） |
| Content ratings（IARC 問卷） | `store/IARC-QUESTIONNAIRE.md`，交完之後將分級結果補返落
  文件底部 |
| Target audience and content | `store/TARGET-AUDIENCE.md`（建議 18+，唔入 Families） |
| Ads | 答**有**廣告（AdMob rewarded） |
| App access | 答「全部功能唔使特殊帳戳／登入就用到」（All functionality available
  without special access，因為冇登入系統） |
| Government app / COVID contact tracing / financial features 等其他聲明 | 全部答否
  （`TARGET-AUDIENCE.md` 底部有講） |

## 5. 簽名 AAB（本機已生成，唔使 GitHub Actions）

- 位置：`~/.cache/apk-serve/junkpile-tycoon-0.0.1-code1-20260918.aab`
- 已用 upload keystore 簽署核實（`keytool -printcert -jarfile` 確認過 signer 憑證）
- Upload keystore：`~/keys/junkpile-upload-keystore.jks`（alias `upload`，密碼喺
  `~/keys/junkpile-upload-keystore.password.txt`，**兩個檔案都喺 repo 外，永久保
  存、唔好刪**——之後每次出新版都要用返同一條 key，否則 Play 會拒收）
- Package: `hk.junkpile.tycoon`，version code 1，version name 0.0.1
- 上載去 **Testing → Closed testing → 建立新軌道**（唔好一開始就用 Production／
  Internal testing 之外嘅其他軌道，跟父 issue 決定嘅「封閉測試 14 日」流程）

## 6. Closed testing

- 跟 `store/CLOSED-TESTING-PLAN.md` 加齊 12+ 位測試者電郵
- 分享 Play 提供嘅 opt-in 測試連結畀佢哋，連埋 `CLOSED-TESTING-PLAN.md` 嘅測試說明
- 回饋渠道（ntfy／email）都喺 `CLOSED-TESTING-PLAN.md`

## 7. 送審

全部欄位填晒、AAB 上載、Data safety／Content rating／Target audience 都送出之後，
Play Console 會提示可以送審。首次審核通常 1–7 日。

## 呢個 run 未做到、仲要跟開嘅嘢

- [ ] 商店截圖（S8+ 未接通，見 `SCREENSHOTS.md`）
- [ ] 去廣告 IAP 真正實作（ALTA-285，商業化實作進行中）；上線後要返嚟改
      `DATA-SAFETY.md`／`IARC-QUESTIONNAIRE.md` 相關幾格
- [ ] AdMob 帳戶由測試 ad unit ID 換成真帳戶（ALTA-154，blocked，要用戶提供 AdMob
      帳戶）
- [ ] `store/privacy.html` 實際部署上 Cloudflare Pages，攞返公開網址
- [ ] 封閉測試者名單（`CLOSED-TESTING-PLAN.md` 表格未填人）
- [ ] 呢個 checklist 本身要用戶登入 Play Console 逐步行一次（ALTA-156）
