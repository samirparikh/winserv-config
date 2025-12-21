#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUTANE_FILE="${SCRIPT_DIR}/fcos/homelab.bu"
IGNITION_FILE="${SCRIPT_DIR}/fcos/homelab.ign"
TARGET_DISK="/dev/nvme0n1"
KEY_URL="http://192.168.1.227:8000"
KEY_FILE="tailscale_keyfile"

# Helpers
log() {
  echo
  echo "==> $1"
}

error() {
  echo "ERROR: $1" >&2
  exit 1
}

confirm() {
  local prompt="$1"
  while true; do
    read -r -p "$prompt [y/N]: " answer
    case "$answer" in
      [yY]|[yY][eE][sS]) return 0 ;;
      [nN]|[nN][oO]|"") return 1 ;;
      *) echo "Please answer yes or no." ;;
    esac
  done
}

########################################
# Pre-flight checks
########################################

log "Running pre-flight checks"

# 1. Verify build script exists
log "Checking build script exists"
if [[ -f "${SCRIPT_DIR}/fcos/build.sh" ]]; then
  BUILD_SCRIPT="${SCRIPT_DIR}/fcos/build.sh"
else
  error "Build script not found: ${SCRIPT_DIR}/fcos/build.sh"
fi

# 2. Verify target disk exists
log "Checking target disk exists: ${TARGET_DISK}"
[[ -b "$TARGET_DISK" ]] || error "Target disk does not exist: ${TARGET_DISK}"

# 3. Verify HTTP server is reachable
log "Checking HTTP server reachability: ${KEY_URL}"
if ! curl -fsI "$KEY_URL" >/dev/null; then
  error "Cannot reach HTTP server at ${KEY_URL}"
fi

########################################
# Execution steps
########################################

# Step 0: Build butane file from modules
log "Building butane file from modular sources"
"${BUILD_SCRIPT}"

# Step 1: Download Tailscale auth key file
log "Downloading Tailscale auth key file"
curl -v -O "${KEY_URL}/${KEY_FILE}"

# Step 2: Export Tailscale auth key
log "Exporting Tailscale auth key"
export TAILSCALE_AUTHKEY
TAILSCALE_AUTHKEY="$(cat "${KEY_FILE}")"

# Step 3: Render Butane configuration
log "Rendering Butane configuration with Tailscale key"
sed "s/__TAILSCALE_AUTHKEY__/${TAILSCALE_AUTHKEY}/" \
  "$BUTANE_FILE" > /tmp/homelab.bu

# Step 4: Pull Butane container image
log "Pulling Butane container image"
podman pull quay.io/coreos/butane:release

# Step 5: Generate Ignition file
log "Generating Ignition file"
podman run --rm -i quay.io/coreos/butane:release --strict \
  < /tmp/homelab.bu > "${IGNITION_FILE}"

# Step 6: Confirm before installing Fedora CoreOS
if confirm "About to INSTALL Fedora CoreOS to ${TARGET_DISK}. THIS WILL ERASE THE DISK. Continue?"; then
  log "Wiping existing partition table"
  sudo wipefs --all "${TARGET_DISK}"

  log "Running coreos-installer"
  sudo coreos-installer install "${TARGET_DISK}" --ignition-file "${IGNITION_FILE}"
else
  log "Installation aborted by user"
  exit 1
fi

# Step 7: Cleanup
log "Cleaning up temporary files"
rm -f /tmp/homelab.bu

# Step 8: Confirm before reboot
if confirm "Installation complete. Reboot now?"; then
  log "Rebooting system"
  sudo reboot
else
  log "Reboot skipped. You must reboot manually."
fi
