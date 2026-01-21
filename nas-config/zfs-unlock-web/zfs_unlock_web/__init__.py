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

# Configuration
DATASET = "firstpool/family"
MOUNT_UNIT = "firstpool-family.mount"

# Dependent services to show status for
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


def get_keystatus():
    """Get the key status of the ZFS dataset (available, unavailable)."""
    # zfs get doesn't require privileges - any user can read properties
    success, stdout, stderr = run_command(
        ["zfs", "get", "-H", "-o", "value", "keystatus", DATASET]
    )
    if success:
        return stdout.strip()
    return "unknown"


def get_mounted():
    """Check if the ZFS dataset is mounted."""
    # zfs get doesn't require privileges - any user can read properties
    success, stdout, stderr = run_command(
        ["zfs", "get", "-H", "-o", "value", "mounted", DATASET]
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


def load_key(passphrase):
    """Load the encryption key for the ZFS dataset."""
    # Requires 'zfs allow -u zfs-unlock load-key,mount firstpool/family'
    success, stdout, stderr = run_command(
        ["zfs", "load-key", DATASET],
        stdin_data=passphrase,
    )
    return success, stderr


def start_mount():
    """Mount the ZFS dataset and start dependent services.

    Uses sudo for zfs mount (Linux requires root for mount syscall),
    then starts the immich-stack target which brings up dependent services.
    """
    success, stdout, stderr = run_command(
        ["sudo", "/run/current-system/sw/bin/zfs", "mount", DATASET]
    )

    if not success:
        return success, stderr

    # Start the immich stack and other services that depend on this mount
    run_command(
        ["sudo", "/run/current-system/sw/bin/systemctl", "start", "immich-stack.target"]
    )
    run_command(
        ["sudo", "/run/current-system/sw/bin/systemctl", "start", "jellyfin.service"]
    )
    run_command(
        ["sudo", "/run/current-system/sw/bin/systemctl", "start", "samba-smbd.service"]
    )
    return True, ""


@app.route("/")
def index():
    """Show status page with unlock form if needed."""
    keystatus = get_keystatus()
    mounted = get_mounted()

    services_status = {}
    for service in DEPENDENT_SERVICES:
        services_status[service] = get_service_status(service)

    return render_template(
        "index.html",
        dataset=DATASET,
        keystatus=keystatus,
        mounted=mounted,
        services=services_status,
    )


@app.route("/unlock", methods=["POST"])
def unlock():
    """Handle unlock form submission."""
    passphrase = request.form.get("passphrase", "")

    if not passphrase:
        flash("Passphrase is required", "error")
        return redirect(url_for("index"))

    keystatus = get_keystatus()

    # Only load key if not already loaded
    if keystatus == "unavailable":
        success, error = load_key(passphrase)
        if not success:
            flash(f"Failed to load key: {error}", "error")
            return redirect(url_for("index"))
        flash("Key loaded successfully", "success")

    # Start the mount unit to mount and trigger dependent services
    mounted = get_mounted()
    if not mounted:
        success, error = start_mount()
        if not success:
            flash(f"Failed to start mount: {error}", "error")
            return redirect(url_for("index"))
        flash("Dataset mounted and services starting", "success")

    return redirect(url_for("index"))


@app.route("/mount", methods=["POST"])
def mount():
    """Handle mount request (when key is loaded but not mounted)."""
    success, error = start_mount()
    if not success:
        flash(f"Failed to start mount: {error}", "error")
    else:
        flash("Dataset mounted and services starting", "success")
    return redirect(url_for("index"))


# WSGI entry point for uwsgi
application = app
