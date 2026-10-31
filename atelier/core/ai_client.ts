// ComfyUI, the local image generator of the AI studio (docs/STUDIO_IA.md): FLUX.1 Kontext [dev] (GGUF) edits an
// image following a text, or draws from the text alone. Installed by tools/ai/setup_ai.ps1, started by
// tools/ai/start_ai.bat; the atelier only talks to its HTTP API on 127.0.0.1.
import fs from "node:fs";

export interface AiConfig { url: string; unet: string; t5: string; clip: string; vae: string; steps: number; guidance: number }
export const DEFAULT_AI_CONFIG: AiConfig = {
  url: "http://127.0.0.1:8188", unet: "flux1-kontext-dev-Q4_K_S.gguf", t5: "t5-v1_1-xxl-encoder-Q4_K_M.gguf",
  clip: "clip_l.safetensors", vae: "ae.safetensors", steps: 20, guidance: 2.5,
};
export const AI_CONFIG_FILE = "C:\\SuperDofus\\ai\\comfy.json";

/** setup_ai.ps1 writes the config; ATELIER_AI_CONFIG points elsewhere. */
export function loadAiConfig(file = process.env.ATELIER_AI_CONFIG ?? AI_CONFIG_FILE): AiConfig {
  try { return { ...DEFAULT_AI_CONFIG, ...JSON.parse(fs.readFileSync(file, "utf-8").replace(/^\uFEFF/, "")) }; } catch { return { ...DEFAULT_AI_CONFIG }; }
}

export interface AiStatus { ready: boolean; summary: string; device?: string; vramGb?: number }

type Node = { class_type: string; inputs: Record<string, unknown> };

/**
 * The workflow in ComfyUI's API format. With `image` (an uploaded file name) Kontext edits it; without, it draws
 * a `width` x `height` image from the text.
 */
export function kontextWorkflow(c: AiConfig, prompt: string, seed: number, image?: string, width = 1024, height = 1024): Record<string, Node> {
  const wf: Record<string, Node> = {
    unet: { class_type: "UnetLoaderGGUF", inputs: { unet_name: c.unet } },
    clip: { class_type: "DualCLIPLoaderGGUF", inputs: { clip_name1: c.clip, clip_name2: c.t5, type: "flux" } },
    vae: { class_type: "VAELoader", inputs: { vae_name: c.vae } },
    text: { class_type: "CLIPTextEncode", inputs: { text: prompt, clip: ["clip", 0] } },
    negative: { class_type: "ConditioningZeroOut", inputs: { conditioning: ["text", 0] } },
    sampler: {
      class_type: "KSampler",
      inputs: { model: ["unet", 0], positive: ["guidance", 0], negative: ["negative", 0], latent_image: ["latent", 0], seed, steps: c.steps, cfg: 1, sampler_name: "euler", scheduler: "simple", denoise: 1 },
    },
    decode: { class_type: "VAEDecode", inputs: { samples: ["sampler", 0], vae: ["vae", 0] } },
    save: { class_type: "SaveImage", inputs: { images: ["decode", 0], filename_prefix: "atelier" } },
  };
  if (image) {
    wf.image = { class_type: "LoadImage", inputs: { image } };
    wf.latent = { class_type: "VAEEncode", inputs: { pixels: ["image", 0], vae: ["vae", 0] } };
    wf.reference = { class_type: "ReferenceLatent", inputs: { conditioning: ["text", 0], latent: ["latent", 0] } };
    wf.guidance = { class_type: "FluxGuidance", inputs: { conditioning: ["reference", 0], guidance: c.guidance } };
  } else {
    wf.latent = { class_type: "EmptySD3LatentImage", inputs: { width, height, batch_size: 1 } };
    wf.guidance = { class_type: "FluxGuidance", inputs: { conditioning: ["text", 0], guidance: c.guidance } };
  }
  return wf;
}

export class ComfyClient {
  constructor(readonly config: AiConfig = loadAiConfig(), private readonly http: typeof fetch = fetch) {}

  private url(p: string) { return this.config.url.replace(/\/$/, "") + p; }

  async status(): Promise<AiStatus> {
    try {
      const r = await this.http(this.url("/system_stats"), { signal: AbortSignal.timeout(3000) });
      if (!r.ok) return { ready: false, summary: `ComfyUI répond mal (HTTP ${r.status}).` };
      const j = (await r.json()) as { devices?: { name?: string; vram_total?: number }[] };
      const d = j.devices?.[0];
      const nodes = await this.http(this.url("/object_info/UnetLoaderGGUF"), { signal: AbortSignal.timeout(3000) }).then((x) => x.json()).catch(() => ({}));
      if (!(nodes as Record<string, unknown>).UnetLoaderGGUF) return { ready: false, summary: "ComfyUI tourne mais le nœud GGUF manque : relancer tools\\ai\\setup_ai.ps1." };
      return { ready: true, summary: "Moteur d'images prêt.", device: d?.name?.replace(/^cuda:\d+ /, "").replace(/ : .*$/, ""), vramGb: d?.vram_total ? Math.round(d.vram_total / 2 ** 30) : undefined };
    } catch {
      return { ready: false, summary: "Le moteur d'images (ComfyUI) n'est pas lancé : tools\\ai\\start_ai.bat (installation : tools\\ai\\setup_ai.ps1)." };
    }
  }

  async upload(png: Buffer, name: string): Promise<string> {
    const form = new FormData();
    form.append("image", new Blob([new Uint8Array(png)], { type: "image/png" }), name);
    form.append("overwrite", "true");
    const r = await this.http(this.url("/upload/image"), { method: "POST", body: form });
    if (!r.ok) throw new Error(`ComfyUI a refusé l'image (HTTP ${r.status})`);
    const j = (await r.json()) as { name: string; subfolder?: string };
    return j.subfolder ? `${j.subfolder}/${j.name}` : j.name;
  }

  /** Runs a workflow and returns the PNG it saved. */
  async run(workflow: Record<string, Node>, timeoutMs = 15 * 60_000): Promise<Buffer> {
    const r = await this.http(this.url("/prompt"), { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ prompt: workflow, client_id: "atelier" }) });
    const body = (await r.json().catch(() => ({}))) as { prompt_id?: string; error?: { message?: string }; node_errors?: unknown };
    if (!r.ok || !body.prompt_id) throw new Error(`ComfyUI a refusé la génération : ${body.error?.message ?? r.status} ${body.node_errors ? JSON.stringify(body.node_errors).slice(0, 300) : ""}`);
    const t0 = Date.now();
    while (Date.now() - t0 < timeoutMs) {
      await new Promise((res) => setTimeout(res, 1000));
      const h = (await this.http(this.url(`/history/${body.prompt_id}`)).then((x) => x.json())) as Record<string, any>;
      const entry = h[body.prompt_id];
      if (!entry) continue;
      if (entry.status?.status_str === "error") {
        const msg = (entry.status.messages ?? []).find((m: any[]) => m[0] === "execution_error")?.[1]?.exception_message;
        throw new Error(`la génération a échoué : ${msg ?? "erreur de ComfyUI"}`);
      }
      const img = Object.values(entry.outputs ?? {}).flatMap((o: any) => o.images ?? [])[0] as { filename: string; subfolder: string; type: string } | undefined;
      if (!img) { if (entry.status?.completed) throw new Error("la génération n'a produit aucune image"); continue; }
      const q = new URLSearchParams({ filename: img.filename, subfolder: img.subfolder ?? "", type: img.type ?? "output" });
      const v = await this.http(this.url(`/view?${q}`));
      if (!v.ok) throw new Error(`image introuvable dans ComfyUI (HTTP ${v.status})`);
      return Buffer.from(await v.arrayBuffer());
    }
    throw new Error("la génération a pris trop de temps");
  }
}
