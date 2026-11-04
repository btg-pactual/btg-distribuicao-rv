@echo off
cd /d C:\Users\PIMENTPA\Projects\Artes\clone-github
git fetch origin pages
if not "%ERRORLEVEL%"=="0" (
  echo FETCH falhou
  exit /b 1
)
git checkout pages
if not "%ERRORLEVEL%"=="0" (
  echo CHECKOUT falhou
  exit /b 1
)
git rm -r -q --ignore-unmatch prateleira
git checkout 5d3128f -- prateleira ops/range_52w.json
if not "%ERRORLEVEL%"=="0" (
  echo RESTORE falhou
  exit /b 1
)
git add prateleira ops/range_52w.json
git commit -m "Prateleira: devolve a semana 03.11 e mantem a aba Educacional."
if not "%ERRORLEVEL%"=="0" (
  echo COMMIT falhou
  git status -sb
  exit /b 1
)
git push origin HEAD:pages
echo PUSH=%ERRORLEVEL%
git log -1 --oneline
if not "%ERRORLEVEL%"=="0" exit /b 1
