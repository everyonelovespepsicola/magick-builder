@echo off
setlocal

echo Setting up AI Project Memory...

:: Create the Permanent Rules file
if not exist .github mkdir .github
(
echo # AI Coding Instructions
echo - Use Python 3.10+ and focus on clean, modular code.
echo - Project uses VS Code and Termux environments.
echo - Prioritize efficiency for PDF processing and ADB tasks.
) > .github\copilot-instructions.md

:: Create the Dynamic State file
(
echo # Project State: %cd%
echo ## Last Session: %DATE%
echo - **Status:** Initialized project memory.
echo - **Current Task:** Ready for instructions.
echo - **Blockers:** None reported.
echo - **Next Steps:** echo   1. Define project core requirements.
) > AGENTS.md

:: Create a .gitignore to keep it clean (optional)
if not exist .gitignore (
echo # AI Metadata > .gitignore
)

echo.
echo [SUCCESS] .github/copilot-instructions.md created.
echo [SUCCESS] AGENTS.md created.
echo.
echo Drop me a line in VS Code and tell me to "Read #AGENTS.md" to begin.
pause