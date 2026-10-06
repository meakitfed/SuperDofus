## Right-click menus (player, item, monster…):
##   ContextMenu.popup(self, get_global_mouse_position(), "Joueur", [["Défier", func(): …], ["Échanger", …, false]])
## An entry is [label, callable, enabled := true].
class_name ContextMenu
extends RefCounted


static func popup(parent: Node, at: Vector2, title: String, entries: Array) -> PopupMenu:
	var menu := PopupMenu.new()
	menu.theme = ClientTheme.get_theme()
	if title != "":
		menu.add_separator(title)
	var actions: Array[Callable] = []
	for e: Array in entries:
		menu.add_item(str(e[0]), actions.size())
		menu.set_item_disabled(menu.item_count - 1, e.size() > 2 and not bool(e[2]))
		actions.append(e[1])
	menu.id_pressed.connect(func(id: int) -> void: actions[id].call())
	menu.popup_hide.connect(menu.queue_free)
	parent.add_child(menu)
	menu.popup(Rect2i(Vector2i(at), Vector2i.ZERO))
	return menu
