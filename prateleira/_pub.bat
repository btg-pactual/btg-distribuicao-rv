@echo off
cd /d C:\Users\PIMENTPA\Projects\Artes\clone-github\prateleira
python _build.py > _build_out.txt 2>&1
set BUILD=%ERRORLEVEL%
echo BUILD=%BUILD%
echo BUILD=%BUILD% > _pub.txt
if not "%BUILD%"=="0" (
  echo BUILD falhou
  findstr /i "Error Traceback excel_fail" _build_out.txt
  exit /b 1
)
findstr /i "excel_sheet week_moves ops pdf_copied" _build_out.txt
findstr /i "excel_sheet week_moves ops pdf_copied range_52w research Error Traceback" _build_out.txt >> _pub.txt
type _excel_week.txt
type _excel_week.txt >> _pub.txt 2>nul
cd ..
git fetch origin pages >> prateleira\_pub.txt 2>&1
git add prateleira/_build.py prateleira/_excel_week.py prateleira/_pub.bat prateleira/index.html prateleira/empresas.html prateleira/estruturas.html prateleira/ops/ prateleira/research_targets.json prateleira/operacoes/ prateleira/leituras/ ops/range_52w.json
git add prateleira/Material-Prateleira-Tatica-*.pdf 2>nul
git add -u -- prateleira/
echo Prateleira: tira o movimento da semana do Overview.> prateleira\_commit_msg.txt
git commit -F prateleira\_commit_msg.txt >> prateleira\_pub.txt 2>&1
set COMMIT=%ERRORLEVEL%
echo COMMIT=%COMMIT%
echo COMMIT=%COMMIT% >> prateleira\_pub.txt
if not "%COMMIT%"=="0" (
  echo COMMIT falhou
  exit /b 1
)
git pull --rebase --autostash origin pages >> prateleira\_pub.txt 2>&1
set PULL=%ERRORLEVEL%
echo PULL=%PULL%
echo PULL=%PULL% >> prateleira\_pub.txt
if not "%PULL%"=="0" (
  git rebase --abort >> prateleira\_pub.txt 2>&1
  echo PULL_FAIL — rebase abortado. Nada foi resetado.
  exit /b 1
)
git branch -f pages HEAD
git push origin HEAD:pages >> prateleira\_pub.txt 2>&1
set PUSH=%ERRORLEVEL%
echo PUSH=%PUSH%
echo PUSH=%PUSH% >> prateleira\_pub.txt
git log -1 --oneline
git log -1 --oneline >> prateleira\_pub.txt 2>&1
if not "%PUSH%"=="0" exit /b 1
