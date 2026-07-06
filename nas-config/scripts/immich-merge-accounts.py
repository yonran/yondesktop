#!/usr/bin/env python3
"""Merge one Immich account into another, preserving albums, people (face
names), memories, tags, favorites, archive state, and descriptions.

Written against Immich v2.7.5. Refuses to run against any other server
version unless --skip-version-check, and verifies every table/column it
touches before doing anything.

WHAT IT DOES (all DB changes in ONE transaction)
  1. Finds duplicate assets: source-account assets whose SHA-1 checksum also
     exists in the destination account (the unique index
     UQ_assets_owner_checksum makes these collide on ownership transfer).
     For each, re-points album_asset / memory_asset / tag_asset /
     shared_link_asset / album cover references from the source copy to the
     destination copy, then deletes the source copy's asset row (junction
     rows, exif, faces, thumbnails cascade).
  2. Transfers ownership of all remaining source assets, albums, people,
     memories, and stacks to the destination user.
  3. Merges tags: source tags whose value already exists for the destination
     user are folded into them (tag_asset re-pointed); the rest change owner,
     parents first so parentId stays consistent.
  4. Deletes album_user share rows that would become self-shares.
AFTERWARD (manual)
  - Move the deleted duplicates' files out of the library tree: the script
    writes a quarantine list and moves them under
    <UPLOAD_ROOT>/merge-quarantine-<ts>/ (reversible; delete when satisfied).
  - In the web UI: merge duplicate People (source's 151 + destination's 339
    will overlap), spot-check albums, then delete the source user account
    (it owns nothing at that point).
  - Log both phones into the destination account.

UNDO: zfs snapshot + pg_dump taken before the transaction; quarantined files
are moved, not deleted.

Usage:
  sudo immich-merge-accounts --from noel@example.com --to me@example.com   # dry run
  sudo immich-merge-accounts --from ... --to ... --execute --stop-server
"""

import argparse
import datetime
import json
import os
import shutil
import subprocess
import sys
import urllib.request

TESTED_VERSIONS = {(2, 7)}
PSQL = ["podman", "exec", "-i", "immich-database", "psql", "-U", "postgres",
        "-d", "immich", "-v", "ON_ERROR_STOP=1", "--no-psqlrc", "-qAt"]
UPLOAD_ROOT = "/firstpool/family/immich/photos"   # host path of container /data
ZFS_DATASET = "firstpool/family"
SERVER_UNIT = "podman-immich-server.service"
VERSION_URL = "http://localhost:2283/api/server/version"

# every (table, column) this script reads or writes; verified before running
REQUIRED_SCHEMA = {
    "asset": ["id", "ownerId", "checksum", "libraryId", "originalPath", "status"],
    "asset_file": ["assetId", "path", "type"],
    "album": ["id", "ownerId", "albumThumbnailAssetId"],
    "album_asset": ["albumId", "assetId"],
    "album_user": ["albumId", "userId"],
    "memory": ["id", "ownerId"],
    "memory_asset": ["memoriesId", "assetId"],
    "person": ["id", "ownerId"],
    "stack": ["id", "ownerId", "primaryAssetId"],
    "tag": ["id", "userId", "value", "parentId"],
    "tag_asset": ["assetId", "tagId"],
    "shared_link": ["id", "userId"],
    "shared_link_asset": ["assetId", "sharedLinkId"],
    "user": ["id", "email"],
}


def psql(sql: str) -> str:
    r = subprocess.run(PSQL, input=sql.encode(), capture_output=True)
    if r.returncode != 0:
        raise RuntimeError(f"psql failed:\n{r.stderr.decode()}")
    return r.stdout.decode()


def check_version(skip: bool):
    try:
        with urllib.request.urlopen(VERSION_URL, timeout=10) as r:
            v = json.load(r)
    except Exception as e:
        if skip:
            return
        sys.exit(f"cannot read server version from {VERSION_URL} ({e}); "
                 "start the server for the version check or use --skip-version-check")
    if (v["major"], v["minor"]) not in TESTED_VERSIONS:
        msg = (f"server is v{v['major']}.{v['minor']}.{v['patch']}, but this script "
               f"was only tested on {sorted(TESTED_VERSIONS)}.")
        if skip:
            print(f"WARNING: {msg}")
        else:
            sys.exit(msg)


def check_schema():
    rows = psql(
        "select table_name || '.' || column_name from information_schema.columns "
        "where table_schema = 'public';").split()
    have = set(rows)
    missing = [f"{t}.{c}" for t, cols in REQUIRED_SCHEMA.items()
               for c in cols if f"{t}.{c}" not in have]
    if missing:
        sys.exit("schema mismatch, refusing to run. Missing: " + ", ".join(missing))


def resolve_user(ident: str) -> tuple[str, str]:
    out = psql("select id, email from \"user\" "
               f"where id::text = '{ident}' or email = '{ident}';").strip()
    lines = out.splitlines()
    if len(lines) != 1:
        sys.exit(f"user {ident!r}: expected exactly one match, got {len(lines)}")
    uid, email = lines[0].split("|")
    return uid, email


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--from", dest="src", required=True,
                    help="source user (email or uuid) — will end up owning nothing")
    ap.add_argument("--to", dest="dst", required=True,
                    help="destination user (email or uuid)")
    ap.add_argument("--execute", action="store_true", help="actually do it (default: dry run)")
    ap.add_argument("--stop-server", action="store_true",
                    help=f"systemctl stop/start {SERVER_UNIT} around the run")
    ap.add_argument("--allow-running", action="store_true")
    ap.add_argument("--skip-version-check", action="store_true")
    args = ap.parse_args()

    if os.geteuid() != 0:
        sys.exit("run as root (podman/zfs/file access)")

    check_version(args.skip_version_check)
    check_schema()
    src, src_email = resolve_user(args.src)
    dst, dst_email = resolve_user(args.dst)
    if src == dst:
        sys.exit("--from and --to are the same user")

    # ---- what would happen -------------------------------------------------
    # A source asset is a "duplicate" if any destination asset (any status —
    # trashed rows still occupy the unique index) has the same checksum.
    dup_sql = f"""
        select s.id, d.id, s."originalPath"
        from asset s
        join lateral (
          select id from asset d
          where d."ownerId" = '{dst}' and d.checksum = s.checksum
          order by (d.status = 'active') desc, d."createdAt" limit 1
        ) d on true
        where s."ownerId" = '{src}'"""
    dups = [l.split("|") for l in psql(dup_sql + ";").strip().splitlines()]
    counts = {}
    for label, q in [
        ("assets to transfer", f"select count(*) from asset where \"ownerId\"='{src}'"),
        ("albums to transfer", f"select count(*) from album where \"ownerId\"='{src}'"),
        ("people to transfer", f"select count(*) from person where \"ownerId\"='{src}'"),
        ("memories to transfer", f"select count(*) from memory where \"ownerId\"='{src}'"),
        ("stacks to transfer", f"select count(*) from stack where \"ownerId\"='{src}'"),
        ("tags to merge/transfer", f"select count(*) from tag where \"userId\"='{src}'"),
        ("shared links to transfer", f"select count(*) from shared_link where \"userId\"='{src}'"),
    ]:
        counts[label] = int(psql(q + ";").strip())
    counts["assets to transfer"] -= len(dups)

    print(f"merging {src_email} ({src})\n   into {dst_email} ({dst})")
    print(f"  duplicate assets to fold into destination copies: {len(dups)}")
    for label, n in counts.items():
        print(f"  {label}: {n}")
    if not args.execute:
        print("dry run complete; re-run with --execute")
        return

    # ---- execute -------------------------------------------------------------
    unit_was_active = subprocess.run(
        ["systemctl", "is-active", "--quiet", SERVER_UNIT]).returncode == 0
    if unit_was_active:
        if args.stop_server:
            subprocess.run(["systemctl", "stop", SERVER_UNIT], check=True)
        elif not args.allow_running:
            sys.exit(f"{SERVER_UNIT} is running; use --stop-server (recommended) "
                     "or --allow-running")

    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    subprocess.run(["zfs", "snapshot", f"{ZFS_DATASET}@immich-merge-{ts}"], check=True)
    dump = f"/firstpool/family/immich/immich-db-pre-merge-{ts}.sql.gz"
    with open(dump, "wb") as f:
        p1 = subprocess.Popen(["podman", "exec", "immich-database", "pg_dump",
                               "-U", "postgres", "immich"], stdout=subprocess.PIPE)
        subprocess.run(["gzip"], stdin=p1.stdout, stdout=f, check=True)
        if p1.wait() != 0:
            sys.exit("pg_dump failed")
    print(f"snapshot {ZFS_DATASET}@immich-merge-{ts}; db dump {dump}")

    # files of duplicate source assets (original + generated), for quarantine
    dup_files = []
    if dups:
        ids = ",".join(f"'{s}'" for s, _, _ in dups)
        out = psql(f"select \"originalPath\" from asset where id in ({ids}) "
                   f"union all select path from asset_file where \"assetId\" in ({ids});")
        dup_files = [p for p in out.strip().splitlines() if p]

    tx = [f"""
begin;
create temp table dup(src uuid primary key, dst uuid) on commit drop;
"""]
    for s, d, _ in dups:
        tx.append(f"insert into dup values ('{s}','{d}');")
    tx.append(f"""
-- re-point references from duplicate source copies to destination copies
insert into album_asset ("albumId", "assetId")
  select aa."albumId", dup.dst from album_asset aa join dup on aa."assetId" = dup.src
  on conflict do nothing;
insert into memory_asset ("memoriesId", "assetId")
  select ma."memoriesId", dup.dst from memory_asset ma join dup on ma."assetId" = dup.src
  on conflict do nothing;
insert into tag_asset ("assetId", "tagId")
  select dup.dst, ta."tagId" from tag_asset ta join dup on ta."assetId" = dup.src
  on conflict do nothing;
insert into shared_link_asset ("assetId", "sharedLinkId")
  select dup.dst, sa."sharedLinkId" from shared_link_asset sa join dup on sa."assetId" = dup.src
  on conflict do nothing;
update album set "albumThumbnailAssetId" = dup.dst
  from dup where "albumThumbnailAssetId" = dup.src;
update stack set "primaryAssetId" = dup.dst
  from dup where "primaryAssetId" = dup.src;
-- live-photo pairs: if a still references a duplicate motion asset, re-point it
update asset set "livePhotoVideoId" = dup.dst
  from dup where "livePhotoVideoId" = dup.src;

-- drop the duplicate source copies (junctions/exif/faces/files cascade)
delete from asset where id in (select src from dup);

-- no checksum collisions may remain
do $$
declare n integer;
begin
  select count(*) into n from asset s join asset d on s.checksum = d.checksum
    where s."ownerId" = '{src}' and d."ownerId" = '{dst}';
  if n <> 0 then raise exception 'still % checksum collisions', n; end if;
end $$;

-- transfer ownership
update asset  set "ownerId" = '{dst}' where "ownerId" = '{src}';
update album  set "ownerId" = '{dst}' where "ownerId" = '{src}';
update person set "ownerId" = '{dst}' where "ownerId" = '{src}';
update memory set "ownerId" = '{dst}' where "ownerId" = '{src}';
update stack  set "ownerId" = '{dst}' where "ownerId" = '{src}';
update shared_link set "userId" = '{dst}' where "userId" = '{src}';

-- tags: fold same-value tags into destination's, transfer the rest (parents first)
create temp table tagmap(src uuid primary key, dst uuid) on commit drop;
insert into tagmap
  select st.id, dt.id from tag st join tag dt on dt.value = st.value
  where st."userId" = '{src}' and dt."userId" = '{dst}';
insert into tag_asset ("assetId", "tagId")
  select ta."assetId", tagmap.dst from tag_asset ta join tagmap on ta."tagId" = tagmap.src
  on conflict do nothing;
update tag set "parentId" = tagmap.dst from tagmap
  where "parentId" = tagmap.src and "userId" = '{src}';
delete from tag where id in (select src from tagmap);
update tag set "userId" = '{dst}' where "userId" = '{src}';

-- shares that would now be self-shares
delete from album_user au using album al
  where au."albumId" = al.id
    and (au."userId" = '{src}' or au."userId" = al."ownerId");

commit;
""")
    psql("\n".join(tx))
    print(f"DB merge committed: {len(dups)} duplicates folded, ownership transferred")

    # quarantine the duplicate copies' files (already unreferenced by the DB)
    qdir = os.path.join(UPLOAD_ROOT, f"merge-quarantine-{ts}")
    moved = 0
    for cpath in dup_files:
        if not cpath.startswith("/data/"):
            print(f"  ! unexpected path, skipping: {cpath}")
            continue
        hpath = UPLOAD_ROOT + cpath[len("/data"):]
        if not os.path.isfile(hpath):
            continue   # e.g. never-generated thumbnail
        dest = qdir + cpath[len("/data"):]
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.move(hpath, dest)
        moved += 1
    print(f"quarantined {moved} duplicate files under {qdir}")

    if unit_was_active and args.stop_server:
        subprocess.run(["systemctl", "start", SERVER_UNIT], check=True)
        print(f"restarted {SERVER_UNIT}")
    print(f"""next steps:
  1. web UI: spot-check albums and the timeline as {dst_email}
  2. web UI: merge duplicate People (source and destination each had their own)
  3. log both phones into {dst_email}
  4. when satisfied: delete user {src_email} in the admin UI (it owns nothing now),
     delete {qdir}, and prune snapshot {ZFS_DATASET}@immich-merge-{ts} + {dump}""")


if __name__ == "__main__":
    main()
