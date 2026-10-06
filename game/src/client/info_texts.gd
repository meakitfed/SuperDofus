## What the player reads for each Protocol info message: the Dofus 3 texts
## (i18n keys of the client, "{0}" = the first value), French fallback.
class_name InfoTexts
extends RefCounted

const KEYS := {
	Protocol.I_ENERGY_LOST: [5231, "Vous avez perdu {0} points d'énergie."],
	Protocol.I_ENERGY_REGAINED: [4704, "Vous avez récupéré {0} points d'énergie."],
	Protocol.I_ENERGY_LOW: [4840, "Votre énergie est dangereusement basse ! {0} point(s)"],
	# notification 14 "Transformation en fantôme"
	Protocol.I_GHOST: [568687, "Vous pouvez ressusciter votre personnage en déplaçant son fantôme jusqu'à un Phénix de résurrection (affiché sur la carte)."],
	Protocol.I_RESURRECTED: [5384, "Vous venez de ressusciter, mais votre énergie est encore faible."],
}


static func text(ev: Dictionary) -> String:
	var k: Array = KEYS.get(str(ev.get("code", "")), [0, str(ev.get("code", ""))])
	var s := UiStyle.plain_text(DofusI18n.text(int(k[0]), str(k[1])))
	var args: Array = ev.get("args", [])
	for i in args.size():
		s = s.replace("{%d}" % i, UiStyle.thousands(int(args[i])))
	return s
