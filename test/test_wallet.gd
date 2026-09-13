extends GutTest

## VR-11：res://autoload/wallet.gd 單元測試。覆蓋：預設值、
## load_from_dict()／to_dict() round-trip、缺欄位當 0、reset()。

func before_each() -> void:
	Wallet.reset()

func after_each() -> void:
	Wallet.reset()

const EPS := 0.001


func test_default_is_zero() -> void:
	assert_eq(Wallet.cash, 0.0)
	assert_eq(Wallet.components, 0.0)
	assert_eq(Wallet.eco, 0.0)

func test_load_from_dict_applies_all_three_fields() -> void:
	Wallet.load_from_dict({"cash": 100.0, "components": 5.0, "eco": 2.5})
	assert_almost_eq(Wallet.cash, 100.0, EPS)
	assert_almost_eq(Wallet.components, 5.0, EPS)
	assert_almost_eq(Wallet.eco, 2.5, EPS)

func test_load_from_dict_missing_fields_reset_to_zero() -> void:
	# load_from_dict() 唔係「淨係覆寫有帶到嘅欄位」——缺咗嘅欄位一律當
	# 0，唔應該保留返之前個殘留值（避免場景之間互相污染 Wallet）。
	Wallet.cash = 999.0
	Wallet.components = 999.0
	Wallet.load_from_dict({})
	assert_eq(Wallet.cash, 0.0)
	assert_eq(Wallet.components, 0.0)

func test_to_dict_round_trip() -> void:
	Wallet.cash = 42.0
	Wallet.components = 3.0
	Wallet.eco = 1.0
	var dict := Wallet.to_dict()

	Wallet.reset()
	Wallet.load_from_dict(dict)

	assert_almost_eq(Wallet.cash, 42.0, EPS)
	assert_almost_eq(Wallet.components, 3.0, EPS)
	assert_almost_eq(Wallet.eco, 1.0, EPS)

func test_reset_zeroes_all_fields() -> void:
	Wallet.load_from_dict({"cash": 1.0, "components": 2.0, "eco": 3.0})
	Wallet.reset()
	assert_eq(Wallet.cash, 0.0)
	assert_eq(Wallet.components, 0.0)
	assert_eq(Wallet.eco, 0.0)
