// Rules on spells, items, classes and monsters.
import type { World } from "./io";
import type { Rule } from "./problems";

const refSpell = (id: number) => ({ kind: "spell", id });

function allMonsters(w: World) {
  return [...Object.entries(w.files.monsters.monsters), ...Object.entries(w.files.monsters.bosses)];
}

export const contentRules: Rule[] = [
  {
    code: "E_TEXT_MISSING", severity: "error",
    doc: "Chaque name_id / description_id pointe un texte de Content/I18n/extra_fr.json.",
    run({ w, report }) {
      const texts = w.files.texts;
      const need = (tid: number | string | null | undefined, where: string, ref: { kind: string; id: string | number }) => {
        if (tid && !(String(tid) in texts)) report("E_TEXT_MISSING", `${where} : texte ${tid} absent`, ref);
      };
      for (const s of w.files.spells.spells) need(s.name_id, `sort ${s.id}`, refSpell(s.id));
      for (const it of w.files.items.items) {
        need(it.name_id, `objet ${it.id}`, { kind: "item", id: it.id });
        need(it.description_id, `objet ${it.id} (description)`, { kind: "item", id: it.id });
      }
      for (const lst of Object.values(w.files.npcs.maps))
        for (const n of lst) need(n.name_id, `PNJ ${n.npc}`, { kind: "npc", id: n.npc });
      for (const [qid, q] of Object.entries(w.files.quests.quests)) {
        const ref = { kind: "quest", id: qid };
        need(q.name_id, `quête ${qid}`, ref);
        for (const st of q.steps) {
          need(st.name_id, `quête ${qid} (étape)`, ref);
          need(st.desc_id, `quête ${qid} (étape)`, ref);
          for (const o of st.objectives)
            for (const a of o.args ?? []) if ("t" in a) need(a.t as number, `quête ${qid} (objectif)`, ref);
        }
      }
    },
  },
  {
    code: "E_SPELL_SUBSPELL", severity: "error",
    doc: "Un effet piège/glyphe/rune/cast référence un sort existant.",
    run({ w, spellIds, report }) {
      for (const s of w.files.spells.spells)
        for (const e of [...s.effects, ...(s.crit_effects ?? [])])
          if (["trap", "glyph_start", "glyph_end", "rune", "cast"].includes(e.kind) && e.spell && !spellIds.has(e.spell))
            report("E_SPELL_SUBSPELL", `sort ${s.id} : sous-sort ${e.spell} inconnu`, refSpell(s.id));
    },
  },
  {
    code: "E_SPELL_SUMMON", severity: "error",
    doc: "Un effet d'invocation référence une invocation déclarée dans spells.summons.",
    run({ w, summonIds, report }) {
      for (const s of w.files.spells.spells)
        for (const e of [...s.effects, ...(s.crit_effects ?? [])])
          if (e.kind === "summon" && e.monster !== undefined && !summonIds.has(e.monster))
            report("E_SPELL_SUMMON", `sort ${s.id} : invocation ${e.monster} inconnue`, refSpell(s.id));
    },
  },
  {
    code: "E_GRADE_MISSING", severity: "error",
    doc: "Chaque grade listé dans spells.grades est un sort défini.",
    run({ w, spellIds, report }) {
      for (const [pid, gl] of Object.entries(w.files.spells.grades))
        for (const g of gl) if (!spellIds.has(g)) report("E_GRADE_MISSING", `grade ${g} du sort ${pid} absent`, refSpell(g));
    },
  },
  {
    code: "E_CLASS_SPELL_NO_GRADES", severity: "error",
    doc: "Chaque sort d'une classe a une liste de grades.",
    run({ w, report }) {
      for (const [bid, c] of Object.entries(w.files.spells.classes))
        for (const pair of c.pairs)
          for (const sid of pair)
            if (!(String(sid) in w.files.spells.grades))
              report("E_CLASS_SPELL_NO_GRADES", `classe ${bid} : le sort ${sid} n'a aucun grade`, { kind: "class", id: bid });
    },
  },
  {
    code: "E_CLASS_NOT_OFFERED", severity: "error",
    doc: "Une classe qui a des sorts est proposée par le monde (world.breeds).",
    run({ w, report }) {
      for (const bid of Object.keys(w.files.spells.classes))
        if (!w.files.world.breeds.includes(Number(bid)))
          report("E_CLASS_NOT_OFFERED", `classe ${bid} non proposée par le monde`, { kind: "class", id: bid });
    },
  },
  {
    code: "E_BREED_NO_ROW", severity: "error",
    doc: "Chaque classe de world.breeds a une ligne dans data/tables/breeds.json.",
    run({ w, report }) {
      for (const b of w.files.world.breeds)
        if (!(String(b) in w.files.breeds.objectsById)) report("E_BREED_NO_ROW", `la classe ${b} n'a pas de ligne`, { kind: "class", id: b });
    },
  },
  {
    code: "E_SUMMON_SPELL", severity: "error",
    doc: "Les sorts d'une invocation (et son sort de départ) existent.",
    run({ w, spellIds, report }) {
      for (const [sid, sm] of Object.entries(w.files.spells.summons))
        for (const g of sm.grades)
          for (const sp of [...g.spells, ...(g.start ? [g.start] : [])])
            if (!spellIds.has(sp)) report("E_SUMMON_SPELL", `invocation ${sid} : sort ${sp} inconnu`, { kind: "summon", id: sid });
    },
  },
  {
    code: "E_ITEM_SET", severity: "error",
    doc: "L'objet référence une panoplie existante.",
    run({ w, setIds, report }) {
      for (const it of w.files.items.items)
        if (it.set && !setIds.has(it.set)) report("E_ITEM_SET", `objet ${it.id} : panoplie ${it.set} inconnue`, { kind: "item", id: it.id });
    },
  },
  {
    code: "E_ITEM_ICON", severity: "error",
    doc: "L'icône de l'objet existe (Content/Picto/Items/<icon>.png).",
    run({ w, probe, report }) {
      for (const it of w.files.items.items)
        if (!probe(`Picto/Items/${it.icon}.png`)) report("E_ITEM_ICON", `objet ${it.id} : icône ${it.icon} absente`, { kind: "item", id: it.id });
    },
  },
  {
    code: "E_SET_ITEM", severity: "error",
    doc: "Les objets d'une panoplie existent.",
    run({ w, itemIds, report }) {
      for (const st of w.files.items.sets)
        for (const i of st.items) if (!itemIds.has(i)) report("E_SET_ITEM", `panoplie ${st.id} : objet ${i} inconnu`, { kind: "set", id: st.id });
    },
  },
  {
    code: "E_SKILL_ITEM", severity: "error",
    doc: "La ressource récoltée par un métier existe.",
    run({ w, itemIds, report }) {
      for (const sk of Object.values(w.files.skills.objectsById))
        if (!itemIds.has(sk.gatheredRessourceItem))
          report("E_SKILL_ITEM", `métier ${sk.id} : objet ${sk.gatheredRessourceItem} inconnu`, { kind: "skill", id: sk.id });
    },
  },
  {
    code: "E_MONSTER_SPELL", severity: "error",
    doc: "Les sorts d'un monstre existent.",
    run({ w, spellIds, report }) {
      for (const [mid, m] of allMonsters(w))
        for (const g of m.grades) for (const sp of g.spells)
          if (!spellIds.has(sp)) report("E_MONSTER_SPELL", `monstre ${mid} : sort ${sp} inconnu`, { kind: "monster", id: mid });
    },
  },
  {
    code: "E_MONSTER_DROP", severity: "error",
    doc: "Les objets lâchés par un monstre existent.",
    run({ w, itemIds, report }) {
      for (const [mid, m] of allMonsters(w))
        for (const g of m.grades) for (const d of g.drops)
          if (!itemIds.has(d.item)) report("E_MONSTER_DROP", `monstre ${mid} : butin ${d.item} inconnu`, { kind: "monster", id: mid });
    },
  },
  {
    code: "E_MONSTER_BONE", severity: "error",
    doc: "Le squelette (look) du monstre existe (Content/Characters/Bones/<id>).",
    run({ w, probe, report }) {
      for (const [mid, m] of allMonsters(w))
        for (const g of m.grades) {
          const bone = g.look.replace(/[{}]/g, "").split("|")[0];
          if (!probe(`Characters/Bones/${bone}`)) report("E_MONSTER_BONE", `monstre ${mid} : squelette ${bone} absent`, { kind: "monster", id: mid });
        }
    },
  },
  {
    code: "E_MONSTER_PORTRAIT", severity: "error",
    doc: "Le portrait du monstre existe (Content/Picto/Monsters/<portrait>.png).",
    run({ w, probe, report }) {
      for (const [mid, m] of allMonsters(w))
        for (const g of m.grades)
          if (g.portrait !== undefined && !probe(`Picto/Monsters/${g.portrait}.png`))
            report("E_MONSTER_PORTRAIT", `monstre ${mid} : portrait ${g.portrait} absent`, { kind: "monster", id: mid });
    },
  },
  {
    code: "E_SUBAREA_MONSTER", severity: "error",
    doc: "Les monstres d'une sous-zone existent.",
    run({ w, mobIds, report }) {
      for (const [sa, d] of Object.entries(w.files.monsters.subareas))
        for (const mid of d.monsters) if (!mobIds.has(mid)) report("E_SUBAREA_MONSTER", `sous-zone ${sa} : monstre ${mid} inconnu`, { kind: "subarea", id: sa });
    },
  },
];
