@echo off
REM Abre viz.html com servidor local (fetch JSON funciona; file:// nao).
setlocal
cd /d "%~dp0.."
set PORT=8765
echo Mr Derivs viz: http://127.0.0.1:%PORT%/viz.html
echo (Ctrl+C para parar)
start "" "http://127.0.0.1:%PORT%/viz.html"
python -m http.server %PORT% 2>nul
if errorlevel 1 py -m http.server %PORT%
