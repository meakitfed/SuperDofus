# Audit des tests de sorts

Genere par `tools/spell_audit.gd` (`godot --headless --path game -s res://tools/spell_audit.gd`) : ne pas editer a la main.
Un grade est couvert par les contrats (`test_spell_contracts`), son golden (`test_spell_golden`) ou un ecart declare
(`SpellGaps`) ; `test_spell_coverage` echoue sinon. Les colonnes ci-dessous disent ce que ces tests n'atteignent pas :
- *effets non atteints* : effets dont aucune cible de l'arene n'est touchee (conditions que l'arene ne reunit pas) ;
- *types sans cas* : types d'effet de la classe qu'aucun cas multi-tours (`spell_cases.gd`) ne joue.

| Classe | Sorts | Grades | Ecarts | Cas | Effets non atteints | Types sans cas |
|---|---|---|---|---|---|---|
| 0 | 1 | 1 | 0 | 1 | 0 | 0 |
| 1 | 44 | 91 | 1 | 6 | 80 | 12 |
| 2 | 44 | 91 | 1 | 7 | 128 | 17 |
| 3 | 44 | 91 | 2 | 4 | 64 | 8 |
| 4 | 44 | 91 | 0 | 5 | 90 | 12 |
| 5 | 44 | 91 | 3 | 4 | 24 | 17 |
| 6 | 44 | 91 | 0 | 7 | 44 | 16 |
| 7 | 44 | 91 | 0 | 6 | 284 | 16 |
| 8 | 44 | 91 | 0 | 8 | 18 | 6 |
| 9 | 44 | 91 | 0 | 7 | 40 | 10 |
| 10 | 44 | 91 | 1 | 4 | 258 | 15 |
| 11 | 44 | 91 | 2 | 5 | 20 | 16 |
| 12 | 44 | 91 | 0 | 3 | 306 | 14 |
| 13 | 44 | 91 | 0 | 5 | 374 | 13 |
| 14 | 44 | 91 | 0 | 3 | 90 | 14 |
| 15 | 44 | 91 | 0 | 4 | 256 | 17 |
| 16 | 44 | 91 | 0 | 3 | 232 | 23 |
| 17 | 44 | 91 | 0 | 4 | 48 | 19 |
| 18 | 44 | 91 | 0 | 3 | 6 | 18 |
| 20 | 44 | 91 | 0 | 4 | 536 | 19 |

## Classe 0

Cas : Bave Affaiblissante: the target takes 20 % more for the turn

Types sans cas : aucun

## Classe 1

Cas : Silbo pushes away from the centre, not the centre itself, Manœuvre swaps the caster with its target, Terre Brûlée's glyph burns an enemy starting its turn in it, Typhon weakens for 3 turns, not more, Bulle hits and lowers the range for the target's next turn only, Égide summons a shield that is destroyed 2 turns after

Types sans cas : ap, glyph_end, glyph_now, glyph_trigger, mp, pull, recoil, taken, teleport, unbuff, unmark, unstate

Effets non atteints (80, 40 premiers) :
- Transhumance (1041057) grade 1 glyph_trigger
- Transhumance (1041057) grade 1 glyph_trigger
- Transhumance (1041057) grade 1 glyph_trigger
- Transhumance (1041057) grade 1 glyph_trigger
- Transhumance (1041057) grade 1 glyph_trigger
- Transhumance (1041057) grade 1 glyph_trigger
- Transhumance (1041057) grade 1 glyph_trigger
- Transhumance (1041057) grade 1 glyph_trigger
- Transhumance (1041057) grade 1 glyph_trigger
- Transhumance (1041057) grade 1 glyph_trigger
- Transhumance (1041057) grade 1 glyph_trigger
- Transhumance (1041057) grade 1 glyph_trigger
- Transhumance (1041057) grade 1 glyph_trigger
- Transhumance (1041057) grade 1 glyph_trigger
- Transhumance (1041057) grade 1 glyph_trigger
- Transhumance (1041057) grade 1 glyph_trigger
- Transhumance (1041057) grade 1 state
- Transhumance (1041057) grade 1 state
- Transhumance (1041058) grade 2 glyph_trigger
- Transhumance (1041058) grade 2 glyph_trigger
- Transhumance (1041058) grade 2 glyph_trigger
- Transhumance (1041058) grade 2 glyph_trigger
- Transhumance (1041058) grade 2 glyph_trigger
- Transhumance (1041058) grade 2 glyph_trigger
- Transhumance (1041058) grade 2 glyph_trigger
- Transhumance (1041058) grade 2 glyph_trigger
- Transhumance (1041058) grade 2 glyph_trigger
- Transhumance (1041058) grade 2 glyph_trigger
- Transhumance (1041058) grade 2 glyph_trigger
- Transhumance (1041058) grade 2 glyph_trigger
- Transhumance (1041058) grade 2 glyph_trigger
- Transhumance (1041058) grade 2 glyph_trigger
- Transhumance (1041058) grade 2 glyph_trigger
- Transhumance (1041058) grade 2 glyph_trigger
- Transhumance (1041058) grade 2 state
- Transhumance (1041058) grade 2 state
- Transhumance (1041059) grade 3 glyph_trigger
- Transhumance (1041059) grade 3 glyph_trigger
- Transhumance (1041059) grade 3 glyph_trigger
- Transhumance (1041059) grade 3 glyph_trigger

## Classe 2

Cas : Saute-granouille jumps over its target, Fouet hits in the caster's best element and pushes 2, Tofu summons a Tofu on the cell, Morsure du Serpent poisons at each of the target's turns, for 2 turns, Piqûre Motivante gives an ally AP and MP, Toison d'Or shields the allies around for one turn and hits the enemies, Déplumage hits the cross and lowers push resistance for 2 turns

Types sans cas : advance, cast, cooldown, heal, heal_attackers, healed, kill, pull, recoil, share, state, steal, swap, sym_impact, teleport, transfer_hp, unstate

Effets non atteints (128, 40 premiers) :
- Fouet (1082230) grade 1 mp
- Fouet (1082230) grade 1 mp
- Fouet (1082230) grade 1 mp
- Fouet (1082230) grade 1 mp
- Cortège Sauvage (1082235) grade 1 kill
- Cortège Sauvage (1082235) grade 1 kill
- Piqûre Motivante (1082236) grade 1 ap
- Piqûre Motivante (1082236) grade 1 ap
- Piqûre Motivante (1082236) grade 1 mp
- Piqûre Motivante (1082236) grade 1 mp
- Saute-granouille (1082237) grade 1 sym_caster
- Saute-granouille (1082237) grade 1 sym_caster
- Saute-granouille (1082237) grade 1 sym_caster
- Saute-granouille (1082237) grade 1 sym_caster
- Charge Bestiale (1082239) grade 1 pull
- Charge Bestiale (1082239) grade 1 pull
- Charge Bestiale (1082239) grade 1 pull
- Charge Bestiale (1082239) grade 1 pull
- Charge Bestiale (1082239) grade 1 pull
- Charge Bestiale (1082239) grade 1 pull
- Charge Bestiale (1082239) grade 1 pull
- Charge Bestiale (1082239) grade 1 pull
- Charge Bestiale (1082239) grade 1 pull
- Charge Bestiale (1082239) grade 1 pull
- Charge Bestiale (1082239) grade 1 pull
- Charge Bestiale (1082239) grade 1 pull
- Charge Bestiale (1082239) grade 1 pull
- Charge Bestiale (1082239) grade 1 pull
- Charge Bestiale (1082239) grade 1 pull
- Charge Bestiale (1082239) grade 1 pull
- Aéropique (1082240) grade 1 cast
- Aéropique (1082240) grade 1 cast
- Aéropique (1082240) grade 1 cast
- Aéropique (1082240) grade 1 cast
- Relais Spirituel (1082246) grade 1 swap
- Relais Spirituel (1082246) grade 1 swap
- Relais Spirituel (1082246) grade 1 state
- Relais Spirituel (1082246) grade 1 state
- Relais Spirituel (1082246) grade 1 cast
- Relais Spirituel (1082246) grade 1 cast

## Classe 3

Cas : Retraite Anticipée roots everyone else now and the caster on its next turn, Souterrain swaps with its target and hits it, Tunnel de Fortune makes the caster invisible, Sac Animé takes the hits of the allies around it

Types sans cas : ap, heal, heal_attackers, heal_pct, push, share, shorten, unstate

Effets non atteints (64, 40 premiers) :
- Sac Animé (1041688) grade 1 intercept
- Sac Animé (1041688) grade 1 intercept
- Sac Animé (1041689) grade 2 intercept
- Sac Animé (1041689) grade 2 intercept
- Sac Animé (1041690) grade 3 intercept
- Sac Animé (1041690) grade 3 intercept
- Péremption (1041703) grade 1 damage
- Péremption (1041703) grade 1 damage
- Péremption (1041703) grade 1 damage
- Péremption (1041703) grade 1 damage
- Péremption (1041704) grade 2 damage
- Péremption (1041704) grade 2 damage
- Péremption (1041704) grade 2 damage
- Péremption (1041704) grade 2 damage
- Remblai (1041709) grade 1 damage
- Remblai (1041709) grade 1 damage
- Remblai (1041709) grade 1 damage
- Remblai (1041709) grade 1 damage
- Remblai (1041710) grade 2 damage
- Remblai (1041710) grade 2 damage
- Remblai (1041710) grade 2 damage
- Remblai (1041710) grade 2 damage
- Remblai (1041711) grade 3 damage
- Remblai (1041711) grade 3 damage
- Remblai (1041711) grade 3 damage
- Remblai (1041711) grade 3 damage
- Musette Animée (1041760) grade 1 share
- Musette Animée (1041760) grade 1 share
- Musette Animée (1041760) grade 1 kill
- Musette Animée (1041760) grade 1 kill
- Musette Animée (1041760) grade 1 kill
- Musette Animée (1041760) grade 1 kill
- Déambulation (1041762) grade 1 cast
- Déambulation (1041762) grade 1 cast
- Obsolescence (1041766) grade 1 damage
- Obsolescence (1041766) grade 1 damage
- Obsolescence (1041766) grade 1 damage
- Obsolescence (1041766) grade 1 damage
- Avarice (1041768) grade 1 stat
- Avarice (1041768) grade 1 stat

## Classe 4

Cas : Arsenic poisons at the start of the target's turn, Toxines poisons at the end of the target's turn, and grows with each cast, Piège Sournois hurts and pulls who walks into it, Invisibilité hides an ally and gives it MP, Extorsion steals Strength first, then life with it

Types sans cas : aura, cooldown, double, heal_attackers, heal_dealt, kill, pull, push, swap, taken, unbuff, unstate

Effets non atteints (90, 40 premiers) :
- Concentration de Chakra (1040886) grade 1 steal
- Concentration de Chakra (1040886) grade 1 steal
- Concentration de Chakra (1040887) grade 2 steal
- Concentration de Chakra (1040887) grade 2 steal
- Peur (1040901) grade 1 push
- Peur (1040901) grade 1 push
- Peur (1040902) grade 2 push
- Peur (1040902) grade 2 push
- Peur (1040903) grade 3 push
- Peur (1040903) grade 3 push
- Double (1040922) grade 1 cast
- Double (1040922) grade 1 cast
- Double (1040922) grade 1 state
- Double (1040922) grade 1 state
- Double (1040922) grade 1 swap
- Double (1040922) grade 1 swap
- Double (1040922) grade 1 swap
- Double (1040922) grade 1 swap
- Double (1040922) grade 1 mp
- Double (1040922) grade 1 mp
- Double (1040922) grade 1 mp
- Double (1040922) grade 1 mp
- Double (1040922) grade 1 kill
- Double (1040922) grade 1 kill
- Double (1040922) grade 1 kill
- Double (1040922) grade 1 kill
- Double (1040923) grade 2 cast
- Double (1040923) grade 2 cast
- Double (1040923) grade 2 state
- Double (1040923) grade 2 state
- Double (1040923) grade 2 swap
- Double (1040923) grade 2 swap
- Double (1040923) grade 2 swap
- Double (1040923) grade 2 swap
- Double (1040923) grade 2 mp
- Double (1040923) grade 2 mp
- Double (1040923) grade 2 mp
- Double (1040923) grade 2 mp
- Double (1040923) grade 2 kill
- Double (1040923) grade 2 kill

## Classe 5

Cas : Frappe de Xélor sends its target to the other side of the caster, Frappe de Xélor onto an ally is a Téléfrag: both swap and get Téléfrag, the caster gains 2 AP, Gelure sends its target back where it was before its last move, Momification gives the caster MP and AP removal

Types sans cas : ap, aura, cooldown, glyph_start, rollback_turn, shorten, splash_taken, steal, summon, swap, sym_impact, sym_target, taken, teleport, trap, unbuff, unstate

Effets non atteints (24) :
- Paradoxe (1041550) grade 1 cast
- Paradoxe (1041550) grade 1 cast
- Paradoxe (1041550) grade 1 cast
- Paradoxe (1041550) grade 1 cast
- Paradoxe (1041550) grade 1 cast
- Paradoxe (1041550) grade 1 cast
- Paradoxe (1041550) grade 1 state
- Paradoxe (1041550) grade 1 state
- Paradoxe (1041551) grade 2 cast
- Paradoxe (1041551) grade 2 cast
- Paradoxe (1041551) grade 2 cast
- Paradoxe (1041551) grade 2 cast
- Paradoxe (1041551) grade 2 cast
- Paradoxe (1041551) grade 2 cast
- Paradoxe (1041551) grade 2 state
- Paradoxe (1041551) grade 2 state
- Paradoxe (1041552) grade 3 cast
- Paradoxe (1041552) grade 3 cast
- Paradoxe (1041552) grade 3 cast
- Paradoxe (1041552) grade 3 cast
- Paradoxe (1041552) grade 3 cast
- Paradoxe (1041552) grade 3 cast
- Paradoxe (1041552) grade 3 state
- Paradoxe (1041552) grade 3 state

## Classe 6

Cas : Bond du Félin teleports onto a free cell, Bond du Félin on an ally gives MP and does not move anyone, Prédation erodes the enemies around, Neuf Vies heals 9 % of the target's life now and on the 2 next turns, Entrechat teleports the caster and raises its escape for one turn, Griffe Joueuse hits and lowers critical resistance for 3 turns, Kraps pushes from the centre and raises the caster's critical damage for 3 turns

Types sans cas : advance, ap, heal, healed, pull, recoil, shield, shorten, steal, summon, sym_caster, sym_impact, sym_target, taken, unbuff, unstate

Effets non atteints (44, 40 premiers) :
- Perception (1040794) grade 1 heal_pct
- Perception (1040794) grade 1 heal_pct
- Perception (1040795) grade 2 heal_pct
- Perception (1040795) grade 2 heal_pct
- Perception (1040796) grade 3 heal_pct
- Perception (1040796) grade 3 heal_pct
- Griffe Invocatrice (1040806) grade 1 stat
- Griffe Invocatrice (1040806) grade 1 stat
- Griffe Invocatrice (1040807) grade 2 stat
- Griffe Invocatrice (1040807) grade 2 stat
- Bluff (1079193) grade 1 damage
- Bluff (1079193) grade 1 damage
- Bluff (1079193) grade 1 damage
- Bluff (1079193) grade 1 damage
- Bluff (1079193) grade 1 damage
- Bluff (1079193) grade 1 damage
- Bluff (1079193) grade 1 damage
- Bluff (1079193) grade 1 damage
- Bluff (1079193) grade 1 damage
- Bluff (1079193) grade 1 damage
- Bluff (1079193) grade 1 damage
- Bluff (1079193) grade 1 damage
- Bluff (1079193) grade 1 damage
- Bluff (1079193) grade 1 damage
- Bluff (1079193) grade 1 damage
- Bluff (1079193) grade 1 damage
- Bluff (1079233) grade 2 damage
- Bluff (1079233) grade 2 damage
- Bluff (1079233) grade 2 damage
- Bluff (1079233) grade 2 damage
- Bluff (1079233) grade 2 damage
- Bluff (1079233) grade 2 damage
- Bluff (1079233) grade 2 damage
- Bluff (1079233) grade 2 damage
- Bluff (1079233) grade 2 damage
- Bluff (1079233) grade 2 damage
- Bluff (1079233) grade 2 damage
- Bluff (1079233) grade 2 damage
- Bluff (1079233) grade 2 damage
- Bluff (1079233) grade 2 damage

## Classe 7

Cas : Mot Vampirique gives an ally part of the caster's life, Mot d'Envol swaps with an ally, Mot Farceur sends its target back at the end of its turn, Mot de Reconstitution heals fully and then blocks the heals, Fontaine de Jouvence heals the allies now and again at the end of the turn, Chapardage steals range and life

Types sans cas : ap, cooldown, glyph_start, heal_attackers, heal_dealt, healed, mp, pull, push, shield, shorten, stat, summon, teleport, unbuff, unstate

Effets non atteints (284, 40 premiers) :
- Mot Exsangue (1041494) grade 1 cast
- Mot Exsangue (1041494) grade 1 cast
- Mot Exsangue (1041494) grade 1 cast
- Mot Exsangue (1041494) grade 1 cast
- Mot de Solidarité (1041496) grade 1 cast
- Mot de Solidarité (1041496) grade 1 cast
- Mot d'Amitié (1065641) grade 1 mp
- Mot d'Amitié (1065641) grade 1 mp
- Mot Alchimique (1065667) grade 1 cast
- Mot Alchimique (1065667) grade 1 cast
- Mot Alchimique (1065667) grade 1 cast
- Mot Alchimique (1065667) grade 1 cast
- Mot d'Amitié (1065735) grade 2 mp
- Mot d'Amitié (1065735) grade 2 mp
- Mot d'Amitié (1065736) grade 3 mp
- Mot d'Amitié (1065736) grade 3 mp
- Mot Alchimique (1065756) grade 2 cast
- Mot Alchimique (1065756) grade 2 cast
- Mot Alchimique (1065756) grade 2 cast
- Mot Alchimique (1065756) grade 2 cast
- Vacarme (1065814) grade 1 cast
- Vacarme (1065814) grade 1 cast
- Vacarme (1065814) grade 1 cast
- Vacarme (1065814) grade 1 cast
- Vacarme (1065814) grade 1 cast
- Vacarme (1065814) grade 1 cast
- Vacarme (1065814) grade 1 cast
- Vacarme (1065814) grade 1 cast
- Cri Assourdissant (1065815) grade 1 cast
- Cri Assourdissant (1065815) grade 1 cast
- Cri Assourdissant (1065815) grade 1 cast
- Cri Assourdissant (1065815) grade 1 cast
- Mot Tapageur (1065816) grade 1 cast
- Mot Tapageur (1065816) grade 1 cast
- Mot Tapageur (1065816) grade 1 cast
- Mot Tapageur (1065816) grade 1 cast
- Chapardage (1065817) grade 1 cast
- Chapardage (1065817) grade 1 cast
- Chapardage (1065817) grade 1 cast
- Chapardage (1065817) grade 1 cast

## Classe 8

Cas : Bond teleports the caster onto the free cell, Précipitation gives AP now and takes 3 back on the ally's next turn, Violence pushes everyone around the caster 4 cells away, Pression erodes for 2 turns, Détermination roots an ally in place and shields it for one turn, Endurance shields the caster for 2 turns and hits, Épée du Jugement condemns: the same hit lands again 2 turns later, Puissance raises power and push damage for 3 turns

Types sans cas : advance, mp, pull, splash_taken, summon, unbuff

Effets non atteints (18) :
- Bond (1041277) grade 1 taken
- Bond (1041277) grade 1 taken
- Bond (1041278) grade 2 taken
- Bond (1041278) grade 2 taken
- Bond (1041279) grade 3 taken
- Bond (1041279) grade 3 taken
- Concentration (1041325) grade 1 damage
- Concentration (1041325) grade 1 damage
- Concentration (1041325) grade 1 damage
- Concentration (1041325) grade 1 damage
- Concentration (1041326) grade 2 damage
- Concentration (1041326) grade 2 damage
- Concentration (1041326) grade 2 damage
- Concentration (1041326) grade 2 damage
- Concentration (1041327) grade 3 damage
- Concentration (1041327) grade 3 damage
- Concentration (1041327) grade 3 damage
- Concentration (1041327) grade 3 damage

## Classe 9

Cas : Pas Chassé teleports the caster and gives it 1 MP on its next turn, Flèche de Recul hits and pushes 2, Tirs Puissants trades range for power, Flèche Harcelante poisons at the start of the target's turns, twice, Œil de Taupe steals range and life for one turn, Balise de Survie disappears 2 turns after, Balise Tactique disappears 3 turns after

Types sans cas : advance, ap, aura, recoil, share, state, taken, trap, unbuff, unstate

Effets non atteints (40) :
- Flèche Fulminante (1085258) grade 1 damage
- Flèche Fulminante (1085258) grade 1 damage
- Flèche Fulminante (1085258) grade 1 damage
- Flèche Fulminante (1085258) grade 1 damage
- Tirs Éloignés (1085273) grade 1 cast
- Tirs Éloignés (1085273) grade 1 cast
- Balise Tactique (1085275) grade 1 push
- Balise Tactique (1085275) grade 1 push
- Balise Tactique (1085275) grade 1 kill
- Balise Tactique (1085275) grade 1 kill
- Balise Tactique (1085275) grade 1 kill
- Balise Tactique (1085275) grade 1 kill
- Balise de Survie (1085282) grade 1 swap
- Balise de Survie (1085282) grade 1 swap
- Balise de Survie (1085282) grade 1 kill
- Balise de Survie (1085282) grade 1 kill
- Balise de Survie (1085282) grade 1 kill
- Balise de Survie (1085282) grade 1 kill
- Tirs Éloignés (1086153) grade 2 cast
- Tirs Éloignés (1086153) grade 2 cast
- Tirs Éloignés (1086154) grade 3 cast
- Tirs Éloignés (1086154) grade 3 cast
- Balise de Survie (1086185) grade 2 swap
- Balise de Survie (1086185) grade 2 swap
- Balise de Survie (1086185) grade 2 kill
- Balise de Survie (1086185) grade 2 kill
- Balise de Survie (1086185) grade 2 kill
- Balise de Survie (1086185) grade 2 kill
- Balise de Survie (1086186) grade 3 swap
- Balise de Survie (1086186) grade 3 swap
- Balise de Survie (1086186) grade 3 kill
- Balise de Survie (1086186) grade 3 kill
- Balise de Survie (1086186) grade 3 kill
- Balise de Survie (1086186) grade 3 kill
- Balise Tactique (1086199) grade 2 push
- Balise Tactique (1086199) grade 2 push
- Balise Tactique (1086199) grade 2 kill
- Balise Tactique (1086199) grade 2 kill
- Balise Tactique (1086199) grade 2 kill
- Balise Tactique (1086199) grade 2 kill

## Classe 10

Cas : La Folle Transmutée becomes a Tree 3 turns after, Arbre summons a tree on the free cell, Vent Empoisonne poisons its target at each of its turns, twice, Chardons Ardents burns the target at the end of its turn

Types sans cas : heal, heal_dealt, heal_pct, kill, mp, pull, reveal, share, shorten, splash_taken, stat, steal, teleport, unbuff, unstate

Effets non atteints (258, 40 premiers) :
- Tremblement (1042080) grade 1 cast
- Tremblement (1042080) grade 1 cast
- Tremblement (1042080) grade 1 damage
- Tremblement (1042080) grade 1 damage
- Tremblement (1042080) grade 1 cast
- Tremblement (1042080) grade 1 cast
- Tremblement (1042080) grade 1 damage
- Tremblement (1042080) grade 1 damage
- Tremblement (1042081) grade 2 cast
- Tremblement (1042081) grade 2 cast
- Tremblement (1042081) grade 2 damage
- Tremblement (1042081) grade 2 damage
- Tremblement (1042081) grade 2 cast
- Tremblement (1042081) grade 2 cast
- Tremblement (1042081) grade 2 damage
- Tremblement (1042081) grade 2 damage
- La Folle Transmutée (1042083) grade 1 replace
- La Folle Transmutée (1042083) grade 1 replace
- Arbre (1042093) grade 1 state
- Arbre (1042093) grade 1 state
- Arbre (1042093) grade 1 state
- Arbre (1042093) grade 1 state
- Arbre (1042094) grade 2 state
- Arbre (1042094) grade 2 state
- Arbre (1042094) grade 2 state
- Arbre (1042094) grade 2 state
- Arbre (1042095) grade 3 state
- Arbre (1042095) grade 3 state
- Arbre (1042095) grade 3 state
- Arbre (1042095) grade 3 state
- La Surpuissante Transmutée (1042096) grade 1 replace
- La Surpuissante Transmutée (1042096) grade 1 replace
- La Sacrifiée Transmutée (1042100) grade 1 replace
- La Sacrifiée Transmutée (1042100) grade 1 replace
- La Gonflable Transmutée (1042101) grade 1 replace
- La Gonflable Transmutée (1042101) grade 1 replace
- La Bloqueuse Transmutée (1042108) grade 1 replace
- La Bloqueuse Transmutée (1042108) grade 1 replace
- Larme de Sadida (1042112) grade 1 cast
- Larme de Sadida (1042112) grade 1 cast

## Classe 11

Cas : Assaut swaps with its target, then hits it, Attirance pulls its target next to the caster, Sacrifice takes the allies' hits on the caster, Fulgurance lands next to its target and hits it, Projection jumps over its target

Types sans cas : advance, aura, heal_attackers, heal_pct, healed, mp, push, shield, shorten, splash_heal, splash_taken, stat, steal, summon, taken, unbuff

Effets non atteints (20) :
- Sacrifice (1040583) grade 1 cast
- Sacrifice (1040583) grade 1 cast
- Sacrifice (1040583) grade 1 transfer_hp
- Sacrifice (1040583) grade 1 transfer_hp
- Sacrifice (1040584) grade 2 cast
- Sacrifice (1040584) grade 2 cast
- Sacrifice (1040584) grade 2 transfer_hp
- Sacrifice (1040584) grade 2 transfer_hp
- Sacrifice (1040585) grade 3 cast
- Sacrifice (1040585) grade 3 cast
- Sacrifice (1040585) grade 3 transfer_hp
- Sacrifice (1040585) grade 3 transfer_hp
- Châtiment (1040614) grade 1 damage
- Châtiment (1040614) grade 1 damage
- Fluctuation (1040617) grade 1 state
- Fluctuation (1040617) grade 1 state
- Fluctuation (1040617) grade 1 mp
- Fluctuation (1040617) grade 1 mp
- Fluctuation (1040617) grade 1 mp
- Fluctuation (1040617) grade 1 mp

## Classe 12

Cas : Karcham carries its target, then throws it, Paume Explosive changes once cast by a sober Pandawa: its next cast hits around, Fermentation shields an ally now and on the next turn

Types sans cas : advance, ap, heal, heal_pct, mp, pull, push, recoil, shorten, steal, summon, sym_caster, sym_target, taken

Effets non atteints (306, 40 premiers) :
- Ivresse (1040634) grade 1 heal_pct
- Ivresse (1040634) grade 1 heal_pct
- Ivresse (1040634) grade 1 state
- Ivresse (1040634) grade 1 state
- Propulsion (1040663) grade 1 heal
- Propulsion (1040663) grade 1 heal
- Propulsion (1040663) grade 1 heal
- Propulsion (1040663) grade 1 heal
- Propulsion (1040663) grade 1 damage
- Propulsion (1040663) grade 1 damage
- Propulsion (1040663) grade 1 damage
- Propulsion (1040663) grade 1 damage
- Propulsion (1040663) grade 1 push
- Propulsion (1040663) grade 1 push
- Propulsion (1040663) grade 1 heal
- Propulsion (1040663) grade 1 heal
- Propulsion (1040663) grade 1 heal
- Propulsion (1040663) grade 1 heal
- Propulsion (1040663) grade 1 damage
- Propulsion (1040663) grade 1 damage
- Propulsion (1040663) grade 1 damage
- Propulsion (1040663) grade 1 damage
- Propulsion (1040663) grade 1 push
- Propulsion (1040663) grade 1 push
- Propulsion (1040664) grade 2 heal
- Propulsion (1040664) grade 2 heal
- Propulsion (1040664) grade 2 heal
- Propulsion (1040664) grade 2 heal
- Propulsion (1040664) grade 2 damage
- Propulsion (1040664) grade 2 damage
- Propulsion (1040664) grade 2 damage
- Propulsion (1040664) grade 2 damage
- Propulsion (1040664) grade 2 push
- Propulsion (1040664) grade 2 push
- Propulsion (1040664) grade 2 heal
- Propulsion (1040664) grade 2 heal
- Propulsion (1040664) grade 2 heal
- Propulsion (1040664) grade 2 heal
- Propulsion (1040664) grade 2 damage
- Propulsion (1040664) grade 2 damage

## Classe 13

Cas : Détonateur sets the Explobombe off and gives AP back, Explobombe summons a bomb, Roublabot summons a robot, Pulsar hits and pushes 2, Piege Magnetique lays a trap

Types sans cas : advance, illusion, mp, pass_turn, pull, rollback_prev, shield, shorten, stat, state, steal, swap, sym_impact

Effets non atteints (374, 40 premiers) :
- Roublardise (1041883) grade 1 shield
- Roublardise (1041883) grade 1 shield
- Roublardise (1041884) grade 2 shield
- Roublardise (1041884) grade 2 shield
- Roublardise (1041885) grade 3 shield
- Roublardise (1041885) grade 3 shield
- Détonateur (1041886) grade 1 unbuff
- Détonateur (1041886) grade 1 unbuff
- Détonateur (1041886) grade 1 cast
- Détonateur (1041886) grade 1 cast
- Détonateur (1041886) grade 1 cast
- Détonateur (1041886) grade 1 cast
- Détonateur (1041886) grade 1 detonate
- Détonateur (1041886) grade 1 detonate
- Détonateur (1041887) grade 2 unbuff
- Détonateur (1041887) grade 2 unbuff
- Détonateur (1041887) grade 2 cast
- Détonateur (1041887) grade 2 cast
- Détonateur (1041887) grade 2 cast
- Détonateur (1041887) grade 2 cast
- Détonateur (1041887) grade 2 detonate
- Détonateur (1041887) grade 2 detonate
- Détonateur (1041888) grade 3 unbuff
- Détonateur (1041888) grade 3 unbuff
- Détonateur (1041888) grade 3 cast
- Détonateur (1041888) grade 3 cast
- Détonateur (1041888) grade 3 cast
- Détonateur (1041888) grade 3 cast
- Détonateur (1041888) grade 3 detonate
- Détonateur (1041888) grade 3 detonate
- Botte (1041892) grade 1 shield
- Botte (1041892) grade 1 shield
- Botte (1041892) grade 1 push
- Botte (1041892) grade 1 push
- Botte (1041892) grade 1 push
- Botte (1041892) grade 1 push
- Botte (1041892) grade 1 push
- Botte (1041892) grade 1 push
- Botte (1041892) grade 1 push
- Botte (1041892) grade 1 push

## Classe 14

Cas : Masque de l'Intrépide: AP for the caster and its allies, pulls who stands 2 cells away, Débandade teleports next to the caster and gives MP, Pivot jumps over the adjacent target

Types sans cas : advance, cooldown, damage, healed, push, recoil, shield, shorten, stat, steal, summon, swap, sym_impact, unbuff

Effets non atteints (90, 40 premiers) :
- Diffraction (1041792) grade 1 shield
- Diffraction (1041792) grade 1 shield
- Diffraction (1041792) grade 1 shield
- Diffraction (1041792) grade 1 shield
- Diffraction (1041792) grade 1 shield
- Diffraction (1041792) grade 1 shield
- Masque de l'Intrépide (1041793) grade 1 cast
- Masque de l'Intrépide (1041793) grade 1 cast
- Masque du Pleutre (1041794) grade 1 cast
- Masque du Pleutre (1041794) grade 1 cast
- Masque du Psychopathe (1041795) grade 1 cast
- Masque du Psychopathe (1041795) grade 1 cast
- Plastron (1041804) grade 1 shield
- Plastron (1041804) grade 1 shield
- Plastron (1041804) grade 1 shield
- Plastron (1041804) grade 1 shield
- Tortoruga (1041805) grade 1 shield
- Tortoruga (1041805) grade 1 shield
- Tortoruga (1041805) grade 1 shield
- Tortoruga (1041805) grade 1 shield
- Transe (1041806) grade 1 shield
- Transe (1041806) grade 1 shield
- Transe (1041806) grade 1 shield
- Transe (1041806) grade 1 shield
- Plastron (1041819) grade 2 shield
- Plastron (1041819) grade 2 shield
- Plastron (1041819) grade 2 shield
- Plastron (1041819) grade 2 shield
- Plastron (1041820) grade 3 shield
- Plastron (1041820) grade 3 shield
- Plastron (1041820) grade 3 shield
- Plastron (1041820) grade 3 shield
- Transe (1041829) grade 2 shield
- Transe (1041829) grade 2 shield
- Transe (1041829) grade 2 shield
- Transe (1041829) grade 2 shield
- Tortoruga (1041837) grade 2 shield
- Tortoruga (1041837) grade 2 shield
- Tortoruga (1041837) grade 2 shield
- Tortoruga (1041837) grade 2 shield

## Classe 15

Cas : Marée swaps with its target and hits it, Torpille hits and pushes 2, Harponneuse summons a steam turret, Foene hits and pushes 2

Types sans cas : advance, ap, heal, heal_pct, intercept, mp, pull, recoil, reveal, shield, stat, state, sym_impact, sym_target, teleport, unbuff, unstate

Effets non atteints (256, 40 premiers) :
- Scaphandre (1042724) grade 1 shield
- Scaphandre (1042724) grade 1 shield
- Scaphandre (1042724) grade 1 shield
- Scaphandre (1042724) grade 1 shield
- Ressac (1042726) grade 1 cast
- Ressac (1042726) grade 1 cast
- Ressac (1042726) grade 1 push
- Ressac (1042726) grade 1 push
- Ressac (1042726) grade 1 cast
- Ressac (1042726) grade 1 cast
- Ressac (1042726) grade 1 push
- Ressac (1042726) grade 1 push
- Vapor (1042731) grade 1 cast
- Vapor (1042731) grade 1 cast
- Vapor (1042731) grade 1 cast
- Vapor (1042731) grade 1 cast
- Ancrage (1042732) grade 1 cast
- Ancrage (1042732) grade 1 cast
- Ancrage (1042732) grade 1 cast
- Ancrage (1042732) grade 1 cast
- Gouvernail (1042733) grade 1 cast
- Gouvernail (1042733) grade 1 cast
- Gouvernail (1042733) grade 1 pull
- Gouvernail (1042733) grade 1 pull
- Gouvernail (1042733) grade 1 cast
- Gouvernail (1042733) grade 1 cast
- Gouvernail (1042733) grade 1 pull
- Gouvernail (1042733) grade 1 pull
- Évolution (1042737) grade 1 state
- Évolution (1042737) grade 1 state
- Évolution (1042737) grade 1 cast
- Évolution (1042737) grade 1 cast
- Évolution (1042737) grade 1 cast
- Évolution (1042737) grade 1 cast
- Évolution (1042737) grade 1 heal_pct
- Évolution (1042737) grade 1 heal_pct
- Évolution (1042737) grade 1 heal_pct
- Évolution (1042737) grade 1 heal_pct
- Évolution (1042737) grade 1 heal_pct
- Évolution (1042737) grade 1 heal_pct

## Classe 16

Cas : Portail lays a portal and raises the caster's final damage, Portail lays a portal that lasts and its bonus ends after 3 turns, Extinction hits once: its delayed hit needs a portal

Types sans cas : advance, ap, cast, heal, heal_dealt, heal_pct, healed, mp, pull, push, recoil, shorten, splash_taken, state, steal, steal_stat, summon, swap, sym_target, teleport, teleportal, unbuff, unportal

Effets non atteints (232, 40 premiers) :
- Poing Fulgurant (1044345) grade 1 push
- Poing Fulgurant (1044345) grade 1 push
- Poing Fulgurant (1044345) grade 1 push
- Poing Fulgurant (1044345) grade 1 push
- Commotion (1044366) grade 1 pull
- Commotion (1044366) grade 1 pull
- Commotion (1044366) grade 1 pull
- Commotion (1044366) grade 1 pull
- Commotion (1044367) grade 2 pull
- Commotion (1044367) grade 2 pull
- Commotion (1044367) grade 2 pull
- Commotion (1044367) grade 2 pull
- Commotion (1044368) grade 3 pull
- Commotion (1044368) grade 3 pull
- Commotion (1044368) grade 3 pull
- Commotion (1044368) grade 3 pull
- Affliction (1044369) grade 1 damage
- Affliction (1044369) grade 1 damage
- Affliction (1044369) grade 1 damage
- Affliction (1044369) grade 1 damage
- Affliction (1044369) grade 1 heal
- Affliction (1044369) grade 1 heal
- Affliction (1044369) grade 1 heal
- Affliction (1044369) grade 1 heal
- Affliction (1044369) grade 1 cast
- Affliction (1044369) grade 1 cast
- Affliction (1044369) grade 1 damage
- Affliction (1044369) grade 1 damage
- Affliction (1044369) grade 1 damage
- Affliction (1044369) grade 1 damage
- Affliction (1044369) grade 1 heal
- Affliction (1044369) grade 1 heal
- Affliction (1044369) grade 1 heal
- Affliction (1044369) grade 1 heal
- Affliction (1044369) grade 1 cast
- Affliction (1044369) grade 1 cast
- Affliction (1044370) grade 2 damage
- Affliction (1044370) grade 2 damage
- Affliction (1044370) grade 2 damage
- Affliction (1044370) grade 2 damage

## Classe 17

Cas : Lance Solaire swaps with its target and hits it, Runification triggers a rune, steals each element and raises the characteristics, Tison lays a fire rune and marks the target with the fire state, Ether lays an air rune and marks the target with the air state

Types sans cas : advance, ap, heal_attackers, healed, mp, pull, push, recoil, rollback_prev, shield, shorten, steal_stat, summon, sym_caster, sym_impact, sym_target, taken, teleport, unbuff

Effets non atteints (48, 40 premiers) :
- Traversée (1042427) grade 1 damage
- Traversée (1042427) grade 1 damage
- Traversée (1042427) grade 1 damage
- Traversée (1042427) grade 1 damage
- Traversée (1042427) grade 1 damage
- Traversée (1042427) grade 1 damage
- Traversée (1042427) grade 1 damage
- Traversée (1042427) grade 1 damage
- Traversée (1042427) grade 1 damage
- Traversée (1042427) grade 1 damage
- Traversée (1042427) grade 1 damage
- Traversée (1042427) grade 1 damage
- Traversée (1042427) grade 1 damage
- Traversée (1042427) grade 1 damage
- Traversée (1042427) grade 1 damage
- Traversée (1042427) grade 1 damage
- Traversée (1042475) grade 2 damage
- Traversée (1042475) grade 2 damage
- Traversée (1042475) grade 2 damage
- Traversée (1042475) grade 2 damage
- Traversée (1042475) grade 2 damage
- Traversée (1042475) grade 2 damage
- Traversée (1042475) grade 2 damage
- Traversée (1042475) grade 2 damage
- Traversée (1042475) grade 2 damage
- Traversée (1042475) grade 2 damage
- Traversée (1042475) grade 2 damage
- Traversée (1042475) grade 2 damage
- Traversée (1042475) grade 2 damage
- Traversée (1042475) grade 2 damage
- Traversée (1042475) grade 2 damage
- Traversée (1042475) grade 2 damage
- Traversée (1042476) grade 3 damage
- Traversée (1042476) grade 3 damage
- Traversée (1042476) grade 3 damage
- Traversée (1042476) grade 3 damage
- Traversée (1042476) grade 3 damage
- Traversée (1042476) grade 3 damage
- Traversée (1042476) grade 3 damage
- Traversée (1042476) grade 3 damage

## Classe 18

Cas : Proie: who hits the prey is healed of part of the damage, Charogne erodes before it hits: the hit already erodes more, Radius swaps with its target and hits it

Types sans cas : advance, aura, cooldown, glyph_now, heal_pct, healed, mp, pull, push, shield, shorten, steal, summon, sym_target, taken, teleport, unbuff, unstate

Effets non atteints (6) :
- Lance-roquet (1042652) grade 1 state
- Lance-roquet (1042652) grade 1 state
- Lance-roquet (1042653) grade 2 state
- Lance-roquet (1042653) grade 2 state
- Lance-roquet (1042654) grade 3 state
- Lance-roquet (1042654) grade 3 state

## Classe 20

Cas : Estoc Brûlant pushes everyone in the cone away from the caster, twice, Estoc Brûlant stops at an obstacle and hurts, Maelstrom swaps with its target and hits it, Volee d'Airain hits and pushes 4 in all (its sub-spell pushes 2 too)

Types sans cas : advance, aura, heal_pct, mp, pass_turn, pull, recoil, shield, shorten, stat, steal, summon, sym_caster, sym_impact, sym_target, taken, teleport, unbuff, unstate

Effets non atteints (536, 40 premiers) :
- Jormun (1059444) grade 1 damage
- Jormun (1059444) grade 1 damage
- Jormun (1059444) grade 1 damage
- Jormun (1059444) grade 1 damage
- Jormun (1059444) grade 1 cast
- Jormun (1059444) grade 1 cast
- Jormun (1059444) grade 1 cast
- Jormun (1059444) grade 1 cast
- Jormun (1059444) grade 1 cast
- Jormun (1059444) grade 1 cast
- Jormun (1059444) grade 1 damage
- Jormun (1059444) grade 1 damage
- Jormun (1059444) grade 1 damage
- Jormun (1059444) grade 1 damage
- Jormun (1059444) grade 1 cast
- Jormun (1059444) grade 1 cast
- Jormun (1059444) grade 1 cast
- Jormun (1059444) grade 1 cast
- Jormun (1059444) grade 1 cast
- Jormun (1059444) grade 1 cast
- Galanterie (1059682) grade 1 cast
- Galanterie (1059682) grade 1 cast
- Galanterie (1059682) grade 1 cast
- Galanterie (1059682) grade 1 cast
- Galanterie (1059682) grade 1 cast
- Galanterie (1059682) grade 1 cast
- Galanterie (1059682) grade 1 cast
- Galanterie (1059682) grade 1 cast
- Renommée (1059689) grade 1 cast
- Renommée (1059689) grade 1 cast
- Renommée (1059689) grade 1 cast
- Renommée (1059689) grade 1 cast
- Phalange (1059713) grade 1 cast
- Phalange (1059713) grade 1 cast
- Parade (1059789) grade 1 cast
- Parade (1059789) grade 1 cast
- Parade (1059789) grade 1 cast
- Parade (1059789) grade 1 cast
- Parade (1059789) grade 1 damage
- Parade (1059789) grade 1 damage

