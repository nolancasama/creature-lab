class_name WebSpeechBackend
extends SpeechBackend
## Thin Chrome Web Speech bridge. It reports the browser's real lifecycle and raw ranked
## alternatives; SpeechService owns sessions and SpeechAttemptClassifier owns language.

const LANGUAGE := "en-US"

const JS_SETUP := """
window.__godotSpeech = (function () {
	var SR = window.SpeechRecognition || window.webkitSpeechRecognition;
	var api = { supported: !!SR, rec: null };
	function send(kind, id, payload) {
		window.godotSpeechBridge(kind, id, payload || '');
	}
	function detach(r) {
		if (!r) return;
		r.onstart = null;
		r.onresult = null;
		r.onerror = null;
		r.onend = null;
		r.onnomatch = null;
	}
	function abandon(r) {
		if (!r) return;
		detach(r);
		try { r.abort(); } catch (e) {}
	}
	api.start = function (id, lang) {
		if (!api.supported) {
			send('error', id, 'unsupported');
			send('end', id, '');
			return;
		}
		if (api.rec) abandon(api.rec);
		var r = new SR();
		r.lang = lang || 'en-US';
		r.continuous = false;
		r.interimResults = true;
		r.maxAlternatives = 4;
		r.__sessionId = id;
		r.onstart = function () { send('start', id, ''); };
		r.onresult = function (e) {
			for (var i = e.resultIndex; i < e.results.length; i++) {
				var alts = [];
				for (var j = 0; j < e.results[i].length; j++) {
					var alt = e.results[i][j];
					alts.push({ text: alt.transcript,
						confidence: (typeof alt.confidence === 'number' ? alt.confidence : -1) });
				}
				send(e.results[i].isFinal ? 'final' : 'interim', id, JSON.stringify(alts));
			}
		};
		r.onerror = function (e) { send('error', id, e.error || 'unknown'); };
		r.onnomatch = function () { send('nomatch', id, ''); };
		r.onend = function () {
			if (api.rec === r) api.rec = null;
			send('end', id, '');
			detach(r);
		};
		api.rec = r;
		try {
			r.start();
		} catch (err) {
			if (api.rec === r) api.rec = null;
			detach(r);
			send('error', id, 'start-failed');
			send('end', id, '');
		}
	};
	api.stop = function (id) {
		var r = api.rec;
		if (!r || r.__sessionId !== id) return;
		try { r.stop(); } catch (e) {}
	};
	api.abort = function (id) {
		var r = api.rec;
		if (!r || r.__sessionId !== id) return;
		api.rec = null;
		abandon(r);
	};
	api.cleanup = function () {
		if (api.rec) abandon(api.rec);
		api.rec = null;
	};
	return api;
})();
"""

var _bridge: Object = null
var _callback: Variant = null # Must stay referenced or the JS callback is collected.
var _ready := false


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
	_ready = true


func start(session_id: int) -> void:
	_ensure_bridge()
	if not _ready:
		error.emit(session_id, "unsupported")
		browser_ended.emit(session_id)
		return
	_bridge.eval("window.__godotSpeech.start(%d, %s);" % [
		session_id, JSON.stringify(LANGUAGE)], true)


func stop(session_id: int) -> void:
	if _ready and _bridge != null:
		_bridge.eval("window.__godotSpeech.stop(%d);" % session_id, true)


func abort(session_id: int) -> void:
	if _ready and _bridge != null:
		_bridge.eval("window.__godotSpeech.abort(%d);" % session_id, true)


func cleanup() -> void:
	if _ready and _bridge != null:
		_bridge.eval("window.__godotSpeech.cleanup();", true)
	_callback = null
	_bridge = null
	_ready = false


func _on_js_event(args: Array) -> void:
	if args.size() < 3:
		return
	var kind := str(args[0])
	var session_id := int(args[1])
	var payload := str(args[2])
	match kind:
		"start":
			browser_started.emit(session_id)
		"interim", "final":
			var decoded := _decode(payload)
			if kind == "final":
				final.emit(session_id, decoded["alternatives"], decoded["confidences"])
			else:
				interim.emit(session_id, decoded["alternatives"], decoded["confidences"])
		"error":
			error.emit(session_id, payload)
		"nomatch":
			no_match.emit(session_id)
		"end":
			browser_ended.emit(session_id)


func _decode(payload: String) -> Dictionary:
	var alternatives := PackedStringArray()
	var confidences := PackedFloat32Array()
	var parsed: Variant = JSON.parse_string(payload)
	if typeof(parsed) != TYPE_ARRAY:
		return {"alternatives": alternatives, "confidences": confidences}
	for item in parsed:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var text := str(item.get("text", "")).strip_edges()
		if text.is_empty():
			continue
		alternatives.append(text)
		confidences.append(float(item.get("confidence", -1.0)))
	return {"alternatives": alternatives, "confidences": confidences}
