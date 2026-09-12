# CREDITS

第三方資產全部 CC0（Creative Commons Zero），可自由用於商業專案，唔強制標註來源；
本檔仍然記低嚟源方便日後追溯／換皮。冇列出嘅資產（場景結構、方塊／CSG 幾何、材質顏色、
GDScript 程式碼）全部自製，唔涉及第三方授權。

## 3D 模型

| 檔案 | 來源 | 授權 |
|---|---|---|
| `assets/models/character-g.glb` + `assets/models/Textures/texture-g.png` | [Kenney — Blocky Characters](https://kenney.nl/assets/blocky-characters)，機械人造型（character-g，金屬灰配紅色），用作礦工 | CC0 |

用途：`systems/visual_factory.gd` 嘅 `make_miner()` 讀呢個 glTF 場景，代替原本嘅純色盒仔灰模。
揀呢個角色皮膚係因為包入面 18 個角色入面淨係佢哋兩個（character-g／character-h）著金屬機械人裝，
其餘大部分係人形／殭屍（character-l、character-o 顯著殭屍綠皮黃牙，明確要避開），
機械人造型完全符合 issue 要求「唔可以似 Idle Zombie Miner」。

## 圖示

| 檔案 | 來源 | 授權 |
|---|---|---|
| `assets/icons/gear.png` | [Kenney — Game Icons](https://kenney.nl/assets/game-icons)（白底，HUD 內用 `modulate` 上色） | CC0 |
| `assets/icons/locked.png` | 同上 | CC0 |
| `assets/icons/unlocked.png` | 同上 | CC0 |
| `assets/icons/star.png` | 同上 | CC0 |
| `assets/icons/wrench.png` | 同上 | CC0 |
| `assets/icons/plus.png` | 同上 | CC0 |
| `assets/icons/arrowRight.png` | 同上 | CC0 |
| `assets/icons/checkmark.png` | 同上 | CC0 |

用途：HUD 資源／升級／鎖／威望標籤前面嘅小圖示（`main.gd` `_build_hud()`）。

## 音效

| 檔案 | 來源 | 授權 | 用喺邊 |
|---|---|---|---|
| `assets/audio/pile_mine.ogg` | Kenney — [Impact Sounds](https://kenney.nl/assets/impact-sounds)（`impactMining_002.ogg`） | CC0 | 山腳碎料 tap scoop |
| `assets/audio/furnace_feed.ogg` | Kenney — Impact Sounds（`impactMetal_medium_001.ogg`） | CC0 | 帶入貨到爐／倉 |
| `assets/audio/upgrade.ogg` | Kenney — [Interface Sounds](https://kenney.nl/assets/interface-sounds)（`confirmation_002.ogg`） | CC0 | 帶／礦工／精煉升級成功 |
| `assets/audio/frenzy_start.ogg` | Kenney — Interface Sounds（`open_003.ogg`） | CC0 | 狂熱車場開始 |
| `assets/audio/gate_pass.ogg` | Kenney — Interface Sounds（`switch_004.ogg`） | CC0 | 車／散幣穿過倍數門 |
| `assets/audio/roller_hit.ogg` | Kenney — Impact Sounds（`impactMetal_light_002.ogg`） | CC0 | 藍波經過刺滾筒變金幣 |
| `assets/audio/lava_fall.ogg` | Kenney — Interface Sounds（`error_004.ogg`） | CC0 | 車跌落窄岩浆（懲罰） |
| `assets/audio/gear_catch.ogg` | Kenney — Impact Sounds（`impactBell_heavy_000.ogg`） | CC0 | 車接中齒輪 |

原 issue 要求用 freesound CC0；因為 freesound.org 下載需要登入帳戶授權，冇辦法喺呢個 runtime
免人手完成，改用一樣係 CC0、免登入直接下載嘅 Kenney Impact/Interface Sounds 兩個音效包，
授權同音量／長度定位一致（8 條，總計 ~55KB，遠低於 1MB）。如果用戶堅持要 freesound 嘅實際檔案，
需要有帳戶嘅人手手動換走呢 8 個檔案。

## 美術風格（自製）

礦山、輸送帶、熔爐、倉、狂熱車場（車、牆、刺滾筒、倍數門、木橋、UPGRADE 墊、齒輪）、山腳碎料／
藍波／金幣全部用 `systems/visual_factory.gd` 入面嘅 Godot 原生 Mesh（BoxMesh／CylinderMesh／
PrismMesh／CSG）現砌，flat-shaded 材質，冇貼圖——跟 issue 講明「冇合適包嘅物件直接用 Godot
CSG／ArrayMesh 砌，flat-shading 下效果一致」。色板見 `visual_factory.gd` 頂部 `PALETTE`
常數，對應 docx 概念圖（洞穴啡／廢料灰啡／熔爐藍＋橙光／岩浆橙紅／礦物階色／齒輪金屬灰／皇冠紫）。

App icon（`assets/icon.png`）：自製，唔涉及第三方素材。
