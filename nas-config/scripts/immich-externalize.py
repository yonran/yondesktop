#!/usr/bin/env python3
"""Convert Immich *managed* assets (uploads) into *external-library* assets,
preserving albums, faces, descriptions, favorites, tags, and stacks —
by moving the file on disk and updating the asset row in place.

Written against Immich v2.7.5 (asset.libraryId/isExternal/originalPath,
checksumAlgorithm=sha1). Refuses to run against any other server version
unless --skip-version-check.

ONE-TIME SETUP (before first use)
  1. Mount the destination tree into the immich-server container READ-ONLY,
     e.g. in nas-config immich.nix:  /firstpool/family/photos:/external:ro
     and restart the stack.
  2. Create an external library (owner = target user) and add /external as an
     import path:  web UI -> Administration -> External Libraries, or API.
     Note its UUID (visible in the URL, or: select id, name from library).
  3. Run this script ON THE NAS as root.

PER-RUN WORKFLOW
  1. Write a plan file, tab-separated, one asset per line:
         <current host path>\t<destination host path>
     e.g. /firstpool/family/immich/photos/upload/ab/cd/xxx.jpg\t/firstpool/family/photos/2025/2025-08 kavi first bike/xxx.jpg
     (Live photos are two assets: still + motion video. List both lines if you
     want both externalized; leaving the motion part managed also works.)
  2. Dry run (default):   ./immich-externalize.py --library-id UUID plan.tsv
  3. Execute:             ./immich-externalize.py --library-id UUID plan.tsv \
                              --execute --stop-server
     This will: stop immich-server, zfs-snapshot the dataset, pg_dump the DB,
     verify every file's SHA-1 against the DB checksum, move the files,
     update all rows in ONE transaction (rolls back on any count mismatch),
     restart immich-server, and write an undo log.
  4. In the web UI, run a scan of the external library and spot-check an
     album that contained moved assets.

UNDO: the undo log (immich-externalize-undo-<ts>.tsv: assetId, old, new) plus
the zfs snapshot and pg_dump make reversal mechanical.
"""

import argparse
import datetime
import hashlib
import json
import os
import shutil
import subprocess
import sys
import urllib.request

TESTED_VERSIONS = {(2, 7)}  # (major, minor) of Immich server this was written against
PSQL = ["podman", "exec", "-i", "immich-database", "psql", "-U", "postgres",
        "-d", "immich", "-v", "ON_ERROR_STOP=1", "--no-psqlrc", "-qAt"]
DEFAULT_MOUNTS = [
    ("/firstpool/family/immich/photos", "/data"),
    ("/firstpool/family/photos", "/external"),
]
ZFS_DATASET = "firstpool/family"
SERVER_UNIT = "podman-immich-server.service"
VERSION_URL = "http://localhost:2283/api/server/version"


def psql(sql: str, input_data: str | None = None) -> str:
    data = (sql if input_data is None else sql + "\n" + input_data)
    r = subprocess.run(PSQL, input=data.encode(), capture_output=True)
    if r.returncode != 0:
        sys.exit(f"psql failed:\n{r.stderr.decode()}")
    return r.stdout.decode()


def to_container(host_path: str, mounts) -> str:
    for h, c in mounts:
        if host_path == h or host_path.startswith(h + "/"):
            return c + host_path[len(h):]
    sys.exit(f"{host_path}: not under any known container mount "
             f"({', '.join(h for h, _ in mounts)})")


def sha1_of(path: str) -> str:
    h = hashlib.sha1()
    with open(path, "rb") as f:
        while chunk := f.read(1 << 20):
            h.update(chunk)
    return h.hexdigest()


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
               f"was only tested on {sorted(TESTED_VERSIONS)}. Re-verify the schema "
               "(asset.originalPath/libraryId/isExternal) before proceeding.")
        if skip:
            print(f"WARNING: {msg}")
        else:
            sys.exit(msg)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("plan", help="TSV: <current host path>\\t<dest host path>")
    ap.add_argument("--library-id", required=True, help="UUID of the external library")
    ap.add_argument("--mount", action="append", metavar="HOST=CONTAINER",
                    help="host=container path mapping (repeatable); "
                         f"default: {', '.join(f'{h}={c}' for h, c in DEFAULT_MOUNTS)}")
    ap.add_argument("--execute", action="store_true", help="actually do it (default: dry run)")
    ap.add_argument("--stop-server", action="store_true",
                    help=f"systemctl stop/start {SERVER_UNIT} around the run")
    ap.add_argument("--allow-running", action="store_true",
                    help="proceed even if immich-server is running (risky: the app "
                         "may read files mid-move)")
    ap.add_argument("--skip-version-check", action="store_true")
    args = ap.parse_args()

    if os.geteuid() != 0:
        sys.exit('run as root (podman/zfs/file access), e.g.:\n'
                 '  sudo "$(command -v python3)" immich-externalize.py ...')

    mounts = ([tuple(m.split("=", 1)) for m in args.mount] if args.mount
              else DEFAULT_MOUNTS)

    # --- read plan ---------------------------------------------------------
    rows = []  # (old_host, new_host, old_cont, new_cont)
    seen_dst = set()
    with open(args.plan) as f:
        for ln, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            try:
                old_h, new_h = line.split("\t")
            except ValueError:
                sys.exit(f"{args.plan}:{ln}: expected exactly one tab")
            if new_h in seen_dst:
                sys.exit(f"{args.plan}:{ln}: duplicate destination {new_h}")
            seen_dst.add(new_h)
            rows.append((old_h, new_h, to_container(old_h, mounts),
                         to_container(new_h, mounts)))
    if not rows:
        sys.exit("plan file is empty")

    check_version(args.skip_version_check)

    # --- sanity: library exists -------------------------------------------
    lib = psql(f"select count(*) from library where id = '{args.library_id}';").strip()
    if lib != "1":
        sys.exit(f"library {args.library_id} not found in DB "
                 "(select id, name from library;)")

    # --- fetch matching assets in one query --------------------------------
    paths_tsv = "\n".join(r[2] for r in rows)
    out = psql(
        "create temp table want(p text);\n"
        "copy want from stdin;\n"
        + paths_tsv + "\n\\.\n"
        + "select a.id, a.\"originalPath\", encode(a.checksum,'hex'), "
          "a.\"libraryId\" is not null, a.\"deletedAt\" is not null, "
          "exists (select 1 from asset_file f where f.\"assetId\" = a.id "
          "        and f.type = 'sidecar') "
          "from asset a join want w on a.\"originalPath\" = w.p;")
    by_path = {}
    for line in out.strip().splitlines():
        aid, opath, cksum, is_ext, is_trashed, has_sidecar = line.split("|")
        by_path[opath] = (aid, cksum, is_ext == "t", is_trashed == "t",
                          has_sidecar == "t")

    # --- verify every row ---------------------------------------------------
    updates, problems = [], []
    for old_h, new_h, old_c, new_c in rows:
        rec = by_path.get(old_c)
        if rec is None:
            problems.append(f"NO DB ROW      {old_c}")
            continue
        aid, cksum, is_ext, is_trashed, has_sidecar = rec
        if is_ext:
            problems.append(f"ALREADY EXTERNAL {old_c}")
            continue
        if is_trashed:
            problems.append(f"IN TRASH       {old_c} (restore or omit)")
            continue
        if has_sidecar:
            problems.append(f"HAS SIDECAR    {old_c} (sidecar moves not implemented; omit)")
            continue
        if os.path.exists(new_h):
            problems.append(f"DEST EXISTS    {new_h}")
            continue
        if not os.path.isfile(old_h):
            problems.append(f"MISSING FILE   {old_h}")
            continue
        actual = sha1_of(old_h)
        if actual != cksum:
            problems.append(f"CHECKSUM MISMATCH {old_h} db={cksum} file={actual}")
            continue
        updates.append((aid, old_h, new_h, new_c))

    print(f"plan: {len(rows)} lines -> {len(updates)} verified, {len(problems)} problems")
    for p in problems:
        print("  !", p)
    if problems:
        sys.exit("fix the problems (or remove those lines) and re-run")
    if not args.execute:
        for aid, old_h, new_h, _ in updates[:10]:
            print(f"  ok {aid} {old_h} -> {new_h}")
        if len(updates) > 10:
            print(f"  ... and {len(updates) - 10} more")
        print("dry run complete; re-run with --execute")
        return

    # --- execute ------------------------------------------------------------
    unit_was_active = subprocess.run(
        ["systemctl", "is-active", "--quiet", SERVER_UNIT]).returncode == 0
    if unit_was_active:
        if args.stop_server:
            subprocess.run(["systemctl", "stop", SERVER_UNIT], check=True)
        elif not args.allow_running:
            sys.exit(f"{SERVER_UNIT} is running; use --stop-server (recommended) "
                     "or --allow-running")

    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    subprocess.run(["zfs", "snapshot", f"{ZFS_DATASET}@immich-externalize-{ts}"],
                   check=True)
    dump = f"/firstpool/family/immich/immich-db-pre-externalize-{ts}.sql.gz"
    with open(dump, "wb") as f:
        p1 = subprocess.Popen(["podman", "exec", "immich-database", "pg_dump",
                               "-U", "postgres", "immich"], stdout=subprocess.PIPE)
        subprocess.run(["gzip"], stdin=p1.stdout, stdout=f, check=True)
        if p1.wait() != 0:
            sys.exit("pg_dump failed")
    print(f"snapshot {ZFS_DATASET}@immich-externalize-{ts}; db dump {dump}")

    undo = f"immich-externalize-undo-{ts}.tsv"
    moved = []
    try:
        with open(undo, "w") as u:
            for aid, old_h, new_h, _ in updates:
                os.makedirs(os.path.dirname(new_h), exist_ok=True)
                shutil.move(old_h, new_h)   # works across datasets
                if sha1_of(new_h) != by_path[to_container(old_h, mounts)][1]:
                    raise RuntimeError(f"post-move checksum mismatch: {new_h}")
                moved.append((old_h, new_h))
                u.write(f"{aid}\t{old_h}\t{new_h}\n")
    except Exception as e:
        print(f"ERROR during move: {e}; rolling back {len(moved)} moves")
        for old_h, new_h in reversed(moved):
            shutil.move(new_h, old_h)
        sys.exit("no DB changes were made")

    moves_tsv = "\n".join(f"{aid}\t{new_c}" for aid, _, _, new_c in updates)
    psql(
        "begin;\n"
        "create temp table moves(id uuid, p text);\n"
        "copy moves from stdin;\n"
        + moves_tsv + "\n\\.\n"
        + f"""
do $$
declare n integer;
begin
  update asset a set "originalPath" = m.p,
                     "libraryId" = '{args.library_id}',
                     "isExternal" = true,
                     "isOffline" = false
  from moves m where a.id = m.id;
  get diagnostics n = row_count;
  if n <> {len(updates)} then
    raise exception 'updated % rows, expected {len(updates)}', n;
  end if;
end $$;
commit;\n""")
    print(f"updated {len(updates)} asset rows; undo log: {undo}")

    if unit_was_active and args.stop_server:
        subprocess.run(["systemctl", "start", SERVER_UNIT], check=True)
        print(f"restarted {SERVER_UNIT}")
    print("next: run an external-library scan in the web UI and spot-check "
          "an album containing moved assets")


if __name__ == "__main__":
    main()
