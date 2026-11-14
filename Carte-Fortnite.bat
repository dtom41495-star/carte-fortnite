@echo off
rem Premier lancement seulement : ensuite, utilise le raccourci "Carte Fortnite" (avec l'icone de coffre), qui n'ouvre aucune fenetre noire.
rem Toutes les verifications (Fortnite ouvert, .NET, preparation de l'outil) se font dans le panneau.
if exist "%SystemRoot%\System32\conhost.exe" (
  start "" "%SystemRoot%\System32\conhost.exe" --headless "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0panneau.ps1"
) else (
  start "" powershell -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0panneau.ps1"
)
exit
