// Names the forms show for the numeric ids the engine uses. Unknown ids are still editable as raw numbers.
export const ITEM_TYPES: [number, string][] = [
  [1, "Amulette"], [2, "Arc"], [3, "Baguette"], [4, "Bâton"], [5, "Dague"], [6, "Épée"], [7, "Marteau"], [8, "Pelle"],
  [9, "Anneau"], [10, "Ceinture"], [11, "Bottes"], [12, "Potion"], [16, "Chapeau"], [17, "Cape"], [19, "Hache"], [82, "Bouclier"],
];

export const WEAPON_TYPES = [2, 3, 4, 5, 6, 7, 8, 19];
export const DEFAULT_WEAPON = { ap: 4, min_range: 1, range: 1, crit: 20, crit_bonus: 5, in_line: 0 as const, los: 1 as const, per_turn: 1 };

export const EFFECTS: [number, string][] = [
  [100, "Dégâts neutre (arme)"], [97, "Dégâts terre (arme)"], [96, "Dégâts eau (arme)"], [98, "Dégâts air (arme)"], [99, "Dégâts feu (arme)"], [108, "Soin (arme)"],
  [118, "Force"], [119, "Agilité"], [123, "Chance"], [124, "Sagesse"], [125, "Vitalité"], [126, "Intelligence"],
  [111, "PA"], [128, "PM"], [117, "Portée"], [115, "Coups critiques"], [112, "Dommages"], [138, "% Dommages"], [178, "Soins"],
  [182, "Invocations"], [176, "Prospection"], [210, "% Résistance terre"], [211, "% Résistance eau"], [212, "% Résistance air"],
  [213, "% Résistance feu"], [214, "% Résistance neutre"],
];

export const typeName = (t: number) => ITEM_TYPES.find(([id]) => id === t)?.[1] ?? `type ${t}`;
export const effectName = (e: number) => EFFECTS.find(([id]) => id === e)?.[1] ?? `effet ${e}`;
