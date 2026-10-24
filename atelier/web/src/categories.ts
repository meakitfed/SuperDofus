import type { Category } from "../../core/asset_usage";

/** Same labels as core/asset_usage.ts, restated here so the browser bundle never pulls the image library in. */
export const CATEGORY_LABELS: Record<Category, string> = {
  item: "Objets", spell: "Sorts", monster: "Monstres", tile: "Tuiles de map",
};
