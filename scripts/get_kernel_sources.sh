#!/bin/bash
set -e  # Exit on error

# Define log directory and file
LOG_DIR="$(dirname "$0")/logs"
LOG_FILE="$LOG_DIR/get_kernel_sources.log"

# Define kernel source directory (for native Jetson builds)
KERNEL_SRC_DIR="/usr/src/"

# Ensure the logs directory exists
mkdir -p "$LOG_DIR"

# Default behavior (interactive mode)
FORCE_REPLACE=0
FORCE_BACKUP=0

# Check if user has sudo privileges
if [[ $EUID -ne 0 ]]; then
  if ! sudo -v; then
    echo "[ERROR] This script requires sudo privileges. Please run with sudo access."
    exit 1
  fi
fi

# Parse command-line options
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --force-replace) FORCE_REPLACE=1 ;;
    --force-backup) FORCE_BACKUP=1 ;;
    *) echo "[ERROR] Invalid option: $1" && exit 1 ;;
  esac
  shift
done

# Logging function
log() {
  echo "[INFO] $(date +"%Y-%m-%d %H:%M:%S") - ${1}" | tee -a "$LOG_FILE"
}

# Extract L4T version details using sed
L4T_MAJOR=$(sed -n 's/^.*R\([0-9]\+\).*/\1/p' /etc/nv_tegra_release)
L4T_MINOR=$(sed -n 's/^.*REVISION: \([0-9]\+\(\.[0-9]\+\)*\).*/\1/p' /etc/nv_tegra_release)

# Construct the kernel source URL and checksum URL
SOURCE_BASE="https://developer.nvidia.com/embedded/l4t/r${L4T_MAJOR}_release_v${L4T_MINOR}/sources"
SOURCE_FILE="public_sources.tbz2"
CHECKSUM_FILE="${SOURCE_FILE}.sha1sum"

log "Detected L4T version: ${L4T_MAJOR} (${L4T_MINOR})"
log "Kernel sources directory: $KERNEL_SRC_DIR"

# Check if kernel sources already exist
if [[ -d "$KERNEL_SRC_DIR/kernel" ]]; then
  if [[ "$FORCE_REPLACE" -eq 1 ]]; then
    log "Forcing deletion of existing kernel sources..."
    sudo rm -rf "$KERNEL_SRC_DIR/kernel"

  elif [[ "$FORCE_BACKUP" -eq 1 ]]; then
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_DIR="${KERNEL_SRC_DIR}kernel_backup_${TIMESTAMP}"
    log "Forcing backup of existing kernel sources to $BACKUP_DIR..."
    sudo mv "$KERNEL_SRC_DIR/kernel" "$BACKUP_DIR"

  else
    echo "Kernel sources already exist at $KERNEL_SRC_DIR/kernel."
    echo "What would you like to do?"
    echo "[K]eep existing sources (default)"
    echo "[R]eplace (delete and re-download)"
    echo "[B]ackup and download fresh sources"

    read -rp "Enter your choice (K/R/B): " USER_CHOICE

    case "$USER_CHOICE" in
      [Rr]* ) 
        log "Deleting existing kernel sources..."
        sudo rm -rf "$KERNEL_SRC_DIR/kernel"
        ;;
      [Bb]* ) 
        TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
        BACKUP_DIR="${KERNEL_SRC_DIR}kernel_backup_${TIMESTAMP}"
        log "Backing up existing kernel sources to $BACKUP_DIR..."
        sudo mv "$KERNEL_SRC_DIR/kernel" "$BACKUP_DIR"
        ;;
      * ) 
        log "Keeping existing kernel sources. Skipping download."
        exit 0
        ;;
    esac
  fi
fi

log "Downloading kernel sources from: $SOURCE_BASE/$SOURCE_FILE"
wget -N "$SOURCE_BASE/$SOURCE_FILE"

log "Downloading checksum file from: $SOURCE_BASE/$CHECKSUM_FILE"
wget -N "$SOURCE_BASE/$CHECKSUM_FILE"

# Extract expected checksum from the downloaded sha1sum file
EXPECTED_HASH=$(awk '{print $1}' "$CHECKSUM_FILE")

# Compute SHA1 hash of the downloaded file
COMPUTED_HASH=$(sha1sum "$SOURCE_FILE" | awk '{print $1}')

log "Expected SHA1: $EXPECTED_HASH"
log "Computed SHA1: $COMPUTED_HASH"

# Compare checksums
if [[ "$COMPUTED_HASH" != "$EXPECTED_HASH" ]]; then
  log "[ERROR] SHA1 checksum mismatch! Downloaded file is corrupt."
  exit 1
else
  log "Checksum verification successful."
fi

log "Extracting sources..."

# Extract kernel source and related components
sudo tar -xvf "$SOURCE_FILE" Linux_for_Tegra/source/public/kernel_src.tbz2 \
                           Linux_for_Tegra/source/public/kernel_oot_modules_src.tbz2 \
                           Linux_for_Tegra/source/public/nvidia_kernel_display_driver_source.tbz2 --strip-components=3

# Extract each component separately into /usr/src/
log "Extracting kernel source..."
sudo tar -xvf kernel_src.tbz2 -C "$KERNEL_SRC_DIR"
log "Extracting NVIDIA out-of-tree kernel modules..."
sudo tar -xvf kernel_oot_modules_src.tbz2 -C "$KERNEL_SRC_DIR"
log "Extracting NVIDIA display driver source..."
sudo tar -xvf nvidia_kernel_display_driver_source.tbz2 -C "$KERNEL_SRC_DIR"

# Cleanup tarballs
rm kernel_src.tbz2 kernel_oot_modules_src.tbz2 nvidia_kernel_display_driver_source.tbz2 "$SOURCE_FILE" "$CHECKSUM_FILE"

log "Kernel sources and modules extracted to $KERNEL_SRC_DIR"

# Copy the current kernel config (requires sudo)
log "Copying current kernel config..."
sudo zcat /proc/config.gz > "$KERNEL_SRC_DIR/kernel/.config"

log "Kernel source setup complete!"
