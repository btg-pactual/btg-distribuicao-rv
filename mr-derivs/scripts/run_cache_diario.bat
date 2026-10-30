@echo off
REM Mr Derivs — atualiza cache COTAHIST (agendar no Agendador de Tarefas, 1x/dia apos 19h)
setlocal
cd /d "%~dp0.."

set RB3_CACHE=%MR_DERIVS_RB3_CACHE%
if "%RB3_CACHE%"=="" set RB3_CACHE=C:\Users\PIMENTPA\OneDrive - Banco BTG Pactual S.A\Documentos\rb3_cache

where Rscript >nul 2>&1
if errorlevel 1 (
  echo Rscript nao encontrado no PATH. Ajuste o caminho abaixo.
  exit /b 1
)

Rscript jobs\atualizar_cache_diario.R "%RB3_CACHE%"
exit /b %ERRORLEVEL%
