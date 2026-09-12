extends Node

## VR-06：8 條 CC0 音效嘅播放器（來源見 CREDITS.md）。Autoload singleton，
## main.gd／frenzy_yard_view.gd 淨係 call `SfxPlayer.play("pile_mine")`
## 呢類 key，唔使自己管理 AudioStreamPlayer。
##
## 用一個細細嘅 player pool（唔係逐次 new，減少同一幀多粒散幣同時觸發
## 滾筒／穿門音效時 node 建立嘅開銷），冇聲音檔案就靜默跳過，唔會令
## 遊戲 crash（例如 export 漏帶 assets/audio）。

const SOUNDS := {
	"pile_mine": "res://assets/audio/pile_mine.ogg",
	"furnace_feed": "res://assets/audio/furnace_feed.ogg",
	"upgrade": "res://assets/audio/upgrade.ogg",
	"frenzy_start": "res://assets/audio/frenzy_start.ogg",
	"gate_pass": "res://assets/audio/gate_pass.ogg",
	"roller_hit": "res://assets/audio/roller_hit.ogg",
	"lava_fall": "res://assets/audio/lava_fall.ogg",
	"gear_catch": "res://assets/audio/gear_catch.ogg",
}

const POOL_SIZE := 6

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_idx := 0


func _ready() -> void:
	for key: String in SOUNDS.keys():
		var stream: AudioStream = load(SOUNDS[key])
		if stream != null:
			_streams[key] = stream
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)


func play(key: String, volume_db: float = 0.0) -> void:
	if not _streams.has(key):
		return
	var player: AudioStreamPlayer = _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % _pool.size()
	player.stream = _streams[key]
	player.volume_db = volume_db
	player.play()
