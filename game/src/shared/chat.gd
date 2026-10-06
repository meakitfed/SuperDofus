## Chat rules (P3.02), pure: the channels, the commands (`/w Bob salut`), the text
## cleaning and the anti-flood. The sim (WorldChat) applies them; the client only uses
## `parse` / `label` to show the tabs. Nothing here is specific to Dofus except the
## table of channel shortcuts (chatchannels), which is data.
##
## Channels (our name -> chatchannels.id, shortcut):
##   general 0 /s (the map; in a fight, the fighters of that fight)  · team 1 /t (the fight)
##   guild 2 /g · alliance 3 /a · group 4 /p (need P3.03 / guilds: channel_unavailable for now)
##   commerce 5 /b · recruitment 6 /r (the whole world) · private 9 /w (one player)
class_name Chat
extends RefCounted

const GENERAL := "general"
const TEAM := "team"
const GUILD := "guild"
const ALLIANCE := "alliance"
const GROUP := "group"
const COMMERCE := "commerce"
const RECRUITMENT := "recruitment"
const PRIVATE := "private"

## channel -> chatchannels.id (shortcuts and names come from the table, see shortcut / name_id)
const IDS := {GENERAL: 0, TEAM: 1, GUILD: 2, ALLIANCE: 3, GROUP: 4, COMMERCE: 5, RECRUITMENT: 6, PRIVATE: 9}
## channels the sim delivers today
const AVAILABLE := [GENERAL, TEAM, COMMERCE, RECRUITMENT, PRIVATE]
## French names when the client texts (i18n) are not loaded
const FR_NAMES := {GENERAL: "Général", TEAM: "Équipe", GUILD: "Guilde", ALLIANCE: "Alliance", GROUP: "Groupe",
		COMMERCE: "Commerce", RECRUITMENT: "Recrutement", PRIVATE: "Privé"}
## the shortcuts of chatchannels, used when the table is not loaded
const SHORTCUTS := {GENERAL: "/s", TEAM: "/t", GUILD: "/g", ALLIANCE: "/a", GROUP: "/p", COMMERCE: "/b", RECRUITMENT: "/r", PRIVATE: "/w"}
## the tabs of the chat window, in order
const TABS := [GENERAL, PRIVATE, COMMERCE, RECRUITMENT]

## APPROX(P3.02): no flood constant in the Dofus data (constants / chatchannels). Values
## are ours: at most `count` messages per `window_ms` on the open channels, one per
## `window_ms` on commerce / recruitment (Dofus 2 had a long delay there; the channel
## description only says it is moderated). Private messages share the open limit.
const FLOOD := {
	"open": {"count": 5, "window_ms": 10000},
	COMMERCE: {"count": 1, "window_ms": 60000},
	RECRUITMENT: {"count": 1, "window_ms": 60000},
}
## APPROX(P3.02): length limit of a message (Dofus 2: 256 characters)
const MAX_LENGTH := 256
## messages kept by the server's journal (moderation, console A1.01)
const LOG_SIZE := 200


## chatchannels row of a channel ({} if the table is missing).
static func row(channel: String) -> Dictionary:
	return GameData.row("chatchannels", int(IDS.get(channel, -1)))


## The shortcut of a channel ("/s"), from the Dofus table.
static func shortcut(channel: String) -> String:
	return str(row(channel).get("shortcut", SHORTCUTS.get(channel, "")))


## i18n id of the channel's name (chatchannels.nameId), 0 if unknown.
static func name_id(channel: String) -> int:
	return int(row(channel).get("nameId", 0))


## The channel behind a command word ("/b" or "b"), "" if none: the shortcuts of
## chatchannels, then the English names ("/w", "/whisper", "/msg").
static func channel_of(word: String) -> String:
	var w := word.to_lower().trim_prefix("/")
	if w in ["whisper", "msg", "mp"]:
		return PRIVATE
	for ch: String in IDS:
		if shortcut(ch) == "/" + w or ch == w:
			return ch
	return ""


## Removes control characters, trims, cuts to MAX_LENGTH ("" = nothing to say).
static func clean(text: String) -> String:
	var out := ""
	for i in text.length():
		var c := text.unicode_at(i)
		out += " " if c < 32 or c == 127 else text[i]
	return out.strip_edges().substr(0, MAX_LENGTH).strip_edges()


## A line typed in the chat box -> {channel, text, to} (`to` only for private), or {error}:
##   "salut"            on `current` (the tab open), `to` kept for a private tab
##   "/b vends dofus"   on commerce      "/w Bob salut"  private to Bob      "/w Bob" -> {channel, to, text: ""}
## An unknown "/x" is an error (the chat box would otherwise send a typo to everyone).
static func parse(text: String, current := GENERAL, current_to := "") -> Dictionary:
	var line := clean(text)
	if not line.begins_with("/"):
		return {"channel": current, "text": line, "to": current_to if current == PRIVATE else ""}
	var cut := line.find(" ")
	var word := line.substr(0, cut) if cut >= 0 else line
	var rest := line.substr(cut + 1).strip_edges() if cut >= 0 else ""
	var channel := channel_of(word)
	if channel == "":
		return {"error": "unknown_command", "word": word}
	if channel != PRIVATE:
		return {"channel": channel, "text": rest, "to": ""}
	var at := rest.find(" ")
	var to := rest.substr(0, at) if at >= 0 else rest
	return {"channel": PRIVATE, "to": to, "text": rest.substr(at + 1).strip_edges() if at >= 0 else ""}


## Anti-flood: `history` = send times (ms) of this player on this channel kind
## (kept by the caller, oldest first). Returns the seconds to wait (rounded up), 0 = allowed.
## The caller appends `now` to the history when it sends, and may drop what is older
## than the window (`trim`).
static func flood_wait(channel: String, history: Array, now: int) -> int:
	var rule: Dictionary = FLOOD.get(channel, FLOOD["open"])
	var recent := history.filter(func(t: int) -> bool: return now - t < int(rule["window_ms"]))
	if recent.size() < int(rule["count"]):
		return 0
	# the message that has to leave the window is the (size - count + 1)th most recent
	var oldest: int = recent[recent.size() - int(rule["count"])]
	return ceili((int(rule["window_ms"]) - (now - oldest)) / 1000.0)


## The flood bucket of a channel: commerce and recruitment have their own, the others share one.
static func bucket(channel: String) -> String:
	return channel if channel in [COMMERCE, RECRUITMENT] else "open"


static func trim(history: Array, channel: String, now: int) -> Array:
	var rule: Dictionary = FLOOD.get(channel, FLOOD["open"])
	return history.filter(func(t: int) -> bool: return now - t < int(rule["window_ms"]))


## The chat_msg event (`to` = the recipient's name, private only).
static func message(channel: String, from: String, from_id: int, text: String, now: int, to := "") -> Dictionary:
	var msg := {"t": Protocol.CHAT_MSG, "channel": channel, "from": from, "from_id": from_id, "text": text, "at": now}
	if to != "":
		msg["to"] = to
	return msg
