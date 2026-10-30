@echo off
REM Define MR_DERIVS_RSCRIPT (Rscript no PATH ou instalacao padrao em Program Files)
if defined MR_DERIVS_RSCRIPT exit /b 0
where Rscript >nul 2>&1
if not errorlevel 1 (
  set "MR_DERIVS_RSCRIPT=Rscript"
  exit /b 0
)
for %%V in (4.4.1 4.4.2 4.4.0 4.3.3) do (
  if exist "C:\Program Files\R\R-%%V\bin\Rscript.exe" (
    set "MR_DERIVS_RSCRIPT=C:\Program Files\R\R-%%V\bin\Rscript.exe"
    exit /b 0
  )
)
echo Rscript nao encontrado. Instale R ou defina MR_DERIVS_RSCRIPT.
exit /b 1
