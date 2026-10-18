## The search box shared by the windows with a list (shop, bank, zaap, recipes, quests, contacts, bag):
## one look (clear button, placeholder), one matching rule (case and accents ignored).
##   var box := UiSearch.field("Rechercher", func(_t): _fill())
##   if UiSearch.matches(name, box.text): …
class_name UiSearch
extends RefCounted

const FROM := "àâäáãçéèêëíìîïñóòôöõúùûüýÿ"
const TO := "aaaaaceeeeiiiinooooouuuuyy"


## Lower case without accents: "epee" finds "Épée".
static func fold(text: String) -> String:
	var out := text.to_lower()
	for i in FROM.length():
		out = out.replace(FROM[i], TO[i])
	return out.replace("œ", "oe").replace("æ", "ae")


## True when `text` contains the query (an empty query matches everything).
static func matches(text: String, query: String) -> bool:
	var q := fold(query.strip_edges())
	return q == "" or fold(text).contains(q)


static func field(placeholder: String, on_change: Callable, min_width := 150) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.clear_button_enabled = true
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.custom_minimum_size = Vector2(min_width, 0)
	e.text_changed.connect(func(_t: String) -> void: on_change.call())
	return e
