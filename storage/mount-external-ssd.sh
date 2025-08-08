#!/bin/bash
# /usr/local/bin/mount-external-ssd.sh
# Automatically mount external SSD drives under /mnt/external

set -e

MOUNT_BASE="/mnt/external"
LOG_FILE="/var/log/external-mount.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

detect_and_mount() {
  sudo mkdir -p "$MOUNT_BASE"
  lsblk -nr -o NAME,TYPE,MOUNTPOINT | \
    awk '$2=="part" && $3=="" {print $1}' | while read dev; do
      uuid=$(blkid -s UUID -o value /dev/"$dev")
      fstype=$(blkid -s TYPE -o value /dev/"$dev")
      label=$(blkid -s LABEL -o value /dev/"$dev" || echo "ssd-$dev")
      mount_point="$MOUNT_BASE/$label"
      if [ ! -d "$mount_point" ]; then
        sudo mkdir -p "$mount_point"
      fi
      if ! mount | grep -q "$mount_point"; then
        case "$fstype" in
          ext4|ext3|ext2)
            sudo mount -o defaults,discard,ssd /dev/"$dev" "$mount_point";;
          ntfs) 
            sudo mount -t ntfs-3g -o defaults,uid=1000,gid=1000 /dev/"$dev" "$mount_point";;
          exfat|vfat)
            sudo mount -t exfat -o defaults,uid=1000,gid=1000 /dev/"$dev" "$mount_point";;
          *)
            log "Unsupported FS: $fstype on /dev/$dev"; continue;;
        esac
        log "Mounted /dev/$dev at $mount_point"
      else
        log "/dev/$dev already mounted"
      fi
    done
}

case "$1" in
  mount)
    detect_and_mount;;
  *)
    echo "Usage: $0 mount"; exit 1;;
esac
