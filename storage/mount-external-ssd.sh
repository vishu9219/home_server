#!/bin/bash
# /usr/local/bin/mount-external-ssd.sh
# Usage: mount-external-ssd.sh mount

set -e

MOUNT_BASE="/mnt/external"
LOG_FILE="/var/log/external-mount.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

if [[ "$1" != "mount" ]]; then
  echo "Usage: $0 mount"
  exit 1
fi

sudo mkdir -p "$MOUNT_BASE"

# Detect and mount each partition
lsblk -nr -o NAME,TYPE,MOUNTPOINT | awk '$2=="part" && $3=="" {print $1}' | while read dev; do
  mount_point="$MOUNT_BASE/$(blkid -s LABEL -o value /dev/$dev || echo "ssd-$dev")"
  sudo mkdir -p "$mount_point"
  if ! mount | grep -q "$mount_point"; then
    fstype=$(blkid -s TYPE -o value /dev/$dev)
    case "$fstype" in
      ext4|ext3|ext2)
        sudo mount -o defaults,discard,ssd /dev/"$dev" "$mount_point";;
      ntfs)
        sudo mount -t ntfs-3g -o defaults,uid=1000,gid=1000 /dev/"$dev" "$mount_point";;
      exfat|vfat)
        sudo mount -t exfat -o defaults,uid=1000,gid=1000 /dev/"$dev" "$mount_point";;
      *)
        log "Unsupported FS: $fstype on /dev/$dev"
        continue;;
    esac
    log "Mounted /dev/$dev at $mount_point"
  else
    log "/dev/$dev already mounted"
  fi
done
