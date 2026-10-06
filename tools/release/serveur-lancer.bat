@echo off
rem Lance le serveur SuperDofus (roadmap X.01). Modifier les trois lignes "set" au besoin.
rem   PORT       port du jeu (WebSocket) ; l'API de contenu ecoute sur PORT + 1
rem   WORLDS     mondes servis, separes par des virgules
rem   SAVES      dossier des sauvegardes (comptes et personnages)
rem   BIND       * = toutes les interfaces ; l'adresse Hamachi (25.x.x.x) limite le serveur au reseau Hamachi
rem   GM         comptes administrateurs (identifiants, separes par des virgules), vide = aucun
set PORT=7777
set WORLDS=@WORLDS@
set SAVES=%~dp0server\saves
set BIND=*
set GM=
cd /d "%~dp0server"
set /a HTTP=%PORT%+1
if "%~1"=="check" goto check
echo Serveur SuperDofus : mondes %WORLDS%, port %PORT% (contenu %HTTP%), sauvegardes %SAVES%
echo Ferme cette fenetre ou Ctrl+C pour arreter proprement.
SuperDofusServeur.console.exe --headless -- --port=%PORT% --http-port=%HTTP% --world=%WORLDS% --save-dir="%SAVES%" --bind=%BIND% --gm=%GM%
goto end
:check
SuperDofusServeur.console.exe --headless -- --check --port=%PORT% --http-port=%HTTP% --world=%WORLDS% --save-dir="%SAVES%"
:end
pause
