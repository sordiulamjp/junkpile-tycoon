# Junkpile Tycoon

半放置廢料礦場手遊（Godot 4.7.2，GDScript，Compatibility 渲染器，Android 先行）。

- `project.godot` / `main.tscn`：專案入口
- `export_presets.cfg`：Android 匯出預設（arm64，Gradle build——ALTA-154 為咗 AdMob plugin 嘅
  Maven 依賴改由非 gradle 轉做 gradle）
- 出 APK（VM headless，第一次或者 `android/` 冇嘢要加 `--install-android-build-template`）：
  `godot --headless --install-android-build-template --export-debug "Android" build/junkpile-tycoon.apk`
- `addons/admob/`：Poing Studios AdMob plugin（MIT，[poingstudios/godot-admob-plugin](https://github.com/poingstudios/godot-admob-plugin)），已驗證對準 Godot 4.7.2；`ads/ad_manager.gd`
  包裝 UMP 同意表格 + 一個 rewarded 測試廣告位。`ads/ad_test.tscn`（ALTA-154 驗證畫面，測試
  rewarded 廣告用）冇搶 `run/main_scene`——依家淨係想睇/測就用 Godot editor 開個 scene 撳
  F6（Run Current Scene），或者出 APK 前臨時將 `run/main_scene` 改去佢
- `systems/event_log.gd`：本機事件 log（`user://events.jsonl`），`debug/event_log_debug.tscn`
  係 debug 畫面（睇／匯出／清除），同 `ads/ad_test.tscn` 一樣冇搶 `run/main_scene`
- `systems/remote_constants.gd` + `systems/remote_constants_loader.gd`：遠端 constants 覆寫
  （VR-08），Worker 部署見 `worker/README.md`
- `autoload/wallet.gd` + `autoload/save.gd`：VR-11（ALTA-227）共用錢包／存檔駁線；
  `systems/unlock_panel.gd`：reusable 解鎖板元件（撳落去夠錢就扣 GameState.cash＋記存檔）
- 「同一場地，由下向上擴張」（field-zones-v9.png，VR-11／ALTA-227）——**唔係獨立場景**，
  全部區域／子系統都掛喺 `main.tscn` 單一 3D 世界下，鏡頭可拖睇到更多。`regions/`
  淨係擺純數值／UI 邏輯（唔掛 SceneTree，方便 GUT 獨立測試），3D 視覺／輸入一律喺
  `main.gd` 或者掛落 `_placement_root` 嘅 class（例如 `regions/region1_mine/mine_zone.gd`）
  起。`regions/region1_mine/`（VR-12，ALTA-228：區域 1 場內礦坑——後壁梯級礦層 →
  礦車路軌 → 倉庫 + 推堆墊）：`mine_state.gd` 純數值、`mine_zone.gd` 3D 場景（後壁
  梯級、UnlockPanel 解鎖板、地面礦堆）、`mine_cross_section_panel.gd` 撳「礦道入口」
  toggle 嘅 2D 剖面面板，三者都由 `main.gd` 構造／驅動，唔係獨立 `.tscn`
- `regions/region2_outer_path/`（VR-13，ALTA-229，PLAN v3 合併原區域 2／3／4：外圍
  險路——左車道 ×2→×3→×4 發光倍數板 + 刺滾筒 + 磚牆 → 頂部轉右金河 + 岩浆 + 100 lb
  木橋限重 → ×5 板 → 礦站，沿路 UPGRADE 小屋 200／500）：`region2_state.gd` 純數值
  （倍數相乘／磚牆撞爛判斷／木橋限重／礦站賣價，自動出貨車 `tick()` 循環），
  `region2_zone.gd` 3D 場景，由 `main.gd`（`_region2_panel` 解鎖之後）構造／驅動，
  同樣唔係獨立 `.tscn`

設計總帳同 PLAN 見 Multica 父 issue。
