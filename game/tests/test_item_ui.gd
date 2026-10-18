## U.06: the item grids and tooltips: comparison of a bag item with the worn one (ItemCompare,
## UiTooltips.compare_for), the equipment's total bonus, the inventory search (accents ignored) and
## the level veil.
extends TestCase

const HAT_WORN := 8162 # level 1: [174, 1-10], [125, 1-5]
const HAT_BAG := 7177 # level 4: [174, 81-100], [752, 3-4]


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()


func test_value_of_an_effect_is_its_middle() -> void:
	near(ItemCompare.value([100, 8, 10, 0]), 9.0)
	near(ItemCompare.value([118, 7, 0, 0]), 7.0)
	near(ItemCompare.value([118, 0, 5, 0]), 5.0)


func test_deltas_list_what_changes() -> void:
	var d := ItemCompare.deltas([[118, 10, 0, 0], [125, 3, 0, 0]], [[118, 4, 0, 0], [126, 2, 0, 0]])
	eq(d.size(), 3)
	eq(d[0], [118, 6.0])
	eq(d[1], [125, 3.0])
	eq(d[2], [126, -2.0])
	eq(ItemCompare.deltas([[118, 4, 0, 0]], [[118, 4, 0, 0]]).size(), 0, "same effects: nothing")
	eq(ItemCompare.totals([[[118, 4, 0, 0]], [[118, 2, 0, 0]]])[118], 6.0)


func test_a_bag_item_compares_to_the_worn_one_in_its_slot() -> void:
	UiTooltips.worn_by_slot = {}
	eq(UiTooltips.compare_for(HAT_BAG, {"uid": 2, "id": HAT_BAG, "pos": -1}), {}, "nothing worn")
	var worn := {"uid": 1, "id": HAT_WORN, "pos": Equipment.HAT, "effects": [[125, 3, 0, 0]]}
	UiTooltips.worn_by_slot = {int(worn["pos"]): worn}
	eq(UiTooltips.compare_for(HAT_BAG, {"uid": 2, "id": HAT_BAG, "pos": -1}), worn)
	eq(UiTooltips.compare_for(HAT_WORN, worn), {}, "a worn item is not compared to itself")
	var tip := UiTooltips.item(HAT_BAG, 1, [[125, 5, 0, 0]], worn)
	var texts := PackedStringArray()
	for l in tip.find_children("", "Label", true, false):
		texts.append((l as Label).text)
	var all := "\n".join(texts)
	check(all.contains("Comparé à"), "comparison block")
	check(all.contains("+2"), "+2 on the shared effect: " + all)
	tip.free()
	UiTooltips.worn_by_slot = {}


func test_search_ignores_case_and_accents() -> void:
	eq(InventoryWindow.fold("Épée de Boisaille"), "epee de boisaille")
	check(InventoryWindow.fold("Épée").contains(InventoryWindow.fold("epee")))


func test_the_inventory_filters_by_name_and_veils_high_level_items() -> void:
	var win := InventoryWindow.new()
	win.setup_window(null)
	win.set_stats({"level": 1, "kamas": 0, "weight": 0, "max_weight": 1000})
	win.set_items([{"uid": 1, "id": HAT_WORN, "qty": 1, "pos": -1, "effects": []},
			{"uid": 2, "id": HAT_BAG, "qty": 1, "pos": -1, "effects": []}])
	win._fill()
	var slots := win._grids[0].get_children().filter(func(c: Node) -> bool: return (c as ItemSlot).item_id != 0 and not c.is_queued_for_deletion())
	eq(slots.size(), 2)
	for s: ItemSlot in slots:
		eq(s.locked, s.item_id == HAT_BAG, "only the level 4 hat is veiled at level 1")
	win._search.text = "zzzz"
	win._fill()
	eq(win._grids[0].get_children().filter(func(c: Node) -> bool: return (c as ItemSlot).item_id != 0 and not c.is_queued_for_deletion()).size(), 0)
	check(win._count.text.contains("Aucun"), win._count.text)
	win._search.text = ""
	win._fill()
	eq(win._count.text, "2 objets")
	win.free()
