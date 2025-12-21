#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUTANE_DIR="${SCRIPT_DIR}/butane"
OUTPUT_FILE="${SCRIPT_DIR}/homelab.bu"

# Colors
GREEN='\033[0;32m'
NC='\033[0m'

log() {
  echo -e "${GREEN}==>${NC} $1"
}

log "Building homelab.bu from modular butane files"

# Create a temporary directory for processing
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

# Extract sections from each file
extract_section() {
  local file="$1"
  local section="$2"
  local output="$3"

  if grep -q "^${section}:" "$file" 2>/dev/null; then
    # Use awk to extract the section
    awk -v section="$section" '
      BEGIN { in_section=0 }
      $0 ~ "^" section ":" { in_section=1; next }
      in_section && /^[a-z_]+:/ { exit }
      in_section { print }
    ' "$file" >> "$output"
  fi
}

# Initialize section files
: > "${TEMP_DIR}/passwd.yaml"
: > "${TEMP_DIR}/storage_dirs.yaml"
: > "${TEMP_DIR}/storage_files.yaml"
: > "${TEMP_DIR}/storage_links.yaml"
: > "${TEMP_DIR}/systemd.yaml"

log "Extracting sections from butane files..."

# Process each file
for file in \
  "${BUTANE_DIR}/network.bu" \
  "${BUTANE_DIR}/users.bu" \
  "${BUTANE_DIR}/storage.bu" \
  "${BUTANE_DIR}/tailscale.bu" \
  "${BUTANE_DIR}/containers/jellyfin.bu" \
  "${BUTANE_DIR}/containers/adguardhome.bu" \
  "${BUTANE_DIR}/containers/homepage.bu" \
  "${BUTANE_DIR}/misc.bu"
do
  if [[ -f "$file" ]]; then
    log "  Processing $(basename "$file")..."
    extract_section "$file" "passwd" "${TEMP_DIR}/passwd.yaml"

    # For storage, we need to extract subdirectories, files, and links separately
    if grep -q "^storage:" "$file" 2>/dev/null; then
      # Extract directories
      awk '
        /^  directories:/ { in_section=1; next }
        in_section && /^  [a-z_]+:/ { in_section=0 }
        in_section && /^[a-z_]+:/ { exit }
        in_section { print }
      ' "$file" >> "${TEMP_DIR}/storage_dirs.yaml"

      # Extract files
      awk '
        /^  files:/ { in_section=1; next }
        in_section && /^  [a-z_]+:/ { in_section=0 }
        in_section && /^[a-z_]+:/ { exit }
        in_section { print }
      ' "$file" >> "${TEMP_DIR}/storage_files.yaml"

      # Extract links
      awk '
        /^  links:/ { in_section=1; next }
        in_section && /^  [a-z_]+:/ { in_section=0 }
        in_section && /^[a-z_]+:/ { exit }
        in_section { print }
      ' "$file" >> "${TEMP_DIR}/storage_links.yaml"
    fi

    extract_section "$file" "systemd" "${TEMP_DIR}/systemd.yaml"
  fi
done

log "Assembling final butane file..."

# Build the final file
{
  # Base (variant and version)
  cat "${BUTANE_DIR}/base.bu"

  # Passwd section
  if [[ -s "${TEMP_DIR}/passwd.yaml" ]]; then
    echo "passwd:"
    cat "${TEMP_DIR}/passwd.yaml"
  fi

  # Storage section
  echo "storage:"

  if [[ -s "${TEMP_DIR}/storage_dirs.yaml" ]]; then
    echo "  directories:"
    cat "${TEMP_DIR}/storage_dirs.yaml"
  fi

  if [[ -s "${TEMP_DIR}/storage_files.yaml" ]]; then
    echo "  files:"
    cat "${TEMP_DIR}/storage_files.yaml"
  fi

  if [[ -s "${TEMP_DIR}/storage_links.yaml" ]]; then
    echo "  links:"
    cat "${TEMP_DIR}/storage_links.yaml"
  fi

  # Systemd section
  if [[ -s "${TEMP_DIR}/systemd.yaml" ]]; then
    echo "systemd:"
    echo "  units:"
    # Remove any duplicate "units:" lines from the extracted content
    grep -v "^  units:" "${TEMP_DIR}/systemd.yaml"
  fi

} > "${OUTPUT_FILE}"

log "Build complete!"
log "Output: ${OUTPUT_FILE}"

# Show stats
line_count=$(wc -l < "${OUTPUT_FILE}")
log "Generated ${line_count} lines"

echo
log "Next steps:"
echo "  1. Review: cat ${OUTPUT_FILE}"
echo "  2. Run install.sh from parent directory"
