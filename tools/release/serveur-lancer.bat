@echo off
rem Lance le serveur SuperDofus (roadmap X.01, C.06). Modifier les lignes "set" au besoin.
rem   PORT       port du jeu (WebSocket) ; l'API de contenu ecoute sur PORT + 1
rem   WORLDS     mondes servis, separes par des virgules
rem   SAVES      dossier des sauvegardes (comptes et personnages)
rem   PACKAGES   dossier du contenu PUBLIE (manifestes, zips, versions) : le serveur le lit, il ne calcule rien
rem   BIND       * = toutes les interfaces ; l'adresse Hamachi (25.x.x.x) limite le serveur au reseau Hamachi
rem   GM         comptes administrateurs (identifiants, separes par des virgules), vide = aucun
rem Commandes : serveur-lancer.bat            demarre (publie d'abord les mondes jamais publies)
rem             serveur-lancer.bat publier    (re)publie le contenu (apres un changement de maps, d'assets...) puis quitte
rem             serveur-lancer.bat check      verifie mondes, dossiers, contenu publie et ports
set PORT=7777
set WORLDS=@WORLDS@
set SAVES=%~dp0server\saves
set PACKAGES=%~dp0server\packages
set BIND=*
set GM=
cd /d "%~dp0server"
set /a HTTP=%PORT%+1
if "%~1"=="check" goto check
if "%~1"=="publier" goto publish
for %%W in (%WORLDS%) do if not exist "%PACKAGES%\%%W\current.json" goto publish_first
goto run
:publish_first
echo Contenu pas encore publie : publication (longue la premiere fois, reprise possible si interrompue).
:publish
SuperDofusServeur.console.exe --headless -- --build-packages --world=%WORLDS% --package-dir="%PACKAGES%" --save-dir="%SAVES%"
if errorlevel 1 goto failed
if "%~1"=="publier" goto end
:run
echo Serveur SuperDofus : mondes %WORLDS%, port %PORT% (contenu %HTTP%), sauvegardes %SAVES%
echo Ferme cette fenetre ou Ctrl+C pour arreter proprement.
SuperDofusServeur.console.exe --headless -- --port=%PORT% --http-port=%HTTP% --world=%WORLDS% --save-dir="%SAVES%" --package-dir="%PACKAGES%" --bind=%BIND% --gm=%GM%
goto end
:check
SuperDofusServeur.console.exe --headless -- --check --port=%PORT% --http-port=%HTTP% --world=%WORLDS% --save-dir="%SAVES%" --package-dir="%PACKAGES%"
goto end
:failed
echo La publication du contenu a echoue : voir les messages ci-dessus.
:end
pause
