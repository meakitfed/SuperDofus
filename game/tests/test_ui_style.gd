## The visual language of the kit (lot U.03, docs/ui/STYLE.md): AA contrast of every text token on its
## surface, theme variations (primary / danger / tab buttons, title / heading / muted labels), a visible
## keyboard focus ring, the kit widgets built with them.
extends TestCase

const TEXTS := {"TEXT": UiStyle.TEXT, "TEXT_MUTED": UiStyle.TEXT_MUTED, "GOLD": UiStyle.GOLD, "HP": UiStyle.HP, "GOOD": UiStyle.GOOD,
		"BAD": UiStyle.BAD, "AP": UiStyle.AP, "MP": UiStyle.MP, "XP": UiStyle.XP}
const SURFACES := {"BG": UiStyle.BG, "BG_RAISED": UiStyle.BG_RAISED, "BG_HEADER": UiStyle.BG_HEADER, "BG_INSET": UiStyle.BG_INSET}


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()


func test_text_tokens_are_aa_on_every_surface() -> void:
	for sname: String in SURFACES:
		for tname: String in TEXTS:
			var c := UiStyle.contrast(TEXTS[tname], SURFACES[sname])
			check(c >= 4.5, "%s on %s: %.2f < 4.5" % [tname, sname, c])


func test_button_variants_are_aa() -> void:
	var th := ClientTheme.get_theme()
	for variant: String in ["Button", UiStyle.V_PRIMARY, UiStyle.V_DANGER, UiStyle.V_TAB]:
		for state in ["normal", "hover", "pressed"]:
			var box := th.get_stylebox(state, variant) as StyleBoxFlat
			var key := "font_color" if state == "normal" else "font_%s_color" % state
			var bg := box.bg_color if box.bg_color.a > 0.5 else UiStyle.BG
			var c := UiStyle.contrast(th.get_color(key, variant), bg)
			check(c >= 4.5, "%s %s text: %.2f" % [variant, state, c])


func test_disabled_text_is_readable_but_dimmer() -> void:
	check(UiStyle.contrast(UiStyle.TEXT_DISABLED, UiStyle.BG) >= 3.0, "disabled text stays legible (3:1)")
	check(UiStyle.contrast(UiStyle.TEXT_DISABLED, UiStyle.BG) < UiStyle.contrast(UiStyle.TEXT_MUTED, UiStyle.BG), "dimmer than muted")


func test_focus_ring_exists_on_interactive_controls() -> void:
	var th := ClientTheme.get_theme()
	for type: String in ["Button", UiStyle.V_PRIMARY, UiStyle.V_DANGER, UiStyle.V_TAB, "LineEdit"]:
		var f := th.get_stylebox("focus", type) as StyleBoxFlat
		check(f != null and not f.draw_center and f.border_width_left >= 2, "%s has a visible focus ring" % type)
		check(UiStyle.contrast(f.border_color, UiStyle.BG) >= 3.0, "%s ring is visible on the window (3:1)" % type)


func test_type_roles_use_the_dofus_fonts_and_the_scale() -> void:
	var th := ClientTheme.get_theme()
	check(th.get_font_size("font_size", UiStyle.V_TITLE) == UiStyle.FS_TITLE, "title size")
	check(th.get_font_size("font_size", UiStyle.V_HEADING) == UiStyle.FS_HEADING, "heading size")
	check(UiStyle.FS_TITLE > UiStyle.FS_HEADING and UiStyle.FS_HEADING > UiStyle.FS_BODY and UiStyle.FS_BODY > UiStyle.FS_SMALL, "scale is ordered")
	eq(str(UiStyle.title("x").theme_type_variation), UiStyle.V_TITLE)
	eq(str(UiStyle.muted("x").theme_type_variation), UiStyle.V_MUTED)


func test_kit_widgets_use_the_variations() -> void:
	var tabs := UiTabs.new()
	tabs.add_tab("A", Control.new())
	tabs.add_tab("B", Control.new())
	eq(tabs.current, 0)
	tabs.select(1)
	eq(tabs.current, 1)
	var b := tabs._buttons[1] as Button
	eq(str(b.theme_type_variation), UiStyle.V_TAB)
	check(b.button_pressed and not (tabs._buttons[0] as Button).button_pressed, "one tab pressed")
	var bar := UiBar.new(UiStyle.HP, 14)
	bar.set_values(30, 100, "30 / 100")
	near(bar.value, 30.0, 0.001, "value set at once without animation in headless")
	tabs.free()
	bar.free()


func test_the_text_scrim_is_dark_enough_for_a_modal() -> void:
	check(UiStyle.SCRIM.a >= 0.5, "the modal dims the screen")
