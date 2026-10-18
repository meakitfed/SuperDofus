# Interface de Dofus 3 : disposition de l'écran et lisibilité en combat

Recherche A (lecture seule). Tout ce qui est marqué **[VÉRIFIÉ]** vient d'un fichier du client Dofus 3 installé (bundles Unity, code natif décompilé, assemblies Cpp2IL). **[DÉDUIT]** = conséquence logique d'un fait vérifié. **[NON VÉRIFIÉ]** = hypothèse ou souvenir, à ne pas coder comme une règle sourcée (à marquer `APPROX(<lot>)`).

Rien du contenu Ankama n'est recopié ici : seulement des noms, des nombres et des règles.

## 1. En dix lignes

1. L'interface est un **panneau UI Toolkit plein écran en `ScreenSpaceOverlay`**, dessiné au-dessus du rendu du monde. Les fenêtres (timeline, barre de sorts, chat, jauges...) sont des `MagneticDragWindow` **flottantes et déplaçables**, positionnées en `position: absolute`.
2. La **caméra du monde n'est jamais recadrée dans une « zone libre » entre les barres d'interface**. Un seul code modifie `Camera.rect` (`fyd.bjbw`) et il ne dépend que de la taille de la fenêtre : il **bride le rapport d'aspect de la vue entre 4:3 et 1935:1010,5 (≈1,915)** avec des bandes noires dessinées par l'UI. Entre ces deux rapports la caméra occupe toute la fenêtre.
3. La caméra est orthographique, `orthographicSize` = **500** (donc 1000 unités monde de haut, toujours), fixé par `MapRenderer.HandleMapMetadataLoaded`. L'échelle de la map est donc **proportionnelle à la hauteur de la vue**, pas à la place laissée par l'UI. Une map (1247 x 881,5 unités) occupe ~88 % de la hauteur.
4. Conséquence **[DÉDUIT]** : le bas de la map passe **sous** la barre de sorts et les autres fenêtres. Dofus compense par la mobilité des fenêtres (aimantation, verrouillage, **préréglages d'interface dont un préréglage dédié au combat**), pas par un recadrage.
5. Échelle de l'UI : le panneau principal est en **`ConstantPhysicalSize` (dpi de référence 96)** : l'UI ne suit pas la résolution. Il existe un second panneau « petit écran » (`ScaleWithScreenSize`, référence 1280 x 1024, correspondance sur la hauteur). Une option « échelle de l'interface » en pourcentage s'ajoute, et 4 tailles de texte (small, medium, large, xlarge).
6. En combat : timeline (déplaçable, 4 orientations, tuiles 78 ou 106 px), widget « fin de tour » (228 x 144), barre de sorts (12 emplacements de 51 px par ligne, jusqu'à 3 lignes, 12 pages), orbe PV / PA / PM (164 x 144), infobulle de combattant dont l'emplacement est choisi par le joueur.
7. Lisibilité : options et raccourcis **`transparencyMode`**, **`toggleDematerialization`**, **mode créature**, `toggleShowUI`, `showGrid`, `showAllNames`, `highlightInteractiveElements`, barres de vie (toujours / au maintien / masquées quand pleines), aperçu des dégâts et du déplacement. Leur effet exact n'est **pas** lu dans le code (voir §8).
8. Aucune règle de « contour ou transparence d'un personnage caché derrière un décor » n'a été trouvée. Le rendu a bien une passe de contour (`OutlinePrepass`, `Animator2DRenderer.SetOutline`) mais son usage n'est pas relié.
9. Infobulles : placement autour de la cible avec **détection de collisions entre infobulles**, flèche orientée, possibilité de les épingler, suivi de la cible du monde (`SyncZoom`).
10. Le client SuperDofus actuel fait l'inverse sur un point : `ClientSession._fit_camera` **réserve une bande** pour la barre de sorts (`player_hud.gd:179`, commentaire « like the Dofus banner that never covers the map », **non sourcé et contredit par ce qui précède**).

## 2. Méthode (reproductible, rien n'est commité)

| Source | Comment |
|---|---|
| Disposition, tailles, classes USS | `uielements_assets_all.bundle` (906 chemins `Assets/UI/...`). Chaque `.uxml` est un `VisualTreeAsset` lisible avec UnityPy (`read_typetree()`, `references.RefIds` = arbre d'éléments, `inlineSheet` = styles en ligne) ; chaque `.uss` est un `StyleSheet` (`m_Rules`, `m_ComplexSelectors`). La version Unity vient de `detect_unity_version` (`tools/extractor/extract.py`). |
| Noms des propriétés de style | les `m_Id` sont des `StylePropertyId` : table lue dans `MelonLoader/Il2CppAssemblies/UnityEngine.UIElementsModule.dll` (champs constants de l'enum, par exemple 131105 = `Width`). |
| Valeurs des énumérations Unity | même DLL : `PanelScaleMode {0 ConstantPixelSize, 1 ConstantPhysicalSize, 2 ScaleWithScreenSize}`, `PanelScreenMatchMode {0 MatchWidthOrHeight, 1 Shrink, 2 Expand}`. Attention : l'ordre n'est pas celui de `CanvasScaler`. |
| Caméra, panneaux | `worldassets_assets_all.bundle` (`MainRenderCamera.prefab`, `RootUI.prefab`) et `uielements_assets_all.bundle` (`PanelSettings.asset`, `SmallScreenPanelSettings.asset`). |
| Code natif | `python tools/client_code/client_code.py decomp <fichier> <RVA...>` et `xref <RVA>` (noms dans `%LOCALAPPDATA%/SuperDofus/client_code/names.tsv`, chaînes dans `strings.tsv`). Les classes principales sont obfuscatées (`fyd`, `sk`, `ebj`) mais les espaces de noms `Core.UILogic.*` et `Core.Engine.*` sont lisibles. Le code décompilé est de l'Ankama : ne jamais le copier dans le dépôt. |
| Raccourcis | `inputactionassets_assets_all.bundle` : 391 références d'actions (noms seulement ; **les touches par défaut ne sont pas dans ce bundle**). |
| Textures | déjà extraites par `tools/extractor/ui.py` (`Content/UI/darkStone/texture/hud/*`, 35 fichiers dont `background_timeline_{blue,red}_{normal,dark,over}`, `icon_hud_creature_mode*`, `icon_arrow_timeline_{horizontal,vertical}`). |

Piège de lecture : dans `fyd`, trois fonctions sœurs (`eie`, `ghh`, `irh`) recopient `bjbw` avec des constantes absurdes (-3733, 7921, 9386...) : code mort d'obfuscation. Seule `bjbw` (constantes propres, 1,0 et 0,5) est appelée par `CheckCameraRatio`.

## 3. Constats sourcés

### 3.1 Caméra et zone de jeu

| # | Constat | Source |
|---|---|---|
| C1 | Une seule caméra de rendu : `MainRenderCamera`, **orthographique**, `m_NormalizedViewPortRect = (0, 0, 1, 1)`, `orthographic size = 500` par défaut, near -1000, far 5000, HDR, post-traitement actif (`m_RenderPostProcessing = 1`), pas de MSAA par défaut (`m_Antialiasing = 0`). | `worldassets_assets_all.bundle`, `Assets/Content/Prefabs/Camera/MainRenderCamera.prefab` (objets Camera et UniversalAdditionalCameraData) |
| C2 | La caméra est instanciée par Addressables depuis ce prefab ; `ebj.CreateCamera` récupère le composant `Camera` et son `cullingMask`. | RVA `0x15dd470` (`ebj/<CreateCamera>d__11.MoveNext`), chaîne `Assets/Content/Prefabs/Camera/MainRenderCamera.prefab` |
| C3 | Après chargement des métadonnées d'une map, `MapRenderer` fixe `orthographicSize` à **500.0** (`0x43fa0000`). Il passe d'abord par 688.0 (`0x442c0000`) le temps de calculer des matrices vue-projection (pour le shader de map), puis revient à 500. | RVA `0x1d585e0` (`MapRenderer/<HandleMapMetadataLoaded>d__69.MoveNext`) ; appels à `Camera.set_orthographicSize` aux xref `0x1d59628` et `0x1d597c1` |
| C4 | `Camera.set_rect` n'est appelé que par `fyd.bjbw` (et ses trois doublons morts), par le split-screen de l'Input System et par DOTween (`DORect`, non utilisé ici). Personne d'autre ne touche `rect` ni `pixelRect`. | `client_code.py xref 0x4C93B50` et `0x4C93990` |
| C5 | `fyd.bjbw` (RVA `0x1d89450`) : constantes du constructeur `fyd..ctor` (`0x1d87e10`) : **1935,0 / 1010,5** et **4,0 / 3,0**. Algorithme : `A = largeur / hauteur` de l'écran ; `cible = clamp(A, 4/3, 1935/1010,5)` (l'interpolation `t` écrite dans le code est l'identité du clamp) ; `f = A / cible` ; si `f < 1` : `rect = (0, (1-f)/2, 1, f)` (bandes en haut et en bas) ; sinon `rect = ((1-1/f)/2, 0, 1/f, 1)` (bandes à gauche et à droite). | RVA `0x1d89450`, `0x1d87e10` |
| C6 | `CheckCameraRatio` attend une frame (`UniTask.NextFrame`) puis appelle `bjbw` (le rect de la caméra) **et** `bjbv`. `bjbv` lit `Screen.width/height`, `Camera.scaledPixelWidth/Height` et fixe le style (longueurs) de **4 `VisualElement`** : **[DÉDUIT]** ce sont les bandes noires, dessinées par l'UI dans les zones que la caméra ne couvre pas (le code ne nomme pas les éléments). | RVA `0x1d81e20` (`fyd/<CheckCameraRatio>d__10.MoveNext`), `0x1d88f90` (`fyd.bjbv`) |
| C7 | Le panneau UI est en `m_RenderMode = 0` (`ScreenSpaceOverlay`) : il recouvre toute la fenêtre, **indépendamment** du rect de la caméra. `RootUI` (UIDocument) a `m_SortingOrder = -1`, `m_WorldSpaceSizeMode = 1`, taille 1920 x 1080 (champs ignorés hors `WorldSpace`). | `PanelSettings.asset` (`m_RenderMode`), `RootUI.prefab` |
| C8 | Un zoom caméra existe : tween `DOOrthoSize`, `ContextMenuFactory.WorldMenuMaker.OnZoom` / `OnResetZoom` (menu contextuel du monde), `NpcDialog.OnMapZoomMessage` (zoom lors d'un dialogue), `TooltipRoot.keepOnZoom` et `BaseTooltipBuilder.SyncZoom` (les infobulles de monde suivent le zoom). Bornes du zoom : non lues. | `names.tsv` (adresses `0x14722F0`, `0x148F9B0`, `0x148F740`, `0x27523F0`, `0x2D49F20`, `0x35B7C90`) |
| C9 | Le `Listener` audio de la caméra a `m_minZoomZ = -20` et `m_maxZoomZ = -500` : ce sont des bornes de volume, pas de zoom caméra. | `MainRenderCamera.prefab` |

### 3.2 Panneau UI, échelle et résolutions

| # | Constat | Source |
|---|---|---|
| S1 | Panneau principal `PanelSettings` (celui que `RootUI` référence, `PathID -5578671114949769200`) : `m_ScaleMode = 1` = **`ConstantPhysicalSize`**, `m_ReferenceDpi = 96`, `m_FallbackDpi = 96`, `m_Scale = 1.0`. Les champs `m_ReferenceResolution = 1920 x 1080`, `m_ScreenMatchMode = 2` (`Expand`) et `m_Match = 1` sont stockés mais **inactifs** dans ce mode. Dynamic atlas 64..4096. | `uielements_assets_all.bundle`, `Assets/UI/PanelSettings.asset` |
| S2 | `SmallScreenPanelSettings` : `m_ScaleMode = 2` = **`ScaleWithScreenSize`**, référence **1280 x 1024**, `m_ScreenMatchMode = 0` (`MatchWidthOrHeight`), `m_Match = 1.0` (donc on suit la **hauteur** : facteur = hauteur / 1024). Ce qui l'active n'est pas lu. | `Assets/UI/SmallScreenPanelSettings.asset` |
| S3 | L'écran de pause crée une catégorie « Interface » avec : `lockUI`, `snappingDistance`, `snappingGap`, `resetUiPositions`, et une catégorie accessibilité avec `uiScale` (liste « N % »), `useDefaultScale`, `textSize` (small / medium / large), taille des icônes de bannière, thème. La liste d'échelles dépend de la résolution (`OnResolutionChanged` appelle `UpdateScaleList`). | RVA `0x2a3d6a0` (`CreateAccessibilityCategory`), `0x2a4aaa0` (`UpdateScaleList`), `0x2a48c80` (`OnUseDefaultScaleUpdated`), `0x2a3d0f0` (`CheckDisplayStateScaleOption`), `0x2a48c70` (`OnResolutionChanged`) ; chaînes `ui.option.uiScale`, `ui.option.useDefaultScale`, `{0} %` |
| S4 | Résolutions : `ScreenManagerUtility.GetWindowedResolutionList` / `GetExclusiveFullScreenResolutionList` / `TryGetResolutionRatioIndex` (liste par moniteur, groupée par rapport) ; `WindowSizeConstraints.MinSize` ; `OptionGeneralUi.CreateDisplayCategory` : résolution, mode (plein écran / fenêtré), V-sync, limite d'images (30 à 360 ou illimité), DirectX 11 / 12, anticrénelage (aucun, FXAA, SMAA, MSAA 1x..8x), qualité, HDR, **échelle de rendu**. | `names.tsv` (`Ankama.ScreenManagement.*`) ; chaînes `ui.option.performance.renderScale`, `ui.option.displayResolution` |
| S5 | Les classes USS `smallUI` (variante réduite d'un widget) existent : orbe PV `146 x 96` au lieu de `164 x 144`, disque de vie 86 px au lieu de 106, ornements masqués. | `Assets/UI/PersistentMenu/characterInformations.uss` |
| S6 | Texte : 4 jeux de tailles `smallFont`, `mediumFont`, `largeFont`, `xlargeFont` (jetons `textShort_*`, `title_*`, `label_*`...). Exemples pour `textShort_mediumRegular` : 12 / 14 / 16 / 18 px (interligne 14 / 18 / 20 / 22) ; `title_medium` : 15 / 18 / 22 / 25 px. Les thèmes de police existent en 11 variantes de faction (Standard, Bonta, Brakmar, Gold and Steel, Tribute, Belladone, Unicorn, Emerald Mine, Sufokia, Pandala, Wabbit) x 3 tailles. | `Assets/UI/Figma/USS/globalStyleFontSize.uss`, `Assets/UI/DofusUISettings.asset` |

### 3.3 Fenêtres libres, aimantation et préréglages

| # | Constat | Source |
|---|---|---|
| W1 | Presque toutes les fenêtres de jeu sont des `Core.UILogic.Components.MagneticDragWindow` avec `drag-position`, `is-magnetic`, `is-magnetic-for-others`, `allow-snap-preview`, `x/y-magnetic-offset`, `use-boundingBox-Boundary`, `corner-resizable`, `horizontal-resizable`, `vertical-resizable`, `has-header`, `header-icon-left` (réduire / étendre), `header-style` (vertical possible). | `FightTimeline.uxml`, `actionBar.uxml`, `chatview.uxml`, `partyDisplay.uxml`, `widgetProgressGauge.uxml`, `EndTurnWidget.uxml`, `FightScoreUi.uxml`, `characterInformations.uxml` ; méthodes `MagneticDragWindow::get_isMagnetic`... (`0x2D2C340` et suivantes) |
| W2 | Options d'aimantation : `lockUI` (verrouiller), `snappingDistance`, `snappingGap`, raccourcis d'aimantation (`snappingShortcuts`, `snappingMoveInfo`, `snappingResizeInfo`, `snappingNoSnapInfo`), `resetUiPositions`. | chaînes `ui.option.lockUI`, `ui.option.snapping*`, `ui.option.resetUiPositions` ; RVA `0x2a457b0` (`OptionGeneralUi.CreateInterfaceCategory`) |
| W3 | **Préréglages d'interface** : `UiPresetOptionsContainer` (`Core.Engine.Options.OptionsContainers`) : `AddPreset`, `RemovePreset`, `EditPreset`, `ApplyPreset`, **`AssignFightPreset` / `UnsetFightPreset`**, propriétés `isUsingFightPreset`, `hasFightPreset`, `currentContextualPreset`. Par préréglage et par identifiant de fenêtre, le client sauvegarde **position** (`SaveUiPositionById`), **dimensions** (`SaveUiDimensionById`) et **état d'en-tête plié / déplié** (`SaveUiHeaderStateById`) ; `ClearSavedUiById` / `ClearAllSavedUi`. Les fenêtres de combat reçoivent `OnRefreshPreset` (`UITimeline`, `BuffsFightUI`, `UIActionBar`, `ChatView`, `CharacterInformation`, `WidgetProgressGaugeUi`, `QuestList`, fenêtres d'esclaves). Le menu du widget manager propose « créer / éditer un préréglage ». | RVA `0x1DF1DA0` .. `0x1DF4AF0` (`UiPresetOptionsContainer`), `0x29EB5E0` (`UITimeline.OnRefreshPreset`), `0x153DB60` (`WidgetManager.OnCreateNewPresetClicked`) |
| W4 | **Raccourci pour masquer toute l'interface** : action `Common/toggleShowUI`. Autres : `Common/closeUI`, `Menu/showFightPositions`, `Option/showGrid`, `Option/showCoord`, `Option/showAllNames`, `Option/showEntitiesTooltips`. | `inputactionassets_assets_all.bundle` |

### 3.4 Positions et tailles par défaut (repère 1920 x 1080 d'édition)

Les `left` / `top` ci-dessous sont ceux écrits dans les UXML : **valeurs d'authoring**. Ils servent de repère de proportion ; le client les remplace par le préréglage actif (voir §8).

| Fenêtre | Position / taille | Remarques |
|---|---|---|
| Barre de sorts (`ActionBar`) | `left 636, top 990`, largeur **706**, `max-height 724` ; grille `fixed-row-count 1`, `fixed-column-count 12`, `item-size 51`, `slot-size small`, `gap-slot 2`, marge intérieure 8, `gap-value 4` | `drag-position=Right`, ni redimensionnable. Étiquettes de ligne 1, 2, 3 (16 x 44 px), boutons page précédente / suivante, bouton de type. Variante `#vertical` (grille 624 px de haut, colonne). 36 raccourcis `QuickSlot/s1..s36`, 12 pages `page1..12`. |
| Timeline de combat (`fightTimelineMagneticDragWindow`) | `left 140, top 223` ; `vertical-resizable=false`, `corner-resizable=false`, `header-style=vertical`, `xMagneticOffset 50`, `y-magnetic-offset 20`, `drag-position=Custom` | contient : compteurs (tour courant, vague, prochaine vague) puis `ScrollView` des combattants (défilement horizontal, ascenseur horizontal visible). |
| Widget fin de tour (`EndTurnWidget`) | **228 x 144** (min 224 x 144), `corner-resizable=false`, `horizontal-resizable=false`, `drag-position=Custom` | bouton principal 208 x 62, compteur de secondes 120 x 48 au-dessus, nombre de tours en bas à gauche, jauge de temps 6 px de haut au-dessus, 6 bascules 32 x 32 en bas (ping permanent, désigner une case, interdire les spectateurs, verrouiller le combat, verrouiller le groupe, quitter). |
| Orbe PV / PA / PM (`CharacterInformations`) | fenêtre **164 x 144** (min 164 x 130), redimensionnable ; disque de vie 106 x 106 ; PA / PM 50 x 50 (PI 38 x 34) ; version `smallUI` 146 x 96 | texte de caractéristiques : `title_large`, contour 1 px, gras. Sert aussi hors combat. |
| Jauge d'XP (`widgetProgressGauge`) | `left 546, top 860`, **566 x 34** (min 240 x 34), sans en-tête | |
| Chat (`Chat`) | ancré `left 0, bottom 0`, **400 x 244** (min 160 x 120), saisie 35 px de haut | un `bottom 35` pour la pastille « nouveaux messages ». |
| Menu de bannière (`BannerMenu`) | `right 0, top 55`, 120 x 115, grille de boutons `item-size 36` | `ctr_moreBtn` pour les boutons en trop. |
| Barre de widgets (`widgetManager`) | 200 x 80, boutons secondaires 12 + réglages + réduire (bascules : chasse au trésor, brèche, groupe, altération, XP, quêtes, carte, émotes, chat, personnage, sorts, modules, inventaire) | hauteur 40, coins bas arrondis 4. |
| Groupe (`PartyDisplay`) | `top 300`, 80 px de large, 8 membres, en-tête « GROUPE » | |
| Info de map (`mapInfo`) | 500 x 110, barre d'icônes en haut à gauche : carte des combats, surbrillance, info, spectateur, **bascule mode créature**, havre-sac, guilde, maison, quitter | |
| Annonce de tour (`newTurnStartUI`) | texte centré, `scale 0.55`, `top -140` | |
| Portrait de début de tour (`playerTurnStartUI`) | 227 px de large, fond noir teinté | |
| Score (`FightScoreUi`) | 268 x 64, haut centre, non aimanté, sans en-tête | |
| Latence (`LatencyUI`) | sablier 40 x 40, marge 20, coin haut droit | |
| Infobulle de combattant (`FighterInfoPlacementUI`) | **706** de large, positionnée par le joueur : voir §3.6 | |
| Choix de sort / butin (`spellPicker`) | fenêtre modale centrée sur fond noir à 50 % | |

### 3.5 Timeline de combat (`Core.UILogic.Fight.UITimeline`, `TimelineFighterUI`)

| # | Constat | Source |
|---|---|---|
| T1 | **4 orientations** : de gauche à droite, de droite à gauche, de haut en bas, de bas en haut (`OnClick...Timeline`, `SetTimelineOrientation`). Les valeurs 0 et 1 sont horizontales, 2 et 3 verticales (test `orientation < 2`). L'orientation par défaut n'est pas lue. | RVA `0x29E9D40`, `0x29EA170`, `0x29EA000`, `0x29E9EA0` ; `0x29E9180` |
| T2 | **Deux tailles de tuile** : `m_tileSize == 1` => « petits portraits », sinon grands. La longueur minimale de la fenêtre est `tuile + marges` avec **tuile = 78 px (petit) ou 106 px (grand)**, et la classe USS `smallTile` est posée sur la fenêtre. | `UITimeline.GetMinSize` RVA `0x29e9510` ; `SetTilesSize` RVA `0x29efb90` ; chaînes `ui.option.timeline.smallPortraits` / `BigPortraits` |
| T3 | **Taille maximale = min(contenu, largeur de l'écran)** (horizontale) ou `min(contenu, hauteur de l'écran)` (verticale) : la timeline ne dépasse jamais la fenêtre. Option « adapter la taille automatiquement » (`OnOptionAdaptAutomaticallyChanged`), défilement qui **suit le combattant en jeu** (`OnTimelineFollowPlayingEntity`, `RefreshTimelineFollow`), `ForceKeepInScreen`, plier / déplier (`OnToggleFold`, `RefreshFoldSizing`). | `GetMaxSize` RVA `0x29e91b0`, `0x29e8f20`, `0x29eb470` |
| T4 | Options : afficher les morts, afficher les invocations, ordre des combattants, jauges de vie à gauche ou à droite, vagues (`SetWaveDisplayAndDirection`). | chaînes `ui.option.showDeadFighters`, `showSummonedFighters`, `timeline.gaugesOnLeft/Right`, `ui.option.orderFighters` |
| T5 | Une tuile (`timelineFighter.uxml`) : fond 9-tranches (8 px, échelle 0,8) teinté par équipe (textures `hud/background_timeline_{blue,red,grey}_{normal,dark,over}`), portrait ou sprite du monstre, **jauge de vie verticale** (rouge 229,33,64), **bouclier** (violet 118,67,190), **seuil** (orange 236,173,85), numéro d'ordre en `textShort_largeRegular` avec ombre (0, 2 px, noir 50 %), masque de temps blanc 30 %, icône d'invocation 20 x 20, pastille de tour supplémentaire, icône de ping 80 x 80, tour courant décalé (`SetShiftedState`, `CreateShiftTween`). | `Assets/UI/Fight/timeline/timelineFighter.uxml` |
| T6 | Interactions d'une tuile : survol (`SetHover`, `OnRollOver`) => met en évidence le combattant sur la map ; clic gauche sélectionne ; clic droit => menu contextuel ; infobulle de classe. | `TimelineFighterUI::*` |

### 3.6 Infobulles et aperçus

| # | Constat | Source |
|---|---|---|
| I1 | Placement : `TooltipUtils.GeneratePositionAroundTarget` (variantes d'ancre précalculées `s_allAnchorVariantsCachedForTooltipPlacement`), `CountTooltipCollisions`, `GeneratePositionOffsetOnCollision`, `TooltipRoot.HandleTooltipCollision` / `RegisterCollisionCheck` : une infobulle **évite de recouvrir les autres** ; `TooltipArrow.direction` oriente la flèche. | `names.tsv` (`Core.UILogic.Components.Tooltips.*`) |
| I2 | `TooltipSyncHandler` (`StartSync` / `StopSync` / `Tick`) : l'infobulle d'une entité suit sa position écran ; `keepOnZoom`. | idem |
| I3 | `TooltipRoot.pinned`, `ToggleDrag`, raccourcis `Tooltip/pinTooltips`, `Tooltip/shiftCloseUI`, `compareItems`, `showTheoreticalEffects` : infobulles **épinglables** et déplaçables. | idem ; `inputactionassets` |
| I4 | **L'emplacement de l'infobulle de combattant est choisi par le joueur** : `FighterInfoPlacementUI` affiche un cadre 706 de large sur fond noir à 50 % avec le texte « déplacez cette fenêtre pour définir le placement de l'infobulle de combattant » et deux boutons (annuler, valider). Option `moveFighterInfoToPlace`. | `Assets/UI/Fight/FighterInfoPlacementUI.uxml` |
| I5 | Délais : `DofusTooltipsSettings.m_defaultTooltipDuration = 2500` ms, `m_defaultCreateDelay = 0`. | `Assets/UI/DofusTooltipsSettings.asset` |
| I6 | Options de combat : `showDamagesPreview`, `showMovePreview`, `showMovementDistance`, `showMovementArea`, `showUsedPaPm`, `showTurnsRemaining`, `showPermanentTargetsTooltips`, `animateFightPreviewTooltips`, `showDamageElementIcon`, `showLogPvDetails`, `healthBarsDisplay` (toujours / au maintien d'un raccourci / jamais, `hideWhenFull`), `spectatorAutoShowCurrentFighterInfo`, `fightSkipTurnDelay`, `remindTurn`, `autoFocus`. | RVA `0x2a42a70` (`OptionGeneralUi.CreateGameCategory`) ; chaînes `ui.option.*` |

### 3.7 Lisibilité : transparence, contour, créatures

| # | Constat | Source |
|---|---|---|
| L1 | Actions de raccourci `Option/transparencyMode` et `Option/toggleDematerialization`, chaînes `ui.option.transparentOverlayMode` (libellé de l'option **« transparentOverlay »**) et `ui.option.creaturesMode`, `ui.shortcuts.transparancyMode`. `CachedDataService.get_transparencyMode` lit **deux valeurs distinctes** (champs `+0x9e0` / `+0x9e8` du conteneur d'options) selon un booléen de contexte ; même schéma pour `get_creatureMode`. | RVA `0x1646180`, `0x1646100`, `0x1E463D0` (`InputEventsDispatcher.OnTransparencyMode`) |
| L2 | **Mode créature** : bascule `tg_creature` dans la barre `mapInfo`, icônes `hud/icon_hud_creature_mode{,_dark,_grey}`, option `ui.fight.displayControlledCreatures` (3 niveaux). | `mapInfo.uxml`, `hud/*.webp` |
| L3 | Le moteur d'animation 2D a une **passe de contour** (`OutlinePrepass` / `OutlinePrepassSettings` dans `Ankama.Animations.Sources.Rendering.CustomPasses`, `Animator2DRenderer.SetOutline`, mot-clé de shader `Outline`). Aucune référence directe n'est trouvée (appel par interface). | `names.tsv` |
| L4 | Aura au premier plan : options `alwaysShowAuraOnFront`, `playerAuraMode`. Surbrillance des éléments interactifs : `highlightInteractiveElements` (et variante « au maintien »). | chaînes `ui.option.*` |
| L5 | Aucun fichier ne définit de règle « le personnage caché derrière un décor est affiché en transparence / en contour ». Le tri de profondeur est celui du moteur de sprites 2D (`FloorElement.ApplyMaterialSortOrder`) ; la visibilité d'un personnage derrière un obstacle n'est pas lue. | recherche exhaustive des noms `*Occlu*`, `*Silhouette*`, `*Transparen*`, `*XRay*` hors Unity : aucun |

## 4. Schéma de disposition (repère 1920 x 1080)

```
+--------------------------------------------------------------------------------------+
| [mapInfo : carte combats | surbrillance | info | mode créature ...]      LatencyUI [BannerMenu]
|  (haut gauche)                                                         (haut droite, top 55)
|
|  [Timeline  x140 y223]        <----------- ZONE DE JEU (caméra plein écran) ---------->
|   tuiles 78|106 px             map 1247 x 881,5 unités = ~88 % de la hauteur de la vue
|   4 orientations                                                      [Groupe y300, 80 px]
|
|  [Chat 400x244                                  [Jauge XP 566x34 @546,860]
|   bas gauche]      [Orbe PV/PA/PM 164x144]  [Fin de tour 228x144]
|                    [Barre de sorts 706 @636,990 : 12 x 51 px, 1 à 3 lignes]
+--------------------------------------------------------------------------------------+
Hors zone de la caméra (rapport > 1,915 ou < 1,333) : bandes noires peintes par l'UI.
Tout est flottant, aimanté et sauvegardé par préréglage (dont un préréglage « combat »).
```

Le dessin est une vue de proportion : les `left` / `top` viennent des UXML d'édition. Le bas de la map (dernières rangées) passe sous la barre de sorts [DÉDUIT : l'espace restant sous la map est `(1000 - 881,5) / 2` ≈ 59 unités, soit ~64 px à 1080p, et la barre commence à 990 px sur 1080].

## 5. Effet de la contrainte d'aspect (calculé avec C3 et C5)

Hauteur de vue = 1000 unités ; `px/unité = hauteur du rect caméra en pixels / 1000`. Taille de la map = 1247 x 881,5 unités (`MapGeometry.screen_bounds`, cellules 86 x 43 ; le décor qui déborde n'est pas compté).

| Fenêtre | Rapport | Rapport de vue | Rect caméra (x, y, w, h) | Pixels caméra | px / unité | Map (px) |
|---|---|---|---|---|---|---|
| 800 x 600 | 1,333 | 1,333 | (0, 0, 1, 1) | 800 x 600 | 0,600 | 748 x 529 |
| 1024 x 768 | 1,333 | 1,333 | (0, 0, 1, 1) | 1024 x 768 | 0,768 | 958 x 677 |
| 1280 x 720 | 1,778 | 1,778 | plein | 1280 x 720 | 0,720 | 898 x 635 |
| 1280 x 1024 (carré) | 1,250 | 1,333 | (0, 0,031, 1, 0,938) | 1280 x 960 | 0,960 | 1197 x 846 |
| 1366 x 768 | 1,779 | 1,779 | plein | 1366 x 768 | 0,768 | 958 x 677 |
| 1600 x 900 | 1,778 | 1,778 | plein | 1600 x 900 | 0,900 | 1122 x 793 |
| 1600 x 1200 | 1,333 | 1,333 | plein | 1600 x 1200 | 1,200 | 1496 x 1058 |
| 1920 x 1080 | 1,778 | 1,778 | plein | 1920 x 1080 | 1,080 | 1347 x 952 |
| 1920 x 1200 | 1,600 | 1,600 | plein | 1920 x 1200 | 1,200 | 1496 x 1058 |
| 2560 x 1440 | 1,778 | 1,778 | plein | 2560 x 1440 | 1,440 | 1796 x 1269 |
| 3440 x 1440 (ultra-large) | 2,389 | 1,915 | (0,099, 0, 0,802, 1) | 2757 x 1440 | 1,440 | 1796 x 1269 |
| 3840 x 2160 | 1,778 | 1,778 | plein | 3840 x 2160 | 2,160 | 2694 x 1904 |
| 5120 x 1440 | 3,556 | 1,915 | (0,231, 0, 0,539, 1) | 2757 x 1440 | 1,440 | 1796 x 1269 |

Lecture : sur un écran plus large que 1,915 la map **ne s'étire pas** (bandes noires latérales, l'UI peut y vivre) ; sur un rapport plus carré que 4:3 elle ne grossit pas non plus (bandes en haut et en bas). Le « zoom » de la map suit la **hauteur**, jamais l'espace laissé par les fenêtres.

## 6. Règles à reproduire

Numérotées pour être citées dans les lots (`APPROX` pour celles qui reposent sur §8).

- **R1 (caméra plein écran).** Ne pas réserver de bande pour la barre de sorts ni pour d'autres fenêtres. Le cadrage de la map est une fonction de la seule taille de la fenêtre : `échelle = hauteur_caméra_px / 1000`, `hauteur_caméra_px` venant de R2.
- **R2 (aspect bridé).** Rapport de vue = `clamp(largeur/hauteur, 4/3, 1935/1010,5)`. Au-delà, bandes verticales ; en deçà, bandes horizontales. Les bandes sont des éléments de l'UI (noir), pas un fond de monde.
- **R3 (UI par-dessus).** L'interface est une couche qui recouvre toute la fenêtre, y compris les bandes. Le monde ne se redimensionne jamais quand une fenêtre s'ouvre, se déplace ou se plie.
- **R4 (fenêtres libres).** Chaque fenêtre de jeu garde : position, dimensions (si redimensionnable) et état plié, par **identifiant stable** et par **préréglage**. Réinitialisation globale possible. Verrouillage (`lockUI`), aimantation avec distance et écart réglables, aperçu d'aimantation.
- **R5 (préréglage de combat).** Un préréglage peut être affecté au combat : en entrant en combat on applique `préréglage_combat` s'il existe, sinon le préréglage courant ; en sortant on revient. Les fenêtres de combat (timeline, buffs, barre de sorts, chat, orbe) se rafraîchissent au changement.
- **R6 (rester à l'écran).** Une fenêtre ne peut pas sortir complètement de l'écran (`ForceKeepInScreen`) ; la timeline est bornée à la largeur (ou hauteur) de la fenêtre et suit le combattant qui joue.
- **R7 (échelle).** Prévoir : (a) échelle de base indépendante de la résolution (px physiques), (b) variante « petit écran » (échelle = hauteur / 1024) avec classes réduites (`smallUI`), (c) option d'échelle en pourcentage, (d) 4 niveaux de taille de texte. Les seuils d'activation de (b) sont à fixer (`APPROX`).
- **R8 (timeline).** Portraits 78 px (petits) ou 106 px (grands) ; 4 orientations ; jauges de vie / bouclier / seuil à gauche ou à droite ; masque de temps sur le combattant qui joue ; numéro d'ordre ; équipe par la couleur du fond (bleu, rouge, gris) avec états normal, sombre, survol ; survol d'une tuile = mise en évidence du combattant sur la map ; options « morts » et « invocations ».
- **R9 (barre de sorts).** 12 colonnes de 51 px (écart 2), 1 à 3 lignes étiquetées, 12 pages, raccourcis `s1..s36` ; variante verticale ; plier / déplier.
- **R10 (infobulles).** Placer autour de la cible, **tester les collisions avec les autres infobulles**, flèche orientée, épinglage, suivi de la cible, durée par défaut 2,5 s. L'infobulle de combattant se place là où le joueur l'a décidé (fenêtre de placement avec annuler / valider).
- **R11 (bascules de lisibilité).** Raccourcis dédiés : masquer toute l'interface, grille, coordonnées, tous les noms, infobulles d'entités, éléments interactifs en surbrillance, mode créature, `transparencyMode`, `toggleDematerialization`. Chacun a un état propre au combat ou non pour au moins `transparencyMode` et le mode créature (sens exact : §8.4).
- **R12 (aperçus).** Aperçu des dégâts et du déplacement, zone de mouvement et distance de mouvement, PA / PM utilisés, barres de vie (3 modes + masquer quand pleines), icône d'élément des dégâts : tous désactivables.

## 7. Écarts avec le client actuel

| Sujet | Dofus 3 | SuperDofus aujourd'hui |
|---|---|---|
| Cadrage de la map | plein écran, échelle = hauteur / 1000, bandes d'aspect | `ClientSession._fit_camera` (`client_session.gd:729-735`) : `min(vp.x / 1247, (vp.y - band) / 881,5)` avec `band = PlayerHud.reserved_bottom()` (`player_hud.gd:179-182`), caméra décalée de `band * 0.5 / z`. La map est **toujours entièrement visible au-dessus de la barre**, sans bandes d'aspect. |
| Échelle de l'UI | px physiques + variante petit écran + pourcentage utilisateur | aucun `stretch` dans `project.godot` (viewport 1280 x 800, lignes 20-21) ; tailles de police fixes (`fight_hud.gd:114`, `:261`). |
| Fenêtres | flottantes, aimantées, par préréglage | `UiWindow` (`ui/ui_window.gd`) : `default_anchor`, `_clamp` (lignes 21, 143-145), pas d'aimantation, pas de préréglage. HUD de combat en positions calculées (`fight_hud.gd:203-209` : timeline centrée à y = 58, barre en bas centrée, bannière à (12, 120)). |
| Timeline | 4 orientations, 2 tailles, suit le joueur | `HBoxContainer` horizontal centré en haut (`fight_hud.gd:36-38`, `:205`) |
| Infobulles | collision, flèche, épinglage, suivi de cible | `ui/ui_tooltips.gd` : constructeurs de contenu (objet, sort, groupe de monstres) ; aucun placement anticollision lu |

## 8. Ce qui est impossible à vérifier ici

1. **Position par défaut réelle des fenêtres.** Les `left` / `top` des UXML sont ceux d'édition (par exemple `left: -315.357px` sur des conteneurs `display: none`). Le préréglage par défaut (`GetCommunityDefault`, `InitDataUi`) peut les remplacer. Le décalage exact barre de sorts / map est donc un ordre de grandeur.
2. **Centre vertical de la caméra** sur la map (donc la marge réelle sous la map) : calculé par `sk` / `MapRenderer` avec des constantes obfusquées (`sk.bpe` écrit `0x45294000`, `0x45208000`, `-5697 x ...`, probable code mort d'obfuscation).
3. **Ce qui active `SmallScreenPanelSettings` et la classe `smallUI`**, la liste exacte des pourcentages d'échelle (le code affiche `valeur + 10` en « % », sans la liste source), et si l'échelle utilisateur agit sur `PanelSettings.scale`, sur le dpi ou sur la taille de police.
4. **Le sens exact de `transparencyMode`, `toggleDematerialization`, du mode créature** et de l'option `transparentOverlayMode`. Textes français des libellés non récupérables : la table nommée de `Content/I18n/fr.bin` (7346 entrées après l'index numérique) est indexée par un hachage de clé que `tools/i18n_lookup.py` ne sait pas lire. Hypothèses plausibles, **non sourcées** : `transparentOverlayMode` rend les fenêtres d'interface translucides au-dessus de la map ; le mode créature remplace les personnages par de petits jetons pour lire un combat chargé ; la dématérialisation rend les autres joueurs immatériels hors combat.
5. **Contour ou transparence d'un personnage derrière un décor** : aucune règle trouvée (voir L5). Ne pas inventer de seuils.
6. **Touches par défaut des raccourcis** (les liaisons ne sont pas dans le bundle `inputactionassets` ; elles viennent de l'asset `InputPreset1` côté code ou du compte).
7. **Orientation par défaut de la timeline**, tailles de tuile par défaut (petite ou grande), bornes de zoom, limites de défilement.
8. **Rendu réel** : aucune capture du client Ankama n'a pu être prise (pas de session). Toutes les tailles viennent des données ; aucune n'a été confrontée à une image.
9. **Valeurs d'`UnityEngine.UIElements` à l'exécution** : le dpi réel de l'écran (Windows peut annoncer 120 ou 144) change l'échelle `ConstantPhysicalSize` (échelle = dpi / 96) ; l'effet en jeu n'a pas été mesuré.

## 9. Pour la suite (pistes, hors de cette recherche)

- Remplacer `reserved_bottom` par R1 / R2 et laisser les fenêtres flotter ; mesurer avec `client_shot` à 1280 x 720, 1920 x 1080, 2560 x 1440, 3440 x 1440 et 1280 x 1024 (relire chaque image avec `Read`).
- Un `UiLayoutPresets` (client, aucune classe de `sim/`) : `{preset: {window_id: {pos, size, folded}}}` sauvegardé via la persistance du client, avec un `fight_preset`.
- Compléter les bascules de lisibilité (R11) par des options de **notre** conception, clairement marquées `APPROX` : le comportement d'origine n'est pas lisible (§8.4, §8.5).
