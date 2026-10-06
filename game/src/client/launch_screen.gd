## First screen of the game (roadmap S.01, S.02a): Solo (the game runs in this process,
## saves in user://saves) or Serveur (address:port of a game server, reached
## through a NetBackend, then an account: login and password, or "create an account").
## Once the server answers login_ok, the loading screen (C.03) lists its worlds and downloads
## what the local cache lacks; the game starts when the chosen world is ready, and the choice
## of the world's character is the next screen (P1.01), unchanged. The address, the login and the
## last world are remembered in user://launch.cfg; the password never is.
## It only builds the GameBackend and hands it to a ClientSession: the client
## does not know which kind it got.
## The exported client (X.01) carries no world: without worlds/ beside the project the Solo button is
## replaced by a note saying a server is needed (solo stays available from the project).
class_name LaunchScreen
extends Control

const CONFIG := "user://launch.cfg"
const DEFAULT_WORLD := "dofus"

var _address: LineEdit
var _login: LineEdit
var _password: LineEdit
var _col: VBoxContainer
var _loading: WorldLoadScreen
var _create: Button
var _status: Label
var _folder_label: Label
var _folder_screen: ContentFolderScreen
var _solo: Button
var _join: Button
var _net: NetBackend
## "solo" | "server" once chosen
var mode := ""
## what to send once the socket is open: Protocol.LOGIN or Protocol.REGISTER
var _asking := ""
var _asked := false
var _remembered_world := DEFAULT_WORLD
## shown in red when the screen opens: why the session ended (S.02c)
var notice := ""


func _ready() -> void:
	theme = ClientTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(CharacterSelectScreen.backdrop())
	var col := VBoxContainer.new()
	_col = col
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	add_child(col)
	var title := UiStyle.label("SuperDofus", UiStyle.GOLD, 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sep: Label
	if solo_available():
		col.add_child(_centered(_solo_button()))
		sep = UiStyle.label("ou rejoindre un serveur", UiStyle.TEXT_MUTED, 15)
	else:
		_solo = Button.new() # kept (never shown): _set_busy toggles it
		sep = UiStyle.label("Ce client n'a pas de monde en local : rejoins un serveur\n(adresse:port donnée par la personne qui l'héberge)", UiStyle.TEXT_MUTED, 15)
	sep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sep)
	_address = LineEdit.new()
	_address.placeholder_text = "adresse:port  (ex. 25.12.34.56:7777)"
	_address.custom_minimum_size = Vector2(320, 36)
	_address.text_submitted.connect(func(_t: String) -> void: _login.grab_focus())
	col.add_child(_centered(_address))
	_login = LineEdit.new()
	_login.placeholder_text = "identifiant"
	_login.max_length = 24
	_login.custom_minimum_size = Vector2(320, 36)
	_login.text_submitted.connect(func(_t: String) -> void: _password.grab_focus())
	col.add_child(_centered(_login))
	_password = LineEdit.new()
	_password.placeholder_text = "mot de passe"
	_password.secret = true
	_password.max_length = 128
	_password.custom_minimum_size = Vector2(320, 36)
	_password.text_submitted.connect(func(_t: String) -> void: _join_server())
	col.add_child(_centered(_password))
	_join = CharacterSelectScreen.gold_button("Se connecter")
	_join.pressed.connect(func() -> void: _join_server())
	col.add_child(_centered(_join))
	_create = CharacterSelectScreen.gold_button("Créer un compte")
	_create.pressed.connect(func() -> void: _join_server(true))
	col.add_child(_centered(_create))
	_status = UiStyle.label("", UiStyle.TEXT_MUTED, 16)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status)
	var folder_row := HBoxContainer.new() # C.04: where the downloaded worlds are stored
	folder_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_folder_label = UiStyle.label("", UiStyle.TEXT_MUTED, 13)
	folder_row.add_child(_folder_label)
	var change := Button.new()
	change.text = "Changer…"
	change.pressed.connect(func() -> void: _open_folder_screen(true))
	folder_row.add_child(change)
	col.add_child(folder_row)
	_load_memory()
	if notice != "":
		_show_error(notice)
	var opts := AutoRun.options()
	_setup_folder(opts)
	if SelfUpdater.enabled(opts) and not opts.has("auto-connect"):
		_start_update()
	if opts.has("auto-connect"):
		var auto := AutoRun.new()
		auto.launch = self
		auto.opts = opts
		get_tree().root.add_child.call_deferred(auto) # outlives this screen (the game replaces it)


## X.02: asks GitHub for a newer client; if there is one it is downloaded, the buttons stay off
## and the game restarts on the new exe. Offline or up to date: nothing shows.
func _start_update() -> void:
	var up := SelfUpdater.new()
	add_child(up)
	up.status.connect(func(text: String) -> void:
		_status.text = text
		_status.add_theme_color_override("font_color", UiStyle.TEXT_MUTED))
	up.status.connect(func(text: String) -> void: _set_busy(text != "" and not text.begins_with("Mise à jour impossible")))
	up.ready_to_apply.connect(up.apply)
	up.start()

## C.04: the folder of the downloaded worlds: command line, else remembered, else the old default.
## The first launch (nothing remembered, no option on the command line) asks the player.
func _setup_folder(opts: Dictionary) -> void:
	var r := ContentFolder.resolve(opts)
	ContentFolder.apply(str(r["path"]))
	if r["source"] == "cli":
		ContentFolder.remember(str(r["path"]))
	_update_folder_label()
	if not r["configured"] and opts.is_empty() and DisplayServer.get_name() != "headless":
		_open_folder_screen(false)


func _update_folder_label() -> void:
	_folder_label.text = "Mondes téléchargés : %s   " % ContentSource.cache_base()


func _open_folder_screen(can_cancel: bool) -> void:
	if _folder_screen != null or _net != null:
		return
	_folder_screen = ContentFolderScreen.new()
	_folder_screen.current = ContentSource.cache_base() if ContentSource.cache_base().is_absolute_path() 			else ContentFolder.legacy_dir()
	_folder_screen.can_cancel = can_cancel
	_folder_screen.chosen.connect(func(path: String) -> void:
		ContentFolder.remember(path)
		ContentFolder.apply(path)
		_update_folder_label()
		_close_folder_screen())
	_folder_screen.cancelled.connect(_close_folder_screen)
	_col.visible = false
	add_child(_folder_screen)


func _close_folder_screen() -> void:
	_folder_screen.queue_free()
	_folder_screen = null
	_col.visible = true


## Fills the form and connects, as if typed (AutoRun, tests).
func drive_connect(address: String, login: String, password: String, register: bool) -> void:
	_address.text = address
	_login.text = login
	_password.text = password
	_join_server(register)


## True when this installation holds a world to play alone (the project, not an exported client).
static func solo_available() -> bool:
	return FileAccess.file_exists(ContentSource.dev_path("worlds/test/world.json")) \
			or FileAccess.file_exists(ContentSource.dev_path("worlds/dofus/world.json"))


func _process(_delta: float) -> void:
	if _net == null:
		return
	_net.poll(0.0) # connecting: wait for the socket, a refusal arrives as a network error
	if _net == null: # a login_error ended the attempt (_on_event)
		return
	match _net.state:
		"open":
			if not _asked: # the socket is open: now the account
				_asked = true
				_net.send(Protocol.register(_login.text, _password.text) if _asking == Protocol.REGISTER
						else Protocol.login(_login.text, _password.text))
				_status.text = "Connexion au compte…"
			elif _net.token != "" and _loading == null:
				_open_loading()
		"closed":
			_status.text = "Serveur injoignable (%s) : %s" % [_address.text.strip_edges(), _net.failure]
			_status.add_theme_color_override("font_color", UiStyle.BAD)
			_net = null
			_set_busy(false)


func _solo_button() -> Button:
	_solo = CharacterSelectScreen.gold_button("Jouer en solo")
	_solo.pressed.connect(func() -> void:
		mode = "solo"
		_start(null))
	return _solo


## Tries the server: the game starts once the account is accepted, else the reason is shown here.
func _join_server(register := false) -> void:
	var address := _address.text.strip_edges()
	if address == "" or _net != null:
		return
	if _login.text.strip_edges() == "" or _password.text == "":
		_show_error("Identifiant et mot de passe requis")
		return
	mode = "server"
	_save_memory()
	_asking = Protocol.REGISTER if register else Protocol.LOGIN
	_asked = false
	_net = NetBackend.new()
	_net.auto_reconnect = true # S.02c: a cut during the game is mended by resume{token}
	_net.event.connect(_on_event)
	_net.connect_to(address)
	_status.text = "Connexion à %s…" % address
	_status.add_theme_color_override("font_color", UiStyle.TEXT_MUTED)
	_set_busy(true)


func _on_event(ev: Dictionary) -> void:
	if str(ev.get("t", "")) == Protocol.LOGIN_ERROR:
		_show_error(ErrorTexts.text(ev))
		_net.close()
		_net = null
		_set_busy(false)


func _show_error(text: String) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", UiStyle.BAD)


## Logged in: the loading screen takes over (worlds, download), the game starts from there.
## The content API is on the game port + 1 (the server's default `--http-port`).
func _open_loading() -> void:
	var addr := WorldLoader.split_address(_address.text, 7777)
	var loader := WorldLoader.new(ContentClient.new(str(addr["host"]), int(addr["port"]) + 1, _net.token))
	_loading = WorldLoadScreen.new()
	_loading.setup(loader, _remembered_world)
	_loading.world_ready.connect(func(id: String) -> void: _start(_net, id))
	_loading.back.connect(_leave_loading)
	_col.visible = false
	add_child(_loading)


## "Retour" on the loading screen: the account session is closed, the form is back.
func _leave_loading() -> void:
	_loading.queue_free()
	_loading = null
	_net.close()
	_net = null
	_col.visible = true
	_set_busy(false)
	_status.text = ""


## Replaces this screen by the game; `backend` null = standalone (the client makes its own).
func _start(backend: NetBackend, world := "") -> void:
	var client: ClientSession = (load("res://scenes/client/client.tscn") as PackedScene).instantiate()
	client.world_id = world if world != "" else DEFAULT_WORLD # solo: the client's own default
	client.backend = backend
	client.back_to_launch = backend != null
	if backend != null and world != "":
		client.zone_gate = _zone_gate(backend.token, world)
	if world != "":
		_remembered_world = world
	_net = null
	get_parent().add_child(client)
	queue_free()


## Zones on demand (C.02d): a client of its own on the content API (game port + 1), same cache folder.
func _zone_gate(token: String, world: String) -> ZoneGate:
	var addr := WorldLoader.split_address(_address.text, 7777)
	var cc := ContentClient.new(str(addr["host"]), int(addr["port"]) + 1, token)
	return ZoneGate.new(ZoneStreamer.new(cc, world, ContentSource.cache_dir_for(world, ContentSource.cache_base())))


func _set_busy(busy: bool) -> void:
	_solo.disabled = busy
	_join.disabled = busy
	_create.disabled = busy
	_address.editable = not busy
	_login.editable = not busy
	_password.editable = not busy


func _centered(c: Control) -> CenterContainer:
	var box := CenterContainer.new()
	box.add_child(c)
	return box


func _load_memory() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG) == OK:
		_address.text = str(cfg.get_value("server", "address", ""))
		_login.text = str(cfg.get_value("server", "login", ""))
		_remembered_world = str(cfg.get_value("server", "world", DEFAULT_WORLD))


func _save_memory() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("server", "address", _address.text.strip_edges())
	cfg.set_value("server", "login", _login.text.strip_edges())
	cfg.set_value("server", "world", _remembered_world) # kept: the loading screen updates it
	cfg.save(CONFIG) # best effort: a read-only profile just forgets
