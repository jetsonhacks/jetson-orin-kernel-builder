#!/bin/bash
# Kernel Source Retrieval and Setup Script for NVIDIA Jetson Developer Kit
# This script downloads, extracts, and configures the kernel source for Jetson Linux 36.X on 
# Ubuntu 22.04 Jammy. It ensures required dependencies are installed, provides options for 
# backing up or replacing existing sources, and sets up the kernel source for compilation.
# Logs the entire process for reference.
#
# Usage:
#   ./get_kernel_sources.sh [--force-replace] [--force-backup]
#
# Options:
#   --force-replace  Delete existing kernel sources and download fresh sources.
#   --force-backup   Backup existing kernel sources before downloading new ones.
#
# Example:
#   ./get_kernel_sources.sh             # Interactive mode: prompts user if sources exist
#   ./get_kernel_sources.sh --force-replace # Force delete and redownload kernel sources
#   ./get_kernel_sources.sh --force-backup  # Backup existing sources and download new ones
#
# Logs are saved in a 'logs' directory within the script's execution path.
#
# Copyright (c) 2016-25 JetsonHacks
# MIT License

set -e  # Exit on error
# Set the log directory to ./logs relative to the current working directory
LOG_DIR="$PWD/logs"
# Generate a timestamp for the log file name
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
# Set the log file path with the timestamp
LOG_FILE="$LOG_DIR/get_kernel_sources_$TIMESTAMP.log"
# Ensure the logs directory exists
mkdir -p "$LOG_DIR"

# Define kernel source directory (for native Jetson builds)
KERNEL_SRC_DIR="/usr/src/"

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
L4T_MINOR_FULL=$(sed -n 's/^.*REVISION: \([0-9]\+\(\.[0-9]\+\)*\).*/\1/p' /etc/nv_tegra_release)

# Extract just the first digit of minor version for URL (e.g., 4.4.4 -> 4)
# NVIDIA's download URLs use r36_release_v4.0 not r36_release_v4.4.4
L4T_MINOR=$(echo "$L4T_MINOR_FULL" | cut -d'.' -f1)

# Construct download URL - NOTE: NVIDIA uses /downloads/ in the path
SOURCE_BASE="https://developer.nvidia.com/downloads/embedded/l4t/r${L4T_MAJOR}_release_v${L4T_MINOR}.0/sources"
SOURCE_FILE="public_sources.tbz2"

log "Detected L4T version: R${L4T_MAJOR}.${L4T_MINOR_FULL}"
log "Download URL base: $SOURCE_BASE"
log "Kernel sources directory: $KERNEL_SRC_DIR"

# Check if kernel sources already exist
if [[ -d "$KERNEL_SRC_DIR/kernel" ]]; then
  if [[ "$FORCE_REPLACE" -eq 1 ]]; then
    log "Forcing deletion of existing kernel sources..."
    sudo rm -rf "$KERNEL_SRC_DIR/kernel"
  elif [[ "$FORCE_BACKUP" -eq 1 ]]; then
    BACKUP_TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_DIR="${KERNEL_SRC_DIR}kernel_backup_${BACKUP_TIMESTAMP}"
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
        BACKUP_TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
        BACKUP_DIR="${KERNEL_SRC_DIR}kernel_backup_${BACKUP_TIMESTAMP}"
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

# Check if file already exists (from manual download)
if [[ -f "$SOURCE_FILE" ]]; then
  log "Found existing $SOURCE_FILE, skipping download"
  log "Using existing file. Delete it first if you want to re-download."
else
  # Attempt download with error handling
  if ! wget -N "$SOURCE_BASE/$SOURCE_FILE"; then
  echo "[ERROR] Failed to download kernel sources from $SOURCE_BASE/$SOURCE_FILE"
  echo ""
  echo "This may be due to:"
  echo "1. Incorrect URL mapping for your L4T version (R${L4T_MAJOR}.${L4T_MINOR_FULL})"
  echo "2. NVIDIA changed their download URL structure"
  echo ""
  echo "To resolve:"
  echo "1. Visit: https://developer.nvidia.com/embedded/jetson-linux-archive"
  echo "2. Find your L4T version: R${L4T_MAJOR}.${L4T_MINOR_FULL}"
  echo "3. Download 'public_sources.tbz2' manually"
  echo "4. Place it in the current directory: $PWD"
  echo "5. Re-run this script - it will use the existing file"
  echo ""
  echo "Alternative: Use git clone method from NVIDIA documentation:"
  echo "  git clone https://nv-tegra.nvidia.com/3rdparty/canonical/linux-jammy.git"
  exit 1
  fi
fi

log "Extracting sources..."
# Extract kernel source and related components
tar -xvf "$SOURCE_FILE" Linux_for_Tegra/source/kernel_src.tbz2 \
                        Linux_for_Tegra/source/kernel_oot_modules_src.tbz2 \
                        Linux_for_Tegra/source/nvidia_kernel_display_driver_source.tbz2 --strip-components=2

# Extract each component separately into /usr/src/
log "Extracting kernel source..."
sudo tar -xvf kernel_src.tbz2 -C "$KERNEL_SRC_DIR"
log "Extracting NVIDIA out-of-tree kernel modules..."
sudo tar -xvf kernel_oot_modules_src.tbz2 -C "$KERNEL_SRC_DIR"
log "Extracting NVIDIA display driver source..."
sudo tar -xvf nvidia_kernel_display_driver_source.tbz2 -C "$KERNEL_SRC_DIR"

# Cleanup tarballs
rm kernel_src.tbz2 kernel_oot_modules_src.tbz2 nvidia_kernel_display_driver_source.tbz2 "$SOURCE_FILE"

log "Kernel sources and modules extracted to $KERNEL_SRC_DIR"

# Copy the current kernel config (requires sudo)
log "Copying current kernel config..."
sudo zcat /proc/config.gz | sudo tee "${KERNEL_SRC_DIR}kernel/kernel-jammy-src/.config" > /dev/null

# Set the local version for the kernel build process
KERNEL_VERSION=$(uname -r)
LOCAL_VERSION="-$(echo ${KERNEL_VERSION} | cut -d "-" -f2-)"
cd ${KERNEL_SRC_DIR}kernel/kernel-jammy-src/
sudo cp .config .config.orig
sudo bash scripts/config --file .config --set-str LOCALVERSION $LOCAL_VERSION

# Check if libssl-dev is installed
if ! dpkg -s libssl-dev > /dev/null 2>&1; then
    log "libssl-dev is not installed. Installing..."
    sudo apt-get install -y libssl-dev
    if [ $? -eq 0 ]; then
        log "libssl-dev installed successfully."
    else
        log "Failed to install libssl-dev. Please install it manually."
        exit 1
    fi
else
    log "libssl-dev is already installed."
fi

log "Kernel source setup complete!"
