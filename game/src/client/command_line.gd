## The command line (Entrée): "/tp 5 -18" -> admin_cmd{cmd: "tp", args: ["5", "-18"]}.
## Only splits the text: the sim checks the role and the arguments (roadmap S.06).
## Up / Down walk the history, Escape closes it.
class_name CommandLine
extends PanelContainer

const HELP := "/tp <map id> [cellule]  ·  /help : toutes les commandes GM"

var backend: GameBackend
var _edit: LineEdit
var _history: PackedStringArray = []
var _at := 0


func _ready() -> void:
	visible = false
	add_theme_stylebox_override("panel", UiStyle.panel(Color(UiStyle.BG, 0.9), UiStyle.BORDER_LIGHT, 6, 6))
	_edit = LineEdit.new()
	_edit.custom_minimum_size = Vector2(460, 34)
	_edit.placeholder_text = HELP
	_edit.add_theme_font_size_override("font_size", 16)
	_edit.text_submitted.connect(_submit)
	_edit.gui_input.connect(_on_key)
	add_child(_edit)


func open() -> void:
	visible = true
	_at = _history.size()
	_edit.clear()
	_edit.grab_focus()


func close() -> void:
	visible = false
	_edit.release_focus()


func _submit(text: String) -> void:
	close()
	var cmd := CommandLine.parse(text)
	if cmd.is_empty():
		return
	_history.append(text.strip_edges())
	backend.send(cmd)


## "/tp 5,-18" -> admin_cmd("tp", ["5", "-18"]); {} for an empty line.
static func parse(text: String) -> Dictionary:
	var line := text.strip_edges().trim_prefix("/")
	if line.to_lower().begins_with("tp "): # "/tp 5,-18"; elsewhere a comma is text (/say bonjour, tous)
		line = line.replace(",", " ")
	var words := line.split(" ", false)
	if words.is_empty():
		return {}
	return Protocol.admin_cmd(words[0].to_lower(), Array(words.slice(1)))


func _on_key(event: InputEvent) -> void:
	if Shortcuts.pressed(event, "close"):
		close()
	elif event is InputEventKey and event.pressed and (event.keycode == KEY_UP or event.keycode == KEY_DOWN):
		if _history.is_empty():
			return
		_at = clampi(_at + (-1 if event.keycode == KEY_UP else 1), 0, _history.size())
		_edit.text = _history[_at] if _at < _history.size() else ""
		_edit.caret_column = _edit.text.length()
	else:
		return
	_edit.accept_event()
