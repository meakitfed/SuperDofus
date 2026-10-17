## The achievement messages (P2.12a), an extension of Protocol: constants, SCHEMA entries and builders of the
## domain. The definitions (names, objectives, points) are static data (data/achievements.json), which the
## client reads itself: the messages only carry the state of the character. Same rules as Protocol.
class_name ProtocolAchievement
extends RefCounted

const C2S := "client → jeu"
const S2C := "jeu → client"

# client -> game
const OPEN := "achievement_open"
# game -> client
const LIST := "achievement_list"
const UNLOCKED := "achievement_unlocked"

const ERROR_CODES := []

const SCHEMA := {
	OPEN: [C2S, "Succès (P2.12a) : demander l'état des succès ; réponse : achievement_list", {}],
	LIST: [S2C, "État des succès du personnage : `points` (obtenus), `total` (points possibles), `done` [{id, day}] (succès obtenus, jour depuis 1970), `progress` [{id, objectives: [ids d'objectifs remplis]}] (succès non obtenus dont des objectifs sont remplis)", {"points": "int", "total": "int", "done": "array", "progress": "array"}],
	UNLOCKED: [S2C, "Un succès vient d'être obtenu (récompenses déjà données : player_stats, item_added suivent) : `achievement` (id), `name_id`, `points` (ce succès), `total_points` (du personnage), `rewards` {xp, kamas, items: [[id, qty]], emotes, spells, titles}", {"achievement": "int", "name_id": "int", "points": "int", "total_points": "int", "rewards": "dict"}],
}


static func open() -> Dictionary:
	return {"t": OPEN}

static func list(view: Dictionary) -> Dictionary:
	return {"t": LIST, "points": int(view["points"]), "total": int(view["total"]), "done": view["done"], "progress": view["progress"]}

static func unlocked(id: int, name_id: int, points: int, total_points: int, rewards: Dictionary) -> Dictionary:
	return {"t": UNLOCKED, "achievement": id, "name_id": name_id, "points": points, "total_points": total_points, "rewards": rewards}
