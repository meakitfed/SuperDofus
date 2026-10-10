@echo off
rem Lance le serveur SuperDofus DEPUIS LE PROJET (toujours le code a jour, sans export). Modifier les lignes "set" au besoin.
rem   WORLDS     mondes servis, separes par des virgules
rem   PORT       port du jeu (WebSocket) ; l'API de contenu ecoute sur PORT + 1
rem   SAVES      comptes et personnages
rem   PACKAGES   contenu PUBLIE (bundles, manifestes, releases) : le serveur le sert tel quel
rem   BIND       * = toutes les interfaces ; l'adresse Hamachi (25.x.x.x) limite le serveur au reseau Hamachi
rem   GM         comptes administrateurs (identifiants, separes par des virgules), vide = aucun
rem Commandes : serveur.bat            demarre (instantane)
rem             serveur.bat publier    publie le contenu des mondes (apres un changement de maps, d'assets...) puis quitte ;
rem                                    incremental : seuls les fichiers modifies sont ecrits
rem             serveur.bat check      verifie mondes, dossiers, contenu publie et ports
set GODOT=C:\Users\natha\Documents\Godot\Godot_v4.7-stable_win64_console.exe
set WORLDS=incarnam,dofus
set PORT=7777
set SAVES=%~dp0saves
set PACKAGES=%APPDATA%\Godot\app_userdata\SuperDofus\packages
set BIND=*
set GM=
set /a HTTP=%PORT%+1
set RUN="%GODOT%" --headless --path "%~dp0game" -s res://src/server/main.gd -- --server
if "%~1"=="publier" goto publish
if "%~1"=="check" goto check
echo Serveur SuperDofus : mondes %WORLDS%, port %PORT% (contenu %HTTP%), sauvegardes %SAVES%
echo Ferme cette fenetre ou Ctrl+C pour arreter proprement.
%RUN% --port=%PORT% --http-port=%HTTP% --world=%WORLDS% --save-dir="%SAVES%" --package-dir="%PACKAGES%" --bind=%BIND% --gm=%GM%
goto end
:publish
%RUN% --no-auth --build-packages --world=%WORLDS% --package-dir="%PACKAGES%"
if errorlevel 1 echo La publication a echoue : voir les messages ci-dessus (la relancer reprend ou elle s'est arretee).
goto end
:check
%RUN% --check --port=%PORT% --http-port=%HTTP% --world=%WORLDS% --save-dir="%SAVES%" --package-dir="%PACKAGES%"
:end
pause
