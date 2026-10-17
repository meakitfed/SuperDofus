## Writes docs/SPELL_AUDIT.md: for each class, what the spell tests do not reach (effects no fighter of the
## arena could be touched by, effect kinds no multi-turn case plays, declared gaps):
##   godot --headless --path game -s res://tools/spell_audit.gd
extends SceneTree

const OUT := "res://../docs/SPELL_AUDIT.md"


func _init() -> void:
	SpellBook.use_file("")
	var lines: PackedStringArray = [
		"# Audit des tests de sorts",
		"",
		"Genere par `tools/spell_audit.gd` (`godot --headless --path game -s res://tools/spell_audit.gd`) : ne pas editer a la main.",
		"Un grade est couvert par les contrats (`test_spell_contracts`), son golden (`test_spell_golden`) ou un ecart declare",
		"(`SpellGaps`) ; `test_spell_coverage` echoue sinon. Les colonnes ci-dessous disent ce que ces tests n'atteignent pas :",
		"- *effets non atteints* : effets dont aucune cible de l'arene n'est touchee (conditions que l'arene ne reunit pas) ;",
		"- *types sans cas* : types d'effet de la classe qu'aucun cas multi-tours (`spell_cases.gd`) ne joue.",
		"",
		"| Classe | Sorts | Grades | Ecarts | Cas | Effets non atteints | Types sans cas |",
		"|---|---|---|---|---|---|---|",
	]
	var details: PackedStringArray = []
	for breed: int in SpellGolden.breeds():
		var r := SpellCoverage.class_report(breed)
		var untested: PackedStringArray = r["untested"]
		var cases: Array = r["cases"]
		var uncased: Array = r["uncased"]
		lines.append("| %d | %d | %d | %d | %d | %d | %d |" % [breed, r["spells"], r["grades"], r["gaps"],
				cases.size(), untested.size(), uncased.size()])
		details.append("## Classe %d" % breed)
		details.append("")
		details.append("Cas : %s" % (", ".join(cases.map(func(c: Dictionary) -> String: return str(c["name"]))) if not cases.is_empty() else "aucun"))
		details.append("")
		details.append("Types sans cas : %s" % (", ".join(uncased) if not uncased.is_empty() else "aucun"))
		details.append("")
		if not untested.is_empty():
			details.append("Effets non atteints (%d%s) :" % [untested.size(), ", 40 premiers" if untested.size() > 40 else ""])
			for u: String in untested.slice(0, 40):
				details.append("- " + u)
			details.append("")
	lines.append("")
	lines.append_array(details)
	var path := ProjectSettings.globalize_path(OUT).simplify_path()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write " + path)
		quit(1)
		return
	f.store_string("\n".join(lines) + "\n")
	print("wrote ", path)
	quit(0)
