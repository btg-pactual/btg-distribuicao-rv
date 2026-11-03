@echo off
cd /d C:\Users\PIMENTPA\Projects\Artes\clone-github\prateleira
python _build.py > _build_out.txt 2>&1
echo BUILD=%ERRORLEVEL% > _pub.txt
if errorlevel 1 exit /b 1
findstr /i "excel_sheet ops pdf_copied range_52w research Error Traceback" _build_out.txt >> _pub.txt
type _excel_week.txt >> _pub.txt 2>nul
cd ..
git fetch origin pages >> prateleira\_pub.txt 2>&1
git add prateleira/_build.py prateleira/_excel_week.py prateleira/index.html prateleira/empresas.html prateleira/estruturas.html prateleira/ops/ prateleira/research_targets.json prateleira/operacoes/ prateleira/leituras/ ops/range_52w.json
git add prateleira/Material-Prateleira-Tatica-*.pdf 2>nul
git add -u -- prateleira/
git status -sb -- prateleira/ ops/range_52w.json > prateleira\_st.txt 2>&1
echo Prateleira: sync ultima aba Excel + rebuild hub.> prateleira\_commit_msg.txt
git commit -F prateleira\_commit_msg.txt >> prateleira\_pub.txt 2>&1
echo COMMIT=%ERRORLEVEL% >> prateleira\_pub.txt
git pull --rebase --autostash origin pages >> prateleira\_pub.txt 2>&1
echo PULL=%ERRORLEVEL% >> prateleira\_pub.txt
if errorlevel 1 (
  git rebase --abort >> prateleira\_pub.txt 2>&1
  echo PULL_FAIL — rebase abortado. Nada foi resetado. >> prateleira\_pub.txt
  exit /b 1
)
git push origin pages >> prateleira\_pub.txt 2>&1
echo PUSH=%ERRORLEVEL% >> prateleira\_pub.txt
git log -1 --oneline >> prateleira\_pub.txt 2>&1
