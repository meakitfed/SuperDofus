## End of fight window (like Dofus): result, duration, then every fighter by
## team, winners first: portrait, name, level and, for players, the XP gained
## (bar towards the next level, level up), kamas and dropped items.
class_name FightResultWindow
extends UiWindow

const TITLES := {"win": ["Victoire", UiStyle.GOLD], "lose": ["Défaite", UiStyle.BAD],
		"abandon": ["Combat abandonné", UiStyle.TEXT_MUTED]}


## `fighters`: fighter dicts as last known by the FightView, `names`: id -> display name.
func setup_result(ev: Dictionary, fighters: Dictionary, names: Dictionary, you: int) -> void:
	var result := str(ev.get("result", ""))
	var t: Array = TITLES.get(result, [result, UiStyle.TEXT])
	setup("fight_result", "Fin du combat", "UI/darkStone/texture/btnIcon/btnIcon_sword")
	var title := UiStyle.label(t[0], t[1], 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	var secs := int(ev.get("duration", 0)) / 1000
	var dur := UiStyle.label("Durée du combat : %d:%02d" % [secs / 60, secs % 60], UiStyle.TEXT_MUTED)
	dur.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(dur)
	var rewards := {}
	for r: Dictionary in ev.get("rewards", []):
		rewards[int(r["id"])] = r
	var my_team := int(fighters.get(you, {}).get("team", 0))
	var winners := my_team if result == "win" else 1 - my_team
	for team: int in [winners, 1 - winners]:
		body.add_child(UiStyle.label("Gagnants" if team == winners else "Perdants", UiStyle.GOLD))
		for id: int in fighters:
			var f: Dictionary = fighters[id]
			if int(f["team"]) == team:
				body.add_child(_row(f, str(names.get(id, "?")), rewards.get(id, {})))
	_challenges(ev)
	var close := Button.new()
	close.text = "Fermer"
	close.focus_mode = Control.FOCUS_NONE
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(close_window)
	body.add_child(close)
	closed.connect(queue_free)
	open()


## The challenges of the fight (FightView.challenges, passed in ev.challenges) and their bonus.
func _challenges(ev: Dictionary) -> void:
	var list: Array = ev.get("challenges", [])
	if list.is_empty():
		return
	body.add_child(UiStyle.label("Challenges", UiStyle.GOLD))
	for c: Dictionary in list:
		var won: bool = c["state"] == "success"
		var l := UiStyle.label("%s %s" % ["✔" if won else "✘", DofusI18n.text(int(c["name_id"]), "?")], UiStyle.GOOD if won else UiStyle.BAD)
		l.tooltip_text = UiStyle.plain_text(DofusI18n.text(int(c["desc_id"]), ""))
		body.add_child(l)
	var bonus := 0
	for r: Dictionary in ev.get("rewards", []):
		bonus = maxi(bonus, int(r.get("challenge_bonus", 0)))
	if bonus > 0:
		body.add_child(UiStyle.label("Bonus d'XP et de butin : +%d %%" % bonus, UiStyle.XP))


func _row(f: Dictionary, fighter_name: String, r: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var tile := TimelineTile.new()
	row.add_child(tile)
	tile.setup(f)
	tile.update(f, false)
	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(170, 0)
	row.add_child(info)
	info.add_child(UiStyle.label(fighter_name))
	info.add_child(UiStyle.label("Niveau %d" % int(r.get("level", f.get("level", 1))), UiStyle.TEXT_MUTED))
	if r.is_empty():
		return row
	# XP towards the next level
	var xp_box := VBoxContainer.new()
	xp_box.custom_minimum_size = Vector2(220, 0)
	row.add_child(xp_box)
	var bar := UiBar.new(UiStyle.XP, 14)
	var floor_xp := int(r.get("xp_floor", 0))
	bar.set_values(int(r.get("xp", 0)) - floor_xp, int(r.get("xp_next", 1)) - floor_xp)
	bar.tooltip_text = "%s / %s XP" % [UiStyle.thousands(int(r.get("xp", 0))), UiStyle.thousands(int(r.get("xp_next", 0)))]
	xp_box.add_child(bar)
	var xp := UiStyle.label("+%s XP" % UiStyle.thousands(int(r.get("xp_gained", 0))))
	if int(r.get("level_up", 0)) > 0:
		xp.text += "   Niveau supérieur !"
		xp.add_theme_color_override("font_color", UiStyle.GOLD)
	xp_box.add_child(xp)
	if int(r.get("energy_lost", 0)) > 0:
		xp_box.add_child(UiStyle.label("-%s énergie" % UiStyle.thousands(int(r["energy_lost"])), UiStyle.ENERGY, 13))
	var kamas := UiStyle.label("%s K" % UiStyle.thousands(int(r.get("kamas", 0))), UiStyle.KAMAS)
	kamas.custom_minimum_size = Vector2(70, 0)
	row.add_child(kamas)
	var items := HBoxContainer.new()
	row.add_child(items)
	for it: Dictionary in r.get("items", []):
		items.add_child(ItemSlot.new(int(it["id"]), int(it["qty"])))
	return row
