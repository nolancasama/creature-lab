class_name WebSpeechBackend
extends SpeechBackend
## Real speech recognition through the browser's Web Speech API (HTML5 export).
##
## Godot ships no speech-to-text, so a web export is the only route to a real microphone
## without a native extension. Everything JavaScript-shaped is confined to this file;
## gameplay never learns that a browser is involved. Alternatives are passed through so a
## young learner's accent gets several chances at a match.

const LANGUAGE := "en-US"
const ALT_SEP := "\u0001" ## Alternatives arrive joined by U+0001, impossible in speech.

const JS_SETUP := """
window.__godotSpeech = (function () {
	var SR = window.SpeechRecognition || window.webkitSpeechRecognition;
	var api = { supported: !!SR, rec: null, active: false };
	api.start = function (lang) {
		if (!api.supported) { window.godotSpeechBridge('error', 'unsupported'); return; }
		if (api.active) { return; }
		var r = new SR();
		r.lang = lang || 'en-US';
		r.interimResults = true;
		r.continuous = false;
		r.maxAlternatives = 4;
		r.onresult = function (e) {
			for (var i = e.resultIndex; i < e.results.length; i++) {
				var alts = [];
				for (var j = 0; j < e.results[i].length; j++) { alts.push(e.results[i][j].transcript); }
				window.godotSpeechBridge(e.results[i].isFinal ? 'final' : 'interim', alts.join('\\u0001'));
			}
		};
		r.onerror = function (e) { window.godotSpeechBridge('error', e.error || 'unknown'); };
		r.onend = function () { api.active = false; window.godotSpeechBridge('end', ''); };
		api.rec = r;
		api.active = true;
		try { r.start(); window.godotSpeechBridge('start', ''); }
		catch (err) { api.active = false; window.godotSpeechBridge('error', 'start-failed'); }
	};
	api.stop = function () { if (api.rec && api.active) { try { api.rec.stop(); } catch (e) {} } };
	return api;
})();
"""

var _bridge: Object = null
var _callback: Variant = null # Must stay referenced or the JS callback is collected.
var _ready_to_listen := false


func backend_id() -> String:
	return "web"


func display_name() -> String:
	return "ボタンを押して話す"


func is_supported() -> bool:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return false
	_ensure_bridge()
	if _bridge == null:
		return false
	return bool(_bridge.eval("!!(window.SpeechRecognition || window.webkitSpeechRecognition)", true))


func _ensure_bridge() -> void:
	if _bridge != null:
		return
	if not Engine.has_singleton("JavaScriptBridge"):
		return
	_bridge = Engine.get_singleton("JavaScriptBridge")
	_callback = _bridge.create_callback(_on_js_event)
	var window: Variant = _bridge.get_interface("window")
	if window == null:
		_bridge = null
		return
	window.godotSpeechBridge = _callback
	_bridge.eval(JS_SETUP, true)
	_ready_to_listen = true


func start() -> void:
	_ensure_bridge()
	if not _ready_to_listen:
		failed.emit("unsupported")
		return
	_bridge.eval("window.__godotSpeech.start('%s');" % LANGUAGE, true)


func stop() -> void:
	if _ready_to_listen and _bridge != null:
		_bridge.eval("window.__godotSpeech.stop();", true)
	if listening:
		listening = false
		listening_changed.emit(false)


func cleanup() -> void:
	stop()
	_callback = null
	_bridge = null
	_ready_to_listen = false


func _on_js_event(args: Array) -> void:
	if args.size() < 2:
		return
	var kind := str(args[0])
	var payload := str(args[1])
	match kind:
		"start":
			listening = true
			listening_changed.emit(true)
		"end":
			if listening:
				listening = false
				listening_changed.emit(false)
		"error":
			listening = false
			listening_changed.emit(false)
			failed.emit(payload)
		"interim":
			transcript.emit(_split(payload), false)
		"final":
			transcript.emit(_split(payload), true)


func _split(payload: String) -> PackedStringArray:
	var out := PackedStringArray()
	for part in payload.split(ALT_SEP, false):
		var text := str(part).strip_edges()
		if not text.is_empty():
			out.append(text)
	return out
