@echo off
REM Seed inicial — 24 meses de COTAHIST (pode demorar; rode uma vez)
setlocal
cd /d "%~dp0.."

set RB3_CACHE=%MR_DERIVS_RB3_CACHE%
if "%RB3_CACHE%"=="" set RB3_CACHE=C:\Users\PIMENTPA\OneDrive - Banco BTG Pactual S.A\Documentos\rb3_cache

where Rscript >nul 2>&1
if errorlevel 1 (
  echo Rscript nao encontrado no PATH.
  exit /b 1
)

Rscript jobs\seed_cache_24m.R "%RB3_CACHE%" 24
exit /b %ERRORLEVEL%
