@echo off
setlocal

REM ============================================================
REM  OpenCode (containerized) launcher
REM
REM  The container gets its OWN data folder instead of sharing the
REM  Windows one. Reason: your native Windows OpenCode stores project
REM  paths as C:\... in its database (in %USERPROFILE%\.local\share\
REM  opencode). Mounting that into Linux makes OpenCode crash at boot
REM  with "Path is not absolute: C:/...". A separate data folder avoids
REM  that; we copy only auth.json across so you stay logged in.
REM
REM  Your global config is still mounted unchanged, and OpenCode
REM  launches directly (no shell, no extra typing).
REM ============================================================

for %%I in ("%CD%") do set "APP_NAME=%%~nxI"
for /f "delims=" %%I in ('powershell -NoProfile -Command "'%APP_NAME%'.ToLowerInvariant() -replace '[^a-z0-9_.-]','-'"') do set "APP_NAME=%%I"
set "DOCKER_DATA=%USERPROFILE%\.opencode-docker\%APP_NAME%\data"
set "WIN_DATA=%USERPROFILE%\.local\share\opencode"
set "WIN_CONFIG=%USERPROFILE%\.config\opencode"
REM Windows NuGet.Config may contain DPAPI-encrypted passwords that Linux
REM containers cannot decrypt. Use a separate user-level config for Docker;
REM create it with --store-password-in-clear-text only outside the repository.
set "NUGET_CONFIG=%USERPROFILE%\.opencode-docker\nuget"
set "SSH_DIR=%USERPROFILE%\.ssh"
set "IMAGE_NAME=my-opencode-dotnet"
set "WINDOWS_APP_PATH=%CD%"

if not exist "%DOCKER_DATA%" mkdir "%DOCKER_DATA%"
if not exist "%NUGET_CONFIG%" mkdir "%NUGET_CONFIG%"

REM ----- Copy your login once so you don't have to re-authenticate ----
if not exist "%DOCKER_DATA%\auth.json" (
    if exist "%WIN_DATA%\auth.json" (
        copy /Y "%WIN_DATA%\auth.json" "%DOCKER_DATA%\auth.json" >nul
    )
)

REM ----- Run container and launch OpenCode directly -----
docker run --rm -it ^
    --name "opencode-%APP_NAME%-%RANDOM%" ^
    -v "%CD%:/app" ^
    -v "%DOCKER_DATA%:/root/.local/share/opencode" ^
    -v "%WIN_CONFIG%:/root/.config/opencode" ^
    -v "%NUGET_CONFIG%:/root/.nuget/NuGet:ro" ^
    -v "%SSH_DIR%:/root/.ssh:ro" ^
    -w /app ^
    -e "TF_WINDOWS_SSH_HOST=host.docker.internal" ^
    -e "TF_WINDOWS_SSH_USER=%USERNAME%" ^
    -e "TF_WINDOWS_SSH_KEY=/root/.ssh/opencode-docker" ^
    -e "TF_WINDOWS_APP_PATH=%WINDOWS_APP_PATH%" ^
    -e "TF_OPENCODE_DOCKER=1" ^
    -e "NUGET_CONFIG_FILE=/root/.nuget/NuGet/NuGet.Config" ^
    "%IMAGE_NAME%" ^
    opencode

endlocal
