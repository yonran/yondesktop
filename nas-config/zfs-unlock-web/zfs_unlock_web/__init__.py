"""
ZFS Unlock Web GUI - Flask application for unlocking ZFS encrypted datasets.

Security model:
- Authentication handled by Caddy (Google OIDC via caddy-security)
- Rate limiting handled by Caddy (5 attempts per 5 minutes on /unlock)
- Runs as unprivileged user with sudo for specific commands only
- Passphrase passed via stdin to zfs load-key (never in args or logs)
- Socket-activated with idle shutdown after 60s
"""

import subprocess
import os
from flask import Flask, render_template, request, redirect, url_for, flash

app = Flask(__name__)
# Secret key for flash messages - in production, this is set via environment
app.secret_key = os.environ.get('FLASK_SECRET_KEY', 'dev-only-change-in-prod')

# Configuration: datasets to manage, in order. Set via ZFS_UNLOCK_DATASETS
# (comma-separated) by the NixOS module; falls back to the primary dataset.
# One submitted passphrase is tried against every still-locked dataset, so a
# shared passphrase unlocks them all in one go; otherwise resubmit per dataset.
DATASETS = [
    d.strip()
    for d in os.environ.get("ZFS_UNLOCK_DATASETS", "firstpool/family").split(",")
    if d.strip()
]

# The dataset whose mount gates the dependent services below (the live data;
# the backup pool has no services to start).
SERVICE_DATASET = "firstpool/family"

# Dependent services to show status for / start once SERVICE_DATASET is mounted.
DEPENDENT_SERVICES = [
    "podman-immich-server.service",
    "podman-immich-database.service",
    "jellyfin.service",
    "samba-smbd.service",
]


def run_command(cmd, stdin_data=None):
    """Run a command and return (success, stdout, stderr)."""
    try:
        result = subprocess.run(
            cmd,
            input=stdin_data,
            capture_output=True,
            text=True,
            timeout=30,
        )
        return result.returncode == 0, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return False, "", "Command timed out"
    except Exception as e:
        return False, "", str(e)


def get_keystatus(dataset):
    """Get the key status of a ZFS dataset (available, unavailable)."""
    # zfs get doesn't require privileges - any user can read properties
    success, stdout, stderr = run_command(
        ["zfs", "get", "-H", "-o", "value", "keystatus", dataset]
    )
    if success:
        return stdout.strip()
    return "unknown"


def get_mounted(dataset):
    """Check if a ZFS dataset is mounted."""
    # zfs get doesn't require privileges - any user can read properties
    success, stdout, stderr = run_command(
        ["zfs", "get", "-H", "-o", "value", "mounted", dataset]
    )
    if success:
        return stdout.strip() == "yes"
    return False


def get_service_status(service):
    """Get the status of a systemd service."""
    success, stdout, stderr = run_command(
        ["systemctl", "is-active", service]
    )
    return stdout.strip() if success else "unknown"


def load_key(dataset, passphrase):
    """Load the encryption key for a ZFS dataset.

    Relies on 'zfs allow -u zfs-unlock load-key,mount <dataset>' delegation,
    so no sudo is needed here.
    """
    success, stdout, stderr = run_command(
        ["zfs", "load-key", dataset],
        stdin_data=passphrase,
    )
    return success, stderr


def mount_dataset(dataset):
    """Mount a ZFS dataset (sudo: Linux requires root for the mount syscall)."""
    success, stdout, stderr = run_command(
        ["sudo", "/run/current-system/sw/bin/zfs", "mount", dataset]
    )
    return success, stderr


def start_dependent_services():
    """Start services that depend on SERVICE_DATASET being mounted."""
    for unit in ["immich-stack.target", "jellyfin.service", "samba-smbd.service"]:
        run_command(
            ["sudo", "/run/current-system/sw/bin/systemctl", "start", unit]
        )


def mount_all_and_start_services():
    """Mount any unlocked-but-unmounted dataset, then start dependent services."""
    for dataset in DATASETS:
        if get_keystatus(dataset) == "available" and not get_mounted(dataset):
            success, error = mount_dataset(dataset)
            if success:
                flash(f"{dataset}: mounted", "success")
            else:
                flash(f"{dataset}: failed to mount: {error.strip()}", "error")

    if get_mounted(SERVICE_DATASET):
        start_dependent_services()


@app.route("/")
def index():
    """Show status page with unlock form if needed."""
    datasets = [
        {
            "name": dataset,
            "keystatus": get_keystatus(dataset),
            "mounted": get_mounted(dataset),
        }
        for dataset in DATASETS
    ]
    any_locked = any(d["keystatus"] == "unavailable" for d in datasets)
    any_unmounted = any(
        d["keystatus"] == "available" and not d["mounted"] for d in datasets
    )

    services_status = {}
    for service in DEPENDENT_SERVICES:
        services_status[service] = get_service_status(service)

    return render_template(
        "index.html",
        datasets=datasets,
        any_locked=any_locked,
        any_unmounted=any_unmounted,
        services=services_status,
    )


@app.route("/unlock", methods=["POST"])
def unlock():
    """Handle unlock form submission.

    Tries the submitted passphrase against every still-locked dataset, then
    mounts whatever is unlocked and starts dependent services.
    """
    passphrase = request.form.get("passphrase", "")

    if not passphrase:
        flash("Passphrase is required", "error")
        return redirect(url_for("index"))

    for dataset in DATASETS:
        if get_keystatus(dataset) == "unavailable":
            success, error = load_key(dataset, passphrase)
            if success:
                flash(f"{dataset}: key loaded", "success")
            else:
                flash(f"{dataset}: failed to load key: {error.strip()}", "error")

    mount_all_and_start_services()

    return redirect(url_for("index"))


@app.route("/mount", methods=["POST"])
def mount():
    """Handle mount request (when keys are loaded but datasets not mounted)."""
    mount_all_and_start_services()
    return redirect(url_for("index"))


# WSGI entry point for uwsgi
application = app
