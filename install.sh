#!/bin/bash
# Improved installer: attempts a short, non-blocking SteamCMD login when username+password are provided
# but no STEAM_AUTH is available. This triggers Steam Guard (email/2FA) without hanging the container.
# If Steam Guard is required the script writes instructions and exits so the admin can provide STEAM_AUTH
# and re-run the installer.
#
# Notes:
# - Uses `timeout --foreground` to run a short login attempt that will be killed if it blocks for input.
# - If STEAM_AUTH is provided, performs a full non-interactive login and continues.
# - If anonymous install is used (STEAM_USER empty), attempts anonymous install (may fail for paid games).
#
set -eo pipefail

# Packages required by the script
apt -y update
apt -y --no-install-recommends --no-install-suggests install wget p7zip-full jq unzip ca-certificates coreutils
wget -q --https-only https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq
chmod +x /usr/bin/yq

# Helper to print and exit with a message
fail() {
  echo "[ERROR] $1" >&2
  exit "${2:-1}"
}

info() { echo "[INFO] $1"; }
warn() { echo "[WARN] $1"; }

# Default/normalize variables (avoid 'unbound variable' failures if set -u were used elsewhere)
STEAM_USER="${STEAM_USER:-}"
STEAM_PASS="${STEAM_PASS:-}"
STEAM_AUTH="${STEAM_AUTH:-}"
WINDOWS_INSTALL="${WINDOWS_INSTALL:-1}"
SRCDS_APPID="${SRCDS_APPID:-1366540}"
SRCDS_BETAID="${SRCDS_BETAID:-}"
SRCDS_BETAPASS="${SRCDS_BETAPASS:-}"
INSTALL_FLAGS="${INSTALL_FLAGS:-}"
V_PROFILECODE="${V_PROFILECODE:-}"
BEPINEX_UPDATE_OVERWRITE="${BEPINEX_UPDATE_OVERWRITE:-0}"

# Setup Steam credentials logic
if [[ -z "$STEAM_USER" ]] || [[ -z "$STEAM_PASS" ]]; then
  info "Steam user/password not provided. Attempting anonymous install."
  STEAM_USER="anonymous"
  STEAM_PASS=""
  STEAM_AUTH=""
else
  info "Steam user provided: ${STEAM_USER}"
fi

# Prepare steamcmd folder
cd /tmp
mkdir -p /mnt/server/steamcmd
if ! curl -sfSL -o steamcmd.tar.gz https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz; then
  fail "Failed to download SteamCMD."
fi
tar -xzvf steamcmd.tar.gz -C /mnt/server/steamcmd
mkdir -p /mnt/server/steamapps
cd /mnt/server/steamcmd
chown -R root:root /mnt || true
export HOME=/mnt/server

# Utility to run the final install (after successful login or anonymous allowed)
run_app_update() {
  info "Running SteamCMD app_update for AppID ${SRCDS_APPID} ..."
  # Build beta and betapassword args safely
  beta_arg=""
  betapass_arg=""
  if [[ -n "${SRCDS_BETAID}" ]]; then
    beta_arg="-beta ${SRCDS_BETAID}"
  fi
  if [[ -n "${SRCDS_BETAPASS}" ]]; then
    betapass_arg="-betapassword ${SRCDS_BETAPASS}"
  fi

  # Run install; use INSTALL_FLAGS if set (splitting intentionally left to shell to handle simple flags)
  if ! ./steamcmd.sh +force_install_dir /mnt/server +login "${STEAM_USER}" "${STEAM_PASS}" ${STEAM_AUTH:+${STEAM_AUTH}} $( [[ "${WINDOWS_INSTALL}" == "1" ]] && printf %s '+@sSteamCmdForcePlatformType windows' ) +app_update "${SRCDS_APPID}" ${beta_arg} ${betapass_arg} ${INSTALL_FLAGS} validate +quit; then
    fail "SteamCMD failed to install the game."
  fi
}

# LOGIN AND INSTALL DECISION LOGIC
if [[ "${STEAM_USER}" == "anonymous" ]]; then
  info "Performing anonymous SteamCMD install (may fail for paid games)."
  # Try anonymous install
  if ! ./steamcmd.sh +force_install_dir /mnt/server +login anonymous +app_update "${SRCDS_APPID}" validate +quit; then
    fail "SteamCMD anonymous install failed."
  fi
else
  # User provided. Two sub-cases:
  # 1) STEAM_AUTH provided => non-interactive login and proceed
  # 2) STEAM_AUTH NOT provided => attempt a short login to trigger Steam Guard, but do not block
  if [[ -n "${STEAM_AUTH}" ]]; then
    info "STEAM_AUTH provided: performing non-interactive login and install."
    run_app_update
  else
    info "Steam credentials provided but no STEAM_AUTH (2FA) code."
    info "Attempting a short non-blocking login attempt to trigger Steam Guard (email/authenticator)."
    # Attempt a short login. This may block if SteamCMD prompts for input; use timeout to avoid hanging.
    TMP_OUTPUT="/tmp/steamcmd_login_output.txt"
    # Use timeout --foreground to ensure child processes receive signals properly in container
    LOGIN_CMD=(timeout --foreground 30s ./steamcmd.sh +login "${STEAM_USER}" "${STEAM_PASS}" +quit)
    if "${LOGIN_CMD[@]}" > "$TMP_OUTPUT" 2>&1; then
      # This means login succeeded quickly (no 2FA). Proceed with install.
      info "Steam login succeeded without 2FA. Proceeding with install."
      run_app_update
    else
      rc=$?
      out=$(sed -n '1,200p' "$TMP_OUTPUT" || true)
      # Check for known Steam Guard indicators in output
      if [[ $rc -eq 124 ]] || echo "$out" | grep -Ei "Steam Guard|SteamGuard|two-factor|2fa|authenticator|code" >/dev/null; then
        warn "Steam Guard likely required (SteamCMD blocked/waiting for 2FA)."
        cat > /mnt/server/steamcmd_manual_instructions.txt <<'EOF'
Steam login requires Steam Guard (2FA). The installer attempted a short login to trigger the Steam Guard flow,
but did not provide a code to avoid hanging the container.

What you can do next:
1) Provide STEAM_AUTH (the current Steam Guard code from your authenticator) as a server variable and re-run the installer (reinstall).
   - This will perform a non-interactive login and continue installation automatically.

OR

2) Perform an interactive login manually (on a host or container where you can interact):
   - cd /mnt/server/steamcmd
   - ./steamcmd.sh
   - At the prompt: login <your_steam_username>
   - Enter your password and Steam Guard code when prompted.
   - Then run:
       force_install_dir /mnt/server
       app_update 1366540 validate
       quit

Notes:
- If Steam sends the code via email, check that account's email.
- Avoid leaving the installer to wait for input in a non-interactive environment (it will hang the container).
EOF
        info "Instructions written to /mnt/server/steamcmd_manual_instructions.txt"
        warn "Re-run the installer with STEAM_AUTH provided (preferred) or perform interactive login as described."
        rm -f "$TMP_OUTPUT"
        exit 2
      else
        # Some other error occurred (bad credentials, network, etc.)
        echo "$out"
        rm -f "$TMP_OUTPUT"
        fail "SteamCMD login failed for an unexpected reason (check output above)."
      fi
    fi
  fi
fi

# If we reach here, install succeeded and we continue with remaining steps.

# Setup Steam libraries (best-effort)
mkdir -p /mnt/server/.steam/sdk32
cp -v linux32/steamclient.so ../.steam/sdk32/steamclient.so || true
mkdir -p /mnt/server/.steam/sdk64
cp -v linux64/steamclient.so ../.steam/sdk64/steamclient.so || true

# Install & Setup Goldberg Steam Emu
info "Downloading Goldberg steam_api64.dll ..."
if ! curl -sfSL -o "$HOME/DSPGAME_Data/Plugins/steam_api64.dll" "https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/jobs/4247811310/artifacts/raw/steam_api64.dll"; then
  fail "Failed to download Goldberg steam_api64.dll."
fi
mkdir -p /mnt/server/DSPGAME_Data/Plugins/steam_settings
touch /mnt/server/DSPGAME_Data/Plugins/steam_settings/disable_networking.txt
echo "1366540" > /mnt/server/DSPGAME_Data/Plugins/steam_appid.txt

# Download and install BepInEx
cd /mnt/server
info "Downloading BepInEx release info ..."
if ! api_response=$(curl -sfSL -H "accept: application/json" "https://thunderstore.io/api/experimental/package/xiaoye97/BepInEx/"); then
    fail "Could not retrieve BepInEx release info from Thunderstore.io API"
fi
download_url=$(echo "$api_response" | jq -r ".latest.download_url")
version_number=$(echo "$api_response" | jq -r ".latest.version_number")
if ! wget --https-only --content-disposition "$download_url"; then
  fail "Failed to download BepInEx package."
fi
if ! unzip -qo xiaoye97-BepInEx-${version_number}.zip; then
  fail "Failed to unzip BepInEx package."
fi
cp -r /mnt/server/BepInExPack/* /mnt/server || true

# Modpack/Profile Installation (unchanged logic, but robust quoting)
if [ ! -z "$V_PROFILECODE" ]; then
  function fix_filenames {
    local BAD_FILES
    BAD_FILES=$(find "$1" -regex '.*\\.*' 2>/dev/null || true)
    while IFS= read -r SRC; do
      if [[ $SRC ]]; then
        local DST
        DST=$(echo "$SRC" | sed 's/\\/\//g')
        mkdir -p "$(dirname "$DST")"
        mv "$SRC" "$DST"
      fi
    done <<< "$BAD_FILES"
  }

  function thunderstore_get_profile {
    local PROFILE_CODE=$1
    local OUT_DIR=$2
    if [[ -d "$OUT_DIR" ]]; then
      rm -r "$OUT_DIR"
    fi
    info "Downloading profile $PROFILE_CODE"
    if ! wget -qO mods.base64 --https-only "https://thunderstore.io/api/experimental/legacyprofile/get/$PROFILE_CODE/"; then
      fail "Failed to download Thunderstore profile."
    fi
    tail -n +2 mods.base64 | base64 --decode > mods.zip
    rm mods.base64

    info "Extracting profile archive"
    if ! 7z x -y mods.zip -o"$OUT_DIR" > /dev/null; then
      fail "Failed to extract Thunderstore profile archive with 7z."
    fi

    rm mods.zip
  }

  function thunderstore_download {
    local OUT_DIR=$1
    local PACKAGE=$2
    local VERSION=$3
    local PACKAGE_ALT
    PACKAGE_ALT=$(echo "$PACKAGE" | sed -r 's/\//-/g')
    info "Downloading mod $PACKAGE @ $VERSION ($PACKAGE_ALT)"
    if ! wget -qO tmp.zip --https-only "https://thunderstore.io/package/download/$PACKAGE/$VERSION/"; then
      fail "Failed to download mod $PACKAGE."
    fi
    mkdir tmp
    7z x tmp.zip -o"tmp" -y > /dev/null
    rm tmp.zip
    fix_filenames ./tmp
    if [[ $(find ./tmp/* -maxdepth 0 -type d 2>/dev/null | wc -l) == 1 ]]; then
      local DIR
      DIR=$(find ./tmp/* -maxdepth 0 -type d)
      while [[ $(find "$DIR"/* -maxdepth 0 2>/dev/null | wc -l) == 1 ]]; do
        DIR=$(find ./tmp/* -maxdepth 0 -type d)
        mv "$DIR"/* "$(dirname "$DIR")"
        rm -r "$DIR"
      done
    fi
    mkdir -p "$OUT_DIR/$PACKAGE_ALT"
    mv ./tmp/* "$OUT_DIR/$PACKAGE_ALT"
    rm -r ./tmp
  }

  function get_profile_mods {
    local YAML_PATH=$1
    yq '[.mods[] | select(.enabled == true) | ((.name | sub("-", "/")) + " " + .version.major + "." + .version.minor + "." + .version.patch)][]' "$YAML_PATH"
  }

  function update_from_profile_code {
    local PROFILE_CODE=$1
    local BEPINEX_DIR=$2
    thunderstore_get_profile "$PROFILE_CODE" ./tmp_mods
    while IFS= read -r args; do
      if [[ $args != *"BepInExPack_"* ]]; then
        thunderstore_download ./tmp_mods/BepInEx/plugins/ $args
      fi
    done <<< "$(get_profile_mods ./tmp_mods/export.r2x)"
    info "Preparing mod files"
    fix_filenames ./tmp_mods
    cp -rf ./tmp_mods/BepInEx/* ./tmp_mods || true
    rm -r ./tmp_mods/BepInEx || true
    rm -rf "$BEPINEX_DIR/plugins/"*
    mkdir -p "$BEPINEX_DIR"
    if [[ "${BEPINEX_UPDATE_OVERWRITE:-0}" == "1" ]]; then
      info "Overwriting all mod files."
      cp -rf ./tmp_mods/* "$BEPINEX_DIR"
    else
      info "Updating mods (not overwriting configs, ensure no changes are required)"
      cp -rfn ./tmp_mods/* "$BEPINEX_DIR"
    fi
    rm -r ./tmp_mods
    info "Mods updated."
  }

  update_from_profile_code "$V_PROFILECODE" /mnt/server/BepInEx
fi

# Clean-up
rm -rf BepInExPack icon.png xiaoye97-BepInEx-* manifest.json README.m || true

info "-----------------------------------------"
info "Installation completed."
info "-----------------------------------------"