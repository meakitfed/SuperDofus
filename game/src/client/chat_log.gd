## One tab of the chat (P3.02c): a RichTextLabel that writes a chat_msg with real smiley icons
## (smileys.gfxId, Content/Picto/Smileys) and `[objet]` links that show the item tooltip when hovered.
class_name ChatLog
extends RichTextLabel

const SMILEY_SIZE := 20

## the item under the mouse (0 = none)
var hovered_item := 0


func _init() -> void:
	bbcode_enabled = true
	meta_underlined = true
	meta_hover_started.connect(_on_hover_started)
	meta_hover_ended.connect(_on_hover_ended)


## The pieces of `text`: {text} / {item: id} / {smiley: id}; only the ids the sim kept (links, smileys
## of the chat_msg) become pieces, any other `{item:..}` stays text.
static func pieces(text: String, links: Array, smileys: Array) -> Array:
	var out: Array = []
	var re := RegEx.create_from_string("\\{(item|smiley):(\\d{1,9})\\}")
	var at := 0
	for m in re.search_all(text):
		var id := int(m.get_string(2))
		var kind := m.get_string(1)
		if not (links if kind == "item" else smileys).any(func(x: Variant) -> bool: return int(x) == id):
			continue
		if m.get_start() > at:
			out.append({"text": text.substr(at, m.get_start() - at)})
		out.append({kind: id})
		at = m.get_end()
	if at < text.length():
		out.append({"text": text.substr(at)})
	return out


## The texture of a smiley (smileys.gfxId), null when the art is not extracted.
static func smiley_texture(id: int) -> Texture2D:
	var gfx := str(GameData.row("smileys", id).get("gfxId", ""))
	return ClientTheme.texture("Picto/Smileys/" + gfx) if gfx != "" else null


## Writes `head : text` in `color`, then a new line.
func write(head: String, ev: Dictionary, color: Color) -> void:
	push_color(color)
	add_text(head + " : ")
	for piece: Dictionary in pieces(str(ev["text"]), ev.get("links", []), ev.get("smileys", [])):
		if piece.has("item"):
			push_meta("item:%d" % int(piece["item"]))
			add_text("[%s]" % ChatPanel.item_name(int(piece["item"])))
			pop()
		elif piece.has("smiley"):
			var tex := smiley_texture(int(piece["smiley"]))
			if tex != null:
				add_image(tex, SMILEY_SIZE, SMILEY_SIZE)
			else:
				add_text("☺")
		else:
			add_text(str(piece["text"]))
	pop()
	newline()


func _on_hover_started(meta: Variant) -> void:
	var s := str(meta)
	if s.begins_with("item:"):
		hovered_item = int(s.substr(5))
		tooltip_text = " " # non-empty: Godot then asks _make_custom_tooltip


func _on_hover_ended(_meta: Variant) -> void:
	hovered_item = 0
	tooltip_text = ""


func _make_custom_tooltip(_for_text: String) -> Object:
	return UiTooltips.item(hovered_item) if hovered_item != 0 else null
