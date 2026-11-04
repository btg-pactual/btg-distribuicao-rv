@echo off
cd /d C:\Users\PIMENTPA\Projects\Artes\clone-github
git fetch origin pages
git checkout 22852a2 -- .github curvas-juros mr-derivs
if errorlevel 1 exit /b 1
cd prateleira
python _build.py > _build_out.txt 2>&1
echo BUILD=%ERRORLEVEL%
if errorlevel 1 exit /b 1
cd ..
git add .github curvas-juros mr-derivs prateleira/_build.py prateleira/_excel_week.py prateleira/_pub.bat prateleira/index.html prateleira/empresas.html prateleira/estruturas.html prateleira/ops prateleira/research_targets.json prateleira/operacoes ops/range_52w.json
git add -u -- .github curvas-juros mr-derivs prateleira/
echo Prateleira: corrige barreira KO do SOC (aba 03.11) e restaura curvas-juros e mr-derivs.> prateleira\_commit_msg.txt
git commit -F prateleira\_commit_msg.txt
if errorlevel 1 exit /b 1
git pull --rebase --autostash origin pages
if errorlevel 1 (
  git rebase --abort
  echo PULL_FAIL
  exit /b 1
)
git push origin pages
echo PUSH=%ERRORLEVEL%
git log -1 --oneline
