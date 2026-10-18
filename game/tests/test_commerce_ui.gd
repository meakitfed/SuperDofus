## Trading windows (lot U.07): one quantity box, one search, one row look and the right confirmations
## in the shop, the bank, the workshop, the zaap, the quests, the contacts, the trade summary and
## the world map. The rules stay in the sim: here only what the windows show and when they ask first.
extends TestCase

const HAT_A := 8162
const HAT_B := 7177


class Sink:
	extends GameBackend
	var sent: Array = []

	func send(msg: Dictionary) -> void:
		sent.append(msg)


func _tree() -> SceneTree:
	return Engine.get_meta("test_tree") as SceneTree


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()


func _mounted(n: Node) -> Node:
	_tree().root.add_child(n)
	return n


func _asks(w: Node) -> Array:
	return w.get_children().filter(func(c: Node) -> bool: return c is UiConfirm and not c.is_queued_for_deletion())


## The children not waiting for queue_free (a refill queues the old rows and adds the new ones).
func _live(box: Node) -> Array:
	return box.get_children().filter(func(c: Node) -> bool: return not c.is_queued_for_deletion())


func _button(root: Node, text: String) -> Button:
	for n: Node in root.find_children("*", "Button", true, false):
		if (n as Button).text == text and not (n as Button).disabled:
			return n
	return null


func test_stepper_clamps_and_reports() -> void:
	var s := QtyStepper.new(1, 50)
	var seen := []
	s.value_changed.connect(func(v: float) -> void: seen.append(int(v)))
	s.value = 12
	s.value = 500
	eq(int(s.value), 50, "clamped to the max")
	s.value = -3
	eq(int(s.value), 1, "clamped to the min")
	eq(seen, [12, 50, 1])
	s.max_value = 20
	s.value = 30
	eq(int(s.value), 20)
	s.max_value = 10
	eq(int(s.value), 10, "a smaller max pulls the value down")
	s._edit.text = "1 5"
	s._commit()
	eq(int(s.value), 10, "typed text is read without its spaces then clamped")
	s._edit.text = "abc"
	s._commit()
	eq(int(s.value), 10, "garbage keeps the old value")
	s.free()


func test_search_ignores_case_and_accents() -> void:
	check(UiSearch.matches("Épée de Boisaille", "epee"))
	check(UiSearch.matches("Épée", "  ÉPÉE "))
	check(not UiSearch.matches("Chapeau", "epee"))
	check(UiSearch.matches("Chapeau", ""), "empty matches all")


func test_confirm_policy() -> void:
	check(not ConfirmPolicy.spend(200, 100000), "a small purchase is not asked")
	check(ConfirmPolicy.spend(ConfirmPolicy.BIG_SPEND, 10000000), "a big one always is")
	check(ConfirmPolicy.spend(3000, 5000), "more than half the purse")
	check(not ConfirmPolicy.spend(300, 400), "half the purse of a tiny sum is not worth a question")
	check(ConfirmPolicy.forge(30) and not ConfirmPolicy.forge(70))
	check(ConfirmPolicy.listing(20000) and not ConfirmPolicy.listing(500))


func test_shop_filters_and_confirms_a_big_purchase() -> void:
	var sink := Sink.new()
	var w := ShopWindow.new()
	_mounted(w)
	w.setup_window(sink)
	w.show_shop({"items": [{"item": HAT_A, "price": 20}, {"item": HAT_B, "price": 20000}], "sell_divisor": 10}, "Marchand",
			{"kamas": 100000, "weight": 0, "max_weight": 1000})
	eq(_live(w._buy_rows).size(), 2)
	var cheap := _button(_live(w._buy_rows)[0], "Acheter")
	cheap.pressed.emit()
	eq(sink.sent.size(), 1, "a small purchase goes out at once")
	eq(_asks(w).size(), 0)
	_button(_live(w._buy_rows)[1], "Acheter").pressed.emit()
	eq(sink.sent.size(), 1, "a big one waits for the answer")
	eq(_asks(w).size(), 1)
	for c: UiConfirm in _asks(w):
		c.free()
	w._search.text = "zzzz"
	w._fill()
	eq(_live(w._buy_rows).size(), 1, "one line: nothing matches")
	check(_live(w._buy_rows)[0] is Label)
	w._search.text = UiTooltips.item_name(HAT_A).substr(0, 4)
	w._fill()
	check(_live(w._buy_rows).any(func(n: Node) -> bool: return n is UiRow))
	w.free()


func test_bank_search_counts_and_kamas_buttons() -> void:
	var sink := Sink.new()
	var w := BankWindow.new()
	_mounted(w)
	w.setup_window(sink)
	w.show_bank({"items": [{"uid": 1, "id": HAT_A, "qty": 3, "effects": []}, {"uid": 2, "id": HAT_B, "qty": 1, "effects": []}],
			"kamas": 500, "cost": 0}, "Banquier", {"kamas": 1000, "weight": 0, "max_weight": 1000})
	check(w._bank_title.text.contains("(2)"), w._bank_title.text)
	w._kamas_amount.value = 800
	check(w._withdraw.disabled, "the chest holds only 500")
	check(not w._deposit.disabled, "the purse holds 1000")
	w._kamas_amount.value = 300
	check(not w._withdraw.disabled)
	w._search.text = "zzzz"
	w._fill()
	var filled := _live(w._bank_grid).filter(func(s: Node) -> bool: return (s as ItemSlot).item_id != 0)
	eq(filled.size(), 0, "the search hides the stacks")
	w.free()


func test_trade_summary_says_what_valider_commits_to() -> void:
	var mine := {"items": [{"uid": 1, "id": HAT_A, "qty": 2}], "kamas": 120, "ready": false}
	var theirs := {"items": [], "kamas": 0, "ready": true}
	eq(TradeWindow.summary_text(mine, theirs, "Bob"), "Vous donnez 2 objets et 120 K. Bob vous donne rien.")


func test_zaap_filters_sorts_and_greys_what_is_too_dear() -> void:
	var sink := Sink.new()
	var w := ZaapWindow.new()
	_mounted(w)
	w.setup_window(sink)
	var dests := [{"map": 10, "coords": [1, 1], "cost": 90, "name_id": 0}, {"map": 11, "coords": [2, 2], "cost": 10, "name_id": 0},
			{"map": 12, "coords": [3, 3], "cost": 500, "name_id": 0}]
	w.show_list({"zaap": 99, "save_map": 11, "destinations": dests}, 100)
	eq(_live(w._rows).size(), 3)
	w._by_price.button_pressed = true
	w._fill()
	var first: UiRow = _live(w._rows)[0]
	check(first.find_children("*", "Label", true, false).any(func(l: Label) -> bool: return l.text == "Sauvegarde"), "the save point is tagged, cheapest first")
	check(_live(w._rows)[2].find_children("*", "Button", true, false).all(func(b: Button) -> bool: return b.disabled), "500 K is out of reach")
	w._search.text = "map 10"
	w._fill()
	eq(_live(w._rows).size(), 1)
	w.free()


func test_contacts_filter_and_tab_counts() -> void:
	var sink := Sink.new()
	var w := ContactsWindow.new()
	_mounted(w)
	w.setup_window(sink)
	var friends := [{"name": "Zed", "online": false, "playing": "", "level": 0, "breed": -1},
			{"name": "Bob", "online": true, "playing": "Bob", "level": 12, "breed": 8}]
	w.set_lists(ProtocolContacts.contacts(friends, [], []))
	eq(_live(w._pages["friend"])[0].get_meta("contact"), "Bob", "who is online comes first")
	eq(w._tabs._buttons[0].text, "Amis (1/2)")
	w._search.text = "ze"
	w._fill()
	eq(_live(w._pages["friend"]).size(), 1)
	w.free()


func test_quests_search_and_abandon_asks_first() -> void:
	var sink := Sink.new()
	var w := QuestWindow.new()
	_mounted(w)
	w.setup_window(sink)
	var q := {"id": 7, "name_id": 0, "step": 0, "steps": 1, "objectives": [], "level": 1, "desc_id": 0, "step_name_id": 0}
	w.quest_started(q)
	var give_up := _button(w, "Abandonner")
	check(give_up != null)
	give_up.pressed.emit()
	eq(sink.sent.size(), 0, "nothing is sent before the answer")
	eq(_asks(w).size(), 1)
	for c: UiConfirm in _asks(w):
		c.free()
	w._search.text = "zzzz"
	w._fill()
	eq(_live(w._list).filter(func(n: Node) -> bool: return n is UiRow).size(), 0)
	w.free()


func test_world_map_labels_and_coordinates() -> void:
	var v := WorldMapView.new()
	v.player = Vector2i(3, 4)
	v.zaaps = [{"coords": [5, 6], "map": 1, "name_id": 0}]
	v.has_save = true
	v.save_coords = Vector2i(5, 6)
	eq(v.label_at(Vector2i(0, 0)), "0, 0")
	check(v.label_at(Vector2i(3, 4)).contains("Vous êtes ici"))
	var z := v.label_at(Vector2i(5, 6))
	check(z.contains("Zaap") and z.contains("Point de sauvegarde"), z)
	v.free()
	var w := WorldMapWindow.new()
	_mounted(w)
	w.setup_window()
	check(w.go_to("12, -3"))
	check(w.go_to("4 5"))
	check(not w.go_to("abc"))
	check(not w.go_to("1,2,3"))
	w.free()
