# OpenCode runs in Linux, but the .NET workload resolver and MAUI tooling are
# materially more reliable on the Debian-based SDK image than on Alpine/musl.
# Keep this aligned with the current app targets. A .NET 9 SDK cannot build a
# net10.0 solution (NETSDK1045).
FROM mcr.microsoft.com/dotnet/sdk:10.0

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

# 3. Install Playwright MCP Server. MAUI workloads are deliberately absent:
# Windows MAUI Blazor Desktop builds run on the Windows host through winrun;
# mobile/iOS/Mac Catalyst builds and runtime tests run natively on a Mac.
RUN npm install -g @playwright/mcp

# 4. Environment Variables for Stability
ENV DOTNET_NOLOGO=1
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV TF_OPENCODE_DOCKER=1
# The container is Linux; do not pretend cmd.exe is available inside it.
# Set TF_WINDOWS_SSH_HOST and TF_WINDOWS_APP_PATH when Windows-head builds are
# required. The bridge uses the host's OpenSSH server and key authentication.
ENV TF_WINDOWS_SSH_HOST=host.docker.internal
ENV TF_WINDOWS_SSH_USER=
ENV TF_WINDOWS_APP_PATH=

RUN install -d /usr/local/bin && printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    ': "${TF_WINDOWS_APP_PATH:?Set TF_WINDOWS_APP_PATH to the Windows app path}"' \
    ': "${TF_WINDOWS_SSH_HOST:=host.docker.internal}"' \
    ': "${TF_WINDOWS_SSH_USER:?Set TF_WINDOWS_SSH_USER to the Windows SSH account}"' \
    ': "${TF_WINDOWS_SSH_KEY:=/root/.ssh/opencode-docker}"' \
    'runtime_dir=/tmp/opencode-docker' \
    'runtime_key="$runtime_dir/opencode-docker"' \
    'known_hosts="$runtime_dir/known_hosts"' \
    'install -d -m 700 "$runtime_dir"' \
    'cp "$TF_WINDOWS_SSH_KEY" "$runtime_key"' \
    'chmod 600 "$runtime_key"' \
    'if [[ ! -s "$known_hosts" ]]; then ssh-keyscan -H "$TF_WINDOWS_SSH_HOST" > "$known_hosts" 2>/dev/null; chmod 600 "$known_hosts"; fi' \
    '[[ -s "$known_hosts" ]] || { echo "winrun: could not establish SSH host key for $TF_WINDOWS_SSH_HOST" >&2; exit 1; }' \
    'command=${*:-}' \
    '[[ -n "$command" ]] || { echo "usage: winrun \"powershell command\"" >&2; exit 2; }' \
    'printf -v remote "Set-Location -LiteralPath '\''%s'\''; %s" "$TF_WINDOWS_APP_PATH" "$command"' \
    'exec ssh -i "$runtime_key" -o BatchMode=yes -o UserKnownHostsFile="$known_hosts" "$TF_WINDOWS_SSH_USER@$TF_WINDOWS_SSH_HOST" powershell.exe -NoProfile -NonInteractive -Command "$remote"' \
    > /usr/local/bin/winrun && chmod +x /usr/local/bin/winrun

# 5. Default Entrypoint
CMD ["/bin/bash"]
