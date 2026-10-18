## A modal question (delete a character, destroy an item…): dims the screen,
## a small window with the text and two buttons. Escape / × = no.
##   UiConfirm.ask(self, "Supprimer", "Supprimer Bob ?", "Supprimer", func(): …)
class_name UiConfirm
extends Control

var window: UiWindow


static func ask(parent: Node, title: String, text: String, yes_label: String, on_yes: Callable, danger := true) -> UiConfirm:
	var c := UiConfirm.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP # modal: nothing behind reacts
	var dim := ColorRect.new()
	dim.color = UiStyle.SCRIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(dim)
	c.window = UiWindow.new()
	c.window.setup("", title)
	c.window.custom_minimum_size = Vector2(360, 0)
	c.add_child(c.window)
	var msg := UiStyle.label(text)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size = Vector2(330, 0)
	c.window.body.add_child(msg)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	c.window.body.add_child(row)
	var no := Button.new()
	no.text = "Annuler"
	no.pressed.connect(c.window.close_window)
	row.add_child(no)
	var yes := Button.new()
	yes.text = yes_label
	yes.theme_type_variation = UiStyle.V_DANGER if danger else UiStyle.V_PRIMARY
	yes.pressed.connect(func() -> void:
		c.queue_free()
		on_yes.call())
	row.add_child(yes)
	c.window.closed.connect(c.queue_free)
	parent.add_child(c)
	c.window.open()
	# the safe answer has the keyboard focus (Enter validates a harmless question, never a destructive one)
	(no if danger else yes).grab_focus.call_deferred()
	return c
