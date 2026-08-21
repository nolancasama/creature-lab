class_name NameGenerator
extends RefCounted
## Fantasy names built from the traits the student actually spoke, so the name is a
## record of the sentences rather than decoration. Deterministic: the same creature
## always offers the same list of names in the same order.

const CANDIDATES := 5

const PREFIXES := {
	"big": ["巨人", "大地", "山"],
	"small": ["こびと", "豆つぶ", "しずく"],
	"tall": ["天空", "塔", "雲"],
	"short": ["ちび", "どんぐり", "こつぶ"],
	"long": ["リボン", "大蛇", "らせん"],
	"hot": ["炎", "火の粉", "灼熱"],
	"cold": ["霜", "氷河", "氷"],
	"old": ["古代", "長老", "伝説"],
	"new": ["オーロラ", "新星", "夜明け"],
	"young": ["若葉", "ひよこ", "春"],
	"hard": ["水晶", "鋼鉄", "ダイヤ"],
	"soft": ["雲", "ビロード", "綿毛"],
	"strong": ["怪力", "岩", "嵐"],
	"weak": ["ささやき", "羽根", "霧"],
	"fast": ["疾風", "流星", "稲妻"],
	"slow": ["苔", "そよ風", "まどろみ"],
	"red": ["ルビー", "紅", "サンゴ"],
	"blue": ["青空", "サファイア", "海"],
	"green": ["ひすい", "若草", "エメラルド"],
	"yellow": ["太陽", "こはく", "はちみつ"],
	"black": ["影", "真夜中", "オニキス"],
	"white": ["雪", "真珠", "象牙"],
	"brown": ["どんぐり", "ココア", "木立"],
	"pink": ["桜", "バラ", "花びら"],
	"purple": ["すみれ", "アメジスト", "たそがれ"],
	"orange": ["夕焼け", "トラ", "マーマレード"],
}


static func candidates(state: CreatureState) -> PackedStringArray:
	var def := Content.animal(state.animal_id)
	var noun := def.fantasy_noun if def != null else "クリーチャー"

	# Ordered by the sentences the student spoke, so the first name offered leads with
	# the first thing they said.
	var words := PackedStringArray()
	for entry in state.entries:
		words.append(str(entry["after"]))
	if words.is_empty():
		return PackedStringArray([noun])

	var out := PackedStringArray()
	for i in CANDIDATES * 2:
		var lead := str(words[i % words.size()])
		var tier: int = int(i / words.size())
		var candidate := "%sの%s" % [_prefix(lead, tier), noun]
		# Later candidates stack a second trait for variety.
		if tier >= 2 and words.size() > 1:
			var second := str(words[(i + 1) % words.size()])
			candidate = "%sと%sの%s" % [_prefix(lead, tier), _prefix(second, 0), noun]
		if not out.has(candidate):
			out.append(candidate)
		if out.size() >= CANDIDATES:
			break
	return out


static func _prefix(word: String, tier: int) -> String:
	var pool: Array = PREFIXES.get(word, [])
	if pool.is_empty():
		return word
	return str(pool[tier % pool.size()])
