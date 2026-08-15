# OpenCode runs in Linux, but the .NET workload resolver and MAUI tooling are
# materially more reliable on the Debian-based SDK image than on Alpine/musl.
FROM mcr.microsoft.com/dotnet/sdk:9.0

# 1. Install dependencies needed by OpenCode, Playwright, and the bridge.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    bash curl git openssh-client ca-certificates nodejs npm \
    libicu-dev libssl-dev zlib1g && \
    rm -rf /var/lib/apt/lists/*

# 2. Install OpenCode manually
# We download the binary directly instead of pulling the Docker image
ARG OPENCODE_BUILD_TS
RUN curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path

# Add OpenCode to PATH
ENV PATH="/root/.opencode/bin:$PATH"

# 3. Install Linux-compatible MAUI workloads. Windows/iOS/Mac Catalyst still
# require their native host; the containerized winrun bridge handles Windows.
RUN dotnet workload install maui-android maui-tizen

# 4. Install Playwright MCP Server
RUN npm install -g @playwright/mcp

# 5. Environment Variables for Stability
ENV DOTNET_NOLOGO=1
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
# The container is Linux; do not pretend cmd.exe is available inside it.
# Set TF_WINDOWS_SSH_HOST and TF_WINDOWS_APP_PATH when Windows-head builds are
# required. The bridge uses the host's OpenSSH server and key authentication.
ENV TF_WINDOWS_SSH_HOST=host.docker.internal
ENV TF_WINDOWS_SSH_USER=
ENV TF_WINDOWS_SSH_KEY=/root/.ssh/opencode-docker
ENV TF_WINDOWS_APP_PATH=

RUN install -d /usr/local/bin && printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    ': "${TF_WINDOWS_APP_PATH:?Set TF_WINDOWS_APP_PATH to the Windows app path}"' \
    ': "${TF_WINDOWS_SSH_HOST:=host.docker.internal}"' \
    ': "${TF_WINDOWS_SSH_USER:?Set TF_WINDOWS_SSH_USER to the Windows SSH account}"' \
    ': "${TF_WINDOWS_SSH_KEY:=/root/.ssh/opencode-docker}"' \
    'command=${*:-}' \
    '[[ -n "$command" ]] || { echo "usage: winrun \"powershell command\"" >&2; exit 2; }' \
    'printf -v remote "Set-Location -LiteralPath '\''%s'\''; %s" "$TF_WINDOWS_APP_PATH" "$command"' \
    'exec ssh -i "$TF_WINDOWS_SSH_KEY" -o BatchMode=yes "$TF_WINDOWS_SSH_USER@$TF_WINDOWS_SSH_HOST" powershell.exe -NoProfile -NonInteractive -Command "$remote"' \
    > /usr/local/bin/winrun && chmod +x /usr/local/bin/winrun

# 6. Default Entrypoint
CMD ["/bin/bash"]
