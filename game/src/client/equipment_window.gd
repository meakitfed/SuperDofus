## Equipment (opens with the inventory, I), roadmap P1.06: the character in the
## middle (animated, its look), the equipment slots around it with the Dofus
## slot pictograms, the six Dofus / trophy slots below, the worn sets and
## their current bonus. Items are dragged from the inventory onto a slot (or
## double-clicked there), dragged back to the bag or double-clicked to take
## them off. The game checks every rule (equip / unequip).
class_name EquipmentWindow
extends UiWindow

const PICTOS := "UI/darkStone/texture/slot/tx_slot_%s"
## slot -> pictogram
const PICTO := {0: "collar", 1: "weapon", 2: "ring", 3: "belt", 4: "ring", 5: "shoe", 6: "helmet", 7: "cape",
		8: "pet", 9: "dofus", 10: "dofus", 11: "dofus", 12: "dofus", 13: "dofus", 14: "dofus", 15: "shield"}
const PREVIEW_SCALE := 1.25
const LEFT := [6, 0, 2, 3]
const RIGHT := [7, 4, 5, 8]

var backend: GameBackend
var _slots := {} # slot -> ItemSlot
var _stage: Node2D
var _preview: ActorView
var _look := ""
var _sets: VBoxContainer


func setup_window(p_backend: GameBackend) -> void:
	backend = p_backend
	setup("equipment", "Équipement", "UI/Figma/menuIcons/1x/equipments")
	default_anchor = Vector2(0.47, 0.35) # left of the inventory
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	body.add_child(h)
	h.add_child(_column(LEFT))
	var centre := VBoxContainer.new()
	centre.add_theme_constant_override("separation", 6)
	h.add_child(centre)
	var stage_box := Control.new()
	stage_box.custom_minimum_size = Vector2(180, 170)
	stage_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_box.clip_contents = true
	centre.add_child(stage_box)
	_stage = Node2D.new()
	_stage.position = Vector2(90, 150)
	stage_box.add_child(_stage)
	_stage.draw.connect(func() -> void:
		_stage.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.42))
		_stage.draw_circle(Vector2.ZERO, 55, Color(0, 0, 0, 0.35))
		_stage.draw_arc(Vector2.ZERO, 55, 0, TAU, 48, Color(UiStyle.GOLD, 0.4), 2.0, true))
	var hands := HBoxContainer.new()
	hands.alignment = BoxContainer.ALIGNMENT_CENTER
	hands.add_theme_constant_override("separation", 10)
	centre.add_child(hands)
	hands.add_child(_slot(Equipment.WEAPON))
	hands.add_child(_slot(Equipment.SHIELD))
	h.add_child(_column(RIGHT))
	var dofus := HBoxContainer.new()
	dofus.alignment = BoxContainer.ALIGNMENT_CENTER
	dofus.add_theme_constant_override("separation", 4)
	body.add_child(dofus)
	for s: int in Equipment.DOFUS:
		dofus.add_child(_slot(s))
	_sets = VBoxContainer.new()
	_sets.add_theme_constant_override("separation", 2)
	body.add_child(_sets)


func _column(slots: Array) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	for s: int in slots:
		v.add_child(_slot(s))
	return v


func _slot(s: int) -> ItemSlot:
	var slot := ItemSlot.new(0, 0, PICTOS % PICTO[s])
	slot.drop_slot = s
	slot.tooltip_text = Equipment.SLOT_NAMES[s]
	slot.dropped.connect(func(uid: int, to: int) -> void: backend.send(Protocol.equip(uid, to)))
	slot.activated.connect(func(_it: ItemSlot) -> void: backend.send(Protocol.unequip(s)))
	_slots[s] = slot
	return slot


## The worn items (item dicts with pos >= 0) and the character's look.
func refresh(items: Dictionary, look: String) -> void:
	var worn := {}
	for it: Dictionary in items.values():
		if int(it.get("pos", -1)) >= 0:
			worn[int(it["pos"])] = it
	for s: int in _slots:
		var slot: ItemSlot = _slots[s]
		if worn.has(s):
			slot.set_instance(worn[s])
		else:
			slot.instance = {}
			slot.set_item(0)
			slot.tooltip_text = Equipment.SLOT_NAMES[s]
	UiTooltips.worn_items = worn.values().map(func(it: Dictionary) -> int: return int(it["id"]))
	_fill_sets(UiTooltips.worn_items)
	if look != _look and look != "":
		_look = look
		if _preview != null:
			_preview.queue_free()
		_preview = ActorView.new()
		_stage.add_child(_preview)
		_preview.setup(look, 0, 1)
		_preview.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)


func _fill_sets(ids: Array) -> void:
	for c: Node in _sets.get_children():
		c.queue_free()
	var counts := Equipment.set_counts(ids)
	for sid: int in counts:
		var st := GameData.item_set(sid)
		var n := int(counts[sid])
		_sets.add_child(UiStyle.label("%s (%d / %d)" % [DofusI18n.text(int(st.get("name_id", 0)), "Panoplie"), n,
				(st.get("items", []) as Array).size()], UiStyle.GOLD, 13))
		var lines := PackedStringArray()
		for e: Array in Equipment.set_bonus(sid, n):
			lines.append(UiTooltips.item_effect_text(e))
		if not lines.is_empty():
			var l := UiStyle.label(" · ".join(lines), UiStyle.GOOD, 12)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(300, 0)
			_sets.add_child(l)
