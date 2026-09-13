extends Node

## VR-11：共用錢包（Cash／Components／Eco），autoload singleton。
##
## 「同一場地，由下向上擴張」（field-zones-v9.png）——唔係獨立場景，
## 淨係一個 main.tscn，理論上唔會出現「跨場景」嘅分裂。獨立呢個
## autoload 出嚟嘅原因：一個存檔要包住共用錢包 + 各區域自己嘅進度（見
## data/save_manager.gd VR-11 v1→v2 遷移），拆出 Wallet 做單一 source of
## truth，等 systems/unlock_panel.gd 呢類唔想識 GameState 內部形狀嘅
## reusable 元件都可以直接讀 Wallet.cash 判斷「夠唔夠錢解鎖」，唔使逐個
## 傳一份 state reference 入去。
##
## 即時數值仍然喺 main.gd 嘅 GameState（`state.cash` 度 tick），Wallet
## 淨係喺存檔前後同步一次（見 main.gd _sync_wallet_from_state()／
## _apply_loaded_state()），唔係每幀都寫。

var cash: float = 0.0
var components: float = 0.0
var eco: float = 0.0

## 存檔讀完之後套用（例如 Save.load_and_apply_wallet()）。淨係識呢三個
## 欄位，唔理／唔識其他 region-specific 欄位（嗰啲留喺各自嘅存檔分支
## 處理，見 data/save_manager.gd）。缺咗嘅欄位當 0，唔會保留舊值。
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
