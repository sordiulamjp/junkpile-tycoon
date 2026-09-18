# 目標受眾／內容分級聲明草稿（Play Console → App content → Target audience and content）

## 目標年齡層

**建議：只揀 18 歲或以上。**

理由：
- 合規清單明確要求「唔入 Families 計劃」（避免 Google Play 兒童與家庭政策嘅額外審查同
  廣告限制），最簡單做法係唔申報任何 13 歲以下嘅年齡層。
- 遊戲入面有廣告同一次性 IAP，主打受眾係休閒放置／大亨遊戲玩家（成年為主）。
- 唔勾兒童年齡層，就唔會觸發「呢個 App 係咪吸引兒童」嘅追加問卷同 Families 政策要求。

如果用戶想擴大受眾（例如想埋 13–17 歲），可以加返呢個年齡層，但要留意會觸發 Google
就「混合受眾（mixed audience）」嘅額外要求（例如唔可以顯示個人化廣告畀已知未成年用
戶、要有額外家長同意機制）。**現階段建議保持單一 18+，上架後如果有數據顯示玩家年齡層
偏年輕，先再檢討。**

## 「呢個 App 係咪特別吸引兒童？」

答：**否**。理由：
- 美術風格用機械人／地精造型礦工，刻意避開「Idle Zombie Miner」呢類殭屍／恐怖元素，
  但都唔係卡通兒童向嘅可愛畫風（低飽和寫實方塊 + CSG 幾何）。
- 冇卡通吉祥物式行銷、冇兒童向 IP 聯乘、冇教育內容包裝。
- App 已經喺 code 層面設定 `RequestConfiguration.tag_for_child_directed_treatment =
  FALSE`（`ads/ad_manager.gd`），同呢個聲明一致。

## Designed for Families 計劃

**不參加。**

## 內容分級（Content rating）

由 IARC 問卷（見 `IARC-QUESTIONNAIRE.md`）自動推算，預期範圍 PEGI 3–7 / ESRB Everyone
（卡通式非寫實破壞、冇血腥）。實際分級以 Play Console 問卷結果為準，交表後貼返落
`IARC-QUESTIONNAIRE.md` 底部存檔。

## 新聞性／時事內容、COVID-19 接觸者追蹤等特別聲明

不適用——本 App 唔涉及新聞、選舉、公共衛生資訊，Play 表格對應題目一律答「否」。
