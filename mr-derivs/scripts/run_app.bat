@echo off
REM Mr Derivs — Shiny (Vol implicita)
setlocal
cd /d "%~dp0.."

call "%~dp0_rscript_path.bat"
if errorlevel 1 exit /b 1

set RB3_CACHE=%MR_DERIVS_RB3_CACHE%
if "%RB3_CACHE%"=="" set RB3_CACHE=C:\Users\PIMENTPA\OneDrive - Banco BTG Pactual S.A\Documentos\rb3_cache
set MR_DERIVS_RB3_CACHE=%RB3_CACHE%

echo Cache COTAHIST: %MR_DERIVS_RB3_CACHE%
echo Abrindo Shiny em http://127.0.0.1:3838 ...
"%MR_DERIVS_RSCRIPT%" -e "options(vol_implicita.limpar_sessao=FALSE, vol_implicita.autorun=FALSE); shiny::runApp('app_vol_implicita.R', launch.browser=TRUE)"
exit /b %ERRORLEVEL%
