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

設計總帳同 PLAN 見 Multica 父 issue。
