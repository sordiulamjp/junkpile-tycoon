# 商店截圖 — 狀態：待影（S8+ 呢次 run 連唔到）

## 呢次 run 嘅結果

`adb connect 100.116.24.90:5555` 兩次都 timeout（`Connection timed out` / 10 秒
`timeout` 冇回應），`adb devices` 見唔到任何裝置——Galaxy S8+ 呢次冇經 VMware USB 交
畀 VM，或者 Tailscale 呢條 link 冇通。**呢步淨係需要用戶令部 S8+ 開機並經 VMware
USB passthrough 交返畀 VM**（同 ALTA-195／ALTA-217 用過嘅同一部裝置、同一個做法），
唔係我哋度可以自己解決嘅嘢——其他部分（合規文件／商店文案／icon／feature graphic／
簽名 AAB）已經全部喺呢個 run 完成，淨返呢一步。

## 影相步驟（裝置一接通就可以做）

```sh
export PATH=$PATH:~/Android/Sdk/platform-tools
adb connect 100.116.24.90:5555
adb devices   # 確認見到裝置
# 出返一個 debug APK 裝上去（唔使簽名，方便快速反覆試相）：
cd ~/junkpile-tycoon   # 或者呢個 issue 嘅 worktree
~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --export-debug "Android" build/junkpile-tycoon-debug.apk
adb install -r build/junkpile-tycoon-debug.apk
adb shell monkey -p hk.junkpile.tycoon -c android.intent.category.LAUNCHER 1
# 玩到目標畫面，然後：
adb exec-out screencap -p > store/assets/screenshots/raw/shot-01.png
```

跟住用 ImageMagick／PIL 裁到 Play 要求嘅比例（見下面尺寸要求），存入
`store/assets/screenshots/`。

## 要影嘅 6–8 張（跟父 issue 玩法順序）

1. 開場：山腳 + 空場地，未召喚礦工
2. 召喚咗第一個機械礦工，敲緊山
3. 輸送帶運緊碎料入爐，HUD 見到 Cash／Components／Eco 三個資源
4. 撳緊「建築升級」（帶／礦工／精煉任一），掣價紅／綠回饋
5. 狂熱車場：跟指揸主戰車衝散幣，見到倍數門
6. 狂熱車場：穿門／滾筒／木橋其中一個風險關卡畫面
7. 離線收入結算面板（回到遊戲見到浣熊經理彈出嘅離線收穫畫面）
8. 場地擴張／解鎖板（VR-11／VR-12 區域 1 礦坑核心畫面，如果已經解鎖到）

## Play 尺寸要求

- **手機截圖**：長邊 ≥ 1920px，短邊 ≥ 1080px（或者對應直向 1080×1920 等），JPEG／
  24-bit PNG（唔可以有 alpha），最少 2 張、最多 8 張。本 App 直版 3:4 相機比例，出嚟
  就用手機原生解析度 screencap（Galaxy S8+ 係 1440×2960 或者相似），Play 會自動縮圖，
  唔使自己再縮。
- **Feature graphic**：1024×500，已經喺 `store/assets/feature-graphic-1024x500.png`
  完成（唔使實機截圖，用現有 icon 美術起稿，符合 Play 政策「唔可以喺 feature graphic
  用截圖／裝置框」）。
- **App icon**：512×512 32-bit PNG（帶 alpha），已經喺
  `store/assets/icon-512.png` 完成。

## 目錄

```
store/assets/
  icon-512.png                      ✅ 完成
  feature-graphic-1024x500.png      ✅ 完成
  screenshots/                      ⏳ 待裝置接通後補
    raw/                            (screencap 原圖，裁剪前)
```
