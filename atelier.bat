@echo off
rem Atelier de mondes : http://127.0.0.1:5174 (ATELIER_PORT pour changer le port)
cd /d "%~dp0atelier"
if not exist node_modules call npm install
call npm run build
start "" http://127.0.0.1:5174
npm start
