// The web app driven by a real browser (Playwright) against a real server on a temp copy of the worlds.
// Set SHOTS_DIR to also save a screenshot at each step (npm run shots).
import { execSync } from "node:child_process";
import fs from "node:fs";
import type http from "node:http";
import os from "node:os";
import path from "node:path";
import { zipSync } from "fflate";
import { chromium, type Browser, type Page } from "playwright";
import sharp from "sharp";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { WorldStore } from "../core/store";
import { startServer } from "../server/server";

const ATELIER = path.resolve(__dirname, "..");
const ROOT = path.resolve(ATELIER, "..");
const SHOTS = process.env.SHOTS_DIR;

let tmp: string, server: http.Server, base: string, browser: Browser, page: Page;

async function shot(name: string, opts: { fullPage?: boolean } = {}) {
  if (!SHOTS) return;
  fs.mkdirSync(SHOTS, { recursive: true });
  await page.screenshot({ path: path.join(SHOTS, `${name}.png`), fullPage: opts.fullPage ?? false });
}

beforeAll(async () => {
  execSync("npm run build", { cwd: ATELIER, stdio: "ignore" });
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "atelier-ui-"));
  const worlds = path.join(tmp, "worlds");
  fs.cpSync(path.join(ROOT, "game", "worlds", "vertebre"), path.join(worlds, "vertebre"), { recursive: true });
  fs.mkdirSync(path.join(worlds, "incarnam"), { recursive: true });
  fs.copyFileSync(path.join(ROOT, "game", "worlds", "incarnam", "world.json"), path.join(worlds, "incarnam", "world.json"));
  const store = new WorldStore(worlds, path.join(tmp, "ranges.json"), path.join(ATELIER, "templates"));
  server = await startServer(store, path.join(ATELIER, "web", "dist"), 0);
  base = `http://127.0.0.1:${(server.address() as any).port}`;
  browser = await chromium.launch();
  page = await (await browser.newContext({ viewport: { width: 1280, height: 800 }, locale: "fr-FR", colorScheme: "light" })).newPage();
});
afterAll(async () => {
  await browser?.close();
  server?.close();
  fs.rmSync(tmp, { recursive: true, force: true });
});

describe("interface", () => {
  it("liste les mondes : gérés cliquables, les autres en lecture seule", async () => {
    await page.goto(base + "/");
    await page.getByRole("heading", { name: "Mondes" }).waitFor();
    await expect(page.getByText("La Vertèbre").first().isVisible()).resolves.toBe(true);
    expect(await page.locator("a.card").count()).toBe(1); // only vertebre is managed
    expect(await page.locator(".card.disabled").count()).toBe(1);
    await shot("01-liste-des-mondes");
  });

  it("le bouton de création reste désactivé tant que le formulaire est invalide", async () => {
    await page.getByRole("button", { name: "+ Nouveau monde" }).click();
    const create = page.getByRole("button", { name: "Créer le monde" });
    await expect(create.isDisabled()).resolves.toBe(true);
    await shot("02-nouveau-monde-vide");
    await page.getByLabel("Nom du monde").fill("Les Terres Brisées");
    await expect(page.getByLabel("Identifiant").inputValue()).resolves.toBe("les_terres_brisees");
    await expect(create.isDisabled()).resolves.toBe(false);
    await page.getByLabel("Identifiant").fill("vertebre");
    await expect(page.getByText("Ce monde existe déjà.").isVisible()).resolves.toBe(true);
    await expect(create.isDisabled()).resolves.toBe(true);
    await shot("03-nouveau-monde-identifiant-pris");
    await page.getByLabel("Identifiant").fill("les_terres_brisees");
    await shot("04-nouveau-monde-pret");
  });

  it("crée le monde et affiche un tableau de cohérence vide", async () => {
    await page.getByRole("button", { name: "Créer le monde" }).click();
    await page.getByRole("heading", { name: "Les Terres Brisées" }).waitFor();
    expect(new URL(page.url()).pathname).toBe("/mondes/les_terres_brisees");
    await expect(page.getByText("Aucun problème").isVisible()).resolves.toBe(true);
    await expect(page.getByRole("button", { name: "↶ Annuler" }).isDisabled()).resolves.toBe(true);
    await shot("05-monde-neuf", { fullPage: true });
  });

  it("renomme, journalise, annule et refait", async () => {
    await page.getByRole("button", { name: "Renommer", exact: true }).click();
    await shot("06-renommer");
    await page.getByLabel("Nom du monde").fill("Terres Brisées II");
    await page.getByRole("button", { name: "Renommer", exact: true }).last().click();
    await page.getByRole("heading", { name: "Terres Brisées II" }).waitFor();
    await expect(page.locator(".journal .current").innerText()).resolves.toContain("Terres Brisées II");
    await shot("07-apres-renommage");
    await page.getByRole("button", { name: "↶ Annuler" }).click();
    await page.getByRole("heading", { name: "Les Terres Brisées" }).waitFor();
    await page.getByRole("button", { name: "↷ Refaire" }).click();
    await page.getByRole("heading", { name: "Terres Brisées II" }).waitFor();
  });

  it("affiche les incohérences introduites à la main après « Relire »", async () => {
    const dir = path.join(tmp, "worlds", "les_terres_brisees");
    const mapFile = path.join(dir, "maps", fs.readdirSync(path.join(dir, "maps"))[0]);
    const m = JSON.parse(fs.readFileSync(mapFile, "utf-8"));
    m.triggers.push({ cell: 300, to_map: 12345, to_cell: 1 });
    m.placement.red.push(9999);
    fs.writeFileSync(mapFile, JSON.stringify(m));
    await page.getByRole("button", { name: "⟳ Relire" }).click();
    await page.locator(".problem.error").first().waitFor();
    await expect(page.locator(".problem.error").count()).resolves.toBeGreaterThanOrEqual(2);
    await expect(page.getByText("porte vers la map inconnue 12345").isVisible()).resolves.toBe(true);
    await shot("08-incoherences-detectees", { fullPage: true });
  });

  it("ouvre La Vertèbre : monde complet et cohérent, sans zone de suppression", async () => {
    await page.goto(base + "/mondes/vertebre");
    await page.getByRole("heading", { name: "La Vertèbre" }).waitFor();
    await expect(page.getByText("Aucun problème").isVisible()).resolves.toBe(true);
    await expect(page.getByText("Supprimer ce monde…").count()).resolves.toBe(0);
    await page.getByRole("heading", { name: "Monde jouable ?" }).waitFor();
    await expect(page.getByText("1 point à voir").isVisible()).resolves.toBe(true); // 3 of its 124 items can be obtained nowhere
    await page.getByRole("button", { name: /Chaque objet peut être obtenu/ }).click();
    await expect(page.getByText("l'objet 9100030 ne peut être obtenu nulle part").isVisible()).resolves.toBe(true);
    await shot("09-la-vertebre", { fullPage: true });
    await page.getByRole("button", { name: "Vérifier avec le jeu" }).click();
    await page.getByRole("status").filter({ hasText: /Le jeu charge ce monde|Godot est introuvable|projet Godot/ }).waitFor({ timeout: 100_000 });
    await shot("09b-verifier-avec-le-jeu", { fullPage: true });
  }, 150_000);

  it("refuse la suppression tant que l'identifiant n'est pas retapé, puis supprime", async () => {
    await page.goto(base + "/mondes/les_terres_brisees");
    await page.getByRole("heading", { name: "Terres Brisées II" }).waitFor();
    await page.getByRole("button", { name: "Supprimer ce monde…" }).click();
    const del = page.getByRole("button", { name: "Supprimer définitivement" });
    await expect(del.isDisabled()).resolves.toBe(true);
    await page.getByLabel("Tape « les_terres_brisees » pour confirmer").fill("les_terres_brisees");
    await expect(del.isDisabled()).resolves.toBe(false);
    await shot("10-confirmer-suppression");
    await del.click();
    await page.getByRole("heading", { name: "Mondes" }).waitFor();
    expect(fs.existsSync(path.join(tmp, "worlds", "les_terres_brisees"))).toBe(false);
    await expect(page.getByText("Terres Brisées").count()).resolves.toBe(0);
  });

  it("importe des images (fichiers et ZIP), signale les refus, puis avertit des images inutilisées", async () => {
    await fetch(base + "/api/worlds", { method: "POST", headers: { "content-type": "application/json", "x-atelier": "1" }, body: JSON.stringify({ id: "monde_images", name: "Monde aux images" }) });
    const icon = (letter: string, color: string) =>
      sharp(Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128"><rect x="8" y="8" width="112" height="112" rx="24" fill="${color}"/><text x="64" y="88" font-size="72" font-family="Arial" font-weight="700" text-anchor="middle" fill="white">${letter}</text></svg>`)).png().toBuffer();
    const dir = path.join(tmp, "uploads");
    fs.mkdirSync(dir, { recursive: true });
    const names = ["epee", "bouclier", "potion"];
    const colors = ["#c0392b", "#2c6fbb", "#27a35a"];
    const files: string[] = [];
    for (const [i, n] of names.entries()) { const f = path.join(dir, `${n}.png`); fs.writeFileSync(f, await icon(n[0].toUpperCase(), colors[i])); files.push(f); }
    await page.goto(base + "/mondes/monde_images/assets");
    await page.getByRole("heading", { name: "Bibliothèque d'images" }).waitFor();
    await page.getByText("Aucune image dans cette catégorie pour l'instant.").waitFor();
    await shot("12-images-vide");
    await page.getByLabel("Fichiers à importer").setInputFiles(files);
    await page.locator(".asset").nth(2).waitFor();
    expect(await page.locator(".asset").count()).toBe(3);
    await expect(page.getByText("3 importées").isVisible()).resolves.toBe(true);
    await shot("13-images-importees");

    const zip = zipSync({ "pack/anneau.png": new Uint8Array(await icon("A", "#8e44ad")), "pack/lisez-moi.txt": new Uint8Array([104, 105]) });
    const zipFile = path.join(dir, "pack.zip");
    fs.writeFileSync(zipFile, zip);
    const bad = path.join(dir, "casse.png");
    fs.writeFileSync(bad, "ceci n'est pas une image");
    await page.getByLabel("Fichiers à importer").setInputFiles([zipFile, bad, files[0]]);
    await page.getByText("refusée").first().waitFor();
    await page.waitForFunction(() => document.querySelectorAll(".asset").length === 4); // 3 + the ring; the duplicate and the bad file are not added
    await expect(page.getByText("déjà présente").isVisible()).resolves.toBe(true);
    expect(await page.locator(".rejected").innerText()).toContain("casse");
    await shot("14-import-zip-doublon-refus");

    await page.getByRole("tab", { name: "Tuiles de map" }).click();
    await page.getByText("Aucune image dans cette catégorie pour l'instant.").waitFor();
    await shot("15-categorie-tuiles");

    await page.getByRole("link", { name: "Vue d'ensemble" }).click();
    await page.locator(".problem.warning").first().waitFor();
    expect(await page.locator(".problem.warning").count()).toBe(4);
    await expect(page.getByText("n'est utilisée par rien").first().isVisible()).resolves.toBe(true);
    await shot("16-avertissements-images-inutilisees", { fullPage: true });

    await page.getByRole("link", { name: "Images" }).click();
    await page.locator(".asset").nth(3).waitFor();
    await page.locator(".asset").first().getByRole("button", { name: "Supprimer" }).click();
    await page.waitForFunction(() => document.querySelectorAll(".asset").length === 3);
  });

  it("crée un objet et une panoplie, retrouve leurs textes, refuse de supprimer un texte utilisé, annule", async () => {
    await page.goto(base + "/mondes/monde_images/objets");
    await page.getByRole("heading", { name: "Objets", exact: true }).waitFor();
    await page.getByText("Aucun objet.").waitFor();
    await shot("17-objets-vide");

    await page.getByRole("button", { name: "+ Nouvelle panoplie" }).click();
    await page.getByRole("dialog").getByLabel("Nom").fill("Panoplie du Gardien");
    await page.getByRole("button", { name: "Créer", exact: true }).click();
    await page.getByText("Panoplie du Gardien").first().waitFor();

    await page.getByRole("button", { name: "+ Nouvel objet" }).click();
    const dlg = page.getByRole("dialog");
    const create = dlg.getByRole("button", { name: "Créer l'objet" });
    await expect(create.isDisabled()).resolves.toBe(true);
    await shot("18-nouvel-objet-vide");
    await dlg.getByLabel("Nom", { exact: true }).fill("Bouclier du Gardien");
    await dlg.getByLabel("Type").selectOption({ label: "Bouclier" });
    await dlg.getByLabel(/^Niveau/).fill("12");
    await dlg.getByLabel("Description (facultative)").fill("Forgé dans les os d'un ancien colosse.");
    await dlg.getByLabel("Panoplie").selectOption({ label: "Panoplie du Gardien" });
    await dlg.getByRole("radio").nth(1).click();
    await dlg.getByRole("button", { name: "+ Ajouter un effet" }).click();
    await dlg.getByLabel("Effet 1", { exact: true }).selectOption({ label: "Vitalité" });
    await dlg.getByLabel("Valeur min 1").fill("40");
    await dlg.getByLabel("Valeur max 1").fill("60");
    await dlg.getByLabel(/^Niveau/).fill("999");
    await expect(create.isDisabled()).resolves.toBe(true); // level out of range
    await dlg.getByLabel(/^Niveau/).fill("12");
    await shot("19-objet-rempli");
    await create.click();
    await page.locator("tr.clickable").first().waitFor();
    expect(await page.locator("tr.clickable").count()).toBe(1);
    await expect(page.locator("tr.clickable").innerText()).resolves.toContain("Bouclier du Gardien");
    await expect(page.locator("tr.clickable").innerText()).resolves.toContain("Panoplie du Gardien");
    await shot("20-objet-cree");

    await page.getByRole("link", { name: "Textes" }).click();
    await page.getByLabel("Rechercher un texte").fill("Gardien");
    await page.locator("tr", { hasText: "Bouclier du Gardien" }).waitFor();
    const used = page.locator("tr", { hasText: "Bouclier du Gardien" });
    await expect(used.getByRole("button", { name: /Supprimer le texte/ }).isDisabled()).resolves.toBe(true);
    await expect(used.innerText()).resolves.toContain("objet");
    await shot("21-textes-recherche");
    await page.getByLabel("Rechercher un texte").fill("");
    await page.getByRole("button", { name: "+ Nouveau texte" }).click();
    await page.getByRole("dialog").getByLabel("Texte").fill("Un texte libre");
    await page.getByRole("button", { name: "Ajouter" }).click();
    const free = page.locator("tr", { hasText: "Un texte libre" });
    await free.waitFor();
    await expect(free.innerText()).resolves.toContain("libre");
    await free.getByRole("button", { name: /Supprimer le texte/ }).click();
    await page.waitForFunction(() => !document.body.innerText.includes("Un texte libre"));

    await page.getByRole("button", { name: "↶ Annuler" }).click(); // undo the free text's deletion
    await page.locator("tr", { hasText: "Un texte libre" }).waitFor();
    await shot("22-annuler-suppression-texte");

    await page.getByRole("link", { name: "Objets" }).click();
    await page.locator("tr.clickable").first().click();
    await page.getByRole("button", { name: "Supprimer…" }).click();
    await page.getByRole("button", { name: "Confirmer la suppression" }).click();
    await page.getByText("Aucun objet.").waitFor();
    await shot("23-objet-supprime");
    const world = JSON.parse(fs.readFileSync(path.join(tmp, "worlds", "monde_images", "data", "items.json"), "utf-8"));
    expect(world.items).toEqual([]);
    expect(world.sets[0].items).toEqual([]);
  });

  it("crée un sort à deux effets, le modifie, voit son usage, refuse un nom vide, puis le supprime", async () => {
    const png = await sharp({ create: { width: 96, height: 96, channels: 4, background: "#d35400" } }).png().toBuffer();
    const r = await fetch(base + "/api/worlds/monde_images/assets/spell", {
      method: "POST", headers: { "content-type": "application/json", "x-atelier": "1" },
      body: JSON.stringify({ files: [{ name: "flamme.png", data: png.toString("base64") }] }),
    });
    expect(r.status).toBe(200);
    await page.goto(base + "/mondes/monde_images/sorts");
    await page.getByRole("heading", { name: "Sorts", exact: true }).waitFor();
    await page.getByText("Aucun sort.").waitFor();
    await shot("24-sorts-vide");
    await page.getByRole("button", { name: "+ Nouveau sort" }).click();
    const dlg = page.getByRole("dialog");
    await expect(dlg.getByRole("button", { name: "Créer le sort" }).isDisabled()).resolves.toBe(true);
    await dlg.getByLabel("Nom", { exact: true }).fill("Souffle de braise");
    await dlg.getByLabel("PA", { exact: true }).fill("4");
    await dlg.getByLabel("Portée max").fill("6");
    await dlg.getByLabel("Type 1").selectOption({ label: "Dommages" });
    await dlg.getByLabel("Élément 1").selectOption({ label: "Feu" });
    await dlg.getByLabel("Minimum 1").fill("18");
    await dlg.getByLabel("Maximum 1").fill("24");
    await dlg.getByRole("button", { name: "+ Ajouter un effet" }).click();
    await dlg.getByLabel("Type 2").selectOption({ label: "PM" });
    await dlg.getByLabel("Cible 2").selectOption({ label: "Ennemis" });
    await dlg.getByLabel("Sens 2").selectOption({ label: "Retrait" });
    await dlg.getByLabel("Minimum 2").fill("1");
    await dlg.getByLabel("Maximum 2").fill("1");
    await shot("25-sort-rempli");
    await dlg.getByRole("button", { name: "Créer le sort" }).click();
    const row = page.locator("tr.clickable", { hasText: "Souffle de braise" });
    await row.waitFor();
    await expect(row.innerText()).resolves.toContain("Dommages 18–24, PM 1–1");
    await shot("26-sort-cree");

    await row.click();
    await page.getByRole("dialog").getByLabel("Nom", { exact: true }).fill("");
    await expect(page.getByRole("button", { name: "Enregistrer" }).isDisabled()).resolves.toBe(true);
    await page.getByRole("dialog").getByLabel("Nom", { exact: true }).fill("Souffle ardent");
    await page.getByRole("button", { name: "Enregistrer" }).click();
    await page.locator("tr.clickable", { hasText: "Souffle ardent" }).waitFor();

    await page.getByRole("link", { name: "Images" }).click();
    await page.getByRole("tab", { name: "Sorts" }).click();
    await page.getByText("utilisée ×1").waitFor();
    await shot("27-icone-de-sort-utilisee");

    await page.getByRole("link", { name: "Sorts" }).click();
    await page.locator("tr.clickable").first().click();
    await page.getByRole("button", { name: "Supprimer…" }).click();
    await page.getByRole("button", { name: "Confirmer la suppression" }).click();
    await page.getByText("Aucun sort.").waitFor();
    const data = JSON.parse(fs.readFileSync(path.join(tmp, "worlds", "monde_images", "data", "spells.json"), "utf-8"));
    expect(data.spells).toEqual([]);
    expect(data.grades).toEqual({});
  });

  it("crée une zone et un monstre à deux grades (squelette copié, sort, butin), puis le modifie et le supprime", async () => {
    const H = { "content-type": "application/json", "x-atelier": "1" };
    const api = (m: string, u: string, b?: unknown) => fetch(base + "/api/worlds/monde_images" + u, { method: m, headers: m === "GET" ? undefined : H, body: b === undefined ? undefined : JSON.stringify(b) });
    const png = await sharp({ create: { width: 96, height: 96, channels: 4, background: "#2c3e50" } }).png().toBuffer();
    await api("POST", "/assets/monster", { files: [{ name: "gobelin.png", data: png.toString("base64") }] });
    const spellRes = await api("POST", "/data/spells", {
      name: "Morsure", icon: (await (await api("GET", "/assets/spell")).json())[0].id, level: 1, ap: 3, range: [1, 1], los: true, inLine: false, perTurn: 2, cooldown: 0, crit: 5, color: "#aa3322",
      area: { shape: "point", size: 0 }, effects: [{ kind: "damage", target: "enemies", min: 4, max: 7, element: "earth" }],
    });
    expect(spellRes.status).toBe(201);
    const itemIcon = (await (await api("GET", "/assets/item")).json())[0].id;
    expect((await api("POST", "/data/items", { name: "Croc de gobelin", icon: itemIcon, type: 9, level: 1, effects: [] })).status).toBe(201);

    await page.goto(base + "/mondes/monde_images/monstres");
    await page.getByRole("heading", { name: "Monstres", exact: true }).waitFor();
    await page.getByText("Aucun monstre.").waitFor();
    await page.getByLabel("Niveau de la nouvelle zone").fill("3");
    await page.getByRole("button", { name: "+ Nouvelle zone" }).click();
    await page.getByText("niveau 3").waitFor();
    await shot("28-monstres-et-zone");

    await page.getByRole("button", { name: "+ Nouveau monstre" }).click();
    const dlg = page.getByRole("dialog");
    await dlg.getByLabel("Nom", { exact: true }).fill("Gobelin des cendres");
    await dlg.getByText("Copier un squelette d'un autre monde").click();
    await dlg.getByRole("button", { name: /Copier le squelette .* de vertebre/ }).first().click();
    await dlg.getByRole("radio", { name: /^Squelette/ }).first().waitFor();
    await dlg.getByRole("checkbox", { name: /Zone niveau 3/ }).check();
    await dlg.getByLabel("Vie").fill("35");
    await dlg.getByRole("checkbox", { name: /Morsure/ }).check();
    await dlg.getByRole("button", { name: "+ Ajouter un butin" }).click();
    await dlg.getByLabel("Chance 1").fill("40");
    await dlg.evaluate((el) => { el.scrollTop = 0; });
    await shot("29-monstre-grade-1-haut");
    await dlg.evaluate((el) => { el.scrollTop = el.scrollHeight; });
    await shot("29-monstre-grade-1");
    await dlg.getByRole("button", { name: "+ Grade" }).click();
    await dlg.getByLabel("Vie").fill("60");
    await shot("30-monstre-grade-2");
    await dlg.getByRole("button", { name: "Créer le monstre" }).click();
    const row = page.locator("tr.clickable", { hasText: "Gobelin des cendres" });
    await row.waitFor();
    await expect(row.innerText()).resolves.toContain("1 · 5");
    await shot("31-monstre-cree");
    const world = JSON.parse(fs.readFileSync(path.join(tmp, "worlds", "monde_images", "monsters.json"), "utf-8"));
    const m = Object.values(world.monsters)[0] as any;
    expect(m.grades.map((g: any) => g.hp)).toEqual([35, 60]);
    expect(m.grades[0].drops[0].pct).toBe(40);
    expect(fs.existsSync(path.join(tmp, "worlds", "monde_images", "Content", "Characters", "Bones", m.grades[0].look.replace(/[{}]/g, "").split("|")[0], "0.png"))).toBe(true);

    await page.getByRole("link", { name: "Vue d'ensemble" }).click();
    await page.getByRole("heading", { name: "Cohérence" }).waitFor();
    expect(await page.locator(".problem.error").count()).toBe(0); // the new monster brought no error
    await page.getByRole("link", { name: "Monstres" }).click();
    await row.click();
    await page.getByRole("dialog").getByRole("button", { name: "Supprimer…" }).click();
    await page.getByRole("button", { name: "Confirmer la suppression" }).click();
    await page.getByText("Aucun monstre.").waitFor();
    await page.getByRole("button", { name: "Supprimer la zone" + "", exact: false }).first().click();
    await page.getByText("Aucune zone.").waitFor();
  });

  it("crée une classe avec un grimoire ordonné, la met par défaut, protège ses sorts, puis la supprime", async () => {
    const H = { "content-type": "application/json", "x-atelier": "1" };
    const api = (m: string, u: string, b?: unknown) => fetch(base + "/api/worlds/monde_images" + u, { method: m, headers: m === "GET" ? undefined : H, body: b === undefined ? undefined : JSON.stringify(b) });
    const icon = (await (await api("GET", "/assets/spell")).json())[0].id;
    for (const [name, lvl] of [["Frappe", 1], ["Entaille", 3], ["Fracas", 6]] as const)
      expect((await api("POST", "/data/spells", { name, icon, level: lvl, ap: 3, range: [1, 3], los: true, inLine: false, perTurn: 2, cooldown: 0, crit: 5, color: "#aa3322", area: { shape: "point", size: 0 }, effects: [{ kind: "damage", target: "enemies", min: 5, max: 8, element: "earth" }] })).status).toBe(201);

    await page.goto(base + "/mondes/monde_images/classes");
    await page.getByRole("heading", { name: "Classes jouables" }).waitFor();
    await page.getByText("Aucune classe dans ce monde.").waitFor();
    await shot("32-classes-vide");
    await page.getByRole("button", { name: "+ Nouvelle classe" }).click();
    const dlg = page.getByRole("dialog");
    await expect(dlg.getByRole("button", { name: "Créer la classe" }).isDisabled()).resolves.toBe(true);
    await dlg.getByLabel("Nom", { exact: true }).fill("Brise-pierre");
    await dlg.getByLabel("Rôle (une ligne)").fill("Combattant de mêlée");
    await dlg.getByLabel("Description").fill("Il frappe fort et de près.");
    await dlg.getByLabel("Ajouter un sort").selectOption({ label: "Fracas (niv. 6, 3 PA)" });
    await dlg.getByLabel("Ajouter un sort").selectOption({ label: "Frappe (niv. 1, 3 PA)" });
    await dlg.getByRole("button", { name: "Monter Frappe" }).click(); // Frappe before Fracas
    await shot("33-classe-grimoire");
    await dlg.getByRole("button", { name: "Créer la classe" }).click();
    await page.getByRole("heading", { name: "Brise-pierre" }).waitFor();
    await expect(page.locator(".card").innerText()).resolves.toContain("Frappe, Fracas");
    await shot("34-classe-creee");
    const cls = JSON.parse(fs.readFileSync(path.join(tmp, "worlds", "monde_images", "data", "spells.json"), "utf-8")).classes;
    expect(Object.values(cls)).toHaveLength(1);
    expect((Object.values(cls)[0] as any).pairs).toHaveLength(2);
    const world = JSON.parse(fs.readFileSync(path.join(tmp, "worlds", "monde_images", "world.json"), "utf-8"));
    expect(world.breeds).toHaveLength(1);
    expect(world.default_breed).toBe(world.breeds[0]);

    await page.getByRole("link", { name: "Sorts" }).click();
    await page.locator("tr.clickable", { hasText: "Frappe" }).click();
    await page.getByRole("button", { name: "Supprimer…" }).click();
    await page.getByRole("button", { name: "Confirmer la suppression" }).click();
    await page.getByText(/utilisé par class/).waitFor(); // a class' spell cannot be deleted
    await page.getByRole("button", { name: "Annuler", exact: true }).click();

    await page.getByRole("link", { name: "Classes" }).click();
    await page.getByRole("button", { name: "Modifier la classe Brise-pierre" }).click();
    await page.getByRole("dialog").getByRole("button", { name: "Supprimer…" }).click();
    await page.getByRole("button", { name: "Confirmer la suppression" }).click();
    await page.getByText("Aucune classe dans ce monde.").waitFor();
    expect(JSON.parse(fs.readFileSync(path.join(tmp, "worlds", "monde_images", "world.json"), "utf-8")).breeds).toEqual([]);
  });

  it("dessine une map sur la grille (murs, placement, porte, voisine), refuse une incohérence, puis la supprime", async () => {
    await page.goto(base + "/mondes/monde_images/maps");
    await page.getByRole("heading", { name: "Maps", exact: true }).waitFor();
    await page.waitForFunction(() => document.querySelectorAll("tr.clickable").length === 1);
    await shot("35-liste-des-maps");

    await page.getByRole("button", { name: "+ Nouvelle map" }).click();
    await page.getByRole("dialog").getByLabel("Nom").fill("Clairière");
    await page.getByRole("button", { name: "Créer la map" }).click();
    await page.getByRole("heading", { name: "Clairière" }).waitFor();
    await shot("36-map-vide");

    const cell = (n: number) => page.getByRole("gridcell", { name: `Cellule ${n}`, exact: true });
    for (const n of [41, 42, 43, 55, 56]) await cell(n).click();
    await page.getByRole("radio", { name: "Placement rouge" }).click();
    for (const n of [100, 101]) await cell(n).click();
    await page.getByRole("radio", { name: "Placement bleu" }).click();
    for (const n of [130, 131]) await cell(n).click();
    await page.getByRole("radio", { name: "Porte" }).click();
    await cell(200).click();
    await page.getByLabel("Voisine Gauche").selectOption({ label: "Départ" });
    await page.getByLabel("Nom", { exact: true }).fill("Clairière dorée");
    await shot("37-map-dessinee", { fullPage: true });
    await page.getByRole("button", { name: "Enregistrer la map" }).click();
    await page.getByRole("button", { name: "Enregistré" }).waitFor();
    const file = (n: string) => JSON.parse(fs.readFileSync(path.join(tmp, "worlds", "monde_images", "maps", n), "utf-8"));
    const maps = fs.readdirSync(path.join(tmp, "worlds", "monde_images", "maps")).map((n) => file(n));
    const mine = maps.find((m: any) => m.name === "Clairière dorée");
    expect(mine.blocked).toEqual([41, 42, 43, 55, 56]);
    expect(mine.placement).toEqual({ red: [100, 101], blue: [130, 131] });
    expect(mine.triggers).toHaveLength(1);
    const first = maps.find((m: any) => m.name === "Départ");
    expect(first.neighbors.right).toBe(mine.id); // reciprocal link written on the other map

    await page.getByRole("radio", { name: "Mur" }).click();
    await cell(100).click(); // a wall on a red placement cell: the cell leaves the placement list
    await page.getByRole("button", { name: "Enregistrer la map" }).click();
    await page.getByRole("button", { name: "Enregistré" }).waitFor();

    await page.getByRole("button", { name: "← Toutes les maps" }).click();
    await page.locator("tr.clickable", { hasText: "Départ" }).click();
    await page.getByRole("heading", { name: "Départ" }).waitFor();
    await cell(300).click(); // the start / rebirth cell of the world
    await page.getByRole("button", { name: "Enregistrer la map" }).click();
    await page.getByRole("alert").waitFor();
    await expect(page.getByRole("alert").innerText()).resolves.toMatch(/renaissance|départ/);
    await shot("38-refus-mur-sur-le-depart");
    await page.getByRole("button", { name: "← Toutes les maps" }).click();

    await page.locator("tr.clickable", { hasText: "Clairière dorée" }).click();
    await page.getByLabel("Voisine Gauche").selectOption({ label: "—" });
    await page.getByRole("button", { name: "Enregistrer la map" }).click();
    await page.getByRole("button", { name: "Enregistré" }).waitFor();
    await page.getByRole("button", { name: "Supprimer cette map…" }).click();
    await page.getByRole("button", { name: "Confirmer la suppression de la map" }).click();
    await page.getByRole("heading", { name: "Maps", exact: true }).waitFor();
    await page.waitForFunction(() => document.querySelectorAll("tr.clickable").length === 1);
    expect(fs.existsSync(path.join(tmp, "worlds", "monde_images", "maps", `${mine.id}.json`))).toBe(false);
    await shot("39-map-supprimee");
  });

  it("place une PNJ marchande, écrit son dialogue (nœuds, boutique, critère refusé), repère un nœud orphelin, puis la retire", async () => {
    await page.goto(base + "/mondes/monde_images/pnj");
    await page.getByRole("heading", { name: "PNJ", exact: true }).waitFor();
    await page.getByText("Aucun PNJ.").waitFor();
    await shot("40-pnj-vide");
    await page.getByRole("button", { name: "+ Nouveau PNJ" }).click();
    const dlg = page.getByRole("dialog");
    await dlg.getByLabel("Nom", { exact: true }).fill("Gardienne du pont");
    await dlg.getByRole("gridcell", { name: "Cellule 150", exact: true }).click();
    await dlg.getByRole("checkbox", { name: /Vend des objets/ }).check();
    await dlg.getByRole("checkbox", { name: /Croc de gobelin/ }).check();
    await shot("41-pnj-formulaire");
    await dlg.getByRole("button", { name: "Placer le PNJ" }).click();
    const row = page.locator("tr", { hasText: "Gardienne du pont" });
    await row.waitFor();
    await expect(row.innerText()).resolves.toContain("boutique (1)");

    await row.getByRole("button", { name: /Dialogue de/ }).click();
    await page.getByRole("heading", { name: "Dialogue de Gardienne du pont" }).waitFor();
    await page.getByLabel("Texte du nœud 0").fill("Halte ! Que cherchez-vous ?");
    await page.getByRole("button", { name: "+ Réponse" }).click();
    await page.getByLabel("Réponse 1 du nœud 0", { exact: true }).fill("Montrez-moi vos marchandises.");
    await page.getByLabel("Action, réponse 1 du nœud 0").selectOption({ label: "Ouvrir la boutique" });
    await page.getByLabel("Identifiant du nouveau nœud").fill("pont");
    await page.getByRole("button", { name: "+ Nouveau nœud" }).click();
    await page.getByLabel("Texte du nœud pont").fill("Le pont est fermé la nuit.");
    await page.getByRole("button", { name: "+ Réponse" }).first().click();
    await page.getByLabel("Réponse 2 du nœud 0", { exact: true }).fill("Et le pont ?");
    await page.getByLabel("Mène à, réponse 2 du nœud 0").selectOption({ label: "→ pont" });
    await page.getByLabel("Identifiant du nouveau nœud").fill("perdu");
    await page.getByRole("button", { name: "+ Nouveau nœud" }).click();
    await page.getByLabel("Texte du nœud perdu").fill("Personne ne vient ici.");
    await page.getByText("jamais atteint").waitFor();
    await shot("42-dialogue-noeuds", { fullPage: true });

    await page.getByLabel("Critère, réponse 1 du nœud 0").fill("n'importe quoi");
    await page.getByRole("button", { name: "Enregistrer le dialogue" }).click();
    await page.getByRole("alert").waitFor();
    await expect(page.getByRole("alert").innerText()).resolves.toContain("invalide");
    await shot("43-dialogue-critere-refuse");
    await page.getByLabel("Critère, réponse 1 du nœud 0").fill("");
    await page.getByRole("button", { name: "Enregistrer le dialogue" }).click();
    await page.getByRole("button", { name: "Enregistré" }).waitFor();
    const saved = JSON.parse(fs.readFileSync(path.join(tmp, "worlds", "monde_images", "dialogs.json"), "utf-8")).dialogs;
    const tree = Object.values(saved)[0] as any;
    expect(Object.keys(tree.nodes).sort()).toEqual(["0", "pont", "perdu"].sort());
    expect(tree.nodes["0"].replies[0].action).toEqual({ type: "shop" });
    expect(tree.nodes["0"].replies.map((r: any) => r.id)).toEqual([1, 2]);

    await page.getByRole("button", { name: "← Tous les PNJ" }).click();
    await page.getByRole("link", { name: "Vue d'ensemble" }).click();
    await page.getByText("n'est jamais atteint").waitFor(); // the validator sees the orphan node too
    await shot("44-cohérence-noeud-orphelin", { fullPage: true });

    await page.getByRole("link", { name: "PNJ" }).click();
    await page.locator("tr", { hasText: "Gardienne du pont" }).getByRole("button", { name: /Modifier le PNJ/ }).click();
    await page.getByRole("button", { name: "Retirer ce PNJ…" }).click();
    await page.getByRole("button", { name: "Confirmer le retrait" }).click();
    await page.getByText("Aucun PNJ.").waitFor();
    expect(JSON.parse(fs.readFileSync(path.join(tmp, "worlds", "monde_images", "dialogs.json"), "utf-8")).dialogs).toEqual({});
  });

  it("compose une quête en trois étapes (parler, chasser et découvrir, rapporter), la modifie, la voit protégée, puis la supprime", async () => {
    const H = { "content-type": "application/json", "x-atelier": "1" };
    const api = (m: string, u: string, b?: unknown) => fetch(base + "/api/worlds/monde_images" + u, { method: m, headers: m === "GET" ? undefined : H, body: b === undefined ? undefined : JSON.stringify(b) });
    const mapId = (await (await api("GET", "/data/maps")).json())[0].id;
    const itemId = (await (await api("GET", "/data/items")).json())[0].id;
    const bone = (await (await fetch(base + "/api/worlds/monde_images/bones")).json()).own[0];
    expect((await api("POST", "/data/npcs", { map: mapId, cell: 180, dir: 3, name: "Capitaine Orme", bone, size: 100, banker: false, shop: null })).status).toBe(201);
    const spellIcon = (await (await api("GET", "/assets/spell")).json())[0].id;
    const portrait = (await (await api("GET", "/assets/monster")).json())[0].id;
    const spell = (await (await api("POST", "/data/spells", { name: "Coup", icon: spellIcon, level: 1, ap: 3, range: [1, 1], los: true, inLine: false, perTurn: 2, cooldown: 0, crit: 5, color: "#aa3322", area: { shape: "point", size: 0 }, effects: [{ kind: "damage", target: "enemies", min: 3, max: 5, element: "earth" }] })).json()).id;
    const zone = (await (await api("POST", "/data/zones", { level: 1 })).json()).id;
    const g = { level: 1, hp: 10, ap: 6, mp: 3, xp: 5, stats: { strength: 0, intelligence: 0, chance: 0, agility: 0, wisdom: 0, ap_dodge: 0, mp_dodge: 0 }, res: { earth: 0, fire: 0, water: 0, air: 0, neutral: 0 }, spells: [spell], drops: [], kamas: [0, 1], aggro: { zone: 2, level_diff: 60, delay: 8000 } };
    expect((await api("POST", "/data/monsters", { name: "Rat des quais", bone, size: 100, portrait, grades: [g], zones: [String(zone)] })).status).toBe(201);

    await page.goto(base + "/mondes/monde_images/quetes");
    await page.getByRole("heading", { name: "Quêtes", exact: true }).waitFor();
    await page.getByText("Aucune quête pour l'instant.").waitFor();
    await shot("45-quetes-vide");
    await page.getByRole("button", { name: "+ Nouvelle quête" }).click();
    await page.getByRole("heading", { name: "Nouvelle quête" }).waitFor();
    await expect(page.getByRole("button", { name: "Créer la quête" }).isDisabled()).resolves.toBe(true);
    await page.getByLabel("Nom", { exact: true }).fill("Rats du port");

    await page.getByLabel("Titre de l'étape 1").fill("Voir le capitaine");
    await page.getByLabel("Description de l'étape 1").fill("Le capitaine Orme a besoin d'aide.");
    await page.getByLabel("Ajouter un objectif à l'étape 1").selectOption({ label: "Parler à un PNJ" });

    await page.getByRole("button", { name: "+ Ajouter une étape" }).click();
    await page.getByLabel("Titre de l'étape 2").fill("Chasse aux rats");
    await page.getByLabel("Description de l'étape 2").fill("Chasse trois rats des quais.");
    await page.getByLabel("Ajouter un objectif à l'étape 2").selectOption({ label: "Vaincre plusieurs monstres" });
    await page.getByLabel("Ajouter un objectif à l'étape 2").selectOption({ label: "Découvrir une map" });
    await page.getByLabel(/Ratio d'XP de l'étape 2/).fill("2");

    await page.getByRole("button", { name: "+ Ajouter une étape" }).click();
    await page.getByLabel("Titre de l'étape 3").fill("Le rapport");
    await page.getByLabel("Description de l'étape 3").fill("Rapporte des dents au capitaine.");
    await page.getByLabel("Ajouter un objectif à l'étape 3").selectOption({ label: "Apporter des objets à un PNJ" });
    await page.getByLabel("Ajouter un objectif à l'étape 3").selectOption({ label: "Retourner voir un PNJ" });
    await page.locator('li[aria-label="Étape 3"]').getByRole("button", { name: "+ Objet de récompense" }).click();
    await shot("46-quete-trois-etapes", { fullPage: true });
    await page.getByRole("button", { name: "Créer la quête" }).click();
    await page.getByRole("heading", { name: "Quêtes", exact: true }).waitFor();
    const row = page.locator("tr.clickable", { hasText: "Rats du port" });
    await row.waitFor();
    await expect(row.innerText()).resolves.toContain("Capitaine Orme");
    await shot("47-quete-creee");
    const raw = JSON.parse(fs.readFileSync(path.join(tmp, "worlds", "monde_images", "quests.json"), "utf-8")).quests;
    const q = Object.values(raw)[0] as any;
    expect(q.steps.map((s: any) => s.objectives.map((o: any) => o.type))).toEqual([[1], [14, 4], [3, 9]]);
    expect(q.steps[1].rewards[0].xp).toBe(2);

    await row.click();
    await page.getByLabel("Titre de l'étape 3").fill("Le rapport final");
    await page.getByRole("button", { name: "Enregistrer la quête" }).click();
    await page.getByRole("button", { name: "Enregistrée" }).waitFor();
    await page.getByLabel("Description de l'étape 1").fill("");
    await expect(page.getByRole("button", { name: "Enregistrer la quête" }).isDisabled()).resolves.toBe(true);
    await page.getByLabel("Description de l'étape 1").fill("Le capitaine Orme a besoin d'aide.");

    await page.getByRole("link", { name: "PNJ" }).click();
    await page.locator("tr", { hasText: "Capitaine Orme" }).getByRole("button", { name: /Modifier le PNJ/ }).click();
    await page.getByRole("button", { name: "Retirer ce PNJ…" }).click();
    await page.getByRole("button", { name: "Confirmer le retrait" }).click();
    await page.getByRole("alert").waitFor();
    await expect(page.getByRole("alert").innerText()).resolves.toContain("quest");
    await shot("48-pnj-protege-par-la-quete");
    await page.getByRole("button", { name: "Annuler", exact: true }).click();

    await page.getByRole("link", { name: "Quêtes" }).click();
    await page.locator("tr.clickable", { hasText: "Rats du port" }).click();
    await page.getByRole("button", { name: "Supprimer cette quête…" }).click();
    await page.getByRole("button", { name: "Confirmer la suppression de la quête" }).click();
    await page.getByText("Aucune quête pour l'instant.").waitFor();
    expect(JSON.parse(fs.readFileSync(path.join(tmp, "worlds", "monde_images", "quests.json"), "utf-8")).quests).toEqual({});
  });

  it("affiche les assistants guidés et leur avancement d'après les données", async () => {
    await page.goto(base + "/mondes/vertebre/assistants");
    await page.getByRole("heading", { name: "Assistants" }).waitFor();
    for (const t of ["Nouvelle classe jouable", "Nouveau monstre, butin et zone", "Nouvelle quête", "Nouveau donjon", "Relier deux maps", "Ajouter un PNJ marchand"])
      await page.getByRole("heading", { name: t }).waitFor();
    await expect(page.getByText("Terminé").count()).resolves.toBeGreaterThanOrEqual(4); // La Vertèbre is a finished world
    await shot("49-assistants", { fullPage: true });
    const fresh = base + "/mondes/monde_images/assistants";
    await page.goto(fresh);
    await page.getByRole("heading", { name: "Assistants" }).waitFor();
    await page.getByRole("button", { name: /Aller à l'étape/ }).first().click();
    await page.waitForURL(/\/mondes\/monde_images\/(sorts|classes|assets|objets|maps|pnj|quetes|monstres)/);
  });

  it("reste utilisable en largeur de téléphone et en thème sombre", async () => {
    const ctx = await browser.newContext({ viewport: { width: 390, height: 780 }, colorScheme: "dark", locale: "fr-FR" });
    const p = await ctx.newPage();
    await p.goto(base + "/mondes/vertebre");
    await p.getByRole("heading", { name: "La Vertèbre" }).waitFor();
    const overflow = await p.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth);
    expect(overflow, "défilement horizontal de la page").toBe(false);
    if (SHOTS) await p.screenshot({ path: path.join(SHOTS, "11-mobile-sombre.png"), fullPage: false });
    await ctx.close();
  });
});
