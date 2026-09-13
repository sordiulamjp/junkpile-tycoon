extends GutTest

## VR-11：res://autoload/save.gd 單元測試。覆蓋「一個存檔入面包住共用
## 錢包」嘅駁線：load_and_apply_wallet() 讀完 SaveManager 嘅 flat dict
## 之後，Wallet 嘅 cash／components／eco 應該同存檔一致（對應驗收「殺
## App 重開，錢包數字一致」）；save_raw() 轉駁去 SaveManager.save_state()
## 唔改個存檔形狀／版本。

func before_each() -> void:
	SaveManager.delete_save()
	Wallet.reset()

func after_each() -> void:
	SaveManager.delete_save()
	Wallet.reset()

const EPS := 0.001


func test_load_and_apply_wallet_with_no_save_file_yields_zero_wallet() -> void:
	var data := Save.load_and_apply_wallet()
	assert_eq(data["cash"], 0.0)
	assert_eq(Wallet.cash, 0.0)
	assert_eq(Wallet.components, 0.0)
	assert_eq(Wallet.eco, 0.0)

func test_save_raw_then_load_and_apply_wallet_round_trip() -> void:
	# 對應驗收「殺 App 重開進度不變」——用 Wallet.reset() 模擬「殺
	# App」：記憶體歸零，淨低 disk 嗰份存檔，重開應該讀返晒。
	var state := SaveManager.default_state()
	state["cash"] = 5000.0
	state["components"] = 12.0
	state["eco"] = 3.0
	var err := Save.save_raw(state)
	assert_eq(err, OK)

	Wallet.reset()
	var loaded := Save.load_and_apply_wallet()

	assert_almost_eq(loaded["cash"], 5000.0, EPS)
	assert_almost_eq(Wallet.cash, 5000.0, EPS)
	assert_almost_eq(Wallet.components, 12.0, EPS)
	assert_almost_eq(Wallet.eco, 3.0, EPS)

func test_load_and_apply_wallet_matches_save_manager_directly() -> void:
	# Save 淨係加一層駁線，SaveManager 嘅 flat dict 形狀／版本遷移完全
	# 唔變——確保 Save 讀返嚟嘅同 SaveManager 直接讀個份一致。
	var state := SaveManager.default_state()
	state["cash"] = 77.0
	SaveManager.save_state(state)

	var via_save := Save.load_and_apply_wallet()
	var via_manager := SaveManager.load_state()

	assert_almost_eq(via_save["cash"], via_manager["cash"], EPS)
	assert_eq(via_save["version"], via_manager["version"])
