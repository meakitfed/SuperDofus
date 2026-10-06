# Rapport de la nuit (2026-10-03)

## Lots faits depuis la fin de la chaîne précédente (lus dans le Journal)
- **P2.03** : quêtes (`quest_log`, `quest_engine`, `quests.json`, fenêtre Q et suivi). APPROX(P2.03) : 3.
- **P1.15** : challenges, fuite, options de combat. Le code existait déjà, vérifié, boutons d'option remontés. Laissé `doing` (dépend de P1.14, formules exactes).
- **P2.05a** : récolte (règles, protocole, clic). Le reste du lot est en P2.05b.
- **P2.08** : banque et coffres (`Bank`, `BankRules`, `bank.json`).
- **R.01** : refactoring sans changement de comportement (`WorldSim` devient un routeur, 7 gestionnaires `WorldHandler`).
- **P1.13p** : codes de déclencheurs déduits des descriptions i18n (`trigger_codes.py`).

## État des tests
- `godot --headless ... run_tests.gd` : **415 tests, 0 failures** (départ : 388, le nombre n'a pas baissé).
- Aucun `SCRIPT ERROR` ni `Parse Error` dans la sortie.
- Les erreurs « resources still in use at exit » en fin de log sont les fuites habituelles à la fermeture, sans effet sur les résultats.
- `roadmap.py check` : 96 lots, 0 erreur. `rules_sources.py --check` : à jour (119 APPROX).
- Avancement : 52/96 lots faits.

## Problèmes restants
- P1.15 et P1.17b restent `doing` (P1.17b : environ 155 grades « partial » de classe).
- P1.14 (exactitude des formules, érosion) bloque la clôture de P1.15.
- Disque C: à 98 % (10 Go libres) : utiliser `--webp` pour toute extraction.
- `docs/REPRISE.md` est périmé (écrit avant l'arrêt du PC) : il parle encore de P2.03 « coupé en plein travail ».

## APPROX ajoutées
APPROX(P2.03) x3, APPROX(P2.05) x2, APPROX(P2.08) x1, APPROX(P2.02) x1 (lots récents) ; voir `docs/RULES_SOURCES.md` pour le registre complet.

## Prochain lot conseillé
**P1.14** (exactitude des formules de combat) : il est marqué PROCHAIN par la roadmap et débloque P1.15. Ensuite P2.05b, P2.03b ou P2.04.
