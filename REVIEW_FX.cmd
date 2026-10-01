@echo off
python "%~dp0tools\fx_review.py" %*
if errorlevel 1 pause
