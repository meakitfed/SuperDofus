# Langage visuel du kit (lot U.03)

Tout est dans `game/src/client/ui/ui_style.gd` (`UiStyle`) ; `ClientTheme.get_theme()` l'applique une fois. Une fenêtre ne met jamais de couleur, de taille de police ni de rayon en dur : elle prend un jeton ci-dessous. Thème unique sombre (pas de variante jour), tous les textes AA (4,5:1) sur chaque surface (`tests/test_ui_style.gd`).

## Surfaces (profondeur)
| Jeton | Usage |
|---|---|
| `BG` | fond d'une fenêtre |
| `BG_RAISED` | bloc surélevé (toast) |
| `BG_HEADER` | barre de titre (filet or `ACCENT_DIM` de 2 px dessous) |
| `BG_INSET` | creux : fond de jauge, champ de saisie, case |
| `BORDER` / `BORDER_LIGHT` | bordure discrète / bordure d'élément flottant (fenêtre, infobulle) |
| `SCRIM`, `SHADOW` | voile d'une question modale, ombre portée (décalée de 3 px, 10 px de flou) |

## Texte
`TEXT` (principal), `TEXT_MUTED` (secondaire), `TEXT_DISABLED` (3:1, désactivé), `TEXT_ON_ACCENT` (sur remplissage or). Accent : `GOLD` = `ACCENT` (titres, sélection, action principale), `ACCENT_DIM` (filets, survol), `FOCUS` (anneau clavier). États : `GOOD`, `BAD`, `HP`, `AP`, `MP`, `XP`, `KAMAS`, `ENERGY`, `ELEMENTS`.

## Typographie (Lexend, polices Dofus)
| Rôle | Fabrique | Police | Taille |
|---|---|---|---|
| Titre | `UiStyle.title(t)` (`V_TITLE`) | Bold, or | `FS_TITLE` 18 |
| Intertitre | `UiStyle.heading(t)` (`V_HEADING`) | SemiBold | `FS_HEADING` 15 |
| Corps | `UiStyle.label(t)` | Medium (défaut) | `FS_BODY` 14 |
| Secondaire | `UiStyle.muted(t)` (`V_MUTED`) | Medium, grisé | 13 |
| Petit / minuscule | `label(t, c, FS_SMALL / FS_TINY)` | Medium | 12 / 11 |

`UiStyle.font("title" | "heading" | "body")` donne la police. Les fabriques posent le thème elles-mêmes (une infobulle n'hérite pas du thème).

## Composants
- **Bouton** : neutre (gris, bord clair ; survol : bord or atténué ; enfoncé : bord or). `V_PRIMARY` (remplissage or, texte sombre) pour l'action principale, `V_DANGER` (rouge sombre) pour une action destructive. `button.theme_type_variation = UiStyle.V_PRIMARY`.
- **Onglet** (`UiTabs`, `V_TAB`) : plat, texte SemiBold, souligné or quand courant, filet gris dessous.
- **Jauge** (`UiBar`) : fond creux, remplissage avec liseré clair en haut, texte blanc cerné ; la valeur glisse vers sa cible (0,28 s, instantané en headless).
- **Champ** (`LineEdit`) : creux `BG_INSET`, curseur or.
- **Focus clavier** : anneau `FOCUS` de 2 px (`UiStyle.focus_ring`) sur Button, onglets, CheckBox, OptionButton, LineEdit ; `UiConfirm` donne le focus à la réponse sûre (Annuler si destructif).
- **Fenêtre** (`UiWindow`) : fond `BG`, bordure claire, ombre, en-tête avec filet or, croix qui rougit au survol.
- **Toast** : bloc surélevé, liseré gauche de la couleur du message, apparition en fondu (0,14 s), sortie en fondu.
- **Cases** (`ItemSlot`, `SpellSlot`) : texture Dofus ; le survol s'allume en 0,08 s (anneau or atténué), la sélection a un anneau or plein (`UiStyle.draw_slot_frame`).
- **Infobulles** (`UiTooltips`) : nom en titre gras or, séparateurs fins, panneau avec ombre.

## Forme et mouvement
`RADIUS` 6 (fenêtres), `RADIUS_SMALL` 4 (boutons, champs, cases), `T_FAST` 0,08 s (survol), `T_BASE` 0,14 s (apparitions). Les animations sont coupées en headless (`UiWindow.animate`).

## Textures Dofus
Les extractions disponibles (`UI/darkStone/texture/slot/*`, `btnIcon/*`, `Figma/menuIcons/*`, étoiles) sont utilisées pour cases et icônes. Il n'existe pas de texture 9-slice de panneau, bouton ou onglet dans le contenu extrait : ces éléments sont des `StyleBoxFlat` soignés.
