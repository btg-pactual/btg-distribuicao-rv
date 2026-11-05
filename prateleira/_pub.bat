@echo off
cd /d C:\Users\PIMENTPA\Projects\Artes\clone-github\prateleira
copy /B /Y "C:\Users\PIMENTPA\Downloads\10.30.2026_*Macro View (1).pdf" "leituras\Cenario-Macro-Novembro-2026.pdf"
set COPY=%ERRORLEVEL%
echo COPY=%COPY%
set PDF_BYTES=0
for %%A in ("leituras\Cenario-Macro-Novembro-2026.pdf") do set PDF_BYTES=%%~zA
echo PDF_BYTES=%PDF_BYTES%
if %PDF_BYTES% LSS 100000 (
  echo PDF pequeno demais ^(%PDF_BYTES% bytes^). Copia incompleta.
  exit /b 1
)
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
git add prateleira/_build.py prateleira/_excel_week.py prateleira/_pub.bat prateleira/index.html prateleira/empresas.html prateleira/estruturas.html prateleira/educacao.html prateleira/ops/ prateleira/research_targets.json prateleira/operacoes/ prateleira/leituras/ ops/range_52w.json
git add prateleira/Material-Prateleira-Tatica-*.pdf 2>nul
git add -u -- prateleira/
echo Prateleira: atualiza o hub.> prateleira\_commit_msg.txt
git commit -F prateleira\_commit_msg.txt >> prateleira\_pub.txt 2>&1
set COMMIT=%ERRORLEVEL%
echo COMMIT=%COMMIT%
echo COMMIT=%COMMIT% >> prateleira\_pub.txt
if not "%COMMIT%"=="0" (
  echo COMMIT falhou
  exit /b 1
)
git merge origin/pages -X ours -m "Prateleira: mantem a semana 03.11." >> prateleira\_pub.txt 2>&1
if errorlevel 1 goto merge_fix
goto merge_ok
:merge_fix
git diff --name-only --diff-filter=U > prateleira\_conflicts.txt
for /f "usebackq delims=" %%F in (prateleira\_conflicts.txt) do git checkout --ours -- "%%F"
git add -A -- prateleira
git add -u -- prateleira ops/range_52w.json
git commit --no-edit >> prateleira\_pub.txt 2>&1
if errorlevel 1 (
  git merge --abort >> prateleira\_pub.txt 2>&1
  echo MERGE_FAIL — merge abortado. Nada foi resetado.
  exit /b 1
)
:merge_ok
echo MERGE=0
echo MERGE=0 >> prateleira\_pub.txt
for /f %%B in ('git rev-parse --abbrev-ref HEAD') do set BR=%%B
if not "%BR%"=="pages" git branch -f pages HEAD
git push origin HEAD:pages >> prateleira\_pub.txt 2>&1
set PUSH=%ERRORLEVEL%
echo PUSH=%PUSH%
echo PUSH=%PUSH% >> prateleira\_pub.txt
git log -1 --oneline
git log -1 --oneline >> prateleira\_pub.txt 2>&1
if not "%PUSH%"=="0" exit /b 1
