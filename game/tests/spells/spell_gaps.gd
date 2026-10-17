## The spell grades allowed to fail SpellCheck, each with why: a rule we cannot reproduce yet (no source
## for it), marked APPROX(<lot>). Keep it short: a gap fixed must leave the list (test_spell_contracts
## checks that every grade here still fails). The partial ones are generated from the game's data (the
## trigger codes / effects tools/extractor/spells.py could not convert).
class_name SpellGaps
extends RefCounted

const GAPS := {
	1040593: "APPROX(P1.18): trigger code DV: no source for its meaning (FightTriggers)", # Berserk
	1041140: "APPROX(P1.18): trigger code DV: no source for its meaning (FightTriggers)", # Ataraxie
	1041642: "APPROX(P1.18): trigger code CI: no source for its meaning (FightTriggers)", # Faille
	1041763: "APPROX(P1.18): casts Boîte à Outils (1062857): trigger code CI: no source for its meaning (FightTriggers)", # Boîte à Outils
	1041872: "APPROX(P1.18): trigger code CT: no source for its meaning (FightTriggers)", # Grimace
	1042218: "APPROX(P1.18): casts Mandragore (1078823): trigger code DI: no source for its meaning (FightTriggers)", # Mandragore
	1043687: "APPROX(P1.18): casts Boîte à Outils (1062857): trigger code CI: no source for its meaning (FightTriggers)", # Boîte à Outils
	1048089: "APPROX(P1.18): trigger code DV: no source for its meaning (FightTriggers)", # Berserk
	1062857: "APPROX(P1.18): trigger code CI: no source for its meaning (FightTriggers)", # Boîte à Outils
	1065598: "APPROX(P1.18): trigger code DV: no source for its meaning (FightTriggers)", # Féerie
	1065723: "APPROX(P1.18): trigger code DV: no source for its meaning (FightTriggers)", # Folie
	1078821: "APPROX(P1.18): casts Mandragore (1078822): casts Mandragore (1078823): trigger code DI: no source for its meaning (FightTriggers)", # Mandragore
	1078822: "APPROX(P1.18): casts Mandragore (1078823): trigger code DI: no source for its meaning (FightTriggers)", # Mandragore
	1078823: "APPROX(P1.18): trigger code DI: no source for its meaning (FightTriggers)", # Mandragore
	1082257: "APPROX(P1.18): casts Pacte Bestial (1085511): casts Pacte Bestial (1085512): trigger code CI: no source for its meaning (FightTriggers)", # Pacte Bestial
	1085511: "APPROX(P1.18): casts Pacte Bestial (1085512): trigger code CI: no source for its meaning (FightTriggers)", # Pacte Bestial
	1085512: "APPROX(P1.18): trigger code CI: no source for its meaning (FightTriggers)", # Pacte Bestial
	1085514: "APPROX(P1.18): casts Pacte Bestial (1085511): casts Pacte Bestial (1085512): trigger code CI: no source for its meaning (FightTriggers)", # Pacte Bestial
	# the Huppermage's elemental runes summon monsters 4258-4261, which the game's monsters table does not have
	1042409: "APPROX(P1.18): summons monster 4258, absent from the game's data (monsters table)", # Rune de Feu
	1042434: "APPROX(P1.18): summons monster 4260, absent from the game's data (monsters table)", # Rune d'Eau
	1042435: "APPROX(P1.18): summons monster 4261, absent from the game's data (monsters table)", # Rune d'Air
	1042436: "APPROX(P1.18): summons monster 4259, absent from the game's data (monsters table)", # Rune de Terre
	# the Synchro's starting spell (Fin des Temps) ends with an instant explosion unless the clock is in state
	# 614, which nothing in the data sets; the spell's text says it explodes only once in the Téléfrag state
	1041541: "APPROX(P1.18): its summon explodes on arrival (startingSpellId Fin des Temps, state 614 unknown)", # Synchro
	1041542: "APPROX(P1.18): its summon explodes on arrival (startingSpellId Fin des Temps, state 614 unknown)", # Synchro
	# H.04b: monster spells of the other zones that fail their contract; each is a rule to check in H.04c
	1004580: "APPROX(H.04c): poison steal: the contract expects a poison buff and sees an immediate hit", # Embaumement
	1005581: "APPROX(H.04c): poison steal: the contract expects a poison buff and sees an immediate hit", # Frappe de Corail
	1005676: "APPROX(H.04c): poison steal: the contract expects a poison buff and sees an immediate hit", # Nervure
	1005861: "APPROX(H.04c): poison steal: the contract expects a poison buff and sees an immediate hit", # Boue sirupeuse
	1020793: "APPROX(H.04c): poison steal: the contract expects a poison buff and sees an immediate hit", # Bondage
	1019162: "APPROX(H.04c): AP removal: no AP buff for the -6 (monster stat the contract does not model)", # Noyade
	1020702: "APPROX(H.04c): reflect: double the expected reflection (stacked reflect source)", # Drako
	1022336: "APPROX(H.04c): MP effect with the opposite sign to the contract", # Macro-Ondes
	1048493: "APPROX(H.04c): summon on cell 327 not placed by the contract arena", # Invocation de Bombombre
	1048533: "APPROX(H.04c): summon on cell 327 not placed by the contract arena", # Invocation de Bombombre
	1054829: "APPROX(H.04c): summon on cell 327 not placed by the contract arena", # Fruit du Sacrifice
	1078250: "APPROX(H.04c): unbuff keeps the buff of spell 29391", # Ossuaire
	1078252: "APPROX(H.04c): unbuff keeps the buff of spell 29391", # Ossuaire
}
