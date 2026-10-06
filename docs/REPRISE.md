# Reprise du travail (écrit le 2026-10-03, avant arrêt du PC)

## État
- Lots faits cette session : P2.01 (PNJ, dialogues), P2.02 (marchands), 10 morceaux de P1.17b (sorts « partial » : 662 -> ~155 grades de classe).
- **P2.03 (quêtes, partie 1) a été coupé en plein travail** (workflows arrêtés à la main) : le code peut être à moitié écrit.
- Pas de git : vérifier d'abord que le projet est sain.

## 1. Vérifier le projet (premier réflexe demain)
```
godot --headless --path game --import
godot --headless --path game -s res://tests/run_tests.gd      # chercher aussi "SCRIPT ERROR" / "Parse Error" : silencieux
python tools/roadmap.py check ; python tools/rules_sources.py --check
```
Si des tests cassent à cause de P2.03 : le lot est `doing`, le reprendre (`/suite P2.03`) ; l'agent lit la dernière ligne du Journal.

## 2. Relancer la chaîne
Dire à Claude : « relance la chaîne ». Script prêt : `tools/workflows/chaine.js` (lots : P2.03, P1.15, P2.05, P2.08, un agent Sonnet à la fois, sans arrêt si l'un échoue) :
`Workflow({scriptPath: "tools/workflows/chaine.js"})`

## 3. Ensuite (dans cet ordre, un agent à la fois)
1. **Refactoring** sans changement de comportement : découper `WorldSim` (~1100 lignes) en routeur + gestionnaires par domaine, remplacer les `_pending_*` de `ClientSession` par un objet, découper `FightRules.zone`, `FightEffects._apply`, `FightView._apply_effects`, règle de taille de fichier dans `test_architecture.gd`. Scénarios de référence IDENTIQUES.
2. **P1.13p** : codes de déclencheurs déduits des descriptions de sorts (`python tools/extractor/trigger_codes.py` : 31 couples code/effet).
3. Contrôle final + rapport.

## Rappels
- Laisser le PC éveillé pendant les workflows ; usage abonnement à surveiller (`/usage`).
- `spells.json` : régénérer avec `classes --world incarnam+astrub` (jamais sans cet argument).
- Personnage de test : `Testeur` (niveau 200) sauvegardé sur la map 146803712 (marchands), 100 000 kamas ; sauvegarde de secours `Testeur.json.bak2`.
