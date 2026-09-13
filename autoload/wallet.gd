extends Node

## VR-11：全部區域共用嘅錢包（Cash／Components／Eco）。四個區域各自係
## 獨立 Godot 場景、各自一套玩法同升級線（見 scenes/zone_map.gd 嘅
## ZONES 路由表），但呢三種資源要跨場景切換都保持一致——單一 source of
## truth 擺呢度（autoload），返地圖／再入場都讀返同一份，唔使各區域自
## 己記一份會唔會同步嘅副本。
##
## 呢個 autoload 本身唔識存檔——邊個時間點讀/寫落 disk 係 Save autoload
## 嘅事（見 autoload/save.gd）：場景（例如 main.gd）_ready() 攞到存檔
## 之後用 load_from_dict() 套落嚟；存檔之前（_save_game()）先用當刻嘅
## 即時數值覆寫返呢度嘅欄位，等 to_dict() 攞到嘅一定係最新值。

var cash: float = 0.0
var components: float = 0.0
var eco: float = 0.0

## 存檔讀完之後套用（例如 Save.load_and_apply_wallet()）。淨係識呢三個
## 欄位，唔理／唔識其他 zone-specific 欄位（嗰啲留喺各區域自己嘅存檔
## 分支處理，見 data/save_manager.gd）。缺咗嘅欄位當 0，唔會保留舊值。
func load_from_dict(data: Dictionary) -> void:
	cash = float(data.get("cash", 0.0))
	components = float(data.get("components", 0.0))
	eco = float(data.get("eco", 0.0))

## 存檔前攞返依家嘅數值，砌成 Save/SaveManager 認得嘅三個欄位。
func to_dict() -> Dictionary:
	return {"cash": cash, "components": components, "eco": eco}

## GUT／debug 用：清零。唔係威望重置嗰種「清 Cash 留終身統計」，純粹
## 測試之間互相隔離，或者未來「完全重來」debug 掣用。
func reset() -> void:
	cash = 0.0
	components = 0.0
	eco = 0.0
