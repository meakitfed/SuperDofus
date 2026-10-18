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
## the path of a server connection, shown on the launch, loading and character screens
const STEPS := ["Serveur", "Compte", "Monde", "Personnage"]

var _address: LineEdit
var _login: LineEdit
var _password: LineEdit
var _col: VBoxContainer
var _loading: WorldLoadScreen
var _create: Button
var _status: Label
var _notice: UiMenu.Notice
var _steps_slot: VBoxContainer
var _folder_label: Label
var _background: CheckBox
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
	UiScale.apply(get_window())
	theme = ClientTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiMenu.backdrop(12))
	_col = UiMenu.card(self)
	UiMenu.header(_col, "SuperDofus", "Un client façon Dofus 3, seul ou entre amis")
	var tabs := UiTabs.new()
	if solo_available():
		tabs.add_tab("Jouer en solo", _solo_page())
	else:
		_solo = Button.new() # kept (never shown): _set_busy toggles it
		var note := UiStyle.muted("Ce client n'a pas de monde en local : rejoins un serveur (adresse:port donnée par la personne qui l'héberge).")
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_col.add_child(note)
	var server_index := tabs.add_tab("Rejoindre un serveur", _server_page())
	if _remembered_server() or not solo_available():
		tabs.select(server_index) # a server was used last time: the form is ready
	_col.add_child(tabs)
	_notice = UiMenu.notice()
	_status = _notice.label
	_col.add_child(_notice)
	_col.add_child(_advanced_section())
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


func _solo_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	var text := UiStyle.muted("Le jeu tourne sur cet ordinateur, sans compte ni connexion. Ta progression est sauvegardée ici.")
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(text)
	_solo = UiMenu.primary("Jouer en solo")
	_solo.pressed.connect(func() -> void:
		mode = "solo"
		_start(null))
	page.add_child(_solo)
	return page


func _server_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	_steps_slot = VBoxContainer.new()
	page.add_child(_steps_slot)
	_address = UiMenu.field(page, "Serveur", "adresse:port  (ex. 25.12.34.56:7777)")
	_address.text_submitted.connect(func(_t: String) -> void: _login.grab_focus())
	_login = UiMenu.field(page, "Identifiant", "identifiant")
	_login.max_length = 24
	_login.text_submitted.connect(func(_t: String) -> void: _password.grab_focus())
	_password = UiMenu.field(page, "Mot de passe", "mot de passe", true)
	_password.max_length = 128
	_password.text_submitted.connect(func(_t: String) -> void: _join_server())
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	_join = UiMenu.primary("Se connecter", 200)
	_join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join.pressed.connect(func() -> void: _join_server())
	buttons.add_child(_join)
	_create = UiMenu.secondary("Créer un compte", 150)
	_create.tooltip_text = "Crée le compte avec l'identifiant et le mot de passe ci-dessus"
	_create.pressed.connect(func() -> void: _join_server(true))
	buttons.add_child(_create)
	page.add_child(buttons)
	_show_steps(0)
	return page


## The path of a connection (server, account, world, character), `current` highlighted.
func _show_steps(current: int) -> void:
	for c in _steps_slot.get_children():
		c.queue_free()
	_steps_slot.add_child(UiMenu.steps(STEPS, current))


## Where the downloaded worlds live and the background download: rarely needed, folded away.
func _advanced_section() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var folder_row := HBoxContainer.new() # C.04: where the downloaded worlds are stored
	folder_row.add_theme_constant_override("separation", 8)
	_folder_label = UiStyle.label("", UiStyle.TEXT_MUTED, UiStyle.FS_SMALL)
	_folder_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_folder_label.clip_text = true
	folder_row.add_child(_folder_label)
	var change := UiMenu.secondary("Changer…", 90)
	change.custom_minimum_size.y = UiMenu.FIELD_H
	change.pressed.connect(func() -> void: _open_folder_screen(true))
	folder_row.add_child(change)
	box.add_child(folder_row)
	_background = CheckBox.new() # C.02f: the whole world behind the player's back
	_background.text = "Télécharger tout le monde en arrière-plan"
	box.add_child(_background)
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 4)
	UiMenu.disclosure(holder, "Options avancées", box)
	return holder


func _remembered_server() -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(CONFIG) == OK and str(cfg.get_value("server", "address", "")) != ""


## X.02: asks GitHub for a newer client; if there is one it is downloaded, the buttons stay off
## and the game restarts on the new exe. Offline or up to date: nothing shows.
func _start_update() -> void:
	var up := SelfUpdater.new()
	add_child(up)
	up.status.connect(func(text: String) -> void: _notice.say(text))
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
	_folder_label.text = "Mondes téléchargés : %s" % UiMenu.elide_path(ContentSource.cache_base(), 40)
	_folder_label.tooltip_text = ContentSource.cache_base()


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
	_show_form(false)
	add_child(_folder_screen)


func _close_folder_screen() -> void:
	_folder_screen.queue_free()
	_folder_screen = null
	_show_form(true)


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
				_notice.say("Vérification du compte…")
				_show_steps(1)
			elif _net.token != "" and _loading == null:
				_open_loading()
		"closed":
			_show_error("Serveur injoignable (%s) : %s\nVérifie l'adresse et que le serveur est lancé." % [_address.text.strip_edges(), _net.failure])
			_net = null
			_set_busy(false)


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
	_notice.say("Connexion à %s…" % address)
	_show_steps(0)
	_set_busy(true)


func _on_event(ev: Dictionary) -> void:
	if str(ev.get("t", "")) == Protocol.LOGIN_ERROR:
		_show_error(ErrorTexts.text(ev))
		_net.close()
		_net = null
		_set_busy(false)


func _show_error(text: String) -> void:
	_notice.say(text, "error")
	_show_steps(0)


## Logged in: the loading screen takes over (worlds, download), the game starts from there.
## The content API is on the game port + 1 (the server's default `--http-port`).
func _open_loading() -> void:
	var addr := WorldLoader.split_address(_address.text, 7777)
	var loader := WorldLoader.new(ContentClient.new(str(addr["host"]), int(addr["port"]) + 1, _net.token))
	_loading = WorldLoadScreen.new()
	_loading.setup(loader, _remembered_world)
	_loading.world_ready.connect(func(id: String) -> void: _start(_net, id, loader.content_of(id)))
	_loading.back.connect(_leave_loading)
	_show_form(false)
	add_child(_loading)


## "Retour" on the loading screen: the account session is closed, the form is back.
func _leave_loading() -> void:
	_loading.queue_free()
	_loading = null
	_net.close()
	_net = null
	_show_form(true)
	_set_busy(false)
	_notice.say("")
	_show_steps(0)


## Replaces this screen by the game; `backend` null = standalone (the client makes its own).
func _start(backend: NetBackend, world := "", content := "") -> void:
	var client: ClientSession = (load("res://scenes/client/client.tscn") as PackedScene).instantiate()
	client.world_id = world if world != "" else DEFAULT_WORLD # solo: the client's own default
	client.content_id = content # S.04b: an instance reads the content of another world
	client.backend = backend
	client.back_to_launch = backend != null
	if backend != null and world != "":
		client.zone_gate = _zone_gate(backend.token, world, content if content != "" else world)
	if world != "":
		_remembered_world = world
	_net = null
	get_parent().add_child(client)
	queue_free()


## Zones on demand (C.02d): a client of its own on the content API (game port + 1), same cache folder.
func _zone_gate(token: String, world: String, content: String) -> ZoneGate:
	var addr := WorldLoader.split_address(_address.text, 7777)
	var cc := ContentClient.new(str(addr["host"]), int(addr["port"]) + 1, token)
	var gate := ZoneGate.new(ZoneStreamer.new(cc, world, ContentSource.cache_dir_for(content, ContentSource.cache_base())))
	gate.background = _background.button_pressed
	return gate


func _set_busy(busy: bool) -> void:
	_solo.disabled = busy
	_join.disabled = busy
	_create.disabled = busy
	_address.editable = not busy
	_login.editable = not busy
	_password.editable = not busy


func _load_memory() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG) == OK:
		_address.text = str(cfg.get_value("server", "address", ""))
		_login.text = str(cfg.get_value("server", "login", ""))
		_remembered_world = str(cfg.get_value("server", "world", DEFAULT_WORLD))
		_background.button_pressed = bool(cfg.get_value("content", "background", false))


func _save_memory() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG) # keeps the other sections (the folder of the worlds, C.04)
	cfg.set_value("content", "background", _background.button_pressed)
	cfg.set_value("server", "address", _address.text.strip_edges())
	cfg.set_value("server", "login", _login.text.strip_edges())
	cfg.set_value("server", "world", _remembered_world) # kept: the loading screen updates it
	cfg.save(CONFIG) # best effort: a read-only profile just forgets


## Hides / shows the whole form (the card and its centring layer) while another screen is over it.
func _show_form(on: bool) -> void:
	_col.get_parent().get_parent().visible = on
