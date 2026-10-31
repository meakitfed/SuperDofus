# Installe le Studio IA de l'atelier (gratuit, local) : ComfyUI portable + FLUX.1 Kontext [dev] en GGUF.
#   powershell -ExecutionPolicy Bypass -File tools\ai\setup_ai.ps1 [-Root C:\SuperDofus\ai]
# Reprenable : relancer le script termine les téléchargements interrompus. Voir docs/STUDIO_IA.md.
param([string]$Root = "C:\SuperDofus\ai")
$ErrorActionPreference = "Stop"

$Comfy = Join-Path $Root "ComfyUI_windows_portable"
$Models = Join-Path $Comfy "ComfyUI\models"
$Files = @(
	@{ Url = "https://huggingface.co/QuantStack/FLUX.1-Kontext-dev-GGUF/resolve/main/flux1-kontext-dev-Q4_K_S.gguf"; Dest = "unet\flux1-kontext-dev-Q4_K_S.gguf"; Size = 6797337888 },
	@{ Url = "https://huggingface.co/city96/t5-v1_1-xxl-encoder-gguf/resolve/main/t5-v1_1-xxl-encoder-Q4_K_M.gguf"; Dest = "text_encoders\t5-v1_1-xxl-encoder-Q4_K_M.gguf"; Size = 2896123072 },
	@{ Url = "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors"; Dest = "text_encoders\clip_l.safetensors"; Size = 246144152 },
	@{ Url = "https://huggingface.co/Comfy-Org/Lumina_Image_2.0_Repackaged/resolve/main/split_files/vae/ae.safetensors"; Dest = "vae\ae.safetensors"; Size = 335304388 }
)

function Need([long]$bytes) {
	$drive = (Get-Item $Root).PSDrive
	$free = (Get-PSDrive $drive.Name).Free
	if ($free -lt $bytes + 2GB) { throw ("Pas assez de place sur {0}: : {1:N1} Go libres, {2:N1} Go nécessaires (+2 Go de marge)." -f $drive.Name, ($free / 1GB), ($bytes / 1GB)) }
}

function Fetch([string]$url, [string]$dest, [long]$size) {
	if ((Test-Path $dest) -and (Get-Item $dest).Length -eq $size) { Write-Host "déjà là : $dest"; return }
	New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
	Write-Host "téléchargement : $url"
	& curl.exe -L --fail --retry 5 -C - -o $dest $url
	if ($LASTEXITCODE -ne 0) { throw "échec du téléchargement de $url" }
	if ($size -gt 0 -and (Get-Item $dest).Length -ne $size) { throw "taille inattendue pour $dest" }
}

New-Item -ItemType Directory -Force $Root | Out-Null

# 1. ComfyUI portable (Python et PyTorch CUDA inclus)
if (-not (Test-Path (Join-Path $Comfy "python_embeded\python.exe"))) {
	Need 8GB
	$archive = Join-Path $Root "ComfyUI_windows_portable_nvidia.7z"
	Fetch "https://github.com/comfyanonymous/ComfyUI/releases/latest/download/ComfyUI_windows_portable_nvidia.7z" $archive 0
	$sevenZip = "C:\Program Files\7-Zip\7z.exe"
	if (Test-Path $sevenZip) { & $sevenZip x $archive "-o$Root" -y | Out-Null } else { & "$env:SystemRoot\System32\tar.exe" -xf $archive -C $Root }
	if ($LASTEXITCODE -ne 0) { throw "échec de la décompression de ComfyUI" }
	Remove-Item $archive -Force
}

# 2. Nœud GGUF (charge les modèles quantifiés qui tiennent dans 8 Go de VRAM)
$gguf = Join-Path $Comfy "ComfyUI\custom_nodes\ComfyUI-GGUF"
if (-not (Test-Path $gguf)) { & git clone --depth 1 https://github.com/city96/ComfyUI-GGUF $gguf; if ($LASTEXITCODE -ne 0) { throw "échec du clone de ComfyUI-GGUF" } }
& (Join-Path $Comfy "python_embeded\python.exe") -s -m pip install --quiet -r (Join-Path $gguf "requirements.txt")
if ($LASTEXITCODE -ne 0) { throw "échec de l'installation des dépendances de ComfyUI-GGUF" }

# 3. Modèles
$missing = 0
foreach ($f in $Files) { $d = Join-Path $Models $f.Dest; if (-not ((Test-Path $d) -and (Get-Item $d).Length -eq $f.Size)) { $missing += $f.Size } }
if ($missing -gt 0) { Need $missing }
foreach ($f in $Files) { Fetch $f.Url (Join-Path $Models $f.Dest) $f.Size }

# 4. Réglages lus par l'atelier
$conf = @{ url = "http://127.0.0.1:8188"; root = $Comfy; unet = "flux1-kontext-dev-Q4_K_S.gguf"; t5 = "t5-v1_1-xxl-encoder-Q4_K_M.gguf"; clip = "clip_l.safetensors"; vae = "ae.safetensors" }
$conf | ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $Root "comfy.json")
Write-Host "Studio IA installé dans $Root. Lancer tools\ai\start_ai.bat avant d'utiliser le Studio IA de l'atelier."
