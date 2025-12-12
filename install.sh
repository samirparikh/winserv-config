#!/usr/bin/env bash

set -euo pipefail

BUTANE_FILE="winserv.bu"
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

# 1. Verify Butane file exists
log "Checking Butane file exists: ${BUTANE_FILE}"
[[ -f "$BUTANE_FILE" ]] || error "Butane file not found: ${BUTANE_FILE}"

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

# Step 1: Download Tailscale auth key file
log "Downloading Tailscale auth key file"
curl -v -O "${KEY_URL}/${KEY_FILE}"

# Step 2: Export Tailscale auth key
log "Exporting Tailscale auth key"
export TAILSCALE_AUTHKEY
TAILSCALE_AUTHKEY="$(cat "${KEY_FILE}")"

# Step 3: Render Butane configuration
log "Rendering Butane configuration"
sed "s/__TAILSCALE_AUTHKEY__/${TAILSCALE_AUTHKEY}/" \
  "$BUTANE_FILE" > /tmp/winserv.bu

# Step 4: Pull Butane container image
log "Pulling Butane container image"
podman pull quay.io/coreos/butane:release

# Step 5: Generate Ignition file
log "Generating Ignition file"
podman run --rm -i quay.io/coreos/butane:release --strict \
  < /tmp/winserv.bu > /tmp/winserv.ign

# Step 6: Confirm before installing Fedora CoreOS
if confirm "About to INSTALL Fedora CoreOS to ${TARGET_DISK}. THIS WILL ERASE THE DISK. Continue?"; then
  log "Running coreos-installer"
  sudo coreos-installer install "${TARGET_DISK}" --ignition-file /tmp/winserv.ign
else
  log "Installation aborted by user"
  exit 1
fi

# Step 7: Cleanup
log "Cleaning up temporary files"
rm -f /tmp/winserv.ign

# Step 8: Confirm before reboot
if confirm "Installation complete. Reboot now?"; then
  log "Rebooting system"
  sudo reboot
else
  log "Reboot skipped. You must reboot manually."
fi
