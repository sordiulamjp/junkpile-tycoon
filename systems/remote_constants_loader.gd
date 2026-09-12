extends Node
class_name RemoteConstantsLoader

## VR-08：App 開機一次性攞遠端 constants 覆寫（worker/README.md 部署
## 步驟）。用 HTTPRequest 起錨；逾時／連唔到／回應唔係 200／JSON 壞晒
## → 一律 fallback（emit 空 Dictionary），main.gd 側維持本機預設，唔會
## 因為呢個 request 擋住／拖慢遊戲入口（見 main.gd `_ready()`：呢個
## fetch 喺世界起完之後先喺背景叫，唔阻頭幾秒嘅放置節奏）。
##
## 淨係負責「發 request + 決定 fallback 原因」；實際 sanitize／merge 邏輯
## 喺 RemoteConstants（純函數，GUT 唔使開網絡都測到）。覆寫來源經
## EventLog 記錄一次（type "remote_config"），方便 debug 畫面／匯出時
## 對得到「呢鋪玩緊嗰份 constants 係咪覆寫過」。

## 部署完 worker/（見 worker/README.md）之後填呢度做正式網址；留空 =
## 停用遠端覆寫，一律用本機預設（同 yaing CONFIG.store.apiBase 空白＝
## 停用嘅設計一致）。
const CONSTANTS_URL := ""

const DEFAULT_TIMEOUT_SECS := 5.0

## overrides：已經 sanitize 過嘅 Dictionary（可能係空，代表冇嘢覆寫或者
## fallback 用緊本機預設）；source：人睇嘅原因字串，寫入 EventLog。
signal finished(overrides: Dictionary, source: String)

var _http: HTTPRequest
var _url: String
var _timeout_secs: float


func _init(url: String = CONSTANTS_URL, timeout_secs: float = DEFAULT_TIMEOUT_SECS) -> void:
	_url = url
	_timeout_secs = timeout_secs


## 開始攞。冇部署（url 空）就即刻 fallback，唔會嘗試連一個唔存在嘅網址。
func start() -> void:
	if _url.is_empty():
		_finish({}, "local_default:no_url")
		return
	_http = HTTPRequest.new()
	add_child(_http)
	_http.timeout = _timeout_secs
	_http.request_completed.connect(_on_request_completed)
	var err := _http.request(_url)
	if err != OK:
		_finish({}, "local_default:request_error_%d" % err)


func _on_request_completed(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_finish({}, "local_default:http_result_%d_code_%d" % [result, response_code])
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		_finish({}, "local_default:bad_json")
		return
	# Worker 回應包一層 {"overrides": {...}}（見 worker/worker.js GET /constants），
	# 但都接受冇包嗰層嘅裸 Dictionary，方便手動擺一個靜態 JSON 測試。
	var raw_overrides: Variant = parsed.get("overrides", parsed)
	var overrides := RemoteConstants.sanitize_overrides(raw_overrides)
	if overrides.is_empty():
		_finish(overrides, "remote_empty")
	else:
		_finish(overrides, "remote_applied:%d_fields" % overrides.size())


func _finish(overrides: Dictionary, source: String) -> void:
	EventLog.log_event("remote_config", {"source": source, "fields": overrides.keys()})
	finished.emit(overrides, source)
	if is_inside_tree():
		queue_free()
