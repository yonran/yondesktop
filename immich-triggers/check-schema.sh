#!/usr/bin/env bash
# check-schema.sh — verify the live Immich DB schema still has every table,
# column, and enum value that the custom triggers in this directory depend on.
#
# Run this AFTER an Immich upgrade (esp. the v2 -> v3 major bump) and BEFORE
# re-applying the triggers. The triggers are plpgsql, so a renamed table/column
# does NOT fail the Immich migration — it fails silently at the next INSERT and,
# because both triggers are AFTER INSERT, rolls back the insert (new uploads /
# album-adds break). This script surfaces such a rename up front.
#
# Usage:  sudo ./check-schema.sh
# Exit 0 = all dependencies present; exit 1 = at least one missing.

set -euo pipefail

PSQL=(sudo podman exec -i immich-database psql -U postgres -d immich -tAqX)

# One row per dependency the triggers rely on: "table:column" (column blank = table only).
# Sources: yon_auto_add_to_family.sql, yon_exclusive_archiving_albums.sql
# v3 note: album.ownerId was removed in Immich v3; the album owner is now the
# album_user row with role='owner' (see the enum check below), so the triggers
# depend on album_user.userId/role, NOT album.ownerId.
DEPS=(
  "album:id"
  "asset:id"
  "asset:ownerId"
  "asset:originalFileName"
  "asset:visibility"
  "album_asset:albumId"
  "album_asset:assetId"
  "album_user:albumId"
  "album_user:userId"
  "album_user:role"
)

fail=0

check_column() {
  local tbl="$1" col="$2"
  local got
  got=$("${PSQL[@]}" -c \
    "SELECT 1 FROM information_schema.columns WHERE table_name='${tbl}' AND column_name='${col}' LIMIT 1;")
  if [[ "$got" == "1" ]]; then
    printf '  OK   %s.%s\n' "$tbl" "$col"
  else
    printf '  MISS %s.%s   <-- trigger depends on this\n' "$tbl" "$col"
    fail=1
  fi
}

echo "== Trigger schema dependencies =="
for dep in "${DEPS[@]}"; do
  check_column "${dep%%:*}" "${dep##*:}"
done

# The 'archive' enum value used by: UPDATE "asset" SET "visibility" = 'archive'
echo
echo "== asset.visibility enum values =="
enum=$("${PSQL[@]}" -c \
  "SELECT string_agg(e.enumlabel, ',' ORDER BY e.enumsortorder)
     FROM pg_type t
     JOIN pg_enum e ON e.enumtypid = t.oid
     JOIN pg_attribute a ON a.atttypid = t.oid
     JOIN pg_class c ON c.oid = a.attrelid
    WHERE c.relname='asset' AND a.attname='visibility';")
if [[ -z "$enum" ]]; then
  echo "  WARN visibility is not an enum type (or column missing) — check the SET 'archive' write manually"
  fail=1
else
  echo "  values: $enum"
  if [[ ",$enum," == *",archive,"* ]]; then
    echo "  OK   'archive' present"
  else
    echo "  MISS 'archive' not in enum   <-- both triggers write visibility='archive'"
    fail=1
  fi
fi

# v3: album owner is the album_user row with role='owner'. Confirm the enum has it.
echo
echo "== album_user.role enum values =="
role_enum=$("${PSQL[@]}" -c \
  "SELECT string_agg(e.enumlabel, ',' ORDER BY e.enumsortorder)
     FROM pg_type t
     JOIN pg_enum e ON e.enumtypid = t.oid
     JOIN pg_attribute a ON a.atttypid = t.oid
     JOIN pg_class c ON c.oid = a.attrelid
    WHERE c.relname='album_user' AND a.attname='role';")
echo "  values: $role_enum"
if [[ ",$role_enum," == *",owner,"* ]]; then
  echo "  OK   'owner' present"
else
  echo "  MISS 'owner' not in enum   <-- both triggers resolve album owner via role='owner'"
  fail=1
fi

# Are the triggers currently installed? (informational — expected absent if you
# dropped them before the migration per the upgrade runbook.)
echo
echo "== Trigger presence (informational) =="
for trig in auto_add_to_album yon_exclusive_archiving_albums; do
  present=$("${PSQL[@]}" -c "SELECT 1 FROM pg_trigger WHERE tgname='${trig}' AND NOT tgisinternal LIMIT 1;")
  [[ "$present" == "1" ]] && echo "  installed: $trig" || echo "  absent:    $trig"
done

echo
if [[ "$fail" -eq 0 ]]; then
  echo "RESULT: all trigger dependencies present — safe to re-apply the triggers."
else
  echo "RESULT: schema drift detected — DO NOT re-apply the triggers until the .sql files are updated to match."
fi
exit "$fail"
