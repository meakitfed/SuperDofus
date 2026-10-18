## Applies HudToggles to the HUD (lot U.14) and reads its shortcuts: `toggle_ui` hides the whole
## interface (in a fight only the end-turn and quit buttons stay, FightHud.compact), `toggle_chat`,
## `toggle_minimap` and `toggle_tracker` fold one block each. Works in exploration and in a fight.
class_name HudVisibility
extends RefCounted

const TOGGLES := {"toggle_chat": "chat", "toggle_minimap": "minimap", "toggle_tracker": "tracker"}


## True when the event was one of the toggles (the toast says what happened).
static func handle(event: InputEvent, toast: Toast) -> bool:
	if Shortcuts.pressed(event, "toggle_ui"):
		HudToggles.toggle_all()
		if HudToggles.hidden_all:
			toast.show_text(HudToggles.hint())
		return true
	for action: String in TOGGLES:
		if Shortcuts.pressed(event, action):
			HudToggles.toggle(TOGGLES[action])
			return true
	return false


## Every frame, after the session decided what shows: hides what the player hid.
static func apply(hud: PlayerHud, fight: FightView, chat: ChatPanel, minimap_box: Control, info: Control) -> void:
	hud.set_ui_hidden(HudToggles.hidden_all)
	var tracker_hidden := HudToggles.is_hidden("tracker")
	if hud.tracker.user_hidden != tracker_hidden:
		hud.tracker.user_hidden = tracker_hidden
	if fight != null and fight.hud != null:
		fight.hud.compact = HudToggles.hidden_all
	info.visible = not HudToggles.hidden_all
	chat.visible = chat.visible and (not HudToggles.is_hidden("chat") or chat.typing())
	minimap_box.visible = minimap_box.visible and not HudToggles.is_hidden("minimap")
