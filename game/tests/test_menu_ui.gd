## Menu screens (lot U.08): launch, world loading, character choice, folder, reconnection banner.
## The kit block UiMenu (card, notice, steps, disclosure), a launch screen that shows no error before
## an attempt, the loading screen's rows and progress, the banner's draining bar.
extends TestCase


func test_elide_path_keeps_both_ends() -> void:
	eq(UiMenu.elide_path("C:/short"), "C:/short")
	var long := "C:/Users/natha/AppData/Roaming/Godot/app_userdata/SuperDofus/worlds"
	var e := UiMenu.elide_path(long, 30)
	check(e.length() <= 30, str(e.length()))
	check(e.begins_with("C:/Users") and e.ends_with("/worlds") and e.contains("…"), e)


func test_notice_is_hidden_until_it_has_something_to_say() -> void:
	var n := UiMenu.notice()
	check(not n.visible)
	n.say("Boom", "error")
	check(n.visible and n.label.text == "Boom")
	n.say("")
	check(not n.visible)
	n.free()


func test_steps_mark_what_is_done() -> void:
	var row := UiMenu.steps(LaunchScreen.STEPS, 2)
	var texts: Array = row.get_children().filter(func(c: Node) -> bool: return c is Label and (c as Label).text != "›").map(func(c: Node) -> String: return (c as Label).text)
	eq(texts, ["✓ Serveur", "✓ Compte", "Monde", "Personnage"])
	row.free()


func test_disclosure_folds_its_content() -> void:
	var host := VBoxContainer.new()
	var content := Label.new()
	var b := UiMenu.disclosure(host, "Avancé", content)
	check(not content.visible)
	b.button_pressed = true
	check(content.visible and b.text.begins_with("▾"))
	host.free()


func test_launch_screen_shows_no_error_before_an_attempt() -> void:
	var tree := Engine.get_meta("test_tree") as SceneTree
	var s := LaunchScreen.new()
	tree.root.add_child(s)
	check(s._notice != null and not s._notice.visible, "nothing to report on opening: " + str(s._notice.label.text))
	s._address.text = "" # (the remembered one is the user's)
	s._join_server() # no address: nothing happens, still silent
	check(not s._notice.visible, "silent: " + s._notice.label.text)
	s._address.text = "127.0.0.1:1"
	s._join_server() # no login
	check(s._notice.visible and s._notice.label.text.contains("Identifiant"), "the missing field is said")
	s.free()


func test_launch_screen_notice_from_a_lost_session_is_an_error() -> void:
	var tree := Engine.get_meta("test_tree") as SceneTree
	var s := LaunchScreen.new()
	s.notice = "Session terminée"
	tree.root.add_child(s)
	check(s._notice.visible and s._notice.label.text == "Session terminée")
	s.free()


func test_banner_bar_drains_towards_the_next_attempt() -> void:
	var banner := ReconnectBanner.new()
	banner.wait(1, 4000)
	check(banner._bar.value < 0.2, "just started: nearly empty (%f)" % banner._bar.value)
	banner._until_ms = Time.get_ticks_msec() # the delay is over
	banner._refresh()
	check(banner._bar.value > 0.99, "time is up: full")
	banner.free()
