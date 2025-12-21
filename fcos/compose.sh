#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUTANE_DIR="${SCRIPT_DIR}/butane"
OUTPUT_FILE="${SCRIPT_DIR}/homelab.bu"

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() {
  echo -e "${GREEN}==>${NC} $1"
}

warn() {
  echo -e "${YELLOW}WARNING:${NC} $1"
}

error() {
  echo -e "${RED}ERROR:${NC} $1" >&2
  exit 1
}

# Check for yq
if ! command -v yq &> /dev/null; then
  error "yq is not installed. Please install it from https://github.com/mikefarah/yq"
fi

log "Starting butane file composition"

# Define the order of files to merge
FILES=(
  "${BUTANE_DIR}/base.bu"
  "${BUTANE_DIR}/network.bu"
  "${BUTANE_DIR}/users.bu"
  "${BUTANE_DIR}/storage.bu"
  "${BUTANE_DIR}/tailscale.bu"
  "${BUTANE_DIR}/containers/jellyfin.bu"
  "${BUTANE_DIR}/containers/adguardhome.bu"
  "${BUTANE_DIR}/containers/homepage.bu"
  "${BUTANE_DIR}/misc.bu"
)

# Verify all files exist
for file in "${FILES[@]}"; do
  if [[ ! -f "$file" ]]; then
    error "Required file not found: $file"
  fi
done

log "Merging butane files..."

# Start with the base file
cp "${FILES[0]}" "${OUTPUT_FILE}"

# Merge each subsequent file
for ((i=1; i<${#FILES[@]}; i++)); do
  file="${FILES[$i]}"
  log "  Merging $(basename "$file")..."

  # Use yq to merge YAML files with deep merge strategy
  yq eval-all '. as $item ireduce ({}; . *+ $item)' "${OUTPUT_FILE}" "$file" > "${OUTPUT_FILE}.tmp"
  mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
done

log "Composition complete!"
log "Output file: ${OUTPUT_FILE}"

# Display some stats
file_count=${#FILES[@]}
line_count=$(wc -l < "${OUTPUT_FILE}")
log "Merged ${file_count} files into ${line_count} lines"

echo
log "Next steps:"
echo "  1. Review the composed file: cat ${OUTPUT_FILE}"
echo "  2. Run the installation script from the parent directory"
