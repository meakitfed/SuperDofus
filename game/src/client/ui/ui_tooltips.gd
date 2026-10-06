## Rich tooltips (Controls returned by _make_custom_tooltip): items, spells,
## monster groups, fighters. One place for how game things are described.
class_name UiTooltips
extends RefCounted

const ELEMENT_NAMES := {"neutral": "Neutre", "earth": "Terre", "fire": "Feu", "water": "Eau", "air": "Air"}
const WIDTH := 260

## item ids the player wears (EquipmentWindow keeps it): set tooltips show the current bonus
static var worn_items: Array = []


static func _box() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.custom_minimum_size = Vector2(WIDTH, 0)
	return v


static func _sep(v: VBoxContainer) -> void:
	var s := HSeparator.new()
	s.add_theme_stylebox_override("separator", UiStyle.bar_fill(UiStyle.BORDER))
	s.add_theme_constant_override("separation", 6)
	v.add_child(s)


static func _wrap(text: String, color := UiStyle.TEXT, size := 14) -> Label:
	var l := UiStyle.label(text, color, size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(WIDTH, 0)
	return l


## effects: an instance's (inventory); [] = the item's possible effects (min à max).
static func item(item_id: int, qty := 1, effects: Array = []) -> Control:
	var data := GameData.item(item_id)
	var v := _box()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	var tex := ClientTheme.texture("Picto/Items/%d" % int(data.get("icon", 0))) if data.has("icon") else null
	if tex != null:
		var icon := TextureRect.new()
		icon.texture = tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.custom_minimum_size = Vector2(40, 40)
		head.add_child(icon)
	var names := VBoxContainer.new()
	head.add_child(names)
	names.add_child(UiStyle.label(item_name(item_id), UiStyle.GOLD, 16))
	var type := GameData.row("itemtypes", int(data.get("type", 0)))
	var type_name := DofusI18n.text(int(type.get("nameId", 0)), "") if not type.is_empty() else ""
	names.add_child(UiStyle.label(("%s · " % type_name if type_name != "" else "") + "Niveau %d" % int(data.get("level", 1)), UiStyle.TEXT_MUTED, 13))
	_sep(v)
	if qty > 1:
		v.add_child(UiStyle.label("Quantité : %s" % UiStyle.thousands(qty), UiStyle.TEXT, 13))
	var lines := effects if not effects.is_empty() else (data.get("effects", []) as Array)
	for e: Array in lines:
		var text := item_effect_text(e)
		if text != "":
			var bonus := int(GameData.row("effects", int(e[0])).get("bonusType", 0))
			v.add_child(_wrap(text, UiStyle.GOOD if bonus > 0 else (UiStyle.BAD if bonus < 0 else UiStyle.TEXT), 14))
	var set_id := int(data.get("set", 0))
	if set_id > 0:
		var st := GameData.item_set(set_id)
		var n := int(Equipment.set_counts(worn_items).get(set_id, 0))
		_sep(v)
		v.add_child(UiStyle.label("%s (%d / %d)" % [DofusI18n.text(int(st.get("name_id", 0)), "Panoplie"), n,
				(st.get("items", []) as Array).size()], UiStyle.GOLD, 13))
		var shown := maxi(n, 2)
		v.add_child(UiStyle.label("Bonus %s %d objets :" % ["actuel à" if n >= 2 else "à", shown], UiStyle.TEXT_MUTED, 12))
		for e: Array in Equipment.set_bonus(set_id, shown):
			v.add_child(UiStyle.label(item_effect_text(e), UiStyle.GOOD if n >= 2 else UiStyle.TEXT_MUTED, 12))
	var desc := UiStyle.plain_text(DofusI18n.text(int(data.get("description_id", 0)), ""))
	if desc != "":
		_sep(v)
		v.add_child(_wrap(desc, UiStyle.TEXT_MUTED, 12))
	var crit := str(data.get("criteria", ""))
	if crit != "":
		v.add_child(UiStyle.label("Conditions : " + crit, UiStyle.TEXT_MUTED, 12))
	v.add_child(UiStyle.label("Poids : %d pod%s" % [int(data.get("weight", 1)), "s" if int(data.get("weight", 1)) > 1 else ""], UiStyle.TEXT_MUTED, 13))
	if bool(data.get("usable", false)):
		v.add_child(UiStyle.label("Double-clic : utiliser", UiStyle.GOLD, 12))
	elif not Equipment.positions(item_id).is_empty():
		v.add_child(UiStyle.label("Double-clic ou glisser : équiper · Niveau requis %d" % int(data.get("level", 1)), UiStyle.GOLD, 12))
	return v


## An item effect [effects.id, diceNum, diceSide, value] in words, from the
## effects.descriptionId template ("#1{{~1~2 à }}#2 Force" -> "7 à 10 Force").
static func item_effect_text(e: Array) -> String:
	var row := GameData.row("effects", int(e[0]))
	var tpl := DofusI18n.text(int(row.get("descriptionId", 0)), "")
	if tpl == "":
		return ""
	var lo := int(e[1])
	var hi := int(e[2])
	var ranged := hi > lo and lo != 0
	tpl = RegEx.create_from_string("\\{\\{~1~2([^}]*)\\}\\}").sub(tpl, "$1" if ranged else "", true)
	tpl = tpl.replace("#1", str(lo) if lo != 0 or hi == 0 else str(hi)).replace("#2", str(hi) if ranged else "").replace("#3", str(int(e[3])))
	tpl = RegEx.create_from_string("\\{\\{~p?s\\}\\}").sub(tpl, "s" if maxi(lo, hi) > 1 else "", true)
	tpl = RegEx.create_from_string("\\{\\{[^}]*\\}\\}").sub(tpl, "", true)
	return UiStyle.plain_text(tpl).strip_edges()


static func item_name(item_id: int) -> String:
	var data := GameData.item(item_id)
	return DofusI18n.text(int(data.get("name_id", 0)), str(data.get("name", "Objet %d" % item_id)))


static func spell(s: Dictionary) -> Control:
	var v := _box()
	var head := HBoxContainer.new()
	v.add_child(head)
	var name_label := UiStyle.label(DofusI18n.text(int(s.get("name_id", 0)), str(s.get("name", "?"))), UiStyle.GOLD, 16)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	head.add_child(UiStyle.label("%d PA" % int(s.get("ap", 0)), UiStyle.AP, 15))
	var r: Array = s.get("range", [1, 1])
	v.add_child(UiStyle.label("Portée %d-%d%s" % [int(r[0]), int(r[1]), " (modifiable)" if bool(s.get("range_boost", false)) else ""],
			UiStyle.TEXT_MUTED, 13))
	_sep(v)
	for e: Dictionary in s.get("effects", []):
		var line := effect_line(e)
		if line != "":
			v.add_child(_wrap(line, UiStyle.ELEMENTS.get(str(e.get("element", "")), UiStyle.TEXT), 14))
	var extra := PackedStringArray()
	if int(s.get("cooldown", 0)) > 0:
		extra.append("Relance : %d tours" % int(s["cooldown"]))
	if int(s.get("crit", 0)) > 0:
		extra.append("Critique : %d %%" % int(s["crit"]))
	if not extra.is_empty():
		_sep(v)
		v.add_child(UiStyle.label(" · ".join(extra), UiStyle.TEXT_MUTED, 13))
	return v


## One effect of a spell, in words ("" when not shown).
static func effect_line(e: Dictionary) -> String:
	var lo := int(e.get("min", 0))
	var hi := int(e.get("max", 0))
	var dice := str(lo) if lo == hi else "%d à %d" % [lo, hi]
	var elem: String = ELEMENT_NAMES.get(str(e.get("element", "")), "")
	var sign := "+" if int(e.get("sign", 1)) > 0 else "-"
	# conditional variants (Pandawa sober / drunk...): state names are not in the client data
	var cond := ""
	for c: Dictionary in e.get("cond", []):
		if c.has("portal"): # targetMask R / r (P1.13f)
			cond = " (si projeté)" if bool(c["portal"]) else " (sans portail)"
		elif bool(c.get("has", false)):
			cond = " (selon l'état)"
	var kind := str(e.get("kind", ""))
	var out := ""
	if kind == "damage":
		out = dice + " dommages " + elem
		if int(e.get("duration", 0)) > 0:
			out += " pendant %d tours" % int(e["duration"])
	elif kind == "steal":
		out = dice + " vol de vie " + elem
	elif kind == "heal":
		out = dice + " soins"
	elif kind == "push":
		out = "Repousse de " + dice + " cases"
	elif kind == "pull":
		out = "Attire de " + dice + " cases"
	elif kind == "ap" or kind == "mp":
		out = sign + dice + (" PA" if kind == "ap" else " PM")
	elif kind == "stat":
		out = sign + dice + " " + str(FightTexts.STAT_NAMES.get(str(e.get("stat", "")), str(e.get("stat", ""))))
	elif kind == "steal_stat":
		out = "Vole " + dice + " " + str(FightTexts.STAT_NAMES.get(str(e.get("stat", "")), str(e.get("stat", ""))))
	elif kind == "shield":
		out = "Bouclier"
	elif kind == "rune":
		out = "Pose une rune"
	elif kind == "runes":
		out = "Déclenche les runes"
	elif kind == "detonate":
		out = "Déclenche une bombe"
	elif kind == "portal":
		out = "Pose un portail (+%d %% dommages par case entre 2 portails)" % int(e.get("per_cell", 0))
	elif kind == "glyph_now":
		out = "Pose un glyphe"
	elif kind == "heal_attackers":
		out = "Soigne l'attaquant de %d %% des dommages" % int(e.get("pct", 0))
	elif kind == "reflect":
		out = "Renvoie %d dommages à l'attaquant" % int(e.get("min", 0))
	elif kind == "intercept":
		out = "Intercepte les dommages"
	elif kind == "share":
		out = "Partage les dommages"
	elif kind == "teleportal":
		out = "Traverse les portails"
	elif kind == "unportal":
		out = "Désactive tous les portails" if bool(e.get("all", false)) else "Désactive un portail"
	return out + cond if out != "" else ""


## Monster group on the map: members (name, level), total level, its stars
## (`bonus` %, one star = 20 %) and the XP the player would win alone
## (`xp`, FightXp.estimate; -1 = unknown).
static func monster_group(members: Array, bonus := 0, xp := -1) -> Control:
	var v := _box()
	var total := 0
	for m: Dictionary in members:
		total += int(m.get("level", 0))
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UiStyle.label("Groupe de monstres", UiStyle.GOLD, 16)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UiStyle.label("Niv. %d" % total, UiStyle.TEXT, 15))
	if bonus != 0:
		var stars := HBoxContainer.new()
		stars.add_theme_constant_override("separation", 1)
		var full := clampi(absi(bonus) / 20, 0, 5)
		for i in 5:
			stars.add_child(UiStyle.icon(UiStyle.STAR_FULL if i < full else UiStyle.STAR_EMPTY, 16,
					Color.WHITE if bonus > 0 else UiStyle.BAD))
		var pct := UiStyle.label("  %+d %% XP et butin" % bonus, UiStyle.GOOD if bonus > 0 else UiStyle.BAD, 13)
		stars.add_child(pct)
		v.add_child(stars)
	_sep(v)
	for m: Dictionary in members:
		var row := HBoxContainer.new()
		var n := UiStyle.label(DofusI18n.text(int(m.get("name_id", 0)), str(m.get("name", "?"))), UiStyle.TEXT, 14)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(n)
		row.add_child(UiStyle.label("niv. %d" % int(m.get("level", 0)), UiStyle.TEXT_MUTED, 13))
		v.add_child(row)
	if xp >= 0:
		_sep(v)
		var r := HBoxContainer.new()
		var l := UiStyle.label("XP estimée", UiStyle.TEXT_MUTED, 13)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(l)
		r.add_child(UiStyle.label(UiStyle.thousands(xp), UiStyle.XP, 14))
		v.add_child(r)
	return v


## Plain lines (first one as a title).
static func lines(texts: Array) -> Control:
	var v := _box()
	for i in texts.size():
		v.add_child(_wrap(str(texts[i]), UiStyle.GOLD if i == 0 else UiStyle.TEXT, 15 if i == 0 else 13))
	return v
