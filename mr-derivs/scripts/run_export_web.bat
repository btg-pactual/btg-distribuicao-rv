@echo off
REM Gera JSON para viz.html (GitHub Pages). Pode demorar (1x por ticker).
setlocal
cd /d "%~dp0.."

call "%~dp0_rscript_path.bat"
if errorlevel 1 exit /b 1

set RB3_CACHE=%MR_DERIVS_RB3_CACHE%
if "%RB3_CACHE%"=="" set RB3_CACHE=C:\Users\PIMENTPA\OneDrive - Banco BTG Pactual S.A\Documentos\rb3_cache
set MR_DERIVS_RB3_CACHE=%RB3_CACHE%

REM Opcional: so alguns tickers — set MR_DERIVS_WEB_TICKERS=BOVA11,PETR4
REM Janela exibida (dias): set MR_DERIVS_WEB_DIAS=180

echo Export web: cache=%MR_DERIVS_RB3_CACHE%
"%MR_DERIVS_RSCRIPT%" jobs\export_iv_web.R "%RB3_CACHE%" 365
exit /b %ERRORLEVEL%
