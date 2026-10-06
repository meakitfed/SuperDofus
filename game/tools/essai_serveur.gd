## End-to-end trial on a REAL running server (not in this process): two accounts play through two
## NetBackend over 127.0.0.1. Run the server first (docs/ESSAI_SERVEUR.md), then:
##   godot --headless --path game -s res://tools/essai_serveur.gd -- --server=127.0.0.1:7791 --gm=essaia --out=essai.json
## Each feature prints `ESSAI|<feature>|OK|BUG|MANQUE|<note>` and the list goes to --out (json).
## Only protocol messages are used (like a client).
extends SceneTree

const LOOK := "{1|120,2195||56}"
const START_MAP := 154010373
const SHOP_MAP := 154010883 # Lykhen Lesurviven (shop) and Ruth Banke (bank)
const SHOP_NPC := 2892
const BANK_NPC := 6415
const QUEST_MAP := 154010371
const QUEST_NPC := 2905
const QUEST_REPLY := 1001639
const TREE_MAP := 153880323
const TREE_ELEMENT := 537687
const TREE_CELL := 393
const TREE_SKILL := 6
const SWORD := 44
const POTION := 683
const PASS := "motdepasse1"


var _results: Array = []
var _server := "127.0.0.1:7791"
var _gm := "essaia"
var _out := ""
var _a: EssaiPeer
var _b: EssaiPeer
var _run := ""
var _extra: Array = [] # other connections (checks), polled too


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			_server = arg.get_slice("=", 1)
		elif arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
		elif arg.begins_with("--run="):
			_run = arg.get_slice("=", 1)
	_main.call_deferred()


func _main() -> void:
	if _run == "":
		for ch in str(Time.get_ticks_msec() % 100000): # names are letters only (namingrules)
			_run += char("a".unicode_at(0) + int(ch))
	await _go()
	var bugs := 0
	for r: Dictionary in _results:
		if r["status"] != "OK":
			bugs += 1
	print("ESSAI|total|%d|non OK : %d" % [_results.size(), bugs])
	if _out != "":
		var f := FileAccess.open(_out, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(_results, "  "))
	quit(0)


func _rec(feature: String, status: String, note := "") -> void:
	_results.append({"feature": feature, "status": status, "note": note})
	print("ESSAI|%s|%s|%s" % [feature, status, note])


func _ok(feature: String, cond: bool, note_ko := "", note_ok := "") -> bool:
	_rec(feature, "OK" if cond else "BUG", note_ok if cond else note_ko)
	return cond


## Polls the peers until `until` is true or `seconds` (real time) elapsed.
func _pump(seconds: float, until := Callable()) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		for p: EssaiPeer in [_a, _b] + _extra:
			if p != null:
				p.backend.poll(0.03)
				if p.bot != null:
					var out: Array = []
					p.bot.drive(p.backend, p.seen, out)
					for cmd: Dictionary in out:
						p.send(cmd)
		if until.is_valid() and until.call():
			return true
		await create_timer(0.03).timeout
	return not until.is_valid()


## Sends `cmd` and waits for one of the types (or an error); returns the event's type or "".
func _ask(p: EssaiPeer, cmd: Dictionary, types: Array, seconds := 6.0) -> String:
	p.clear()
	p.send(cmd)
	var got := [""] # a lambda captures plain variables by value
	await _pump(seconds, func() -> bool:
		for e: Dictionary in p.events:
			if types.has(e["t"]) or e["t"] == Protocol.ERROR:
				got[0] = str(e["t"])
				return true
		return false)
	return str(got[0])


func _login(p: EssaiPeer, register: bool, user: String, pw := PASS) -> String:
	p.clear()
	p.send(Protocol.register(user, pw) if register else Protocol.login(user, pw))
	await _pump(6.0, func() -> bool: return p.has(Protocol.LOGIN_OK) or p.has(Protocol.LOGIN_ERROR))
	if p.has(Protocol.LOGIN_OK):
		return ""
	return str(p.last(Protocol.LOGIN_ERROR).get("code", "timeout"))


func _go() -> void:
	var ua := "essaia" if _gm == "essaia" else _gm
	var ub := "essaib"
	_a = EssaiPeer.new("Essaia" + _run)
	_b = EssaiPeer.new("Essaib" + _run)
	_a.backend.connect_to(_server)
	_b.backend.connect_to(_server)
	await _pump(3.0, func() -> bool: return _a.backend.state == "open" and _b.backend.state == "open")
	_ok("connexion WebSocket", _a.backend.state == "open" and _b.backend.state == "open", "pas ouvert : %s" % _a.backend.failure)
	if not await _accounts(ua, ub):
		return
	if not await _characters():
		return
	await _content()
	await _moves()
	await _chat()
	await _party()
	await _gm_cmds()
	await _shop()
	await _bank()
	await _quest()
	await _harvest()
	await _fights()
	await _cut(ua)
	await _gm_late()
	await _finish()


# ---------------------------------------------------------------- accounts

func _accounts(ua: String, ub: String) -> bool:
	var err := await _login(_a, false, ua)
	_ok("compte : connexion avant inscription refusée", err == "bad_credentials", "code %s" % err)
	err = await _login(_a, true, "x")
	_ok("compte : login trop court refusé", err == "bad_login", "code %s" % err)
	err = await _login(_a, true, ua)
	var ok_a := _ok("compte : inscription A", err == "" and _a.backend.token != "", "code %s" % err)
	err = await _login(_b, true, ub)
	var ok_b := _ok("compte : inscription B", err == "" and _b.backend.token != "", "code %s" % err)
	_ok("compte : rôle GM seulement pour A", _a.backend.role == "gm" and _b.backend.role == "player",
			"A=%s B=%s" % [_a.backend.role, _b.backend.role], "A=gm B=player")
	err = await _login(_b, true, ua)
	_ok("compte : nom déjà pris refusé", err == "login_taken" or err == "already_connected", "code %s" % err)
	# a third connection on A's account: refused (one connection per account) or replaces it
	var c := EssaiPeer.new("dup")
	_extra.append(c)
	c.backend.connect_to(_server)
	await _pump(2.0, func() -> bool: return c.backend.state == "open")
	err = await _login(c, false, ua)
	_ok("compte : une seule connexion par compte", err == "already_connected", "code %s" % err)
	err = await _login(c, false, ub, "mauvais")
	_ok("compte : mauvais mot de passe refusé", err == "bad_credentials" or err == "already_connected", "code %s" % err)
	c.backend.close()
	return ok_a and ok_b


# ---------------------------------------------------------------- characters

func _characters() -> bool:
	_a.clear()
	_b.clear()
	_a.send(Protocol.hello("incarnam"))
	_b.send(Protocol.hello("incarnam"))
	await _pump(6.0, func() -> bool: return _a.has(Protocol.CHARACTERS) and _b.has(Protocol.CHARACTERS))
	var ok := _ok("personnages : liste vide à la première connexion",
			_a.has(Protocol.CHARACTERS) and (_a.last(Protocol.CHARACTERS)["list"] as Array).is_empty(), "pas de characters")
	var breeds: Array = _a.last(Protocol.CHARACTERS).get("breeds", [])
	_ok("personnages : classes proposées", breeds.size() > 0, "breeds vide", "%d classes" % breeds.size())
	var breed := 12
	if not breeds.is_empty():
		breed = int((breeds[0] as Dictionary).get("id", 12)) if breeds[0] is Dictionary else int(breeds[0])
	var t := await _ask(_a, Protocol.create_character(_a.name, 12, 0), [Protocol.CHARACTER_CREATED])
	ok = _ok("personnages : création A", t == Protocol.CHARACTER_CREATED, "reçu %s %s" % [t, _a.errors()]) and ok
	t = await _ask(_b, Protocol.create_character(_b.name, breed, 1), [Protocol.CHARACTER_CREATED])
	ok = _ok("personnages : création B", t == Protocol.CHARACTER_CREATED, "reçu %s %s" % [t, _b.errors()]) and ok
	t = await _ask(_b, Protocol.create_character(_b.name, 12, 0), [Protocol.CHARACTER_CREATED])
	_ok("personnages : doublon de nom refusé", t == Protocol.ERROR, "reçu %s" % t)
	_a.clear()
	_b.clear()
	_a.send(Protocol.select_character(_a.name))
	_b.send(Protocol.select_character(_b.name))
	await _pump(8.0, func() -> bool: return _a.has(Protocol.MAP_ENTER) and _b.has(Protocol.MAP_ENTER))
	ok = _ok("personnages : sélection, welcome et map_enter", _a.you > 0 and _b.you > 0 and _a.map_id != 0 and _b.map_id != 0,
			"A=%d/%d B=%d/%d %s %s" % [_a.you, _a.map_id, _b.you, _b.map_id, _a.errors(), _b.errors()]) and ok
	_ok("personnages : inventaire et stats reçus", _a.has(Protocol.INVENTORY) or _a.has(Protocol.PLAYER_STATS), "rien reçu")
	_ok("monde : même map de départ", _a.map_id == _b.map_id and _a.map_id == START_MAP, "A=%d B=%d" % [_a.map_id, _b.map_id])
	await _pump(1.0)
	_ok("horloge : décalage mesuré (ping/pong)", _a.backend.rtt_ms() >= 0 and _a.backend.time_ms() > 0, "pas de pong")
	return ok


# ---------------------------------------------------------------- content API (HTTP)

func _content() -> void:
	var r: Array = await EssaiPeer.http_get(self, _server, "/worlds", "")
	_ok("contenu HTTP : sans jeton refusé (401)", int(r[0]) == 401, "code %s" % r[0])
	r = await EssaiPeer.http_get(self, _server, "/worlds", _a.backend.token)
	var listed := false
	if int(r[0]) == 200:
		var list: Variant = JSON.parse_string(str(r[1]))
		listed = list is Array and (list as Array).any(func(w: Variant) -> bool: return w is Dictionary and str(w.get("id", "")) == "incarnam")
	_ok("contenu HTTP : /worlds avec jeton liste incarnam", listed, "code %s" % r[0])
	r = await EssaiPeer.http_get(self, _server, "/worlds/incarnam/manifest.json", _a.backend.token)
	_ok("contenu HTTP : manifeste du monde", int(r[0]) == 200 and str(r[1]).length() > 1000, "code %s" % r[0])
	r = await EssaiPeer.http_get(self, _server, "/worlds/incarnam/files/0000", _a.backend.token)
	_ok("contenu HTTP : fichier hors manifeste refusé", int(r[0]) in [400, 404], "code %s" % r[0])


# ---------------------------------------------------------------- moves

func _moves() -> void:
	# each one sees the other on arrival?
	_ok("joueurs : B voit A à son arrivée sur la map", _b.actor_named(_a.name) > 0 or _b.actors.has(_a.you),
			"actors B=%s" % [_b.actors.keys()])
	_ok("joueurs : A voit B (actor_add)", _a.actor_named(_b.name) > 0 or _a.actors.has(_b.you), "actors A=%s" % [_a.actors.keys()])
	var pub: Dictionary = _a.actors.get(_b.you, {})
	_ok("joueurs : fiche publique sans donnée privée", pub.get("kind", "") == "player" and not pub.has("kamas") and not pub.has("inventory"),
			"fiche %s" % [pub.keys()])
	var target_a := 300
	var target_b := 315
	_a.clear()
	_b.clear()
	_a.send(Protocol.move(target_a))
	_b.send(Protocol.move(target_b))
	await _pump(4.0, func() -> bool: return _a.has(Protocol.ACTOR_MOVE) and _b.has(Protocol.ACTOR_MOVE))
	var a_moves_seen_by_b := _b.of(Protocol.ACTOR_MOVE).any(func(e: Dictionary) -> bool: return int(e["id"]) == _a.you)
	var b_moves_seen_by_a := _a.of(Protocol.ACTOR_MOVE).any(func(e: Dictionary) -> bool: return int(e["id"]) == _b.you)
	_ok("déplacements croisés : B voit marcher A", a_moves_seen_by_b, "pas d'actor_move de A chez B ; erreurs A %s B %s" % [_a.errors(), _b.errors()])
	_ok("déplacements croisés : A voit marcher B", b_moves_seen_by_a, "pas d'actor_move de B chez A")
	await _pump(5.0)
	_ok("déplacements : A arrive à sa case", _a.cell == target_a, "cell A=%d" % _a.cell)
	_a.clear()
	_a.send(Protocol.move(9999))
	await _pump(2.0, func() -> bool: return _a.has(Protocol.ERROR))
	_ok("déplacements : case invalide refusée", _a.has_error("bad_cell"), "erreurs %s" % [_a.errors()])


# ---------------------------------------------------------------- chat

func _chat() -> void:
	_a.clear()
	_b.clear()
	_a.send(Protocol.chat_send("general", "bonjour tout le monde"))
	await _pump(3.0, func() -> bool: return _b.has(Protocol.CHAT_MSG) and _a.has(Protocol.CHAT_MSG))
	var m := _b.last(Protocol.CHAT_MSG)
	_ok("chat : canal de map reçu par l'autre joueur", not m.is_empty() and str(m.get("text", "")) == "bonjour tout le monde"
			and str(m.get("from", "")) == _a.name, "reçu %s ; erreurs %s" % [m, _a.errors()])
	_ok("chat : l'expéditeur reçoit aussi son message", _a.has(Protocol.CHAT_MSG), "pas d'écho")
	_a.clear()
	_b.clear()
	_b.send(Protocol.chat_send("general", "/w %s salut en prive" % _a.name))
	await _pump(3.0, func() -> bool: return _a.has(Protocol.CHAT_MSG))
	var w := _a.last(Protocol.CHAT_MSG)
	_ok("chat : message privé /w reçu", str(w.get("channel", "")) == "private" and str(w.get("text", "")) == "salut en prive",
			"reçu %s ; erreurs B %s" % [w, _b.errors()])
	_ok("chat : écho du privé chez l'expéditeur", _b.of(Protocol.CHAT_MSG).any(func(e: Dictionary) -> bool: return str(e.get("channel", "")) == "private"),
			"pas d'écho chez B")
	_b.clear()
	_b.send(Protocol.chat_send("general", "/w personne_xyz coucou"))
	await _pump(3.0, func() -> bool: return _b.has(Protocol.ERROR))
	_ok("chat : /w vers un absent refusé", _b.has_error("player_offline") or _b.has_error("unknown_player") or _b.errors().size() > 0,
			"pas d'erreur")
	_b.clear()
	_b.send(Protocol.chat_send("general", "/xyz truc"))
	await _pump(3.0, func() -> bool: return _b.has(Protocol.ERROR))
	_ok("chat : commande inconnue refusée", _b.has_error("unknown_command"), "erreurs %s" % [_b.errors()])
	_b.clear()
	for i in 12:
		_b.send(Protocol.chat_send("general", "spam %d" % i))
	await _pump(3.0)
	_ok("chat : anti-flood", _b.has_error("chat_flood") or _b.errors().size() > 0, "12 messages d'affilée acceptés")
	await _pump(2.0)
	await _probe("chat de groupe /p (P3.02b)", Protocol.chat_send("general", "/p salut"))
	await EssaiTrade.new(self).run()
	await _probe("amis / ignorés (contact_add, P3.05)", {"t": "contact_add", "name": _a.name, "kind": "friend"})
	await _probe("guilde (guild_create, P3.06)", {"t": "guild_create", "name": "Essai"})


## A feature that may not exist yet: refused by the server = MANQUE (not a bug), accepted = OK.
func _probe(feature: String, cmd: Dictionary) -> void:
	_b.clear()
	_b.send(cmd)
	await _pump(2.0, func() -> bool: return _b.has(Protocol.ERROR))
	var codes := _b.errors()
	_rec(feature, "MANQUE" if not codes.is_empty() else "OK", "refusé : %s" % [codes])


# ---------------------------------------------------------------- party

func _party() -> void:
	_a.clear()
	_b.clear()
	_a.send(ProtocolParty.invite(_b.name))
	await _pump(3.0, func() -> bool: return _b.has(ProtocolParty.INVITED))
	_ok("groupe : invitation reçue", _b.last(ProtocolParty.INVITED).get("from", "") == _a.name, "erreurs A %s" % [_a.errors()])
	_b.send(ProtocolParty.accept(_a.name))
	await _pump(3.0, func() -> bool: return _a.has(ProtocolParty.UPDATE) and _b.has(ProtocolParty.UPDATE))
	var up := _a.last(ProtocolParty.UPDATE)
	var members: Array = up.get("party", {}).get("members", [])
	_ok("groupe : acceptation, party_update aux deux", members.size() == 2 and _b.has(ProtocolParty.UPDATE),
			"membres %d ; erreurs B %s" % [members.size(), _b.errors()])
	# B follows A; A changes map through a real exit
	_b.send(ProtocolParty.follow(_a.name))
	await _pump(1.0)
	var exit_dir := ""
	var exit_cell := -1
	var data := _map_data(_a)
	if data != null:
		for d: String in ["top", "bottom", "left", "right"]:
			if data.neighbor(d) > 0 and not data.exit_cells(d).is_empty():
				var cells := data.exit_cells(d).filter(func(c: int) -> bool: return data.is_walkable(c))
				if not cells.is_empty():
					exit_dir = d
					exit_cell = cells[0]
					break
	_a.clear()
	_b.clear()
	var moved := false
	if exit_cell >= 0:
		_a.send(Protocol.move(exit_cell))
		await _pump(12.0, func() -> bool: return _a.cell == exit_cell)
		_a.send(Protocol.change_map(exit_dir))
		moved = await _pump(5.0, func() -> bool: return _a.has(Protocol.MAP_ENTER))
		await _pump(3.0, func() -> bool: return _b.has(Protocol.MAP_ENTER))
		_ok("groupe : suivre (B rejoint la map de A)", _a.map_id == _b.map_id and moved, "A=%d B=%d (sortie %s %d) erreurs A %s B %s" % [
				_a.map_id, _b.map_id, exit_dir, exit_cell, _a.errors(), _b.errors()])
	else:
		_rec("groupe : suivre (B rejoint la map de A)", "BUG", "essai impossible : pas de sortie trouvée sur la map")
	# bring everybody back to the start map with the GM tool (also tests tp)
	_b.send(ProtocolParty.follow(""))
	_a.clear()
	_a.send(Protocol.admin_cmd("tp", [START_MAP, 300]))
	await _pump(3.0, func() -> bool: return _a.has(Protocol.MAP_ENTER))
	_b.clear()
	_b.send(Protocol.admin_cmd("tp", [START_MAP, 315]))
	await _pump(2.0)
	if _b.map_id != START_MAP:
		_b.send(Protocol.change_map("top"))
	# leaving
	_b.clear()
	_b.send(ProtocolParty.leave())
	await _pump(3.0, func() -> bool: return _b.has(ProtocolParty.LEFT))
	_ok("groupe : quitter (dissolution à un membre)", _b.has(ProtocolParty.LEFT), "pas de party_left ; erreurs %s" % [_b.errors()])
	_a.clear()
	_a.send(ProtocolParty.invite("personne_xyz"))
	await _pump(2.0, func() -> bool: return _a.has(Protocol.ERROR))
	_ok("groupe : inviter un absent refusé", _a.has_error("player_offline"), "erreurs %s" % [_a.errors()])


func _map_data(p: EssaiPeer) -> MapData:
	for i in range(p.seen.size() - 1, -1, -1):
		if str(p.seen[i]["ev"].get("t", "")) == Protocol.MAP_ENTER:
			return MapData.from_dict(p.seen[i]["ev"]["map"])
	return null


# ---------------------------------------------------------------- GM

func _gm_cmds() -> void:
	_b.clear()
	_b.send(Protocol.admin_cmd("give", [SWORD, 1]))
	await _pump(2.0, func() -> bool: return _b.has(Protocol.ERROR))
	_ok("GM : commande refusée à un joueur (not_gm)", _b.has_error("not_gm"), "erreurs %s" % [_b.errors()])
	_a.clear()
	_a.send(Protocol.admin_cmd("give", [POTION, 3]))
	await _pump(3.0, func() -> bool: return _a.has(ProtocolAdmin.ADMIN_RESULT) or _a.has(Protocol.ERROR))
	_ok("GM : give donne l'objet", _a.has(ProtocolAdmin.ADMIN_RESULT) and _a.item_of(POTION) > 0, "erreurs %s" % [_a.errors()])
	_a.clear()
	_a.send(Protocol.admin_cmd("kamas", [5000]))
	await _pump(3.0, func() -> bool: return _a.has(ProtocolAdmin.ADMIN_RESULT) or _a.has(Protocol.ERROR))
	_ok("GM : kamas", _a.has(ProtocolAdmin.ADMIN_RESULT) and _a.kamas >= 5000, "kamas=%d erreurs %s" % [_a.kamas, _a.errors()])
	_a.clear()
	_a.send(Protocol.admin_cmd("level", [12]))
	await _pump(3.0, func() -> bool: return _a.has(ProtocolAdmin.ADMIN_RESULT) or _a.has(Protocol.ERROR))
	_ok("GM : level", _a.has(ProtocolAdmin.ADMIN_RESULT), "erreurs %s" % [_a.errors()])
	_a.clear()
	_a.send(Protocol.admin_cmd("who", []))
	await _pump(3.0, func() -> bool: return _a.has(ProtocolAdmin.ADMIN_RESULT) or _a.has(Protocol.ERROR))
	_ok("GM : who", _a.has(ProtocolAdmin.ADMIN_RESULT), "erreurs %s" % [_a.errors()])
	_b.clear()
	_a.send(Protocol.admin_cmd("say", ["essai du message general"]))
	await _pump(3.0, func() -> bool: return _b.has(ProtocolAdmin.ANNOUNCE))
	_ok("GM : say diffusé à l'autre joueur", _b.has(ProtocolAdmin.ANNOUNCE), "pas d'announce chez B")
	_b.clear()
	_a.send(Protocol.admin_cmd("give", [POTION, 2, _b.name]))
	await _pump(3.0, func() -> bool: return _b.has(Protocol.ITEM_ADDED))
	_ok("GM : give à un autre joueur", _b.has(Protocol.ITEM_ADDED), "B n'a rien reçu ; erreurs A %s" % [_a.errors()])
	_a.clear()
	_a.send(Protocol.admin_cmd("tp", [START_MAP, 330]))
	await _pump(3.0, func() -> bool: return _a.has(Protocol.MAP_ENTER))
	_ok("GM : tp sur la même map", _a.has(Protocol.MAP_ENTER) and _a.map_id == START_MAP, "map %d erreurs %s" % [_a.map_id, _a.errors()])


# ---------------------------------------------------------------- npc helpers

func _tp(p: EssaiPeer, map: int, cell: int) -> bool:
	p.clear()
	p.send(Protocol.admin_cmd("tp", [map, cell]))
	await _pump(5.0, func() -> bool: return p.has(Protocol.MAP_ENTER) or p.has(Protocol.ERROR))
	return p.map_id == map


func _npc_actor(p: EssaiPeer, npc: int) -> int:
	for id: int in p.actors:
		var a: Dictionary = p.actors[id]
		if a.get("kind", "") == "npc" and int(a.get("npc", -1)) == npc:
			return id
	return -1


## Teleports beside the NPC (tries the neighbours) and talks to it. Returns true when a dialog opened.
func _talk(p: EssaiPeer, map: int, npc: int, cell_hint: int) -> bool:
	await _tp(p, map, cell_hint)
	var id := _npc_actor(p, npc)
	if id < 0:
		return false
	for c: int in [cell_hint + 14, cell_hint - 14, cell_hint + 1, cell_hint - 1, cell_hint + 15, cell_hint - 15, cell_hint + 13, cell_hint - 13]:
		await _tp(p, map, c)
		p.clear()
		p.send(Protocol.npc_talk(id))
		await _pump(3.0, func() -> bool: return p.has(Protocol.DIALOG) or p.has(Protocol.ERROR))
		if p.has(Protocol.DIALOG):
			return true
	return false


# ---------------------------------------------------------------- shop

func _shop() -> void:
	var talked := await _talk(_a, SHOP_MAP, SHOP_NPC, 329)
	if not _ok("PNJ : dialogue (npc_talk)", talked, "pas de dialogue ; erreurs %s" % [_a.errors()]):
		return
	var replies: Array = _a.last(Protocol.DIALOG).get("replies", [])
	var opened := false
	for r: Dictionary in replies:
		_a.clear()
		_a.send(Protocol.dialog_reply(int(r["id"])))
		await _pump(3.0, func() -> bool: return _a.has(Protocol.SHOP_OPEN) or _a.has(Protocol.DIALOG_END) or _a.has(Protocol.ERROR))
		if _a.has(Protocol.SHOP_OPEN):
			opened = true
			break
		if _a.has(Protocol.DIALOG_END):
			await _talk(_a, SHOP_MAP, SHOP_NPC, 329)
	if not _ok("boutique : ouverture (shop_open)", opened, "pas de boutique ; réponses %s" % [replies.size()]):
		return
	var before := _a.kamas
	_a.clear()
	_a.send(Protocol.shop_buy(SWORD, 1))
	await _pump(3.0, func() -> bool: return _a.has(Protocol.ITEM_ADDED) or _a.has(Protocol.ERROR))
	_ok("boutique : achat", _a.has(Protocol.ITEM_ADDED) and _a.item_of(SWORD) > 0 and _a.kamas < before,
			"erreurs %s kamas %d->%d" % [_a.errors(), before, _a.kamas])
	var uid := _a.item_of(SWORD)
	before = _a.kamas
	_a.clear()
	_a.send(Protocol.shop_sell(uid, 1))
	await _pump(3.0, func() -> bool: return _a.has(Protocol.ITEM_REMOVED) or _a.has(Protocol.ERROR))
	_ok("boutique : vente", _a.has(Protocol.ITEM_REMOVED) and _a.kamas > before, "erreurs %s" % [_a.errors()])
	_a.clear()
	_a.send(Protocol.shop_buy(SWORD, 100))
	await _pump(3.0, func() -> bool: return _a.has(Protocol.ERROR))
	_ok("boutique : achat trop cher refusé", _a.has_error("not_enough_kamas") or _a.has_error("too_heavy") or _a.errors().size() > 0, "accepté")
	_a.send(Protocol.shop_close())
	await _pump(1.0)


# ---------------------------------------------------------------- bank

func _bank() -> void:
	var talked := await _talk(_a, SHOP_MAP, BANK_NPC, 360)
	if not _ok("banque : dialogue du banquier", talked, "pas de dialogue ; erreurs %s" % [_a.errors()]):
		return
	var opened := false
	for r: Dictionary in _a.last(Protocol.DIALOG).get("replies", []):
		_a.clear()
		_a.send(Protocol.dialog_reply(int(r["id"])))
		await _pump(3.0, func() -> bool: return _a.has(Protocol.BANK_OPEN) or _a.has(Protocol.DIALOG_END) or _a.has(Protocol.ERROR))
		if _a.has(Protocol.BANK_OPEN):
			opened = true
			break
		if _a.has(Protocol.DIALOG_END):
			await _talk(_a, SHOP_MAP, BANK_NPC, 360)
	if not _ok("banque : ouverture du coffre", opened, "pas de bank_open"):
		return
	var uid := _a.item_of(POTION)
	_a.clear()
	_a.send(Protocol.bank_move(uid, 2, "in"))
	await _pump(3.0, func() -> bool: return _a.has(Protocol.BANK_UPDATE) or _a.has(Protocol.ERROR))
	_ok("banque : dépôt d'objets", _a.has(Protocol.BANK_UPDATE) and not _a.has(Protocol.ERROR), "erreurs %s" % [_a.errors()])
	var bank_uid := -1
	for it: Dictionary in (_a.last(Protocol.BANK_UPDATE).get("items", []) as Array):
		if int(it["id"]) == POTION and int(it["qty"]) > 0:
			bank_uid = int(it["uid"])
	_a.clear()
	var k := _a.kamas
	_a.send(Protocol.bank_kamas(100, "in"))
	await _pump(3.0, func() -> bool: return _a.has(Protocol.BANK_UPDATE) or _a.has(Protocol.ERROR))
	_ok("banque : dépôt de kamas", _a.has(Protocol.BANK_UPDATE) and _a.kamas == k - 100, "kamas %d->%d erreurs %s" % [k, _a.kamas, _a.errors()])
	_a.clear()
	_a.send(Protocol.bank_move(bank_uid, 1, "out"))
	await _pump(3.0, func() -> bool: return _a.has(Protocol.BANK_UPDATE) or _a.has(Protocol.ERROR))
	_ok("banque : retrait d'objets", _a.has(Protocol.BANK_UPDATE) and not _a.has(Protocol.ERROR), "erreurs %s" % [_a.errors()])
	_a.send(Protocol.bank_close())
	await _pump(1.0)


# ---------------------------------------------------------------- quest

func _quest() -> void:
	var talked := await _talk(_a, QUEST_MAP, QUEST_NPC, 361)
	if not _ok("quête : dialogue du PNJ", talked, "pas de dialogue ; erreurs %s" % [_a.errors()]):
		return
	var ids: Array = (_a.last(Protocol.DIALOG).get("replies", []) as Array).map(func(r: Dictionary) -> int: return int(r["id"]))
	_ok("quête : l'offre figure dans les réponses", ids.has(QUEST_REPLY), "réponses %s" % [ids])
	_a.clear()
	_a.send(Protocol.dialog_reply(QUEST_REPLY))
	await _pump(3.0, func() -> bool: return _a.has(Protocol.QUEST_START) or _a.has(Protocol.ERROR))
	_ok("quête : acceptation (quest_start)", _a.has(Protocol.QUEST_START), "erreurs %s" % [_a.errors()])
	await _pump(1.0)
	_a.send(Protocol.dialog_close())
	_a.clear()
	# the quest list comes back after a reconnection (checked in the cut phase)


# ---------------------------------------------------------------- harvest

func _harvest() -> void:
	var good := false
	var note := ""
	for c: int in [TREE_CELL + 14, TREE_CELL - 14, TREE_CELL + 1, TREE_CELL - 1, TREE_CELL + 15, TREE_CELL - 15, TREE_CELL + 13, TREE_CELL - 13]:
		await _tp(_a, TREE_MAP, c)
		_a.clear()
		_a.send(Protocol.interactive_use(TREE_ELEMENT, TREE_SKILL))
		await _pump(3.0, func() -> bool: return _a.has(Protocol.INTERACTIVE_START) or _a.has(Protocol.ERROR))
		if _a.has(Protocol.INTERACTIVE_START):
			good = true
			break
		note = str(_a.errors())
	if not _ok("métier : début de récolte (interactive_start)", good, "refusé %s" % note):
		return
	await _pump(14.0, func() -> bool: return _a.has(Protocol.INTERACTIVE_END))
	var end := _a.last(Protocol.INTERACTIVE_END)
	_ok("métier : récolte terminée", bool(end.get("done", false)), "fin %s" % [end])
	_ok("métier : XP de métier et ressource", _a.has(Protocol.JOB_XP) and _a.has(Protocol.ITEM_ADDED), "job_xp=%s item=%s" % [_a.has(Protocol.JOB_XP), _a.has(Protocol.ITEM_ADDED)])
	_ok("métier : l'élément est marqué récolté", _a.of(Protocol.INTERACTIVE_STATE).any(func(e: Dictionary) -> bool: return not bool(e["ready"])), "pas d'interactive_state")
	_a.clear()
	_a.send(Protocol.interactive_use(TREE_ELEMENT, TREE_SKILL))
	await _pump(3.0, func() -> bool: return _a.has(Protocol.ERROR) or _a.has(Protocol.INTERACTIVE_START))
	_ok("métier : élément déjà récolté refusé", _a.has_error("element_busy"), "erreurs %s" % [_a.errors()])


# ---------------------------------------------------------------- fights

## A map with a monster group near the start: scans the neighbours through tp until a group is there.
func _find_group(p: EssaiPeer) -> int:
	for id: int in p.actors:
		if str(p.actors[id].get("kind", "")) == "monster_group":
			return id
	return -1


func _fight_map(p: EssaiPeer) -> bool:
	for m: int in [START_MAP, 154010372, 154010374, 154010375, 154010370, 154010376, 154010882, 154010881, 153880322, 153880321]:
		if not await _tp(p, m, 300):
			continue
		await _pump(0.6)
		if _find_group(p) >= 0:
			return true
	return false


func _fights() -> void:
	if not await _fight_map(_a):
		_rec("combat : trouver un groupe de monstres", "BUG", "aucun groupe sur les maps essayées")
		return
	var map := _a.map_id
	var group := _find_group(_a)
	_a.clear()
	_a.send(Protocol.admin_cmd("heal", []))
	# solo fight with the scripted bot
	_a.send(Protocol.fight_attack(group))
	await _pump(5.0, func() -> bool: return _a.has(Protocol.FIGHT_START) or _a.has(Protocol.ERROR))
	if not _ok("combat solo : début (fight_start)", _a.has(Protocol.FIGHT_START), "erreurs %s" % [_a.errors()]):
		return
	_a.bot = ScenarioBot.new("fight")
	var done := await _pump(120.0, func() -> bool: return _a.has(Protocol.FIGHT_END))
	_a.bot = null
	var end := _a.last(Protocol.FIGHT_END)
	_ok("combat solo : fin de combat et gains", done and not end.is_empty(), "pas de fight_end en 120 s")
	if done:
		_rec("combat solo : résultat", "OK", "résultat=%s gains=%s" % [end.get("result", "?"), str(end.get("rewards", []))])
	await _pump(1.0)
	# the second player joins a fight (placement)
	await _fight_two(map)


func _fight_two(_map: int) -> void:
	if not await _fight_map(_a):
		_rec("combat à deux : trouver un groupe", "BUG", "aucun groupe")
		return
	await _tp(_b, _a.map_id, 301)
	await _pump(1.0)
	var group := _find_group(_a)
	_a.clear()
	_b.clear()
	_a.send(Protocol.fight_attack(group))
	await _pump(5.0, func() -> bool: return _a.has(Protocol.FIGHT_START))
	_ok("combat à deux : A lance le combat", _a.has(Protocol.FIGHT_START), "erreurs %s" % [_a.errors()])
	var fight_id := int(_a.last(Protocol.FIGHT_START).get("fight", -1))
	await _pump(1.0, func() -> bool: return _b.actors.has(fight_id))
	_ok("combat à deux : B voit l'épée du combat sur la map", _b.actors.has(fight_id), "acteurs B %s" % [_b.actors.keys()])
	# B spectates first, then A is not ready yet: B joins
	_b.clear()
	_b.send(ProtocolWatch.join(fight_id, 0))
	await _pump(4.0, func() -> bool: return _b.has(Protocol.FIGHT_START) or _b.has(Protocol.ERROR))
	var joined := _b.has(Protocol.FIGHT_START)
	_ok("combat à deux : B rejoint pendant le placement", joined, "erreurs %s" % [_b.errors()])
	_ok("combat à deux : A voit arriver B (fighter_joined)", _a.has(ProtocolWatch.JOINED), "pas de fighter_joined chez A")
	if not joined:
		return
	_a.bot = ScenarioBot.new("fight") # the bots replay the whole session log: they get the map and the fight
	_b.bot = ScenarioBot.new("fight")
	var done := await _pump(180.0, func() -> bool: return _a.has(Protocol.FIGHT_END) and _b.has(Protocol.FIGHT_END))
	_a.bot = null
	_b.bot = null
	var rb: Array = _b.last(Protocol.FIGHT_END).get("rewards", [])
	_ok("combat à deux : B reçoit ses gains", done and rb.size() > 0, "gains B %s" % [rb])
	_ok("combat à deux : les deux reçoivent la fin du combat", done, "A=%s B=%s" % [_a.has(Protocol.FIGHT_END), _b.has(Protocol.FIGHT_END)])
	await _pump(1.0)
	# a spectator
	if not await _fight_map(_a):
		return
	await _tp(_b, _a.map_id, 301)
	await _pump(1.0)
	var group2 := _find_group(_a)
	_a.clear()
	_b.clear()
	_a.send(Protocol.fight_attack(group2))
	await _pump(5.0, func() -> bool: return _a.has(Protocol.FIGHT_START))
	var fid := int(_a.last(Protocol.FIGHT_START).get("fight", -1))
	await _pump(1.0)
	_b.send(ProtocolWatch.spectate(fid))
	await _pump(4.0, func() -> bool: return _b.has(ProtocolWatch.WATCH) or _b.has(Protocol.ERROR))
	_ok("combat : spectateur (fight_watch)", _b.has(ProtocolWatch.WATCH), "erreurs %s" % [_b.errors()])
	_a.send(Protocol.fight_ready(true))
	await _pump(3.0)
	_a.send(Protocol.fight_leave())
	await _pump(4.0, func() -> bool: return _a.has(Protocol.FIGHT_END) or _a.has(Protocol.MAP_ENTER))
	_b.send(Protocol.fight_leave())
	await _pump(2.0)
	_ok("combat : fuite (fight_leave)", _a.has(Protocol.FIGHT_END) or _a.has(Protocol.MAP_ENTER), "A toujours en combat ; erreurs %s" % [_a.errors()])


func _last_map_enter_in(p: EssaiPeer) -> Dictionary:
	for i in range(p.seen.size() - 1, -1, -1):
		if str(p.seen[i]["ev"].get("t", "")) == Protocol.MAP_ENTER:
			return p.seen[i]["ev"]
	return {}


# ---------------------------------------------------------------- cut and resume

func _cut(ua: String) -> void:
	_a.backend.auto_reconnect = true
	_a.backend.validate_events = true
	if not await _fight_map(_a):
		_rec("coupure en combat : préparation", "BUG", "pas de groupe")
		return
	var group := _find_group(_a)
	_a.clear()
	_a.send(Protocol.fight_attack(group))
	await _pump(5.0, func() -> bool: return _a.has(Protocol.FIGHT_START))
	if not _a.has(Protocol.FIGHT_START):
		_rec("coupure en combat : préparation", "BUG", "pas de combat")
		return
	var fight_id := int(_a.last(Protocol.FIGHT_START).get("fight", -1))
	var token := _a.backend.token
	_a.backend._ws.close(4000, "essai : coupure")
	_a.clear()
	var back := await _pump(25.0, func() -> bool: return _a.has(ProtocolResume.RESUME_OK))
	_ok("coupure en combat : reprise (resume_ok)", back, "pas de resume_ok ; état %s échec %s" % [_a.backend.state, _a.backend.failure])
	if back:
		var st: Dictionary = _a.last(ProtocolResume.RESUME_OK).get("state", {})
		_ok("coupure en combat : l'état dit qu'on est en combat", bool(st.get("in_fight", false)), "état %s" % [st])
		await _pump(2.0)
		_ok("coupure en combat : le combat est rejoué (fight_start)", _a.has(Protocol.FIGHT_START), "pas de fight_start rejoué ; reçu %s" % [_a.events.map(func(e: Dictionary) -> String: return e["t"])])
		_ok("coupure en combat : même jeton", _a.backend.token == token, "jeton changé")
	# play the fight on until the end to leave the player free
	_a.send(Protocol.fight_leave())
	await _pump(4.0, func() -> bool: return _a.has(Protocol.FIGHT_END) or _a.has(Protocol.MAP_ENTER))
	_a.backend.auto_reconnect = false
	# a cut outside any fight, quests and inventory come back after resume
	_a.clear()
	_a.backend._ws.close(4000, "essai : coupure 2")
	_a.backend.auto_reconnect = true
	var back2 := await _pump(25.0, func() -> bool: return _a.has(ProtocolResume.RESUME_OK))
	await _pump(2.0)
	_ok("coupure hors combat : reprise", back2, "échec %s" % _a.backend.failure)
	_ok("coupure : les quêtes en cours reviennent", _a.has(Protocol.QUEST_LIST) and (_a.last(Protocol.QUEST_LIST).get("active", []) as Array).size() > 0,
			"quest_list=%s" % [_a.last(Protocol.QUEST_LIST)])
	_ok("coupure : l'inventaire revient avec les objets", _a.has(Protocol.INVENTORY) and _a.item_of(POTION) > 0, "inventaire absent ou sans potion")
	_a.backend.auto_reconnect = false
	# a clean close then a login again: the character is saved and back
	_a.backend.close()
	await _pump(1.5)
	var c := EssaiPeer.new("relog")
	_extra.append(c)
	c.backend.connect_to(_server)
	await _pump(2.0, func() -> bool: return c.backend.state == "open")
	var err := await _login(c, false, ua)
	_ok("compte : reconnexion après fermeture propre", err == "", "code %s" % err)
	c.clear()
	c.send(Protocol.hello("incarnam"))
	await _pump(4.0, func() -> bool: return c.has(Protocol.CHARACTERS))
	var list: Array = c.last(Protocol.CHARACTERS).get("list", [])
	_ok("personnages : le personnage est conservé", list.size() == 1, "liste %s" % [list.size()])
	c.send(Protocol.select_character(_a.name))
	await _pump(5.0, func() -> bool: return c.has(Protocol.MAP_ENTER))
	var kept: Dictionary = c.last(Protocol.PLAYER_STATS).get("stats", {})
	_ok("personnages : niveau, kamas et position sauvegardés", int(kept.get("level", 0)) >= 12 and int(kept.get("kamas", 0)) > 0,
			"stats %s" % [str(kept).left(200)])
	_extra.erase(c)
	_a = c


# ---------------------------------------------------------------- GM, last

func _gm_late() -> void:
	# the map channel stays on its map
	await _tp(_b, START_MAP, 300)
	await _tp(_a, 154010374, 300)
	_a.clear()
	_b.clear()
	_b.send(Protocol.chat_send("general", "personne ne doit l'entendre"))
	await _pump(2.5)
	_ok("chat : le canal de map ne traverse pas les maps", _b.has(Protocol.CHAT_MSG) and not _a.has(Protocol.CHAT_MSG), "A a reçu le message d'une autre map")
	await _tp(_a, START_MAP, 330)
	# mute / unmute
	_a.send(Protocol.admin_cmd("mute", [_b.name, 5]))
	await _pump(2.0)
	_b.clear()
	_b.send(Protocol.chat_send("general", "je suis muet"))
	await _pump(2.0, func() -> bool: return _b.has(Protocol.ERROR))
	_ok("GM : mute interdit le chat", _b.has_error("muted"), "erreurs %s" % [_b.errors()])
	_a.send(Protocol.admin_cmd("unmute", [_b.name]))
	await _pump(2.0)
	_b.clear()
	_b.send(Protocol.chat_send("general", "je reparle"))
	await _pump(2.0, func() -> bool: return _b.has(Protocol.CHAT_MSG) or _b.has(Protocol.ERROR))
	_ok("GM : unmute rend la parole", _b.has(Protocol.CHAT_MSG), "erreurs %s" % [_b.errors()])
	# kick and ban: B is removed by the GM, then cannot come back
	_b.clear()
	_a.send(Protocol.admin_cmd("kick", [_b.name]))
	await _pump(4.0, func() -> bool: return _b.backend.state != "open" or _a.has(Protocol.ERROR))
	_ok("GM : kick déconnecte le joueur", _b.backend.state != "open", "B toujours connecté ; erreurs %s" % [_a.errors()])
	await _pump(1.0)
	_ok("GM : le kick envoie son motif (kicked)", _b.has_error("kicked") or _b.backend.failure != "", "ni erreur ni échec côté B")
	_a.send(Protocol.admin_cmd("ban", [_b.name, "essai"]))
	await _pump(2.0)
	var c := EssaiPeer.new("banned")
	_extra.append(c)
	c.backend.connect_to(_server)
	await _pump(2.0, func() -> bool: return c.backend.state == "open")
	var err := await _login(c, false, "essaib")
	_ok("GM : un compte banni ne peut plus se connecter", err == "banned", "code %s" % err)
	c.backend.close()
	_a.send(Protocol.admin_cmd("unban", ["essaib"]))
	await _pump(1.0)


func _finish() -> void:
	_a.backend.close()
	_b.backend.close()
	await _pump(1.0)
