extends Node
## Keeps the student's own voice so the transformation can play it back.
##
## The recogniser only ever hands back text, so the take a student just gave is gone the
## moment it is understood. This captures the audio alongside it and hands it back at the
## end of the round.
##
## It records in the BROWSER, through MediaRecorder, and never through Godot's own audio
## input. That is the whole design, and it is not a stylistic choice: switching the
## engine's audio input on makes Godot ask for the microphone while it is still bringing
## its audio driver up, and when that request is pending or refused the output context
## never starts. The result is a game with no sound at all - no effects, no speech, no
## playback - while the recogniser carries on working perfectly, because Web Speech does
## not use Godot's audio either. That shipped once. Nothing here touches AudioServer, so
## it cannot happen again: if the capture fails, the only thing that fails is the capture.
##
## The pattern is lifted from the esl-family project's recorder.js, which has been doing
## this next to a live SpeechRecognition session for a while: one stream opened on the
## first tap and kept open, one MediaRecorder segment per answer, playback from an object
## URL. Sharing the microphone with the recogniser is fine - they are separate consumers.
##
## It is deliberately incapable of breaking a lesson. Everything is guarded, `clip_length`
## returns 0.0 when there is nothing, and the caller falls back to the lab speaking the
## sentence - which is what a typed classroom gets anyway, and has to look deliberate.
##
## Clips live only for the round, in the browser, and are never written to disk or put in
## CreatureState: a save file is a record of what a child said, and a recording of a
## child's voice is a different kind of thing to keep.

const BRIDGE := "window.__creatureVoice"
## In SAY_SPLIT the student says each sentence in two takes - "It was small." now, "Now it
## is big." in a later pass over all three - so the halves are recorded minutes apart and
## have to be filed separately. Present clauses live above this offset, past ones below.
const PRESENT_SLOT := 100

var _supported := false
var _armed := false
var _capture_session_id := -1
## Every slot filed this round, recorded whether or not a browser is present.
##
## The recorder itself only exists in the web build, so nothing about it can be observed by
## running the game on a desktop - which makes "is the present half being filed at all?" a
## question no local test could answer. This list is the part that CAN be checked anywhere:
## it says what the game asked the recorder to do, even when there is no recorder listening.
var kept_slots: Array[int] = []


func _ready() -> void:
	if not OS.has_feature("web") or not JavaScriptBridge.eval("1", true):
		return ## Desktop and the editor: the lab speaks the sentences.
	_install()
	_supported = bool(JavaScriptBridge.eval("%s.supported()" % BRIDGE, true))
	if _supported:
		Speech.session_capture_started.connect(_on_capture_started)
		Speech.session_capture_finished.connect(_on_capture_finished)


## Defined once on the page. Kept as one object on window so repeated evals are cheap and
## so nothing here depends on Godot holding JavaScript references alive.
func _install() -> void:
	JavaScriptBridge.eval("""
	if (!window.__creatureVoice) window.__creatureVoice = (function () {
	  var stream = null, rec = null, captureSerial = 0;
	  var pending = null, pendingSlot = -1, lastLen = 0;
	  var clips = {}, urls = {}, lens = {}, playing = null;
	  var PREFERRED = ['audio/webm;codecs=opus', 'audio/webm', 'audio/ogg;codecs=opus', 'audio/mp4'];
	  function pickMime() {
	    if (window.MediaRecorder && MediaRecorder.isTypeSupported) {
	      for (var i = 0; i < PREFERRED.length; i++) {
	        if (MediaRecorder.isTypeSupported(PREFERRED[i])) return PREFERRED[i];
	      }
	    }
	    return '';
	  }
	  function assign(slot, blob, len) {
	    if (urls[slot]) URL.revokeObjectURL(urls[slot]);
	    clips[slot] = blob; urls[slot] = URL.createObjectURL(blob); lens[slot] = len;
	  }
	  function begin() {
	    var segmentChunks = [], segmentMime = pickMime(), segment = null;
	    try { segment = new MediaRecorder(stream, segmentMime ? { mimeType: segmentMime } : {}); } catch (e) { return; }
	    rec = segment;
	    var segmentT0 = Date.now();
	    segment.ondataavailable = function (e) { if (e.data && e.data.size > 0) segmentChunks.push(e.data); };
	    segment.onstop = function () {
	      if (segment.__discard) { pending = null; pendingSlot = -1; return; }
	      pending = new Blob(segmentChunks, { type: segmentMime || 'audio/webm' });
	      lastLen = (Date.now() - segmentT0) / 1000;
	      // The slot is only known once the sentence is accepted, which can land either
	      // side of this event, so whichever arrives second does the filing.
	      if (pendingSlot >= 0) { assign(pendingSlot, pending, lastLen); pending = null; pendingSlot = -1; }
	    };
	    try { segment.start(); } catch (e) {}
	  }
	  return {
	    supported: function () {
	      return !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia && window.MediaRecorder);
	    },
	    start: function () {
	      var serial = ++captureSerial;
	      pending = null; pendingSlot = -1;
	      if (stream) { begin(); return; }
	      // Opened on the tap that starts listening, which is a real user gesture - the
	      // only moment a browser will grant this without a fight.
	      navigator.mediaDevices.getUserMedia({ audio: true, video: false })
	        .then(function (s) { stream = s; if (serial === captureSerial) begin(); }).catch(function () {});
	    },
	    stop: function () {
	      captureSerial++;
	      if (rec && rec.state !== 'inactive') { try { rec.stop(); } catch (e) {} }
	    },
	    discard: function () {
	      pending = null; pendingSlot = -1;
	      if (rec) rec.__discard = true;
	    },
	    keep: function (slot) {
	      // Which branch this takes is the answer to "was the present half captured?":
	      // "now" means a finished take was waiting, "on stop" means the sentence was
	      // accepted while still recording, and either is fine. Nothing logged at all
	      // means keep() was never reached for that slot.
	      console.log('[creature-voice] keep slot=' + slot
	        + (pending ? ' filing now' : ' filing on stop'));
	      if (pending) { assign(slot, pending, lastLen); pending = null; pendingSlot = -1; }
	      else { pendingSlot = slot; }
	    },
	    len: function (slot) { return lens[slot] || 0; },
	    play: function (slot) {
	      if (!urls[slot]) return 0;
	      try {
	        if (playing) { playing.pause(); }
	        playing = new Audio(urls[slot]);
	        playing.play().catch(function () {});
	      } catch (e) { return 0; }
	      return lens[slot] || 0;
	    },
	    playPair: function (a, b) {
	      var first = lens[a] || 0, second = lens[b] || 0;
	      console.log('[creature-voice] playPair past=' + a + '(' + first.toFixed(2) + 's)'
	        + ' present=' + b + '(' + second.toFixed(2) + 's)');
	      if (!first && !second) return 0;
	      var self = this;
	      if (!first) { self.play(b); return second; }
	      self.play(a);
	      if (second) {
	        // Chained on the element rather than on a timer: a timer drifts against
	        // whatever the browser actually decoded, and the halves would overlap.
	        if (playing) {
	          playing.onended = function () { self.play(b); };
	        }
	        return first + second + 0.25;
	      }
	      return first;
	    },
	    // Written to the browser console so a silent transformation can be diagnosed from a
	    // classroom laptop. The capture fails quietly by design - it must never interrupt a
	    // lesson - which also means it needs somewhere to say that it failed.
	    report: function (note) {
	      var made = [];
	      for (var k in lens) { made.push(k + ':' + lens[k].toFixed(2) + 's'); }
	      console.log('[creature-voice] ' + note
	        + ' supported=' + this.supported()
	        + ' stream=' + (stream ? 'open' : 'none')
	        + ' clips={' + made.join(' ') + '}');
	    },
	    halt: function () { if (playing) { try { playing.pause(); playing.onended = null; } catch (e) {} playing = null; } },
	    clear: function () {
	      this.halt();
	      for (var k in urls) { URL.revokeObjectURL(urls[k]); }
	      clips = {}; urls = {}; lens = {}; pending = null; pendingSlot = -1;
	    }
	  };
	})();
	""", true)


func available() -> bool:
	return _supported


# --- Capture -----------------------------------------------------------------

func _on_capture_started(session_id: int) -> void:
	_capture_session_id = session_id
	_armed = true
	JavaScriptBridge.eval("%s.start()" % BRIDGE, true)
	# Capture begins on the tap, not on recognition's later onstart. The two browser APIs
	# remain independent, but the kept take still includes the child's first word.
	report("armed session=%d" % session_id)


func _on_capture_finished(session_id: int, tail_seconds: float, discard: bool) -> void:
	if not _armed or session_id != _capture_session_id:
		return
	if discard:
		JavaScriptBridge.eval("%s.discard()" % BRIDGE, true)
	if tail_seconds > 0.0:
		await get_tree().create_timer(tail_seconds).timeout
		# A delayed tail from an accepted interim must never stop a newer recording.
		if not _armed or session_id != _capture_session_id:
			return
	_armed = false
	JavaScriptBridge.eval("%s.stop()" % BRIDGE, true)
	report("stopped session=%d" % session_id)


func discard_session(session_id: int) -> void:
	if not _supported or session_id != _capture_session_id:
		return
	JavaScriptBridge.eval("%s.discard()" % BRIDGE, true)


## Called when a sentence is accepted, so the take that is kept is the one that passed
## rather than whatever was said last.
func keep_for(slot: int) -> void:
	if slot < 0:
		return
	kept_slots.append(slot)
	if not _supported:
		return
	JavaScriptBridge.eval("%s.keep(%d)" % [BRIDGE, slot], true)
	if slot < PRESENT_SLOT:
		report("kept past half %d" % slot)


## The present half of a split sentence, filed against the entry it completes.
func keep_present_for(index: int) -> void:
	keep_for(PRESENT_SLOT + index)
	report("kept present half %d" % index)


## Prints the recorder's state to the browser console.
func report(note: String) -> void:
	# On screen as well as in the console: the recorder's own account of what it captured is
	# half the story, and the console holding it is the half nobody can reach.
	Diagnostics.note("[voice]", "%s slots=%s" % [note, kept_slots])
	if _supported:
		JavaScriptBridge.eval('%s.report("%s")' % [BRIDGE, note], true)


func has_clip(slot: int) -> bool:
	return clip_length(slot) > 0.0


## Length in seconds, or 0.0 when there is no recording for this slot - which is the
## caller's cue to have the lab speak the sentence instead.
func clip_length(slot: int) -> float:
	if not _supported or slot < 0:
		return 0.0
	return float(JavaScriptBridge.eval("%s.len(%d)" % [BRIDGE, slot], true))


## Starts the clip and reports how long it runs, so the sequence can time its surge to
## land on the student's last word rather than over it.
func play(slot: int) -> float:
	if not _supported or slot < 0:
		return 0.0
	return float(JavaScriptBridge.eval("%s.play(%d)" % [BRIDGE, slot], true))


## Both halves of one sentence, in the order they were said, as a single beat: the past
## clip, then the present clip when the split mode recorded one. Returns the whole run so
## the surge can land after the student has finished the thought, not halfway through it.
func play_sentence(index: int) -> float:
	if not _supported or index < 0:
		return 0.0
	return float(JavaScriptBridge.eval("%s.playPair(%d, %d)" % [
		BRIDGE, index, PRESENT_SLOT + index], true))


func stop() -> void:
	if _supported:
		JavaScriptBridge.eval("%s.halt()" % BRIDGE, true)


## A new creature starts with no voice, so one child's recording can never surface in the
## next child's transformation.
func clear() -> void:
	if _supported:
		JavaScriptBridge.eval("%s.clear()" % BRIDGE, true)
