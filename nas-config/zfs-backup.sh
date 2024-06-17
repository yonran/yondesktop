
#!/bin/sh

set -eux

# Configuration variables
source_pool="$1"
source_fs="$2"
backup_pool="$3"
backup_fs="$4"

datestamp=$(date +"%Y-%m-%d-%H-%M-%S")
snapshotname="${source_pool}/${source_fs}@backup-${datestamp}"

if ! zpool list -H -o name | grep -q "^${source_pool}$"; then
  echo >&2 "Source pool ${source_pool} does not exist; not performing backup"
  exit 0
fi
if ! zpool list -H -o name | grep -q "^${backup_pool}$"; then
  echo >&2 "Backup pool ${backup_pool} does not exist; not performing backup"
  exit 0
fi

# Create a new snapshot
zfs snapshot $snapshotname

# Determine if the filesystem is encrypted
encryption_root=$(zfs get -H -o value encryptionroot ${source_pool}/${source_fs})
RAW_FLAG=
if [ "$encryption_root" != "-" ]; then
  RAW_FLAG=--raw
fi

# Check for the last snapshot and perform incremental backup if possible
source_snapshots=$(zfs list -t snapshot -H -o name -s creation "${source_pool}/${source_fs}" | grep "^${source_pool}/${source_fs}@backup-")
backup_snapshots=$(zfs list -t snapshot -H -o name -s creation "${backup_pool}/${backup_fs}" | grep "^${backup_pool}/${backup_fs}@backup-")
last_snapshot=
for snap in $source_snapshots; do
  backup_snap="${snap/${source_pool}\/${source_fs}/${backup_pool}\/${backup_fs}}"
  if echo "$backup_snapshots" | grep -q "^${backup_snap}$"; then
    last_snapshot=$snap
  fi
done
if [ -n "$last_snapshot" ]; then
  echo >&2 "Last snapshot found, performing incremental ${RAW_FLAG:-non-raw} backup since $last_snapshot"
  zfs send -R $RAW_FLAG -i $last_snapshot $snapshotname | zfs receive -F $backup_pool/$backup_fs
else
  echo >&2 "No previous snapshot found, performing full ${RAW_FLAG:-non-raw} backup"
  # zfs recv -F: force rollback to the last snapshot in case 
  zfs send -R $RAW_FLAG $snapshotname | zfs receive $backup_pool/$backup_fs
fi


# Cleanup snapshots, keeping only the last 7
# zfs list -t snapshot -o name | grep "${source_pool}/${source_fs}@backup-" | head -n -7 | xargs -r zfs destroy
