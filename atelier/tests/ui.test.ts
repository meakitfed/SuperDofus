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
    await shot("09-la-vertebre", { fullPage: true });
  });

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
    expect(await page.locator(".asset").count()).toBe(4); // 3 + the ring; the duplicate and the bad file are not added
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
