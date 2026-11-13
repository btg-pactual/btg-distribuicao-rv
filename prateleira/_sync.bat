@echo off
cd /d C:\Users\PIMENTPA\Projects\Artes\clone-github
git fetch origin pages
if errorlevel 1 (
  echo FETCH_FAIL
  exit /b 1
)
for /f %%H in ('git rev-parse HEAD') do set LOCAL=%%H
for /f %%R in ('git rev-parse origin/pages') do set REMOTE=%%R
echo LOCAL=%LOCAL%
echo REMOTE=%REMOTE%
if "%LOCAL%"=="%REMOTE%" (
  echo JA_ATUALIZADO
  exit /b 0
)
for /f %%B in ('git rev-parse --abbrev-ref HEAD') do set BR=%%B
if not "%BR%"=="pages" (
  echo FETCH feito. Branch atual: %BR%. Nao troquei de branch.
  exit /b 0
)
git diff --quiet
if errorlevel 1 (
  echo FETCH feito. Ha alteracoes locais, entao nao misturei.
  exit /b 0
)
git merge-base --is-ancestor HEAD origin/pages
if errorlevel 1 (
  echo Este PC e o GitHub andaram em separado. Rode .\_pub.bat
  exit /b 0
)
git merge --ff-only origin/pages
if errorlevel 1 (
  echo SYNC_FAIL
  exit /b 1
)
echo SYNC=0
