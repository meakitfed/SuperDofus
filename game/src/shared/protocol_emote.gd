## The emote messages (P3.02c), an extension of Protocol (protocol.gd stays under its size limit).
## An emote is a one-shot animation on the character (table emoticons), seen by the whole map.
class_name ProtocolEmote
extends RefCounted

const C2S := "client → jeu"
const S2C := "jeu → client"

# client -> game
const EMOTE := "emote"
# game -> client
const EMOTE_PLAY := "emote_play"

const E_UNKNOWN_EMOTE := "unknown_emote"  # emote: no such emoticon, or one the player has not earned (Emotes.usable)
const ERROR_CODES := [E_UNKNOWN_EMOTE]

const SCHEMA := {
	EMOTE: [C2S, "Émote (P3.02c) : jouer l'émoticône `emote` (table emoticons) hors combat. Réponse : emote_play à toute la map (vous compris), ou error (unknown_emote, in_fight, ghost)", {"emote": "int"}],
	EMOTE_PLAY: [S2C, "Un joueur de la map joue l'émoticône `emote` : `actor` (id d'acteur), `anim` (emoticons.animName), `duration` (ms, 0 = jusqu'au prochain mouvement)", {"actor": "int", "emote": "int", "anim": "str", "duration": "int"}],
}


static func emote(id: int) -> Dictionary:
	return {"t": EMOTE, "emote": id}


static func play(actor: int, id: int, anim: String, duration: int) -> Dictionary:
	return {"t": EMOTE_PLAY, "actor": actor, "emote": id, "anim": anim, "duration": duration}
