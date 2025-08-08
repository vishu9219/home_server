#!/usr/bin/env bash

set -euo pipefail

# Non-interactive script to automatically mount all unmounted /dev/sd* devices
# at consecutive /mnt/extN directories and ensure persistent fstab entries.

FSTAB="/etc/fstab"
FSTAB_BAK="${FSTAB}.bak"

# Backup fstab once
if [[ ! -f "${FSTAB_BAK}" ]]; then
  sudo cp "${FSTAB}" "${FSTAB_BAK}"
fi

# Function to get next available mountpoint index
next_index() {
  local base="/mnt/ext"
  local i=1
  while [[ -e "${base}${i}" ]]; do
    ((i++))
  done
  echo "${i}"
}

# Iterate through all /dev/sd* block devices and partitions
for dev in /dev/sd*; do
  [[ -b "${dev}" ]] || continue
  # Skip if already mounted
  if mount | grep -q "^${dev} "; then
    continue
  fi

  # Get UUID (if any)
  uuid=$(blkid -s UUID -o value "${dev}" 2>/dev/null || true)

  # If fstab already has entry, mount via fstab path
  if [[ -n "${uuid}" ]] && grep -qF "${uuid}" "${FSTAB}"; then
    mp=$(grep -F "${uuid}" "${FSTAB}" | awk '{print $2}')
    sudo mount "${mp}"
    continue
  fi

  # Create filesystem if none
  if [[ -z "${uuid}" ]]; then
    sudo mkfs.ext4 -F "${dev}"
    uuid=$(blkid -s UUID -o value "${dev}")
  fi

  # Create mountpoint
  idx=$(next_index)
  mp="/mnt/ext${idx}"
  sudo mkdir -p "${mp}"

  # Add fstab entry
  echo "UUID=${uuid}    ${mp}    ext4    defaults,noatime    0    2" | sudo tee -a "${FSTAB}" >/dev/null

  # Mount it
  sudo mount "${mp}"
done

echo "Done: all unmounted /dev/sd* devices have been mounted and fstab updated."
