## Harvested resources on the map (P2.05c): while an element has not grown back (interactive_state),
## its sprites are greyed and faded; they return to normal when it is ready. Only `self_modulate` is
## touched: the hover light (MapHover) works on `modulate`, the two add up.
## `sprites_at` = Callable(cell, gfx) -> Array of CanvasItem (DofusMapNode.elements_at).
class_name ResourceView
extends RefCounted

const DEPLETED := Color(0.5, 0.5, 0.5, 0.45)


static func tint(depleted: bool) -> Color:
	return DEPLETED if depleted else Color.WHITE


## Applies the state of one element (a Dictionary {cell, gfx} of MapData.interactive).
static func apply(sprites_at: Callable, element: Dictionary, depleted: bool) -> void:
	if element.is_empty():
		return
	for item: Variant in sprites_at.call(int(element["cell"]), int(element.get("gfx", 0))):
		if is_instance_valid(item):
			(item as CanvasItem).self_modulate = tint(depleted)


## Every element of the map, from the depleted ones (element id -> sim time they grow back).
static func apply_all(sprites_at: Callable, interactives: Array, depleted: Dictionary) -> void:
	for el: Dictionary in interactives:
		apply(sprites_at, el, depleted.has(int(el["e"])))
