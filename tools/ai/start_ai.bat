@echo off
rem Lance ComfyUI (moteur du Studio IA de l'atelier) sur http://127.0.0.1:8188. Installation : tools\ai\setup_ai.ps1
set ROOT=C:\SuperDofus\ai\ComfyUI_windows_portable
if not exist "%ROOT%\python_embeded\python.exe" (
	echo ComfyUI absent : lancer d'abord  powershell -ExecutionPolicy Bypass -File tools\ai\setup_ai.ps1
	exit /b 1
)
cd /d "%ROOT%"
python_embeded\python.exe -s ComfyUI\main.py --windows-standalone-build --listen 127.0.0.1 --port 8188 --lowvram --disable-auto-launch
