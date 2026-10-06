## Texts of the fight screen (split from FightView, R.01): stat names, buff and trigger
## descriptions shown in floating texts, tooltips and the timeline.
class_name FightTexts
extends RefCounted

const STAT_NAMES := {"strength": "Force", "intelligence": "Intelligence", "chance": "Chance",
		"agility": "Agilité", "wisdom": "Sagesse", "vitality": "Vitalité", "power": "Puissance",
		"damage": "Dommages", "heals": "Soins", "range": "PO", "crit": "% Critique", "mp_dodge": "Esquive PM",
		"push_res": "Rés. Poussée", "res_earth": "% Rés. Terre", "res_fire": "% Rés. Feu",
		"res_water": "% Rés. Eau", "res_air": "% Rés. Air", "res_neutral": "% Rés. Neutre",
		"final_damage": "% Dommages finaux", "final_heals": "% Soins finaux", "combo": "% Dommages Combo",
		"tackle": "Tacle", "escape": "Fuite"}


static func buff_text(b: Dictionary) -> String:
	match str(b["kind"]):
		"stat":
			return "%+d %s" % [int(b["value"]), STAT_NAMES.get(str(b.get("stat", "")), str(b.get("stat", "")))]
		"shield":
			return "+%d bouclier" % int(b["value"])
		"state":
			var n := DofusI18n.text(int(b.get("state_name_id", 0)), "")
			return UiStyle.plain_text(n)
		"poison":
			return "Poison"
		"trigger": # P1.13b: fires on an event (Protocol buff dict `on`)
			match str(b.get("effect", "")):
				"taken":
					return "Dommages subis x%d%%" % int(b["value"])
				"healed":
					return "Soins reçus x%d%%" % int(b["value"])
			var when: Array = (b.get("on", []) as Array).map(func(c: Variant) -> String: return trigger_text(str(c)))
			return "Effet déclenché " + " ou ".join(PackedStringArray(when))
		"delay":
			return "Effet à retardement"
		"spell_reflect": # P1.13r
			return "Renvoi de sort (grade %d max)" % int(b["value"])
	return ""


## When a triggered buff fires (FightTriggers codes).
const TRIGGER_TEXTS := {"TB": "en début de tour", "TE": "en fin de tour", "D": "quand il subit des dommages",
		"DA": "aux dommages Air", "DE": "aux dommages Terre", "DF": "aux dommages Feu", "DW": "aux dommages Eau",
		"DN": "aux dommages Neutre", "DBE": "quand un ennemi le frappe", "DBA": "quand un allié le frappe",
		"DM": "quand on le frappe au corps à corps", "DR": "quand on le frappe à distance",
		"H": "quand il est soigné", "X": "à sa mort",
		# P1.13f / P1.13e
		"PT": "quand il traverse un portail", "CPT": "quand une entité traverse un portail",
		"CCMPARR": "pour chaque PM utilisé",
		# P1.13i
		"DS": "quand un sort le frappe", "DT": "quand un piège le frappe", "DG": "quand un glyphe le frappe",
		"PD": "quand il subit des dommages de poussée", "CD": "quand il inflige des dommages",
		"CDA": "quand il inflige des dommages Air", "CDE": "quand il inflige des dommages Terre",
		"CDF": "quand il inflige des dommages Feu", "CDW": "quand il inflige des dommages Eau",
		"CDN": "quand il inflige des dommages Neutre", "CDBA": "quand il frappe un allié",
		"CDBE": "quand il frappe un ennemi", "CDM": "quand il frappe au corps à corps",
		"CDR": "quand il frappe à distance", "CDS": "quand il frappe avec un sort",
		"CDT": "quand il frappe avec un piège", "CDG": "quand il frappe avec un glyphe",
		"CH": "quand il soigne", "CS": "quand il donne un bouclier", "CC": "sur un coup critique",
		"K": "quand il achève un combattant", "KWS": "quand il achève un combattant avec un sort",
		"M": "quand il est déplacé", "P": "quand il est poussé", "MA": "quand il est attiré",
		"APA": "quand ses PA changent", "MPA": "quand ses PM changent", "R": "quand il perd de la portée",
		"LPU": "quand sa vitalité augmente", "ION": "quand il devient invisible", "IOFF": "quand il redevient visible",
		# P1.13m
		"MS": "quand il échange de position", "PO": "quand il déplace un combattant",
		"CAPA": "quand il vole des PA", "CMPA": "quand il vole des PM", "DIS": "quand il est désenvoûté",
		"DCAC": "quand une arme le frappe", "CDCAC": "quand il frappe avec une arme",
		"KWW": "quand il achève un combattant avec une arme",
		"DCCBA": "quand un allié le frappe d'un coup critique", "DCCBE": "quand un ennemi le frappe d'un coup critique",
		"CDCCBA": "quand il frappe un allié d'un coup critique", "CDCCBE": "quand il frappe un ennemi d'un coup critique",
		"CION": "quand il rend un combattant invisible", "CIOFF": "quand il rend un combattant visible",
		"V": "quand ses PV changent", "VA": "quand ses PV changent", "VM": "quand ses PV max changent",
		"VE": "quand il subit de l'érosion", "PPD": "quand il subit des dommages de poussée"}


## The text of trigger code `c` (EON<n> / EOFF<n>: a state, EK:<mask>: a death).
static func trigger_text(c: String) -> String:
	if TRIGGER_TEXTS.has(c):
		return TRIGGER_TEXTS[c]
	if c.begins_with("EK:"):
		return "quand un combattant meurt"
	if c.begins_with("EON"):
		return "quand il entre dans un état"
	if c.begins_with("EOFF"):
		return "quand il sort d'un état"
	return c
