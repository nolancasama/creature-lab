class_name WebSpeechBackend
extends SpeechBackend
## Browser Web Speech recognition. JavaScript remains confined here; normalisation and
## grammar stay in their own stages.

const LANGUAGE := "en-US"

const JS_SETUP := """
window.__godotSpeech = (function () {
	var SR = window.SpeechRecognition || window.webkitSpeechRecognition;
	var api = { supported: !!SR, rec: null, active: false,
		biasingAvailable: false, biasingApplied: false };
	api.start = function (lang, phrases) {
		if (!api.supported) { window.godotSpeechBridge('error', 'unsupported'); return; }
		if (api.active) { return; }
		var r = new SR();
		r.lang = lang || 'en-US';
		r.interimResults = true;
		r.continuous = false;
		r.maxAlternatives = 6;
		// Contextual biasing is DETECTED but deliberately NOT APPLIED.
		//
		// Chrome exposes SpeechRecognitionPhrase, so the feature test passes, but biasing
		// only works when recognition is running on-device - and assigning r.phrases
		// without that made start() fail. The failure arrives as an async error/end event,
		// so the try/catch around the assignment never saw it and could not swallow it:
		// the microphone flipped to listening and straight back to idle, and no sentence
		// could be recorded at all.
		//
		// A speculative accuracy gain is not worth a chance of no recording. Re-enable
		// only alongside processLocally, and only after testing in a real browser.
		api.biasingAvailable = ('phrases' in r && typeof window.SpeechRecognitionPhrase === 'function');
		api.biasingApplied = false;
		r.onresult = function (e) {
			for (var i = e.resultIndex; i < e.results.length; i++) {
				var alts = [];
				for (var j = 0; j < e.results[i].length; j++) {
					var alt = e.results[i][j];
					alts.push({ text: alt.transcript,
						confidence: (typeof alt.confidence === 'number' ? alt.confidence : -1) });
				}
				window.godotSpeechBridge(e.results[i].isFinal ? 'final' : 'interim', JSON.stringify(alts));
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
var _context_phrases := PackedStringArray()


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


func set_context(phrases: PackedStringArray) -> void:
	_context_phrases = phrases.duplicate()


func biasing_status() -> Dictionary:
	if not _ready_to_listen or _bridge == null:
		return {"available": false, "applied": false}
	return {
		"available": bool(_bridge.eval("!!window.__godotSpeech.biasingAvailable", true)),
		"applied": bool(_bridge.eval("!!window.__godotSpeech.biasingApplied", true)),
	}


func start() -> void:
	_ensure_bridge()
	if not _ready_to_listen:
		failed.emit("unsupported")
		return
	_bridge.eval("window.__godotSpeech.start(%s, %s);" % [
		JSON.stringify(LANGUAGE), JSON.stringify(Array(_context_phrases))], true)


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
		"interim", "final":
			var decoded := _decode(payload)
			transcript.emit(decoded["alternatives"], decoded["confidences"], kind == "final")


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
