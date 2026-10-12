# Commandes

Toutes les commandes utiles, par usage. Les essentielles sont aussi dans `CLAUDE.md`. `godot` = l'exécutable ci-dessous ; les captures `client_shot` se relisent avec l'outil Read.

## Godot, tests, sim, captures par mécanique
Godot : `C:\Users\natha\Documents\Godot\Godot_v4.7-stable_win64_console.exe`
```bash
godot --headless --path game --import                                   # après tout nouveau class_name
godot --headless --path game -s res://tests/run_tests.gd                # tous les tests
godot --headless --path game -s res://tools/sim_cli.gd -- --world=test --seconds=30 --cmd=0:move:293
godot --path game -s res://tools/client_shot.gd -- --out=shot.png --cmd=500:move:16! --cmd=4500:change_map:top
godot --headless --path game -s res://tools/sim_cli.gd -- --world=incarnam --seconds=60 --cmd=500:fight_attack --cmd=1000:fight_ready
godot --path game -s res://tools/client_shot.gd -- --world=incarnam --out=f.png --seconds=12 --cmd=1500:attack --cmd=3000:ready --cmd=7000:win --shot=8500
godot --headless --path game -s res://tools/protocol_doc.gd            # régénère docs/PROTOCOL.md après un changement de Protocol.SCHEMA
godot --headless --path game -s res://tools/sim_cli.gd -- --scenario=res://tests/scenarios/fight_won.jsonl   # rejoue un scénario de référence
godot --headless --path game -s res://tools/sim_cli.gd -- --rerecord=res://tests/scenarios/traps.jsonl   # réenregistre un scénario (mêmes commandes) après un changement de règle voulu
python tools/rules_sources.py                                           # registre des APPROX + index des formules officielles (docs/RULES_SOURCES.md)
dotnet run tools/client_enums/client_enums.cs -- docs/client_enums.md   # enums du client (noms des effets, formes de zone, codes de déclencheurs), source des règles
python tools/client_code/client_code.py decomp out.c "SpellZoneShape.*blhx"   # code natif du client décompilé (names / import / strings une fois ; find, xref ; usage <lRam…> = le type d'un emplacement de métadonnées, refs <adresse> = qui le lit) : la règle telle que le client la calcule, chaînes en clair
godot --path game -s res://tools/client_shot.gd -- --world=incarnam --out=n.png --seconds=9 --cmd=400:goto:154010882:300 --cmd=1200:npc --shot=7000   # PNJ : clic sur le premier PNJ de la map, dialogue (npc)
godot --path game -s res://tools/ui_demo.gd -- --out=ui.png              # capture du kit d'interface (client/ui)
godot --path game -s res://tools/client_shot.gd -- --lobby=1 --world=incarnam --out=l.png --cmd=300:create:Jean-Luc --cmd=2000:select:Jean-Luc --shot=1500   # choix du personnage
godot --path game -s res://tools/client_shot.gd -- --lobby=1 --world=incarnam --out=c.png --cmd=300:newchar:Jean-Luc --cmd=600:breed:12:1:5:ff2040   # création (classe, sexe, visage, couleur)
godot --path game -s res://tools/client_shot.gd -- --world=incarnam --out=s.png --cmd=500:level:120 --cmd=900:variant:12815 --cmd=1500:spells:12815   # grimoire (sorts, variantes, barre)
godot --path game -s res://tools/client_shot.gd -- --world=incarnam --out=k.png --cmd=500:level:110:545 --cmd=800:boost:strength:120 --cmd=1500:characteristics --cmd=2600:tab:1   # caractéristiques (points:<stat>[:<n>[:ok]] = fenêtre de répartition par lot)
godot --path game -s res://tools/client_shot.gd -- --world=incarnam --out=i.png --cmd=400:give:1182:3 --cmd=500:give:683:2 --cmd=1200:inventory --cmd=1500:use:683   # inventaire (give = raccourci outil)
godot --path game -s res://tools/client_shot.gd -- --world=incarnam --out=e.png --cmd=300:level:20 --cmd=400:give:2473 --cmd=500:give:44 --cmd=1200:inventory --cmd=1500:equip:2473 --cmd=1900:equip:44   # équipement
godot --path game -s res://tools/client_shot.gd -- --world=incarnam --out=d.png --cmd=500:goto:153879812:300 --cmd=900:grid --cmd=1500:door:198 --shot=6500   # maps : goto (raccourci outil), grid (sorties vertes, portes bleues, numéros), mark:<cell>, door:<cell> (clic sur une porte : entrée de la Mine)
godot --path game -s res://tools/client_shot.gd -- --world=incarnam --out=sh.png --seconds=9 --cmd=300:goto:154010883:343 --cmd=500:kamas:1500 --cmd=600:give:683:2 --cmd=1200:npc --cmd=4000:reply:1 --cmd=5000:buy:10801:2 --shot=7000   # boutique de PNJ (reply:<id> = réponse du dialogue, buy:/sell:<objet>[:<n>])
godot --path game -s res://tools/client_shot.gd -- --world=incarnam --out=z.png --seconds=13 --cmd=400:goto:154010371 --cmd=1000:goto:153880064:400 --cmd=1300:kamas:100 --cmd=1600:zaap --shot=6000 --cmd=7000:travel:154010371 --cmd=9000:worldmap --shot=11500   # zaap (fenêtre, voyage) et carte du monde (M)
godot --path game -s res://tools/client_shot.gd -- --world=incarnam --out=q.png --seconds=11 --cmd=300:goto:154010371:300 --cmd=800:npc --cmd=4500:reply:1001639 --cmd=5000:goto:153879813:300 --cmd=5600:npc --cmd=8600:quests --shot=10500   # quêtes : offre dans le dialogue (reply:<1000000 + id de quête>), suivi, journal (quests = Q)
godot --path game -s res://tools/client_shot.gd -- --world=incarnam --out=g.png --seconds=7 --cmd=800:hover --shot=1800 --cmd=2500:aggro --shot=3300   # infobulle de groupe (XP estimée), agression (« ! » puis combat) ; stars:<pct> = étoiles de la sous-zone (monde test : Incarnam n'en a pas)
godot --path game -s res://tools/client_shot.gd -- --world=incarnam --out=p.png --seconds=9 --cmd=500:energy:0 --cmd=1500:goto:153881088:440 --shot=3000 --cmd=3500:phoenix --shot=7000   # fantôme (energy:0, raccourci outil), clic sur le phénix du Cimetière -> résurrection
godot --path game -s res://tools/client_shot.gd -- --world=incarnam --out=v.png --seconds=16 --cmd=300:level:10 --cmd=1500:attack --cmd=3000:ready --cmd=9000:summon:1082231 --shot=11500   # invocation (summon:<sort>, raccourci outil : le Tofu de l'Osamodas)
godot --path game -s res://tools/client_shot.gd -- --world=incarnam --out=k.png --seconds=16 --cmd=300:level:10 --cmd=1500:attack --cmd=3000:ready --cmd=9000:carry:1040662 --shot=11000 --cmd=12000:throw:1040662 --shot=14500   # porter / lancer (carry:<sort> met l'ennemi le plus proche à côté, raccourci outil ; throw:<sort> sur la case la plus loin)
godot --path game -s res://tools/client_shot.gd -- --world=incarnam --out=t.png --seconds=14 --cmd=300:level:15 --cmd=1500:attack --cmd=3000:ready --cmd=9000:lay:1040895 --cmd=9400:lay:1041063 --shot=10500   # piège Sram et glyphe (lay:<sort>, raccourci outil)
godot --path game -s res://tools/client_shot.gd -- --world=incarnam --out=a.png --seconds=12 --cmd=300:level:5 --cmd=1500:attack --cmd=3000:ready --cmd=9000:carry:1040898 --cmd=9800:tip --shot=11000   # buff déclenché (Arsenic) : tip = infobulle de l'ennemi le plus proche, tip:me = la sienne
godot --path game -s res://tools/client_shot.gd -- --world=incarnam --out=i.png --seconds=12 --cmd=300:level:5 --cmd=1500:attack --cmd=3000:ready --cmd=9000:self:1040916 --shot=10500   # invisibilité (self:<sort> = sur soi ; carry:1040916 rend l'ennemi invisible : il disparaît)
godot --path game -s res://tools/client_shot.gd -- --world=incarnam --out=b.png --seconds=19 --cmd=300:level:10 --cmd=1500:attack --cmd=3000:ready --cmd=9000:wall:1041922 --shot=13000 --cmd=13500:detonate:1041886 --shot=15200   # bombes (wall:<sort> = deux bombes alignées, un mur entre ; detonate:<sort> = sur sa première bombe ; at:<sort>:<dx>:<dy> = sur une case voisine) ; runes : carry:1042410 puis carry:1042414
godot --path game -s res://tools/client_shot.gd -- --lobby=1 --world=incarnam --out=o.png --seconds=19 --cmd=300:create:Eli:m:16 --cmd=1500:select:Eli --cmd=2300:level:10 --cmd=3300:attack --cmd=4800:ready --cmd=10800:fmove --cmd=12300:lay:1044339 --cmd=12700:on:1044431 --shot=14300 --cmd=14800:project:1044344 --shot=15500   # portails (un Eliotrope : lay = Portail, on:<sort> = sur l'ennemi le plus proche (Exil), project:<sort> = sur un de ses portails libres)
godot --path game -s res://tools/client_shot.gd -- --lobby=1 --world=incarnam --out=x.png --seconds=16 --cmd=300:create:Xel:m:5 --cmd=1500:select:Xel --cmd=2300:level:10 --cmd=3300:attack --cmd=4800:ready --cmd=10000:mirror:1041556 --shot=13800   # Téléfrag (mirror:<sort> = deux ennemis de part et d'autre, lancer sur le premier : Frappe de Xélor les échange)
godot --path game -s res://tools/client_shot.gd -- --lobby=1 --world=incarnam --out=z.png --seconds=12 --cmd=300:create:Vap:m:15 --cmd=1500:select:Vap --cmd=2300:level:45 --cmd=3300:attack --cmd=4800:ready --cmd=10000:aim:1042785:2:0 --shot=11000   # aperçu de zone (aim:<sort>:<dx>:<dy> : sélectionne le sort et survole la case)
godot --path game -s res://tools/client_shot.gd -- --world=dofus --out=b.png --seconds=13 --cmd=300:level:30 --cmd=800:console:/tp_5_10 --cmd=4000:attack --cmd=6000:ready --shot=11000   # ligne de commande (Entrée) : /tp <map id> [cellule] ou /tp <x> <y> [world map] (admin_cmd, rôle GM : le joueur local en standalone)
godot --headless --path game -s res://src/server/main.gd -- --server --port=7777 --world=incarnam --save-dir=C:/SuperDofus/saves   # serveur réseau (S.01) ; --bind=<ip Hamachi>, --gm=ip-<adresse>, --seconds=N ; arrêt propre = personnages sauvegardés ; --http-port=7778 (API de contenu, jeton de session), --package-dir=<dir>, **--build-packages (PUBLIE le contenu : bundles, manifestes, release, pointeur ; incrémental, reprenable ; le serveur démarre instantanément et sert le contenu publié tel quel, un monde non publié est listé « non publié »)**, --rebuild, --bundle-mb=, --keep-versions= ; sans le jeu : `python tools/publish_content.py --world=<id> --package-dir=<d>`
serveur.bat [publier|check]   # le serveur de l'utilisateur : lancé depuis le projet (pas dist/), sauvegardes dans saves/, contenu dans user://packages
python tools/build_release.py --zip --smoke   # export (X.01) : dist/client (sans contenu), dist/server (exe + worlds/data/content à côté), serveur-lancer.bat, LISEZMOI.txt ; serveur exporté : `-- --check` vérifie ports, dossiers, paquets ; client exporté : `-- --auto-connect=ip:port --login= --password= --register=1 --pick=<monde> --character=<nom> --auto-shot=x.png --auto-seconds=N` (voir docs/EXPORT.md)
godot --path game -s res://tools/client_shot.gd -- --world=incarnam --server=127.0.0.1:7777 --out=n.png --seconds=9 --cmd=500:move:320   # le client joue sur un serveur (les raccourcis qui touchent la sim locale ne marchent pas)
godot --path game -s res://tools/launch_shot.gd -- --out=l.png --seconds=11 --address=127.0.0.1:1   # écran de lancement (ici : serveur injoignable)
godot --headless --path game -s res://tools/make_character.gd -- --name=Testeur --level=200 --all-items   # personnage de test dans la sauvegarde locale (user://saves), vraies règles
```

## Petits outils
```bash
TEST_ONLY=test_trade,test_party godot --headless --path game -s res://tests/run_tests.gd   # quelques fichiers (sous-chaînes, séparées par des virgules) ; TEST_SKIP pareil, TEST_CASE=<texte> pour les cas paramétrés
python tools/i18n_lookup.py 554207 535632                               # texte français d'ids i18n (lit game/content)
godot --headless --path game -s res://tools/essai_serveur.gd             # essai de bout en bout à deux comptes sur un vrai serveur local (docs/ESSAI_SERVEUR.md)
python tools/golden/compare.py                                           # non-régression du rendu contre d3-ts-renderer (voir la mémoire reference-d3-ts-golden)
```
