extends Node

## VR-11：低層 JSON 讀寫／版本遷移全部喺 data/save_manager.gd
## （SaveManager，VR-05 已經有嘅框架，欄位形狀／遷移見嗰個檔案嘅
## 註解）——呢個 autoload 唔重新定義存檔形狀，淨係加一層「讀檔之餘順手
## 套用 Wallet」嘅駁線：邊個場景要顯示／用到最新錢包數值，自己 _ready()
## 度 call load_and_apply_wallet() 就得，唔使識 SaveManager 個存檔形狀，
## 亦唔使自己 import Wallet。

## 讀返成個 flat save dict，同時將入面嘅 cash／components／eco 套用落
## Wallet。冇存檔就回傳 SaveManager.default_state() 嘅形狀（cash 全部
## 0），Wallet 都會跟住歸零。
func load_and_apply_wallet() -> Dictionary:
	var data := SaveManager.load_state()
	Wallet.load_from_dict(data)
	return data

## 存返成個 flat dict——呼叫方（例如 main.gd _save_game()）負責喺呼叫
## 之前將自己嗰刻嘅即時數值同步落 Wallet（見 main.gd
## _sync_wallet_from_state()），等呢度存落 disk 嗰份同 Wallet 記憶體嗰份
## 一致。
func save_raw(state: Dictionary) -> Error:
	return SaveManager.save_state(state)
