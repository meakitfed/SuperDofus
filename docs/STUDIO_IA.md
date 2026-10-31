# Studio IA de l'atelier

Créer des apparences, des icônes et des décors à partir d'un modèle existant et d'une description, avec une IA d'images **gratuite, locale** (rien ne quitte l'ordinateur). Onglet **Studio IA** d'un monde dans l'atelier (`/mondes/<id>/studio`).

## Installation (une fois, environ 12 Go)
```bat
powershell -ExecutionPolicy Bypass -File tools\ai\setup_ai.ps1    &rem ComfyUI portable + FLUX.1 Kontext [dev] Q4 GGUF dans C:\SuperDofus\ai
tools\ai\start_ai.bat                                             &rem à lancer avant d'utiliser le Studio IA (http://127.0.0.1:8188)
```
- Ce qui est téléchargé :
  - ComfyUI portable (Python et PyTorch CUDA inclus) ;
  - le nœud `ComfyUI-GGUF` ;
  - `flux1-kontext-dev-Q4_K_S.gguf` (6,8 Go) ;
  - `t5-v1_1-xxl-encoder-Q4_K_M.gguf` (2,9 Go) ;
  - `clip_l` et `ae` (la VAE Flux).
- Le script se reprend là où il s'est arrêté et vérifie la place libre sur le disque. Il écrit `C:\SuperDofus\ai\comfy.json`, que l'atelier lit ; on peut indiquer un autre fichier avec `ATELIER_AI_CONFIG`.
- Durée d'une image de 1024 px sur une RTX 3070 Ti Laptop (8 Go) : environ une minute.
- Licence : FLUX.1 Kontext [dev] est non commercial. Pour un usage commercial, il faut changer de modèle dans `comfy.json` et le workflow de `atelier/core/ai_client.ts`.

## Personnage : re-skin d'un squelette
Un skin Dofus est un **atlas de pièces** (`0.webp` / `0.png`) dont `skin.json` donne les triangles et les UV ; le squelette anime ces pièces dans toutes les directions. Repeindre l'atlas re-skinne donc **toutes les animations et directions d'un coup**. La silhouette et le mouvement restent ceux du modèle.

Les étapes :
1. **Vues du modèle** : `game/tools/skin_probe.gd` rend 6 vues (statique, marche et attaque, directions 1 et 5) sur une planche 1008×1024.
   - Il fait deux passes : une en couleur, puis une avec les **atlas de coordonnées** de `DofusContent.probe_atlases`. Dans cette passe, chaque pixel encode le texel et l'atlas qu'il montre, sans filtrage, sans mélange et sans teinte.
2. **Génération** : Kontext repeint la planche entière, un appel par variante. Toutes les vues sont sur la même image, donc elles restent cohérentes.
3. **Projection** (`atelier/core/reskin.ts`, environ 200 ms) : chaque pixel repeint retourne à son texel.
   - On ne garde que les pixels intérieurs (pas les bords de silhouette ni les coutures entre pièces), et on ignore le fond blanc qui déborde.
   - Texels vus : moyenne des vues.
   - Pièce vue en partie : le texel vu le plus proche dans la même île de l'atlas.
   - Pièce jamais vue : une table de couleurs apprise sur les vues (couleur du modèle → couleur générée).
   - Retouches possibles sans IA : teinte, saturation, luminosité.
4. **Aperçu** : `game/tools/anim_sheet.gd` rend toutes les animations dans toutes les directions en bandes de frames, et l'atelier les joue dans un `<canvas>`.
5. **Ajout au monde** : le dossier du squelette, ou du skin, est copié sous un nouvel id pris dans la tranche `asset` du monde, avec l'atlas repeint en `0.png`. `bone.json` est renommé avec ce `m_Name`, car c'est par lui que le jeu trouve les animations. Le nouveau squelette apparaît dans les éditeurs de monstres, de PNJ et de classes.
   - Par défaut, les emplacements de palette du modèle sont retirés (`pos.z = 0` dans `skin.json`), sinon les couleurs du look teinteraient une seconde fois les pièces repeintes. L'option « Garder les couleurs personnalisables » les conserve.
   - Les squelettes découpés en paquets (bone 1 des joueurs) ne sont pas repeints : seuls leurs skins le sont.

## Icônes et décors
- On part d'une image de référence (bibliothèque Dofus ou image du monde) ou de rien.
- Kontext édite la référence (même cadrage, même style) ou dessine à partir du texte seul.
- Ensuite :
  - le fond est rendu transparent : on remplit à partir des bords la couleur du fond, avec un bord adouci ;
  - l'image est recadrée autour du dessin ;
  - une icône est mise au carré ;
  - elle est importée par le chemin habituel (`importAssets` : PNG ré-encodé, 96×96 pour les icônes).

## API (serveur de l'atelier)
| Route | Rôle |
|---|---|
| `GET /api/ai/status` | moteur prêt ?, carte graphique, Godot présent |
| `POST /api/ai/character` `{world, look, prompt, count}` | lance une tâche de personnage |
| `POST /api/ai/image` `{world, category, prompt, count, reference?}` | lance une tâche d'icône ou de décor |
| `GET /api/ai/jobs/:id` | état de la tâche, variantes prêtes |
| `GET /api/ai/jobs/:id/files/<chemin>` | planche, variantes, bandes d'aperçu |
| `POST /api/ai/jobs/:id/preview` `{variant, adjust, bake}` | projection dans un monde de brouillon et aperçu animé |
| `POST /api/ai/jobs/:id/accept` `{variant, adjust, bake, name}` | ajout au monde |

Les tâches vivent en mémoire et dans `%TEMP%\atelier-ai` (vidé au démarrage). Rien n'entre dans le monde avant `accept`.

## Tests
`atelier/tests/studio.test.ts` couvre :
- le codage UV ;
- la projection (texels vus, pièce vue en partie, pièce jamais vue, fond blanc, teinte) ;
- le détourage et le workflow ;
- une tâche d'icône avec un faux générateur ;
- le parcours complet d'un personnage avec le vrai Godot et un faux générateur (planche dont la teinte est décalée) : nouveau squelette, `m_Name`, alpha intact, couleurs changées.

Le vrai générateur ne sert qu'à la main.

## Limites connues
- La forme ne change pas : un « golem » fait à partir d'un Bouftou reste un Bouftou repeint. Pour une autre silhouette, il faut partir d'un autre squelette.
- Les pièces qu'on ne voit dans aucune des 6 vues (accessoires d'une seule attaque, par exemple) reçoivent une couleur devinée par la table. On peut ajouter des vues avec `--views=` de `skin_probe.gd`.
- Les copies de squelettes Dofus restent des dérivés d'assets Ankama : comme `game/content`, elles ne se publient pas.
