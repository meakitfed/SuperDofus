# Interface adaptative (recherche C)

Recherche faite par lecture du code (`UiStyle`, `UiWindow`, `ClientSession`, `PlayerHud`, `FightHud`, `MapFrame`, `MapView`, `project.godot`). **Aucune capture n'a été prise** : les chiffres de taille ci-dessous sont déduits du code, et la première étape de la mise en oeuvre est de mesurer (voir « Plan »). Les points marqués **[à vérifier]** sont des hypothèses sur Godot 4.7 à confirmer par un micro-test avant de s'y fier.

## 1. État actuel

- `project.godot` : viewport 1280x800, **aucun** réglage `display/window/stretch/*`. Donc mode `disabled` : un écran 2560x1440 donne un viewport de 2560x1440 pixels réels avec une UI de taille fixe, minuscule. Rien n'est mis à l'échelle.
- Disposition : tout est positionné à la main, **à chaque frame**, avec `get_viewport_rect().size` :
  - `PlayerHud._process` (barre de sorts centrée en bas, boîte perso en bas à gauche, donjon en haut au centre) ;
  - `FightHud._process` (timeline, messages, options) ;
  - `ClientSession._process` (minimap en haut à droite, tracker de quêtes, groupe, chat, bandeau) ;
  - `Toast._place`, `ReconnectBanner`, `ZoneIndicator`, tooltips de `MapHover` / `OtherPlayers` (clampés au viewport).
  Les positions fixes (`Vector2(12, 84)`, `Vector2(12, 230)`, `size.y - 110`…) ne dépendent pas du ratio.
- Caméra de la map : `ClientSession._fit_camera` (relancée sur `Viewport.size_changed` et `PlayerHud.band_changed`). Zoom = `min(vp.x / b.x, (vp.y - band) / b.y)` avec `b = MapGeometry.screen_bounds()` (~1333x924 px, ratio ~1,44 : la map est limitée par la hauteur en 16:9). Le centre est décalé vers le bas de `band/2` pour que la map reste au-dessus de la barre de sorts (`PlayerHud.reserved_bottom()`). C'est déjà l'esquisse de la « zone de jeu réservée », mais seulement pour le bas.
- Molette : `_camera.zoom *= 1.1` sans borne, et sans conserver le zoom d'ajustement : un redimensionnement de la fenêtre l'écrase.
- Clics map : `_unhandled_input` + `get_global_mouse_position()` (donc la transformation de la `Camera2D`) ; survols protégés par `gui_get_hovered_control() == null`. `PlayerHud` et `FightHud` sont plein écran en `MOUSE_FILTER_IGNORE` : seuls leurs enfants capturent la souris.
- Fenêtres : `UiWindow` mémorise un `[x, y]` **en pixels** dans `user://ui_layout.json`. `_clamp` garde 80 px de la fenêtre dans l'écran, mais seulement pendant le drag, à l'ouverture, et dans `_fit`. **Rien ne la re-clampe quand l'écran change** (redimensionnement, plein écran, autre moniteur). Position par défaut = `(vp - size) * default_anchor`. Une fenêtre plus grande que l'écran dépasse sans défilement.
- Le kit ne connaît ni échelle, ni marge de sécurité. Polices : `ClientTheme.default_font_size = 15`, plus 19 usages de tailles de police explicites ; ~90 `custom_minimum_size` en pixels de design.
- `client_session.gd` fait **739 lignes** (limite 800) : tout code de disposition ajouté doit sortir dans un nouveau fichier.

## 2. Approche recommandée

Principe : **concevoir pour un viewport virtuel de 1280x720 qui s'étend, et laisser Godot faire la mise à l'échelle ; ne plus faire de maths de pixels dans les écrans.**

### 2.1 Réglages Godot

```
[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/size/window_width_override=1600     ; taille de départ confortable
window/size/window_height_override=900
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
window/stretch/scale_mode="fractional"
window/dpi/allow_hidpi=true
```

- `canvas_items` (et non `viewport`) : le rendu est fait à la résolution réelle, donc les polices Lexend (dynamiques) et les `StyleBoxFlat` restent nets à 1,5x ou 2x. Le mode `viewport` rasterise en 1280x720 puis étire : texte flou, inacceptable.
- `expand` : le viewport virtuel garde la hauteur ou la largeur de base et **gagne de la place sur l'autre axe**. 16:9 : 1280x720 ; 21:9 : ~1680x720 ; 4:3 : 1280x960 ; 1:1 : 1280x1280. `get_viewport_rect().size` renvoie cette taille virtuelle, ce qui garde le code existant (centrage, clamp des tooltips, `Camera2D`) valide. La souris est convertie par le `Window` : `get_global_mouse_position()` et les clics map n'ont rien à changer **[à vérifier avec le test de la section 5]**.
- Facteur d'échelle effectif = `min(fenêtre.x / 1280, fenêtre.y / 720)` x `content_scale_factor`. 1920x1080 donne 1,5 ; 2560x1440 donne 2,0 ; 1024x768 donne 0,8 (police 15 rendue à 12 px réels).
- Base 720 plutôt que 800 : on conçoit pour le cas le plus contraint (portables 1366x768). Fixer `Window.min_size = (1024, 576)` (facteur plancher 0,8) pour éviter un texte illisible.

### 2.2 Échelle utilisateur et DPI

- L'échelle de `canvas_items` suit la **résolution**, pas la **densité**. Un écran 4K en 100 % Windows donne un facteur 3 : proportionnellement identique à 720p, donc tout est grand. Pour ce cas (et les petits écrans HiDPI) : un réglage **« Taille de l'interface »** 75 % / 100 % / 125 % / 150 %, appliqué avec `get_window().content_scale_factor = pref`.
- Défaut automatique : 1.0. Ne pas deviner par DPI au premier lancement tant qu'on n'a pas vu le résultat : sous Windows, `DisplayServer.screen_get_scale()` n'est pas fiable (macOS / Wayland oui) **[à vérifier]**, et `screen_get_dpi() / 96.0` est un repli. Si on l'utilise : `clampf(dpi / 96.0, 1.0, 2.0)` arrondi à 0,25, seulement quand l'utilisateur n'a rien choisi.
- Le facteur utilisateur **réduit** le viewport virtuel (125 % : 1024x576 virtuels depuis 1280x720). Les fenêtres et la barre doivent donc tenir à 1024x576 : c'est la contrainte de conception réelle.

### 2.3 Disposition : ancres et conteneurs, plus de `_process`

Le commentaire de `FightHud` (« a Control under a CanvasLayer has no parent rect to anchor to ») est probablement inexact : un `Control` dont le parent n'est pas un `Control` s'ancre sur `get_viewport().get_visible_rect()` **[à vérifier avec le test de la section 5]**. Si c'est confirmé :

- chaque HUD devient un arbre : racine `Control` en `PRESET_FULL_RECT` > `MarginContainer` (marges de sécurité) > conteneurs ; ou des enfants directs avec `set_anchors_and_offsets_preset(PRESET_BOTTOM_LEFT, PRESET_MODE_MINSIZE, 12)` ;
- coins : minimap + tracker en `PRESET_TOP_RIGHT` (dans un `VBoxContainer`, qui gère seul la visibilité de l'un des deux), groupe en `PRESET_TOP_LEFT`, chat en `PRESET_BOTTOM_LEFT` (au-dessus de la barre, voir 2.5), barre de sorts en `PRESET_CENTER_BOTTOM`, toast/bandeau en `PRESET_CENTER_TOP` ;
- on supprime les `position = …` par frame de `PlayerHud`, `FightHud` et `ClientSession`.

Sinon (l'ancrage sous `CanvasLayer` ne marche pas) : un `Control` racine `HudRoot` plein écran, redimensionné sur `size_changed`, sous lequel tout s'ancre ; même résultat.

### 2.4 Marges de sécurité

Desktop : aucune zone morte matérielle. Une constante `UiStyle.MARGIN = 12` (déjà le chiffre utilisé partout) plus une marge réglable `UiScale.safe_margin` (0 à 5 % de la largeur virtuelle, défaut 0) pour les téléviseurs et les bords d'écran coupés. Mobile/console plus tard : `DisplayServer.get_display_safe_area()` converti en coordonnées virtuelles via `get_window().get_final_transform()`. Les écrans de lancement et de choix de personnage passent par le même `MarginContainer`.

### 2.5 Zone de jeu réservée à la map

Généraliser `reserved_bottom()` en un rectangle : **`GameArea`**, un petit objet (`RefCounted` avec signal `changed`, créé par `ClientSession`, passé à `PlayerHud` / `FightHud`) qui contient les marges réservées (`top`, `bottom`, `left`, `right`) déclarées par les éléments du HUD qui ne doivent pas couvrir la map :

- `bottom` : la barre de sorts / la boîte perso (c'est `reserved_bottom()` actuel) ; en combat, la barre de combat ;
- `top` : la timeline de combat (aujourd'hui elle recouvre le haut de la map) ;
- `left` / `right` : 0 par défaut. En très large (21:9 : ~180 px de bande vide de chaque côté de la map à 720p), les panneaux flottants (chat, minimap, tracker) peuvent se placer dans ces bandes : `GameArea.side_free()` = `(vp.x - map_w_zoomé) / 2`, et un panneau n'y est « docké » que si sa largeur y tient. Optionnel, lot ultérieur.

`_fit_camera` devient : `rect = area.rect()` ; `z = min(rect.size.x / b.size.x, rect.size.y / b.size.y)` ; `camera.position = b.get_center() - (rect.get_center() - vp / 2) / z`. Les **fenêtres** (inventaire, etc.) restent flottantes **au-dessus** de la map, comme dans Dofus : elles ne réservent rien, sinon la map sauterait à chaque ouverture.

Zoom : mémoriser `_fit_zoom`, borner la molette à `[_fit_zoom * 0.6, _fit_zoom * 2.5]`, et à chaque `_fit_camera` conserver le rapport choisi par le joueur (`zoom = fit * user_ratio`) ; un raccourci « recentrer » (`Shortcuts`) remet le rapport à 1.

### 2.6 Fenêtres déplaçables qui restent dans l'écran

Dans `UiWindow` :

1. **Clamp dur** à la zone sûre (`UiScale.safe_rect`) : la barre de titre toujours entièrement visible, et la fenêtre entière tant qu'elle tient. Remplace « 80 px visibles ».
2. **Re-clamp sur changement d'écran** : `ClientSession` (déjà abonné à `size_changed`) appelle `UiWindow.relayout_all()`, qui replace toutes les fenêtres enregistrées (liste statique `_all`, ouvertes ou non). `_placed` ne doit plus être un « une seule fois » : re-clamp à chaque `open()`.
3. **Taille maximale** : `max_size = safe_rect.size`. Le corps passe dans un `ScrollContainer` (`scroll_body := true` par défaut, plafond vertical) pour les fenêtres hautes (banque, métiers, grimoire) à 1024x576.
4. **Positions mémorisées relatives** : au lieu de pixels, stocker la position en fraction de l'espace libre `pos / (vp - size)`. Format v2 : `{"v": 2, "windows": {"inventory": {"fx": 0.82, "fy": 0.12}}}`. Migration : un `[x, y]` v1 est lu comme des pixels puis clampé, réécrit en v2 au prochain drag. La fraction suit le ratio : une fenêtre ne « sort » pas après un passage de 16:9 à 4:3.
5. Une écriture par drag (déjà le cas), aucune si la valeur n'a pas changé.
6. « Réinitialiser les fenêtres » : `UiWindow.reset_layout()` existe déjà (utilisé par `client_shot` pour des captures déterministes) ; l'exposer dans l'écran d'options.

### 2.7 Points propres au rendu

- `MapFrame` : `blur_px = 0.9` est en pixels **réels** de l'écran (`SCREEN_PIXEL_SIZE`). À 2x, le flou est deux fois plus fin. Multiplier par `get_window().get_final_transform().get_scale().x`. Son rect (`grow(4000)`) couvre tous les zooms bornés ci-dessus.
- Textures Dofus raster (`ItemSlot`, `UiStyle.icon`) : lissées à 1,5x / 2x ; mettre un filtrage linéaire (avec mipmaps si réduites) sur les icônes. Pas de refonte des assets.
- Polices : Lexend est un TTF dynamique ; vérifier que le suréchantillonnage suit `canvas_items` **[à vérifier visuellement]**.

## 3. API du kit à créer ou changer

Nouveau `game/src/client/ui/ui_scale.gd` (`class_name UiScale`, statique, pas d'autoload) :

```gdscript
static func apply(window: Window) -> void                   # lit les préférences, règle content_scale_factor et min_size
static func set_ui_scale(window: Window, f: float) -> void  # 0.75..1.5, persiste (user://ui_settings.json)
static func ui_scale() -> float
static func safe_margin() -> float                          # en pixels virtuels
static func virtual_size(node: Node) -> Vector2             # = node.get_viewport_rect().size, point d'accès unique
static func safe_rect(node: Node) -> Rect2                  # virtual_size moins les marges
```

Nouveau `game/src/client/ui/game_area.gd` (`class_name GameArea`) : `reserve(owner: Object, side: int, px: float)` / `release(owner)`, `rect() -> Rect2`, `side_free(map_px: Vector2) -> Vector2`, signal `changed`. Remplace `PlayerHud.reserved_bottom()` et le signal `band_changed`.

Nouveau `game/src/client/ui/ui_dock.gd` (`class_name UiDock`) : `static func corner(c: Control, preset: Control.LayoutPreset, margin := UiStyle.MARGIN)` appliquant `set_anchors_and_offsets_preset`, pour ne pas répéter les presets partout.

`UiStyle` : `const MARGIN := 12`, `const GUTTER := 8`, et `static func fs(size: int)` (taille de police en unités de design, centralise les 19 appels `add_theme_font_size_override`). Couleurs et raccourcis restent dans le kit.

`UiWindow` : `safe_rect` à la place de `get_viewport_rect()`, `static var _all`, `static func relayout_all()`, `scroll_body`, `max_size`, layout v2 + migration, re-clamp à chaque `open()`. Signatures publiques inchangées (`setup`, `open`, `toggle`, `body`, `default_anchor`) : les ~20 fenêtres n'ont pas à bouger.

`Toast`, `ReconnectBanner`, `ZoneIndicator`, tooltips : `UiScale.safe_rect(self)` ou ancres. `Shortcuts` : action `recenter` (zoom de la map).

## 4. Fichiers touchés

| Fichier | Changement |
|---|---|
| `game/project.godot` | section `[display]` ci-dessus |
| `game/src/client/ui/ui_scale.gd` (nouveau) | échelle, marges, zone sûre |
| `game/src/client/ui/game_area.gd` (nouveau) | zone de jeu réservée |
| `game/src/client/ui/ui_dock.gd` (nouveau) | helper d'ancrage |
| `game/src/client/ui/ui_window.gd` | clamp, re-clamp, scroll, layout v2 |
| `game/src/client/ui/ui_style.gd` | `MARGIN`, `GUTTER`, `fs()` |
| `game/src/client/ui/toast.gd`, `client/reconnect_banner.gd`, `client/zone_indicator.gd` | ancres / zone sûre |
| `game/src/client/client_session.gd` | **extraire** la disposition (lignes ~205-222) dans `client/hud_layout.gd` ; `_fit_camera` via `GameArea` ; zoom borné. Fichier à 739 lignes : ne rien ajouter sans extraire |
| `game/src/client/player_hud.gd`, `client/fight/fight_hud.gd` | ancres, déclaration à `GameArea`, fin des `_process` de position |
| `game/src/client/map_frame.gd` | flou proportionnel au facteur d'échelle |
| `launch_screen.gd`, `character_select_screen.gd`, `character_creation_screen.gd`, `world_load_screen.gd`, `content_folder_screen.gd` | vérifier le centrage (ils utilisent déjà des presets) à 1024x576 et 21:9 |
| `bank_window.gd`, `craft_window.gd`, `characteristics_window.gd`, `spell_book_window.gd`, `achievements_window.gd`, `market_window.gd` | mesurer, tenir dans 1024x576 virtuels (via `scroll_body`) |
| `game/tools/client_shot.gd` | option `--size=LxH` (voir risques) |
| `docs/COMMANDES.md`, `docs/CARTE.md` | documenter `--size`, `UiScale`, `GameArea` |
| `game/tests/test_ui_layout.gd` (nouveau) | voir risques et plan |

## 5. Risques et parades

1. **Clic sur la map.** Avec `canvas_items`, l'entrée est transformée par le `Window`, et `get_global_mouse_position()` passe en plus par la `Camera2D` : aucune modification attendue. Risque réel : un conteneur de HUD ancré qui couvre la map avec `MOUSE_FILTER_STOP` (un `MarginContainer` ou `Container` plein écran capture la souris par défaut). Règle : tous les conteneurs de disposition en `MOUSE_FILTER_IGNORE`, seuls les widgets interactifs capturent. Test : pour chaque taille, vérifier `gui_get_hovered_control() == null` au centre de la map (c'est ce qui garde `MapHover` / `OtherPlayers`), et qu'un clic sur une cellule et sur une flèche de sortie donne la bonne cellule via `MapGeometry.screen_to_cell`.
2. **Échelle fractionnaire.** `scale_mode="fractional"` sur des tailles non entières décale légèrement le rendu par rapport à la souris sub-pixel : tolérance d'1 px dans les tests de clic.
3. **Captures.** `client_shot` sauve `root.get_texture().get_image()` : avec `canvas_items`, c'est à la **taille réelle de la fenêtre**, pas 1280x720. Il faut `--size=LxH` qui règle `get_window().size` puis attend 2 frames avant la première commande. `root.warp_mouse(root.get_canvas_transform() * pos)` (lignes ~159-181) mélange coordonnées virtuelles et réelles **[à vérifier]**, probablement à convertir par `get_final_transform()`. Les captures de référence existantes changent de format : régénérer celles qui sont concernées, garder 1280x720 par défaut dans les outils. Écrire les captures dans le scratchpad (disque C: presque plein), pas dans le dépôt.
4. **Tests existants.** Les tests headless tournent à la taille du projet (1280x800 aujourd'hui, 1280x720 demain) : les tests qui lisent des positions de HUD ou `get_viewport_rect` (à chercher : `Grep` sur `get_viewport_rect`, `reserved_bottom`, `band_changed`, `ui_layout`) peuvent bouger de 80 px en hauteur. Parade : assertions relatives (« dans le viewport », « ne chevauche pas la barre »), et `PlayerHud.reserved_bottom` gardé en alias déprécié le temps de la transition. `test_architecture` n'est pas concerné (pas de `sim/`), mais la limite de 800 lignes l'est (`client_session.gd` 739, `fight_view.gd` 796).
5. **Layout sauvegardé.** Un `ui_layout.json` v1 existe chez l'utilisateur : migration silencieuse, jamais d'erreur si le fichier est invalide.
6. **Boucle de redimensionnement.** `size_changed` > `_fit_camera` > `band_changed` > `_fit_camera` : `GameArea.reserve` ne signale que si la valeur change.
7. **Lisibilité à petite échelle.** Facteur 0,8 (1024x768) cumulé à une interface à 75 % donne 0,6 : borner le produit à >= 0,75 dans `UiScale.apply`.
8. **Ordre d'initialisation.** `UiWindow._restore_position` est différé ; sans re-clamp à l'ouverture, une fenêtre ouverte avant la première frame peut prendre la mauvaise taille.
9. **Multi-moniteurs / DPI mixtes.** Vérifier le déplacement de la fenêtre entre deux écrans ; le `relayout_all` sur `size_changed` couvre la position.

## 6. Plan de mise en oeuvre (lots suggérés)

1. **Mesurer + micro-tests** (aucun changement de comportement) : `--size` dans `client_shot`, captures du HUD actuel à 1280x720, 1920x1080, 2560x1440, 1024x768 et 1280x1280 (carré), toutes relues avec l'outil Read ; trancher les points « à vérifier » (ancrage sous `CanvasLayer`, `warp_mouse`, suréchantillonnage des polices).
2. **Stretch + `UiScale`** : `project.godot`, `UiScale.apply`, `min_size`, borne de zoom ; corriger ce que les captures montrent.
3. **`UiWindow`** : clamp, re-clamp, scroll, layout v2 (+ `test_ui_layout.gd` : fenêtres dans l'écran pour 5 tailles, migration v1).
4. **HUD en ancres + `GameArea`** : extraire `hud_layout.gd`, supprimer les positions par frame, caméra via `GameArea`.
5. **Réglages utilisateur** (taille de l'interface, marge, réinitialiser les fenêtres) dans un écran d'options.

Critère de fin : sur les cinq tailles, aucune fenêtre ni élément de HUD hors écran, la map entière visible au-dessus de la barre, clics map et flèches de sortie fonctionnels, captures relues.
