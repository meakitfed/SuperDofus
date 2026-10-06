## The toasts of a job_xp event (P2.05): "+10 XP Bûcheron", then the new level.
class_name JobTexts
extends RefCounted


static func xp_lines(ev: Dictionary) -> Array:
	var view: Dictionary = ev["view"]
	var job_name := DofusI18n.text(int(Jobs.job(int(view["job"])).get("nameId", 0)), "Métier")
	var lines: Array = ["+%d XP %s" % [int(ev["gained"]), job_name]]
	if int(ev["levels"]) > 0:
		lines.append("%s : niveau %d" % [job_name, int(view["level"])])
	return lines
