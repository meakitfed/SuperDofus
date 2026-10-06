"""
Real Dofus 3 spells -> game/data/spells.json (SpellBook format) + their icons and FX bones.

    python spells.py classes --world incarnam+astrub  # every class (P1.03) + the spells of the monsters of Incarnam and Astrub (P1.17)
    python spells.py breed 12                      # old format: one class, first grades only

Every castable spell is a spell *level* (grade): its id is LEVEL_SPELL + spelllevels.id, for
the classes and the monsters alike (a monster grade uses a given level; maps.py writes the same
ids in the monsters' `spells`). `classes` also writes, per breed, the spell pairs of
`spellvariants` (Dofus 3: each slot has two spells, one is chosen) and, per spell, its grade
ids (the grade a character uses is the highest whose `minPlayerLevel` <= its level).

Class spells use their first grade and go in the spell bar (`key`). Monster spells are
spell *levels* (a monster grade uses a given level): their id is MONSTER_SPELL + levelId,
the same id maps.py writes in the monsters' `spells`, and they have `bar: false`.

A spell: {id, name_id, name, key?, bar, icon, level, ap, range: [min, max], range_boost, los,
          in_line, need_free_cell, need_taken_cell, per_turn, per_target, cooldown,
          initial_cooldown, crit (%), area: {shape, size}, effects: [effect], crit_effects: [effect],
          anim, fx, partial?: [unsupported effect ids]}
An effect: {kind, target: enemies|allies|all|caster, min, max, duration, delay, area, ...}
  kinds: damage/steal/heal {element}, push/pull/recoil/advance {damage}, teleport, swap,
         sym_target, sym_caster, sym_impact, rollback_prev, rollback_turn, to_start {effect: effects id, P1.13n / P1.13q}, ap/mp {sign, dodge, steal?} (steal P1.13m), dispel (P1.13m), stat {stat, sign}, steal_stat {stat} (P1.13d),
         shield {of: level|max_hp|flat},
         state/unstate {state, state_name_id, flags},
         summon {monster, grade} / double / replace {monster, grade, replaces} (P1.11),
         carry {states} / throw (P1.12),
         trap / glyph_start / glyph_end / aura {spell: castable sub-spell, color, mark: area, origin} and
         unmark {origin} (P1.13a, aura P1.13b),
         cast {spell, by?: "target"} (a chained sub-spell), taken / healed {pct} (x% damage suffered / heals
         received), unbuff {origin}, kill, heal_pct (% of max HP) (P1.13b),
         reveal (P1.13c; invisibility is a state with the flag `invisible`),
         rune (a mark, like the glyphs) / runes (sets off the caster's runes under the target),
         detonate (the target bomb explodes) (P1.13d),
         portal {spell: the castable a fighter entering it gets (Téléportail), bonus, per_cell} /
         teleportal (the target crosses the portals from its cell) / unportal {all} (P1.13f)
  cond: [{who, state, has}] (states) or [{who, monsters: [monsters.id], has}] (monster filters)
        or [{portal: true|false}] (the spell is / is not projected through a portal, P1.13f)
  carried: true = the effect only touches the entity the caster carries (targetMask K)
  on: [trigger codes] (P1.13b): the effect is not applied at cast but fires on these events,
      as a buff of `turns` turns on its target (-1 = the whole fight); now: also at cast.
A spell also has origin (its spells.id) and max_stack (spelllevels.maxStack), and
start_states (P1.13f): states its owner starts its fights in (VARIANT_STATES).
`summons` (P1.11): monster id -> what a summon effect brings in (summon_data), with each
grade's `start` spell (startingSpellId, cast when it arrives, P1.13b); a bomb (P1.13d) has
`explode`, `chain`, `instant` (castables per grade: spellbombs explodSpellId, chainReactionSpellId,
instantSpellId) and `wall` {spells (per
grade), color, linear, min, max} (spellbombwalls: the spell hitting the wall's cells, minHop / maxHop).
Spells with an unsupported effect or trigger code are marked `partial`, and so are the spells
whose sub-spells (cast, marks, start spells) are. Icons -> Content/Picto/Spells/<icon>.webp, FX bones -> Content/Characters/Bones/<id>/.
"""
from __future__ import annotations

import argparse
import json
import re
import struct
import sys
from pathlib import Path

import UnityPy

sys.path.insert(0, str(Path(__file__).parent))
from extract import DEFAULT_GAME, Extractor, detect_unity_version  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CONTENT = ROOT / "game" / "content" / "Content"
OUT = ROOT / "game" / "data" / "spells.json"
TABLES = ("spellsdataroot", "spelllevelsdataroot", "spellscriptsdataroot", "breedsdataroot", "spellstatesdataroot",
          "spellvariantsdataroot")
MONSTER_SPELL = LEVEL_SPELL = 1_000_000
COMMON_SPELLS = [0]  # spells.id 0 "Coup de poing"
# states a class starts its fights in (Pandawa: Sober 3531; its spells switch it to Drunk 498)
START_STATES = {12: [3531]}

# SpellLevel.m_flags bits
IN_LINE, IN_DIAGONAL, TEST_LOS, NEED_FREE_CELL, NEED_TAKEN_CELL = 1, 2, 4, 8, 16
RANGE_BOOSTABLE = 64
# effect ids (same as Dofus 2) -> our effect kinds (see shared/spell_book.gd)
# 2822 "dommages du meilleur élément" / 2828 "vol du meilleur élément" (P1.17b): the element is chosen when
# the hit lands, the caster's best one (FightEffects.best_element)
DAMAGE = {96: "water", 97: "earth", 98: "air", 99: "fire", 100: "neutral", 2822: "best"}
STEAL = {91: "water", 92: "earth", 93: "air", 94: "fire", 95: "neutral", 2828: "best"}
# 3002 "Soins du meilleur élément" (P1.17b 7): the caster's best element (FightEffects.best_element)
HEAL = {3002: "best", 108: "fire", 2998: "water", 2999: "air", 3000: "earth", 81: "neutral"}
# P1.17b (10): 1012-1016 "#1 à #2 dommages <élément> (% PM restants)": the dice scaled by the share of the
# target's MP left (FightEffects._base `mp_left`). APPROX(P1.17b): only the i18n text, no formula found
MP_LEFT_DAMAGE = {1012: "neutral", 1013: "air", 1014: "water", 1015: "fire", 1016: "earth"}
LIFE_PCT_DAMAGE, AP_USED_DAMAGE = 1071, 1132  # damage of a % of the target's life / per AP it used (P1.17)
HEAL_PCT = 1109  # "Soin : #1{{~1~2 à }}#2% des PV max" (P1.13b)
PUSH = {5: "push", 1103: "push", 1021: "push", 783: "push", 1043: "pull", 6: "pull", 1041: "recoil", 1042: "advance"}
MOVES = {4: "teleport", 8: "swap", 1101: "swap", 1023: "swap", 1104: "sym_target", 1105: "sym_caster",
         1106: "sym_impact", 1100: "rollback_prev", 1099: "rollback_turn", 784: "to_start"}  # P1.13q
# P1.13n: the effect id stays on the move ({effect}): the client's swap rules (gzj.bmxr / gzj.bmww,
# FightEffects.can_swap) differ between 8 and 1101 (FightTeleswap) and between the others
# +/- AP and MP. dodge: the loss can be dodged (rolls on the caster's wisdom vs the target's dodge)
RESOURCES = {111: ("ap", 1, False), 128: ("mp", 1, False), 101: ("ap", -1, True), 127: ("mp", -1, True),
             168: ("ap", -1, False), 169: ("mp", -1, False),
             1079: ("ap", -1, True), 1080: ("mp", -1, True)}
# P1.13m: AP / MP steals (client enum ActionId: 84 CharacterActionPointsSteal, 77 CharacterMovementPointsSteal;
# dodgeable, the "NoEvade" variants are other ids): the target loses them as with 101 / 127, the caster wins what
# was lost for as long (resource `steal`). CAPA / CMPA on the caster (gzp.bnaa: a stat output with isSteal)
STEAL_RESOURCES = {84: "ap", 77: "mp"}
# P1.13m: 132 CharacterRemoveAllEffects "Enlève les envoûtements" (dispel): the target loses its buffs whose
# effect has dispellable 1; the effects' `dispellable` (1 / 2 / 3: the client's buff tooltip,
# BuffsUiHelpTooltipBinding: dispellable, dispellableAtDeath, notDispellable) is kept when not 1
DISPEL = 132
# characteristic buffs: effect id -> (stat, sign)
STATS = {118: ("strength", 1), 119: ("agility", 1), 123: ("chance", 1), 124: ("wisdom", 1), 125: ("vitality", 1),
         126: ("intelligence", 1), 138: ("power", 1), 186: ("power", -1), 112: ("damage", 1), 121: ("damage", 1),
         142: ("damage", 1), 143: ("heals", 1), 117: ("range", 1), 116: ("range", -1), 161: ("mp_dodge", 1),
         171: ("crit", -1), 210: ("res_earth", 1), 211: ("res_water", 1), 212: ("res_air", 1),
         213: ("res_fire", 1), 214: ("res_neutral", 1), 417: ("push_res", -1),
         # "#1% Dommages finaux", "-#1% Dommages finaux", "#1% Soins finaux", "#1% Dommages Combo" (P1.13d)
         1171: ("final_damage", 1), 1172: ("final_damage", -1), 2971: ("final_heals", 1), 1027: ("combo", 1),
         753: ("tackle", 1), 754: ("escape", -1),  # "#1 Tacle", "-#1 Fuite"
         # P1.17, the Deboost twins of the boosts above (their i18n texts "-#1 Force", "-#1% Résistance Terre"…)
         157: ("strength", -1), 154: ("agility", -1), 152: ("chance", -1), 155: ("intelligence", -1),
         215: ("res_earth", -1), 216: ("res_water", -1), 217: ("res_air", -1), 218: ("res_fire", -1),
         219: ("res_neutral", -1), 1076: ("res_all", 1),  # 1076 "#1% Résistance": every element (Fighter.stat)
          163: ("mp_dodge", -1), 179: ("heals", -1), 752: ("escape", 1),  # 752 "#1 Fuite"
          # P1.17b: 115 "#1% Critique", 178 "#1 Soin" (like 143), 414 "#1 Dommages Poussée" (Fighter push_damage)
          115: ("crit", 1), 178: ("heals", 1), 414: ("push_damage", 1),
          # 420 "#1 Résistance Critiques": flat damage taken less from critical hits (FightEffects.damage)
          420: ("crit_res", 1),
          # 182 "#1 Invocation" (Fighter "summons", read by Summons.max_summons); 776 "#1% Erosion": stat buff
          # kept for P1.14 (APPROX(P1.17b): erosion itself is not simulated, nothing reads "erosion")
          182: ("summons", 1), 776: ("erosion", 1),
         # P1.17b (12): 781 CharacterUnlucky / 782 CharacterMaximizeRoll (client enum ActionId): the bearer's damage and heal
         # rolls are forced to their minimum / maximum (FightEffects.roll). APPROX(P1.17b): from the enum names only
         781: ("roll_min", 1), 782: ("roll_max", 1),
         # P1.17b (5), names from the client enum ActionId (docs/client_enums.md): 145 DeboostDamages,
         # 160 / 162 Boost / Deboost ActionPointsLostDodge, 410 / 412 Boost Ap / Mp Attack (stats ap_attack /
         # mp_attack, EquipmentCharacteristic 82 / 83), 416 BoostPushDamageReduction, 418 BoostCriticalDamagesBonus,
         # 755 DeboostTakleBlock. APPROX(P1.17b): signs and stat names from the enum names only
         145: ("damage", -1), 160: ("ap_dodge", 1), 162: ("ap_dodge", -1), 410: ("ap_attack", 1),
         412: ("mp_attack", 1), 416: ("push_res", 1), 418: ("crit_damage", 1), 755: ("tackle", -1),
         # P1.17b (6): 419 / 421 "-#2 Dommages / Résistance Critiques" (twins of 418 / 420), 265 "-#2 dommages reçus",
         # 2800 / 2804 / 2812 "#2% Dommages mêlée / distance / aux sorts", 2803 "#2% Résistance mêlée".
         # APPROX(P1.17b): the last four have no reader in the formulas yet (melee / ranged / spell damage multipliers)
         419: ("crit_damage", -1), 421: ("crit_res", -1), 265: ("dmg_taken", -1), 2800: ("melee_damage", 1),
         2804: ("ranged_damage", 1), 2812: ("spell_damage", 1), 2803: ("melee_res", -1),
         # P1.17b (9), names from the client enum ActionId + texts: 2802 / 2806 "-#1% Résistance mêlée / distance"
         # (Boost ReceivedDamagePercentMultiplier = more damage taken), 2807 "+#2% Résistance distance", 2805
         # "-#1% Dommages distance", 2972 "-#1% Soins finaux". APPROX(P1.17b): no reader in the formulas yet
         2802: ("melee_res", -1), 2806: ("ranged_res", -1), 2807: ("ranged_res", 1),
         2805: ("ranged_damage", -1), 2972: ("final_heals", -1)}
# P1.17b, buffs on one spell of the target: 285 "#1 : -#3 PA" (diceNum = the spell, value = the AP),
# 2935 "#1 : +#3 soins de base" -> a stat buff "spell_mod:<ap|heal>:<spells.id>" read by Fighter.spell
# 2905 / 2906 "#1 : Portée maximale / minimale fixée à #3" (rmax / rmin: set, not added)
SPELL_MODS = {285: ("ap", -1), 2935: ("heal", 1), 2905: ("rmax", 1), 2906: ("rmin", 1),
              # P1.17b (6): 290 "#1 : +#3 lancer(s) par tour", 280 "#1 : +#3 Portée minimale", 287 "#1 : +#3% Critique",
              # 289 "#1 : ligne de vue désactivée", 299 "#1 : case libre nécessaire activée" (flags: value forced to 1)
              290: ("perturn", 1), 295: ("rminadd", -1),  # 295 DeboostSpellRangeMin "#1 : -#3 Portée minimale"
               280: ("rminadd", 1), 287: ("crit", 1), 289: ("nolos", 1), 299: ("freecell", 1),
              # P1.17b (9): 291 "#1 : +#3 lancer(s) par cible", 297 "#1 : case occupée nécessaire désactivée",
              # 314 "#1 : case occupée nécessaire activée", 798 "#1 : cible visible nécessaire activée"
              291: ("pertarget", 1), 297: ("notaken", 1), 314: ("taken", 1), 798: ("visible", 1)}
# P1.17b, 1078 "#1% Vitalité": a vitality buff of that % of the target's max life (FightEffects "stat", `pct`);
# 1026 "Déclenche les glyphes": the caster's glyphs under the target go off
VITALITY_PCT, GLYPH_TRIGGER = 1078, 1026
VITALITY_PCT_LOSS = 1048  # P1.17b (6) "-#2% PV": the same buff, negative
# P1.17b (9): 2844 CharacterBoostVitalityPercent "#1 à #2% Vitalité", 1033 "-#1 à #2% Vitalité" (same buffs)
VITALITY_PCT_MORE, VITALITY_PCT_LESS = 2844, 1033
# 279 "Dommages Neutre : #1 à #2% PV manquants du lanceur", 2832 "#1 à #2 dommages du pire élément"
CASTER_MISSING_DAMAGE, WORST_DAMAGE = 279, 2832
# "Vole #1 Portée" (P1.13d): the target loses it, the caster gains it
STEAL_STATS = {320: "range", 266: "chance", 267: "vitality", 268: "agility", 269: "intelligence",
               270: "wisdom", 271: "strength"}  # 266-271 CharacterSteal<stat> (P1.17b, like 320)
SHIELDS = {1020: "level", 1039: "max_hp", 1040: "flat"}  # 1040 "#1 Bouclier": that many points
# summons (P1.11): diceNum = the monster (monsters.id), diceSide = its grade.
# 181 "Invoque : #1", 180 "Invoque un double du lanceur", 405 / 2796 "Tue la cible et remplace
# par l'invocation : #1" (effects table). APPROX(P1.11): 1011 and 1008 (bombs) have the same text
# as 181 and are summoned the same way; what sets them apart (controlled summons, bomb walls,
# explosions) is server-side, bombs' mechanics come with the glyphs (P1.13)
SUMMONS = {181: "summon", 1011: "summon", 1008: "summon", 180: "double", 405: "replace", 2796: "replace"}
# monsters.m_flags: the booleans of the Dofus 2 Monster class, in field order (bit 0
# useSummonSlot = summonCost > 0 for 4 646 of 4 665 monsters; bits 2 / 3 boss / mini-boss, P1.09)
M_SUMMON_SLOT, M_BOMB_SLOT, M_CAN_PLAY, M_CAN_TACKLE = 1, 2, 1 << 6, 1 << 7
# P1.13n, client code MonsterData.get_canSwitchPos / get_canSwitchPosOnTarget: m_flags bits 9 / 10
M_CAN_SWITCH, M_CAN_SWITCH_ON_TARGET = 1 << 9, 1 << 10
# P1.17b (13): 952 "Désactive l'état #3" read as unstate (APPROX: the state is removed, not suspended)
STATES = {950: "state", 951: "unstate", 952: "unstate"}
# carry / throw (P1.12): 50 "Porte la cible", 51 "Lance une entité" (effects table). The carrier
# is in state 3 "Porteur" (spellstates: preventsSpellCast; the throws need it: statesCriterion
# HS=3), the carried one in state 8 "Porté" (Karcham: HS!8). targetMask *e3 / *E3 picks the
# carry or the throw of Karcham / Chamrak, K the carried entity.
CARRY = {50: "carry", 51: "throw"}
CARRIER_STATE, CARRIED_STATE = 3, 8
SPELL_RANGE = 281  # "#1 : +#3 Portée maximale" (diceNum = the spell)
# marks (P1.13a): 400 "Pose un piège", 401 "Pose un glyphe de début de tour", 402 "... de fin
# de tour" (effects table). diceNum = the spell the mark casts, diceSide = its grade, value =
# the mark's colour (RGB), zone = the mark's cells, duration = the caster's turns (0 = until
# triggered). 2018 "Dissipe les glyphes": the caster's marks of spell diceNum.
# 1091 "Pose un glyphe-aura" (P1.13b): same shape, its spell's effects last while inside.
# 2022 "Pose une rune" (P1.13d): same shape; set off by 2023 "Déclenche les runes".
# 1165 (P1.13e): "Pose un glyphe" = ActionId FightAddGlyphCastingSpellImmediate (client enum
# Metadata.Effect.ActionId, docs/client_enums.md): its spell is cast at once on who stands in it.
MARKS = {400: "trap", 401: "glyph_start", 402: "glyph_end", 1091: "aura", 2022: "rune", 1165: "glyph_now"}
UNMARK, RUNES = 2018, 2023
# P1.17b, cooldown changes (client enum ActionId, texts "#1 : relance fixee a #3 tour", "-#3 tour de
# relance", "+#3 tour de relance"): diceNum = the spell (spells.id), value = the turns
COOLDOWNS = {1045: "set", 1036: "sub", 1035: "add"}
# P1.17b (7): 1031 CharacterPassCurrentTurn "Passe le tour": the target's turn ends (FightEffects.pass_turn)
PASS_TURN = 1031
# bombs (P1.13d): 1009 "Déclenche une bombe": the bomb casts its explosion (spellbombs.explodSpellId,
# at the bomb's grade); walls (spellbombwalls) link two aligned bombs
DETONATE = 1009
# portals (P1.13f): 1181 "Pose un portail (+#3% dommages, +#1% dommages par case d'éloignement
# entre 2 portails)": diceNum = #1, value = #3, diceSide = the spelllevels.id of "Téléportail"
# (1182), what a fighter entering the portal gets. 1182 "Téléportail": the target crosses the
# portals. 1183 "Désactive un portail" for `duration` turns; Interruption "Désactive tous les
# portails" has zone shape A: APPROX(P1.13f): A = every portal, read from its description
# (JondoEmu docs/zonas.md: A not measured).
PORTAL, TELEPORTAL, UNPORTAL = 1181, 1182, 1183
# the Eliotrope's variant pair Portail / Errance: spells 24955 "Portail" and 24956 "Errance" set
# states 3737 "Portail" / 3738 "Errance" on their caster, and the portal spells place their portal
# only in one of them (*E3737 / *E3738). APPROX(P1.13f): nothing in the data casts 24955 / 24956
# (a passive of the chosen variant, server-side): linked by their names, the owner of the variant
# starts its fights in that state.
VARIANT_STATES = {14574: [3737], 14604: [3738]}
# chained spells (P1.13b): "#1", diceNum = the spell, diceSide = its grade (JondoEmu
# Managers/EffectEngine.cs LosQueEncadenan: 99 % of these entries name a real spell and grade)
CAST = {792, 1017, 1018, 1019, 1160, 2160, 2794, 2795, 2960}
# 792: the TARGET casts the spell (APPROX(P1.13b): read from the data, not measured: the Sram's
# "Échange du Double" reached by a 792 kills its caster, which must be the Double holding it;
# the summons' 792 hooks are on themselves). The others: the caster casts it on the target.
CAST_BY_TARGET = {792}
# 1163 "Dommages subis x#1%", 1159 "Soins reçus x#1%": multipliers (diceNum = the %)
MULTIPLIERS = {1163: "taken", 1159: "healed"}
# P1.13e, names from the client enum Metadata.Effect.ActionId (docs/client_enums.md), always on a
# damage trigger (D, DM): 786 CharacterHealAttackers "Soin sur l'attaquant : #1% des dommages" (value = the
# %), 765 CharacterSacrify "Intercepte les dommages", 1061 CharacterShareDamages "Partage les dommages"
REDIRECTS = {786: "heal_attackers", 765: "intercept", 1061: "share"}
# P1.13o: 107 CharacterLifeLostReflector "Renvoie #1 dommages" / 220 CharacterReflectorUnboosted (always on D:
# the monsters' buffs; diceNum = the damage sent back, a flat value). 106 CharacterSpellReflector is not read (APPROX)
REFLECTS = {107: "boosted", 220: "unboosted"}
# P1.13r: 106 CharacterSpellReflector (34 grades, monster spells: diceSide 1-100, value 15-100, triggers
# "APA|D" or "D", which say nothing about it). APPROX(P1.13r): nothing in the client names the fields
# (no reader in the native code; only the texts ui.fight.reflectSpell): diceSide = the highest spell
# grade sent back, value = the chance in %, a plain buff for `duration` turns (no trigger code)
SPELL_REFLECT = 106
UNBUFF_RANK, CASTER_LIFE_DAMAGE = 1406, 89
# P1.17b (11): 90 "Transfere #1 a #2% des PV" (the caster gives that % of its life to the target), 2973 "Soin : #1 a #2% des
# dommages occasionnes" (the target heals that % of the damage the caster dealt in this cast), 1223 "Dommages : #1 a #2% des
# dommages finaux subis" (a damage trigger: the target takes that % of the hit that fired it). APPROX(P1.17b): only the i18n texts.
TRANSFER_HP, HEAL_DEALT, SPLASH_TAKEN = 90, 2973, 1223
SPLASH_HEAL = 2020  # P1.17b (13) "Soin : #1 à #2% des dommages subis" (APPROX: i18n text only)
KILL, UNBUFF = 141, 406  # "Tue la cible", "Enlève les effets du sort #2" (value = spells.id)
# invisibility (P1.13c): 150 "Rend la cible invisible" = spellstates 250 "Invisible" (APPROX(P1.13c):
# linked by their names; the state has no other flag), 202 "Dévoile les entités invisibles"
INVISIBLE, INVISIBLE_STATE, REVEAL = 150, 250, 202
# trigger codes the sim fires (sim/fight/FightTriggers); an effect with another code makes its spell partial
TRIGGERS = {"TB", "TE", "D", "DA", "DE", "DF", "DW", "DN", "DBE", "DBA", "DM", "DR", "H", "X",
            # P1.13f: PT the holder crosses a portal, CPT any fighter crosses one. APPROX(P1.13f): read
            # from their spells' texts (Coalition "Soigne la cible lorsqu'elle traverse un portail",
            # Entraide "lorsqu'une entité traverse un portail"); only Eliotrope spells use CPT
            "PT", "CPT",
            # P1.13e: CCMPARR, once per MP the holder uses walking (JondoEmu docs/disparadores.md: measured
            # on a capture, eleven cells, eleven triggers; its spells' texts: "pour chaque PM utilisé")
            "CCMPARR",
            # P1.13i: read in the client's fight preview (class gzp, see FightTriggers): hits (DS, DT, DG, PD),
            # what the holder does (CD..., CH, CS, CC, K, KWS), moves (M, P, MA), AP / MP / range / vitality
            # (APA, MPA, R, LPU), invisibility (ION, IOFF); EON<n> / EOFF<n> and EK:<mask> (TRIGGER_PARAMS)
            "DS", "DT", "DG", "PD", "CD", "CDA", "CDE", "CDF", "CDW", "CDN", "CDBA", "CDBE", "CDM", "CDR",
            "CDS", "CDT", "CDG", "CH", "CS", "CC", "K", "KWS", "M", "P", "MA", "APA", "MPA", "R", "LPU",
            "ION", "IOFF",
            # P1.13m, gzp: MS the holder is swapped (a move output with swappedEntityId), PO it moves a
            # fighter (bnaa), CAPA / CMPA it steals AP / MP, DIS it is dispelled (a dispel output),
            # DCAC / CDCAC / KWW by a weapon (hv.nhd), DCCBA / DCCBE / CDCCBA / CDCCBE by an ally / an
            # enemy with a critical effect, CION / CIOFF it makes someone invisible / visible, V / VA its
            # life changes (VM / VE: permanent damage, never here: no erosion), PPD push damage
            "MS", "PO", "CAPA", "CMPA", "DIS", "DCAC", "CDCAC", "KWW", "DCCBA", "DCCBE", "CDCCBA", "CDCCBE",
            "CION", "CIOFF", "V", "VA", "VE", "VM", "PPD",
            # P1.13p, deduced from the i18n descriptions of the spells using them (FightTriggers.ALIASES):
            # XD / XPD / XDM / XDTB = D / PD / DM / DTB, TP moved, CPD moves a fighter, CMPAS / CAPAS steals
            # MP / AP, DTB poison damage, DTE (never lit). APPROX(P1.13p): not measured
            "XD", "XPD", "XDM", "XDTB", "TP", "CPD", "CMPAS", "CAPAS", "DTB", "DTE",
            # P1.17b (14): CMPARR = CCMPARR (the client's name; FightTriggers.ALIASES)
            "CMPARR"}
# codes with a parameter (grs.blfu reads the letters, Triggers.blgb / blfz the rest): state n, a mask
TRIGGER_PARAMS = {"EON": r"\d+", "EOFF": r"\d+", "EK": r":[^|]+"}


def known_trigger(code: str) -> bool:
    m = re.fullmatch(r"([A-Za-z]+)(.*)", code)
    if not m:
        return False
    if m.group(1) in TRIGGER_PARAMS:
        return re.fullmatch(TRIGGER_PARAMS[m.group(1)], m.group(2)) is not None
    return code in TRIGGERS


WHOLE_FIGHT = 63  # effectTriggerDuration of the summons' hooks (never counts down)
# triggers / visuals we can skip without changing what the spell does
# 2792 TargetExecuteSpellGlobalLimitation (Xelor, text "#1", inactive, diceNum = a spells.id, value = a count):
# APPROX(P1.17b): a global cast limit on the target we cannot read; the spells keep their own per_turn / per_target
# 2184 TargetFollowCaster (P1.17b 14): APPROX(P1.17b): the target following its caster's moves is not simulated
# 2027 ControlEntity "Prend le controle de l'entite" (P1.17b 15; buff of unlimited duration on a summon / Double / turret):
# APPROX(P1.17b): the player does not take over the entity's turn, FightAI keeps playing it
IGNORED = {2027, 2184, 2793, 333, 2792, 2017,  # 2017 TargetExecuteSpellOnSourceGlobalLimitation (like 2792, P1.17b 9)
            # P1.17b (7): 2793 (like 2792, animated), 333 CharacterChangeColor (looks)
           3792, 3793, 1075, 120, 666, 293, 296, 281, 411, 413, 335,  # 335 "Change l'apparence" (P1.17b: looks only)  # 411/413: % AP/MP retreat
           1060, 149}  # "Taille : #1", "Change l'apparence": looks only (APPROX(P1.13d): not shown)
# zoneDescr.shape: the client enum Metadata.Enums.SpellZoneShape (docs/client_enums.md) names each letter
# (P1.13e); shared/FightRules.zone draws them as the client's native code does (P1.13g: factory gru.blgy,
# classes SpellZoneShape*Behavior). N (Regular) has no class in the client (gru.blgy logs an error): it
# stays a point; ; (Custom) lists zoneDescr.cellIds (monster spells only, zone_of: "custom").
SHAPES = {"P": "point", "C": "circle", "X": "cross", "G": "square", "Q": "cross_ring", "O": "ring",
          "L": "line", "T": "tline", "*": "star", "a": "all",
          "A": "all",  # WholeMapWithTheDead (the dead have no cell here)
          "+": "diagonal_cross", "#": "diagonal_cross_ring", "/": "diagonal_line", "-": "diagonal_tline",
          "l": "from_caster", "V": "cone", "U": "half_circle", "F": "fork", "W": "square_ring", "I": "outside",
          "D": "checkerboard", "B": "boomerang", "R": "rectangle", "Z": "outside_complex"}
# shapes whose param2 is a minimum distance / first step (gru.blgy passes it to Circle, Cross, Line,
# PerpendicularLine, Boomerang, Checkerboard); R's param2 is its length, l's its number of cells
MIN_SHAPES = {"C", "X", "Q", "+", "#", "*", "L", "/", "T", "-", "B", "D"}
STATE_FLAGS = {"cantBeMoved": "cant_be_moved", "cantBePushed": "cant_be_pushed", "invulnerable": "invulnerable",
               "preventsSpellCast": "no_cast", "cantTackle": "cant_tackle", "cantBeTackled": "cant_be_tackled",
               "cantDealDamage": "no_damage", "incurable": "incurable", "cantSwitchPosition": "cant_switch"}


def i18n_reader(path: Path):
    b = path.read_bytes()
    n = b[0]
    pos = 1 + n
    count = struct.unpack_from("<i", b, pos)[0]
    pos += 4
    index = dict(struct.unpack_from("<ii", b, pos + 8 * i) for i in range(count))

    def text(key: int) -> str:
        off = index.get(int(key))
        if off is None:
            return ""
        length = shift = 0
        while True:
            c = b[off]
            off += 1
            length |= (c & 0x7F) << shift
            shift += 7
            if c < 0x80:
                break
        return b[off:off + length].decode("utf-8")
    return text


def parse_params(raw: str) -> dict:
    out = {}
    for kv in raw.split(","):
        if ":" in kv:
            k, v = kv.split(":", 1)
            out[k.strip()] = v.strip()
    return out


def zone_of(z: dict | None) -> dict:
    shape = chr(z["shape"]) if z and z["shape"] else "P"
    if shape == ";":  # Custom (P1.13l, client class grx): the listed cells, wherever the spell is cast
        return {"shape": "custom", "size": 0, "cells": [int(c) for c in z.get("cellIds") or []]}
    if shape not in SHAPES or shape == "P":
        return {"shape": "point", "size": 0}
    out = {"shape": SHAPES[shape], "size": int(z["param1"])}
    # P1.13l: onlyAffectIfInSightLine (grt -> gtb.blnw: only the cells in sight from the centre)
    # and includeCarried (gtz.nhs: a carried fighter is only touched with it; 1 on every point,
    # so only written on the other shapes)
    if z.get("onlyAffectIfInSightLine"):
        out["sight"] = True
    if z.get("includeCarried"):
        out["with_carried"] = True
    p2 = int(z.get("param2") or 0)
    if shape in MIN_SHAPES and p2 > 0:
        out["min"] = p2
    elif shape == "R":
        out["length"] = p2
    elif shape == "l":  # LineFromCaster: param1 = first cell (from the caster), param2 = number of cells
        out["max"] = p2
        if z.get("isStopAtTarget"):
            out["stop"] = True
    # damage decrease in areas (P1.13j, FightRules.efficiency): step % per step away from the centre,
    # at most `steps` times (10 / 4 on almost every effect)
    if (z.get("damageDecreaseStepPercent") or 0) > 0 and (z.get("maxDamageDecreaseApplyCount") or 0) > 0:
        out["step"] = int(z["damageDecreaseStepPercent"])
        out["steps"] = int(z["maxDamageDecreaseApplyCount"])
    return out


# targetMask side letters (client class gty, sides read by gtz.blqf; see sim target_mask.gd)
SIDE_LETTERS = set("aAgcChHlLmMjJiIsSdDx")


def conditions(mask: list) -> list:
    """The target-mask conditions checked before the targets (the caster's ones) and shown in the
    tooltips; per target, the whole mask is checked by sim TargetMask (client code gtz.blqe, P1.13h).
    *E<id> / *e<id> = the caster is / is not in state id, E<id> / e<id> = same for the target
    -> [{who: caster|target, state, has}]. F<id>... = the target is one of these monsters
    (monsters.id), f<id> = it is not -> {who, monsters: [ids], has} (several F are alternatives,
    gtz.blqd)."""
    out = []
    # R / r: the spell is / is not projected through a portal (gtz.blqe: the fight state's cell
    # 0..559; Poing Fulgurant pushes 2 with r, 4 with R: "si le sort est projeté")
    for m in mask:
        if m in ("R", "r"):
            out.append({"portal": m == "R"})
    for m in mask:
        who = "caster" if m.startswith("*") else "target"
        m = m.lstrip("*")
        if len(m) > 1 and m[0] in "Ee" and m[1:].isdigit():
            out.append({"who": who, "state": int(m[1:]), "has": m[0] == "E"})
    for letter, has in (("F", True), ("f", False)):
        for who, star in (("target", ""), ("caster", "*")):
            ids = [int(m[len(star) + 1:]) for m in mask if m.startswith(star + letter) and m[len(star) + 1:].isdigit()]
            if ids and has:
                out.append({"who": who, "monsters": ids, "has": True})
            elif ids:
                out += [{"who": who, "monsters": [i], "has": False} for i in ids]
    return out


def convert_effect(e: dict, states: dict):
    """One level effect -> our effect dict, None if skippable, "unsupported" otherwise."""
    eid = e["effectId"]
    mask = [m.strip() for m in e["targetMask"].split(",") if m.strip()]
    # `mask`: the raw targetMask, checked per target by sim TargetMask as the client's native code
    # does (P1.13h, class gtz). `target` only sums up its side letters (AI, marks, tooltips):
    # lowercase = the caster's side, uppercase = the other one, C / c = the caster.
    letters = {m for m in mask if m in SIDE_LETTERS}
    if letters <= {"C", "c"} and letters:
        team = "caster"
    elif letters and letters <= set("AHLMJISD"):
        team = "enemies"
    elif letters and letters <= set("agcChlmjisd"):
        team = "allies"
    else:
        team = "all"
    lo, hi = e["diceNum"], max(e["diceNum"], e["diceSide"])
    out = {"target": team, "min": lo, "max": hi, "duration": int(e["duration"]), "delay": int(e["delay"]),
           "area": zone_of(e["zoneDescr"])}
    if mask:
        out["mask"] = ",".join(mask)
    cond = conditions(mask)
    if cond:
        out["cond"] = cond
    if "K" in mask:
        out["carried"] = True
    if eid in DAMAGE:
        out.update(kind="damage", element=DAMAGE[eid])
    elif eid == LIFE_PCT_DAMAGE:  # P1.17, 1071 "Dommages Neutre : #1% PV de la cible"
        out.update(kind="damage", element="neutral", hp_pct=int(e["diceNum"]), min=0, max=0)
    elif eid in MP_LEFT_DAMAGE:
        out.update(kind="damage", element=MP_LEFT_DAMAGE[eid], mp_left=True)
    elif eid == CASTER_MISSING_DAMAGE:  # P1.17b (9)
        out.update(kind="damage", element="neutral", caster_missing_pct=True)
    elif eid == WORST_DAMAGE:  # P1.17b (9)
        out.update(kind="damage", element="worst")
    elif eid == CASTER_LIFE_DAMAGE:  # P1.17b (8), 89 "Dommages Neutre : #1 à #2% PV du lanceur"
        out.update(kind="damage", element="neutral", caster_hp_pct=True)
    elif eid == AP_USED_DAMAGE:  # P1.17, 1132 "#2 dommages Eau pour #1 PA utilisé"
        out.update(kind="damage", element="water", per_ap=[int(e["diceNum"]), int(e["diceSide"])], min=0, max=0)
    elif eid in STEAL:
        out.update(kind="steal", element=STEAL[eid])
    elif eid in HEAL:
        out.update(kind="heal", element=HEAL[eid])
    elif eid == TRANSFER_HP:
        out.update(kind="transfer_hp")
    elif eid == HEAL_DEALT:
        out.update(kind="heal_dealt")
    elif eid == SPLASH_TAKEN:
        out.update(kind="splash_taken")
    elif eid == SPLASH_HEAL:
        out.update(kind="splash_heal")
    elif eid == HEAL_PCT:
        out.update(kind="heal_pct")
    elif eid in PUSH:
        out.update(kind=PUSH[eid], min=max(1, lo), max=max(1, lo), damage=eid not in (1103,))
    elif eid in MOVES:
        out.update(kind=MOVES[eid], effect=eid)
    elif eid in RESOURCES:
        res, sign, dodge = RESOURCES[eid]
        out.update(kind=res, sign=sign, dodge=dodge)
    elif eid in STEAL_RESOURCES:
        out.update(kind=STEAL_RESOURCES[eid], sign=-1, dodge=True, steal=True)
    elif eid == DISPEL:
        out.update(kind="dispel", min=0, max=0)
    elif eid in STATS:
        stat, sign = STATS[eid]
        out.update(kind="stat", stat=stat, sign=sign)
    elif eid in SPELL_MODS:
        what, sign = SPELL_MODS[eid]
        val = 1 if what in ("nolos", "freecell") else int(e["value"])
        out.update(kind="stat", stat="spell_mod:%s:%d" % (what, int(e["diceNum"])), sign=sign, min=val, max=val)
    elif eid == VITALITY_PCT:
        out.update(kind="stat", stat="vitality", sign=1, pct=True)
    elif eid == VITALITY_PCT_LOSS or eid == VITALITY_PCT_LESS:
        out.update(kind="stat", stat="vitality", sign=-1, pct=True)
    elif eid == VITALITY_PCT_MORE:
        out.update(kind="stat", stat="vitality", sign=1, pct=True)
    elif eid == GLYPH_TRIGGER:
        out.update(kind="glyph_trigger", min=0, max=0)
    elif eid in SHIELDS:
        out.update(kind="shield", of=SHIELDS[eid])
    elif eid in STEAL_STATS:
        out.update(kind="steal_stat", stat=STEAL_STATS[eid])
    elif eid in SUMMONS:
        out.update(kind=SUMMONS[eid], monster=int(e["diceNum"]), grade=max(1, int(e["diceSide"])), min=0, max=0)
        replaces = [int(m[1:]) for m in mask if m[:1] == "F" and m[1:].isdigit()]  # F<id>: the target is that monster
        if replaces:
            out["replaces"] = replaces[0]
    elif eid in MARKS:
        out.update(kind=MARKS[eid], sub=[int(e["diceNum"]), max(1, int(e["diceSide"]))],
                   color="#%06x" % (int(e["value"]) & 0xFFFFFF), mark=out["area"], min=0, max=0)
        out["area"] = {"shape": "point", "size": 0}
    elif eid in COOLDOWNS:
        out.update(kind="cooldown", mode=COOLDOWNS[eid], origin=int(e["diceNum"]), turns=int(e["value"]), min=0, max=0)
    elif eid == UNMARK:
        out.update(kind="unmark", origin=int(e["diceNum"]), min=0, max=0)
    elif eid == RUNES:
        out.update(kind="runes", min=0, max=0)
    elif eid == DETONATE:
        out.update(kind="detonate", min=0, max=0)
    elif eid == PORTAL:
        out.update(kind="portal", sub_level=int(e["diceSide"]), per_cell=int(e["diceNum"]), bonus=int(e["value"]),
                   min=0, max=0)
    elif eid == TELEPORTAL:
        out.update(kind="teleportal", min=0, max=0)
    elif eid == UNPORTAL:
        out.update(kind="unportal", all=bool(e["zoneDescr"]) and chr(e["zoneDescr"]["shape"] or 80) == "A", min=0, max=0)
    elif eid in CAST:
        out.update(kind="cast", sub=[int(e["diceNum"]), max(1, int(e["diceSide"]))], min=0, max=0)
        if eid in CAST_BY_TARGET:
            out["by"] = "target"
    elif eid in MULTIPLIERS:
        out.update(kind=MULTIPLIERS[eid], pct=int(e["diceNum"]), min=0, max=0)
    elif eid in REDIRECTS:
        out.update(kind=REDIRECTS[eid], min=0, max=0)
        if eid == 786:
            out["pct"] = int(e["value"])
    elif eid in REFLECTS:
        out.update(kind="reflect", boosted=REFLECTS[eid] == "boosted")
    elif eid == SPELL_REFLECT:
        dur = int(e.get("duration", 1))
        out.update(kind="spell_reflect", level=int(e["diceSide"]), pct=int(e["value"]), min=0, max=0,
                   turns=-1 if dur < 0 else max(1, dur))
        if int(e.get("dispellable", 1)) != 1:
            out["dispellable"] = int(e["dispellable"])
        return out
    elif eid == KILL:
        out.update(kind="kill", min=0, max=0)
    elif eid == INVISIBLE:
        st = _state(states, "target", INVISIBLE_STATE)
        out.update(kind="state", state=INVISIBLE_STATE, state_name_id=st["state_name_id"],
                   flags=st["flags"] + ["invisible"], min=0, max=0)
    elif eid == REVEAL:
        out.update(kind="reveal", min=0, max=0)
    elif eid == UNBUFF:
        out.update(kind="unbuff", origin=int(e["value"]), min=0, max=0)
    elif eid == UNBUFF_RANK:  # P1.17b (8), 1406 "Enlève les effets du rang #1 du sort #2" (diceSide = rank, value = spells.id)
        out.update(kind="unbuff", origin=int(e["value"]), grade=int(e["diceSide"]), min=0, max=0)
    elif eid in CARRY:
        out.update(kind=CARRY[eid], min=0, max=0)
        if eid == 50:
            out["states"] = [_state(states, "caster", CARRIER_STATE), _state(states, "target", CARRIED_STATE)]
    elif eid == PASS_TURN:
        out.update(kind="pass_turn", min=0, max=0)
    elif eid in STATES:
        st = states.get(str(e["value"]), {})
        out.update(kind=STATES[eid], state=int(e["value"]), state_name_id=int(st.get("nameId", 0)),
                   flags=[v for k, v in STATE_FLAGS.items() if st.get(k)], min=0, max=0)
    elif eid in IGNORED:
        return None
    else:
        return "unsupported"
    if int(e.get("dispellable", 1)) != 1:
        out["dispellable"] = int(e["dispellable"])
    codes = [c for c in str(e.get("triggers") or "I").split("|") if c]
    if codes != ["I"]:
        out["on"] = [c for c in codes if c != "I"]
        etd = int(e.get("effectTriggerDuration", 1))
        out["turns"] = -1 if etd == WHOLE_FIGHT else max(1, etd)
        if "I" in codes:
            out["now"] = True
    return out


def _state(states: dict, who: str, sid: int) -> dict:
    st = states.get(str(sid), {})
    return {"who": who, "state": sid, "state_name_id": int(st.get("nameId", 0)),
            "flags": [v for k, v in STATE_FLAGS.items() if st.get(k)]}


def convert_effects(raw: list, states: dict) -> tuple[list, list]:
    """(effects, unsupported effect ids). A level lists conditional variants: state conditions
    are kept (`cond`), and variants for the carried entity (K, `carried`)."""
    effects, unsupported = [], []
    carries = any(e["effectId"] in CARRY for e in raw)
    for e in raw:
        # the carry sets the carrier / carried states itself
        if carries and e["effectId"] in STATES and int(e["value"]) in (CARRIER_STATE, CARRIED_STATE):
            continue
        eff = convert_effect(e, states)
        if eff == "unsupported":
            unsupported.append(e["effectId"])
            continue
        if eff and "on" in eff:
            known = [c for c in eff["on"] if known_trigger(c)]
            if len(known) < len(eff["on"]):
                unsupported.append(e["effectId"])
            if not known and not eff.get("now"):
                continue
            eff["on"] = known
            if not known:
                del eff["on"], eff["turns"], eff["now"]
        if eff and eff not in effects:
            effects.append(eff)
    return effects, unsupported


def visuals(spell: dict, scripts: dict) -> tuple[list, dict]:
    fx = {}
    anim = ["AnimAttaque0"]
    for usage in spell.get("boundScriptUsageData", []):
        script = scripts.get(str(usage["scriptId"]))
        if not script or script.get("type") != 1:
            continue
        p = parse_params(script["rawParams"])
        if "animId" in p:
            anim = [f"AnimAttaque{p['animId']}", "AnimAttaque0"]
        for key, out in (("casterGfxId", "caster"), ("targetGfxId", "target"), ("targetGfxId2", "target2"),
                         ("missileGfxId", "missile"), ("glyphGfxId", "glyph")):
            if p.get(key, "0").lstrip("-").isdigit() and int(p.get(key, "0")) > 0:
                fx[out] = int(p[key])
        for key, out in (("missileSpeed", "missile_speed"), ("missileCurvature", "missile_curvature"),
                         ("missileGfxYOffset", "missile_y"), ("targetGfxYOffset", "target_y")):
            if key in p:
                try:
                    fx[out] = float(p[key])
                except ValueError:
                    pass
        if p.get("targetGfxShowUnder2") == "1":
            fx["target2_under"] = True
        if p.get("targetGfxShowUnder") == "1":
            fx["target_under"] = True
        break
    return anim, fx


def convert(spell: dict, level: dict, scripts: dict, states: dict, text, sid: int | None = None,
            keep: bool = False) -> dict | None:
    """keep: a class spell, kept even when it only buffs its caster or nothing is simulated."""
    effects, unsupported = convert_effects(level["effects"], states)
    if not keep and not any(e["kind"] not in ("state", "unstate") and e["target"] != "caster" for e in effects):
        return None
    crit_effects, _ = convert_effects(level.get("criticalEffect", []), states)
    flags = level["m_flags"]
    anim, fx = visuals(spell, scripts)
    main = next((e for e in effects if e["target"] != "caster"), effects[0] if effects else {"area": zone_of(None)})
    out = {
        "id": sid if sid is not None else int(spell["id"]), "name_id": int(spell["nameId"]),
        "name": text(spell["nameId"]), "icon": int(spell["iconId"]), "level": int(level.get("minPlayerLevel", 1)),
        "ap": level["apCost"], "range": [level["minRange"], level["range"]],
        "range_boost": bool(flags & RANGE_BOOSTABLE),
        "los": bool(flags & TEST_LOS), "in_line": bool(flags & IN_LINE),
        "need_free_cell": bool(flags & NEED_FREE_CELL), "need_taken_cell": bool(flags & NEED_TAKEN_CELL),
        "per_turn": level["maxCastPerTurn"] or 99, "per_target": level["maxCastPerTarget"] or 99,
        "cooldown": int(level["minCastInterval"]), "initial_cooldown": int(level["initialCooldown"]),
        "crit": int(level["criticalHitProbability"]),
        "area": main["area"], "effects": effects, "crit_effects": crit_effects, "anim": anim, "fx": fx,
        "origin": int(spell["id"]), "max_stack": int(level.get("maxStack", 0)),
    }
    # Sac Animé (P1.13e): "Le Sac Animé est détruit 3 tours après son invocation", its 141 "Tue la
    # cible" has delay 3 and mask C, where Musette Animée's (same text, 2 turns) has "a,A" on the
    # summon's cell. APPROX(P1.13e): a delayed kill of the caster in a summoning spell kills the summon.
    if any(e["kind"] == "summon" for e in effects):
        for e in effects:
            if e["kind"] == "kill" and e["target"] == "caster" and e["delay"] > 0:
                e["target"] = "all"
    if level.get("statesCriterion"):
        out["criterion"] = level["statesCriterion"]
    for e in effects + crit_effects:
        if e["kind"] in list(MARKS.values()) + ["portal"]:
            e["origin"] = int(spell["id"])  # what unmark (2018) names
    # Karcham / Chamrak: "La portée maximale du sort est augmentée lorsque le lanceur porte une
    # cible" (spell description) = their SPELL_RANGE effect on themselves
    if any(e["kind"] == "carry" for e in effects):
        for e in level["effects"]:
            if e["effectId"] == SPELL_RANGE and int(e["diceNum"]) == int(spell["id"]):
                out["carry_range"] = int(e["value"])
    if unsupported:
        out["partial"] = sorted(set(unsupported))
    return out


def class_spells(breeds: dict, variants: dict, spells: dict, levels: dict, scripts: dict, states: dict, text):
    """-> (castables, classes {breed: {start_states, pairs}}, grades {spell: [castable ids]})."""
    out, classes, grades, partial = [], {}, {}, 0
    for bid in sorted(breeds, key=int):
        order = {sid: i for i, sid in enumerate(breeds[bid]["breedSpellsId"])}
        pairs = [v["spellIds"] for v in variants.values() if str(v["breedId"]) == bid]
        if not pairs:
            continue
        # grimoire order: breeds.breedSpellsId (the first spell of each pair, by unlock level)
        pairs.sort(key=lambda ids: order.get(ids[0], 999))
        classes[bid] = {"start_states": START_STATES.get(int(bid), []), "pairs": pairs}
        for sid in (i for ids in pairs for i in ids):
            spell = spells.get(str(sid))
            if not spell:
                continue
            grades[str(sid)] = []
            for g, lid in enumerate(spell["spellLevels"]):
                s = convert(spell, levels[str(lid)], scripts, states, text, sid=LEVEL_SPELL + lid, keep=True)
                s.update(spell=sid, grade=g + 1, breed=int(bid), description_id=int(spell.get("descriptionId", 0)))
                if sid in VARIANT_STATES:
                    s["start_states"] = VARIANT_STATES[sid]
                partial += "partial" in s
                out.append(s)
                grades[str(sid)].append(s["id"])
    # common spells: "Coup de poing" (spells 0), the hit of a character without a weapon
    for sid in COMMON_SPELLS:
        spell = spells[str(sid)]
        grades[str(sid)] = []
        for g, lid in enumerate(spell["spellLevels"]):
            s = convert(spell, levels[str(lid)], scripts, states, text, sid=LEVEL_SPELL + lid, keep=True)
            s.update(spell=sid, grade=g + 1, breed=0, description_id=int(spell.get("descriptionId", 0)), bar=False)
            out.append(s)
            grades[str(sid)].append(s["id"])
    print(f"{len(classes)} classes, {len(grades)} spells, {len(out)} grades ({partial} partly simulated)")
    return out, classes, grades


def extract_icons(icons: set[int]) -> None:
    out = CONTENT / "Picto" / "Spells"
    out.mkdir(parents=True, exist_ok=True)
    env = UnityPy.load(str(DEFAULT_GAME / "Dofus_Data/StreamingAssets/Content/Picto/Spells/spell_assets_1x.bundle"))
    wanted = {f"sort_{i}" for i in icons}
    n = 0
    for o in env.objects:
        if o.type.name == "Sprite" and o.peek_name() in wanted:
            o.read().image.save(out / f"{o.peek_name()[5:]}.webp", lossless=True, quality=0, method=0, exact=True)
            n += 1
    print(f"  icons: {n}/{len(icons)}")


# subareas.id of the Astrub area (18): Cité, Carrière, Forêt, Champs, Souterrains, Égouts, Cimetière, Prairies, Calanques
ASTRUB_SUBAREAS = [95, 96, 97, 98, 99, 100, 102, 173, 335]


def world_monster_spells(world: str) -> set[int]:
    """Spell ids (MONSTER_SPELL + levelId) used by the monsters of game/worlds/<world>:
    monsters.json (P1.09) and the groups of hand-made maps."""
    ids = set()
    if "+" in world:  # "incarnam+astrub"
        for w in world.split("+"):
            ids |= world_monster_spells(w)
        return ids
    if world == "astrub":  # P1.17: no world of its own, the monsters of the Astrub subareas of "dofus"
        mons = json.loads((ROOT / "game" / "worlds" / "dofus" / "monsters.json").read_text(encoding="utf-8"))
        keep = {m for sa in ASTRUB_SUBAREAS for m in mons["subareas"][str(sa)]["monsters"]}
        for mid in keep:
            for g in mons["monsters"][str(mid)]["grades"]:
                ids.update(int(s) for s in g.get("spells", []))
        return ids
    folder = ROOT / "game" / "worlds" / world
    if (folder / "monsters.json").exists():
        for mo in json.loads((folder / "monsters.json").read_text(encoding="utf-8"))["monsters"].values():
            for g in mo["grades"]:
                ids.update(int(s) for s in g.get("spells", []))
    for f in (folder / "maps").glob("*.json"):
        for g in json.loads(f.read_text(encoding="utf-8")).get("groups", []):
            for m in g.get("members", []):
                ids.update(int(s) for s in m.get("spells", []))
    return ids


def _look(monsters: dict, mid: int) -> str:
    """monsters.look; "{<id>}" naming another monster means "that monster's look"."""
    look = str(monsters[str(mid)].get("look", ""))
    for _ in range(4):
        inner = look.strip("{}")
        if not inner.isdigit() or inner == str(mid) or inner not in monsters:
            break
        mid = int(inner)
        look = str(monsters[inner].get("look", ""))
    return look


BONUS = {"lifePoints": "hp", "strength": "strength", "intelligence": "intelligence", "chance": "chance",
         "agility": "agility", "wisdom": "wisdom", "bonusEarthDamage": "damage_earth", "bonusFireDamage": "damage_fire",
         "bonusWaterDamage": "damage_water", "bonusAirDamage": "damage_air", "bonusNeutralDamage": "damage_neutral"}


def sub_spells(out: list, spells: dict, levels: dict, scripts: dict, states: dict, text) -> None:
    """Marks (P1.13a) and chained spells (cast, P1.13b) name a spell and a grade: adds that
    grade to `out` (bar: false, its id LEVEL_SPELL + spelllevels.id like any castable) and sets
    the effect's `spell` to it."""
    known = {s["id"] for s in out}
    todo = list(out)
    n = 0
    while todo:
        s = todo.pop()
        for e in s["effects"] + s["crit_effects"]:
            if "sub_level" in e:  # a spelllevels.id (1181)
                lid = e.pop("sub_level")
                spell = spells.get(str(levels.get(str(lid), {}).get("spellId", -1)))
                if not spell:
                    continue
            elif "sub" in e:
                sid, grade = e.pop("sub")
                spell = spells.get(str(sid))
                if not spell or not spell["spellLevels"]:
                    continue
                lid = spell["spellLevels"][min(grade, len(spell["spellLevels"])) - 1]
            else:
                continue
            e["spell"] = LEVEL_SPELL + lid
            if e["spell"] in known:
                continue
            sub = convert(spell, levels[str(lid)], scripts, states, text, sid=e["spell"], keep=True)
            sub["bar"] = False
            out.append(sub)
            known.add(sub["id"])
            todo.append(sub)
            n += 1
    print(f"  sub-spells: {n}")


def partial_subs(out: list) -> None:
    """A spell casting a partial sub-spell is partial too (its unsupported ids added)."""
    by_id = {s["id"]: s for s in out}
    changed = True
    while changed:
        changed = False
        for s in out:
            ids = set(s.get("partial", []))
            for e in s["effects"] + s["crit_effects"]:
                sub = by_id.get(e.get("spell", 0))
                ids |= set(sub.get("partial", [])) if sub else set()
            if len(ids) > len(s.get("partial", [])):
                s["partial"] = sorted(ids)
                changed = True
    print(f"  partial (with sub-spells): {sum('partial' in s for s in out if 'breed' in s)} class grades")


def summon_data(out: list, spells: dict, levels: dict, scripts: dict, states: dict, text) -> dict:
    """monster id -> {name_id, look, portrait, slot, bomb, plays, tackles, grades: [{grade, hp,
    ap, mp, stats, res, bonus, spells}]} for every monster a spell of `out` summons (and the
    summons of those summons). Their spells are added to `out` (bar: false).
    bonus = monsters.grades.bonusCharacteristics: HP growing with the summoner's level, the rest
    the % of the summoner's characteristics the summon gets (sim/Summons, P1.11b)."""
    import maps
    monsters = maps._cached_table("monstersdataroot")
    bombs, walls = maps._cached_table("spellbombsdataroot"), maps._cached_table("spellbombwallsdataroot")
    known = {s["id"] for s in out}
    result: dict = {}
    todo = {int(e["monster"]) for s in out for e in s["effects"] + s["crit_effects"] if e["kind"] in ("summon", "replace")}
    while todo:
        mid = todo.pop()
        mo = monsters.get(str(mid))
        if str(mid) in result or not mo or not mo.get("grades"):
            continue
        flags = int(mo.get("m_flags", 0))
        grades = []
        for g in mo["grades"]:
            m = maps.monster_member(mo, int(g["grade"]))
            bonus = {BONUS[k]: int(v) for k, v in g.get("bonusCharacteristics", {}).items() if k in BONUS and int(v)}
            grades.append({"grade": m["grade"], "hp": max(0, m["hp"]), "ap": m["ap"], "mp": m["mp"], "stats": m["stats"],
                           "res": m["res"], "bonus": bonus, "spells": m["spells"]})
            start = int(g.get("startingSpellId", 0))  # a spell level: cast when it arrives (P1.13b)
            level = levels.get(str(start)) if start else None
            if level and str(level["spellId"]) in spells:
                grades[-1]["start"] = LEVEL_SPELL + start
                if LEVEL_SPELL + start not in known:
                    s = convert(spells[str(level["spellId"])], level, scripts, states, text, sid=LEVEL_SPELL + start, keep=True)
                    s["bar"] = False
                    out.append(s)
                    known.add(s["id"])
            for sid in m["spells"]:
                if sid in known:
                    continue
                level = levels.get(str(sid - MONSTER_SPELL))
                spell = level and spells.get(str(level["spellId"]))
                s = spell and convert(spell, level, scripts, states, text, sid=sid, keep=True)
                if s:
                    s["bar"] = False
                    out.append(s)
                    known.add(sid)
                    todo.update(int(e["monster"]) for e in s["effects"] if e["kind"] in ("summon", "replace"))
        result[str(mid)] = {"name_id": int(mo["nameId"]), "look": _look(monsters, mid), "portrait": int(mo.get("gfxId", 0)),
                            "slot": bool(flags & M_SUMMON_SLOT), "bomb": bool(flags & M_BOMB_SLOT),
                            "plays": bool(flags & M_CAN_PLAY), "tackles": bool(flags & M_CAN_TACKLE),
                            "switch": bool(flags & M_CAN_SWITCH), "switch_on_target": bool(flags & M_CAN_SWITCH_ON_TARGET),
                            "grades": grades}
        bomb = bombs.get(str(mid))
        if bomb:
            def castables(spell_id: int) -> list:
                spell = spells.get(str(spell_id))
                ids = []
                for g in range(1, len(grades) + 1):
                    lid = spell["spellLevels"][min(g, len(spell["spellLevels"])) - 1]
                    ids.append(LEVEL_SPELL + lid)
                    if LEVEL_SPELL + lid not in known:
                        s = convert(spell, levels[str(lid)], scripts, states, text, sid=LEVEL_SPELL + lid, keep=True)
                        s["bar"] = False
                        out.append(s)
                        known.add(s["id"])
                return ids
            result[str(mid)]["explode"] = castables(int(bomb["explodSpellId"]))
            result[str(mid)]["chain"] = castables(int(bomb["chainReactionSpellId"]))
            result[str(mid)]["instant"] = castables(int(bomb["instantSpellId"]))
            wall = walls.get(str(bomb["wallId"]))
            if wall:
                result[str(mid)]["wall"] = {"spells": castables(int(wall["spellId"])),
                                            "color": "#%06x" % (int(wall["color"]) & 0xFFFFFF),
                                            "linear": bool(wall["linear"]), "min": int(wall["minHop"]),
                                            "max": int(wall["maxHop"])}
    print(f"  summons: {len(result)} monsters")
    return result


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("breed")
    b.add_argument("breed", type=int)
    b.add_argument("--max", type=int, default=8)
    b.add_argument("--world", default="", help="also convert the spells of this world's monsters")
    c = sub.add_parser("classes")
    c.add_argument("--world", default="", help="also convert the spells of this world's monsters")
    args = ap.parse_args()

    UnityPy.config.FALLBACK_UNITY_VERSION = detect_unity_version(DEFAULT_GAME)
    ex = Extractor(DEFAULT_GAME, CONTENT.parent, "webp")
    for t in TABLES:
        if not (CONTENT / "Data" / f"{t}.json").exists():
            ex.data(t)
    load = lambda n: json.loads((CONTENT / "Data" / f"{n}.json").read_text(encoding="utf-8"))["objectsById"]  # noqa: E731
    spells, levels, scripts, breeds, states, variants = (load(t) for t in TABLES)
    text = i18n_reader(CONTENT / "I18n" / "fr.bin")
    if args.cmd == "classes":
        out, classes, grades = class_spells(breeds, variants, spells, levels, scripts, states, text)
        out += monster_spells(args.world, spells, levels, scripts, states, text)
        while True:  # sub-spells can summon, summons have start spells
            n = len(out)
            summons = summon_data(out, spells, levels, scripts, states, text)
            sub_spells(out, spells, levels, scripts, states, text)
            if len(out) == n:
                break
        partial_subs(out)
        OUT.write_text(json.dumps({"_doc": "Generated by tools/extractor/spells.py classes"
                                           + (f" --world {args.world}" if args.world else "") + ". See shared/spell_book.gd.",
                                   "classes": classes, "grades": grades, "common": COMMON_SPELLS, "spells": out,
                                   "summons": summons},
                                  ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        print(f"-> {OUT} ({OUT.stat().st_size // 1024} KB)")
        extract_icons({s["icon"] for s in out if "spell" in s})
        extract_bones(ex, out)
        extract_looks(ex, [m["look"] for m in summons.values()])
        import ui
        ui.portraits({m["portrait"] for m in summons.values() if m["portrait"]})
        return
    out = []
    skipped = []
    for sid in breeds[str(args.breed)]["breedSpellsId"]:
        spell = spells.get(str(sid))
        if not spell or not spell["spellLevels"]:
            continue
        s = convert(spell, levels[str(spell["spellLevels"][0])], scripts, states, text)
        if not s:
            continue
        if "partial" in s:
            skipped.append(f"{s['name']} {s['partial']}")
            continue
        s["key"] = str(len(out) + 1)
        s["bar"] = True
        out.append(s)
        if len(out) >= args.max:
            break
    print(f"{len(out)} class spells: " + ", ".join(s["name"] for s in out))
    if skipped:
        print("  not simulated (unsupported effects): " + "; ".join(skipped))
    out += monster_spells(args.world, spells, levels, scripts, states, text)
    OUT.write_text(json.dumps({"_doc": f"Generated by tools/extractor/spells.py breed {args.breed}"
                                       + (f" --world {args.world}" if args.world else "") + ". See shared/spell_book.gd.",
                               "start_states": START_STATES.get(args.breed, []),
                               "spells": out}, indent="\t", ensure_ascii=False), encoding="utf-8")
    print(f"-> {OUT}")
    extract_icons({s["icon"] for s in out if s.get("bar")})
    extract_bones(ex, out)


def monster_spells(world: str, spells: dict, levels: dict, scripts: dict, states: dict, text) -> list:
    out = []
    for mid in sorted(world_monster_spells(world)) if world else []:
        level = levels.get(str(mid - MONSTER_SPELL))
        spell = level and spells.get(str(level["spellId"]))
        s = spell and convert(spell, level, scripts, states, text, sid=mid)
        if s:
            s["bar"] = False
            out.append(s)
    if world:
        print(f"  monster spells of {world}: {len(out)}")
    return out


def extract_looks(ex, looks: list) -> None:
    """Bones and skins of looks ("{bone|skin,skin|colors|scale}")."""
    bones, skins = set(), set()
    for look in looks:
        parts = look.strip("{}").split("|")
        if parts[0].isdigit():
            bones.add(parts[0])
        if len(parts) > 1:
            skins.update(x for x in parts[1].split(",") if x.isdigit())
    ok = [b for b in sorted(bones) if ex.bone(b)]
    oks = [k for k in sorted(skins) if ex.skin(k)]
    print(f"  summon looks: bones {len(ok)}/{len(bones)}, skins {len(oks)}/{len(skins)}")


def extract_bones(ex, out: list) -> None:
    bones = sorted({g for s in out for k, g in s["fx"].items() if k in ("caster", "target", "target2", "missile", "glyph")})
    ok = [g for g in bones if ex.bone(str(g))]
    print(f"  fx bones: {len(ok)}/{len(bones)}")


if __name__ == "__main__":
    main()
