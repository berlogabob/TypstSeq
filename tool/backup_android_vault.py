#!/usr/bin/env python3
"""Auditable non-destructive Android vault backup."""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Optional, Dict, Any


def get_repo_root() -> Path:
    """Get the repository root from this script, independent of cwd."""
    return Path(__file__).resolve().parents[1]


def validate_source_path(source: str) -> Path:
    """Validate that source path is safe and within allowed directories."""
    source_path = Path(source)

    unsafe_chars = set("|&;$()<>`\\\"'*?[]{}")
    if any(ord(char) < 32 or ord(char) == 127 or char in unsafe_chars for char in source):
        raise ValueError("Source path contains unsafe characters")

    # Convert to string for path comparison
    source_str = source.rstrip('/')

    # Check if source is within allowed directories
    allowed_roots = ['/sdcard', '/storage/emulated/0']
    is_allowed = False
    for root in allowed_roots:
        if source_str.startswith(root + '/'):
            segments = source_str[len(root) + 1:].split('/')
            if any(segment in ('', '.', '..') for segment in segments):
                raise ValueError("Source path contains traversal or dot segments")
            is_allowed = True
            break

    if not is_allowed:
        raise ValueError(f"Source must be under {' or '.join(allowed_roots)}: {source}")

    return source_path


def validate_destination(destination: str) -> Path:
    """Validate that destination is new and outside the repository."""
    dest_path = Path(destination).expanduser().resolve()
    repo_root = get_repo_root().resolve()

    # Check if destination is inside repo
    if dest_path.is_relative_to(repo_root):
        raise ValueError(f"Destination must be outside repository: {destination}")

    # Check if destination already exists
    if dest_path.exists():
        raise ValueError(f"Destination must be new (must not exist): {destination}")

    # Check if parent directory exists and is writable
    parent = dest_path.parent
    if not parent.exists():
        raise ValueError(f"Parent directory does not exist: {parent}")

    if not os.access(parent, os.W_OK):
        raise ValueError(f"Parent directory is not writable: {parent}")

    return dest_path


def get_adb_path(adb_arg: Optional[str] = None) -> str:
    """Get the adb executable path."""
    if adb_arg:
        adb_path = Path(adb_arg)
        if not adb_path.exists() or not os.access(adb_path, os.X_OK):
            raise ValueError(f"adb not found or not executable: {adb_arg}")
        return str(adb_path)

    # Try to find adb in PATH
    adb = shutil.which("adb")
    if adb:
        return adb

    raise ValueError("adb not found in PATH and not specified with --adb")


def run_adb(adb_path: str, serial: Optional[str], args: list, check: bool = True) -> subprocess.CompletedProcess:
    """Run an adb command."""
    cmd = [adb_path]
    if serial:
        cmd.extend(["-s", serial])
    cmd.extend(args)
    return subprocess.run(cmd, capture_output=True, text=True, check=check)


def check_device(adb_path: str, serial: Optional[str]) -> None:
    """Check if device is available."""
    result = run_adb(adb_path, serial, ["shell", "echo", "ok"], check=False)
    if result.returncode != 0:
        raise RuntimeError("Device not available or adb error")


def get_remote_manifest(adb_path: str, serial: Optional[str], source: str) -> Dict[str, Dict[str, str]]:
    """Get SHA256 hashes of files on remote using fixed shell script with safe path passing."""
    source_path = validate_source_path(source)

    # The source has been validated, so it is safe to quote for the remote shell.
    quoted_source = '"' + str(source_path).replace('"', '\\"') + '"'
    script = ("set -e; test -d %s; test -z \"$(find %s -type l -print -quit)\"; "
              "test -n \"$(find %s -type f -print -quit)\"; "
              "find %s -type f -exec sha256sum {} +" % (quoted_source, quoted_source, quoted_source, quoted_source))
    cmd = [adb_path]
    if serial:
        cmd.extend(["-s", serial])
    cmd.extend(["shell", script])

    result = subprocess.run(cmd, capture_output=True, text=True, check=False)

    if result.returncode != 0:
        raise RuntimeError("Unable to read remote vault manifest")

    manifest = {}
    for line in result.stdout.splitlines():
        parts = line.split(None, 1)
        if len(parts) != 2 or len(parts[0]) != 64 or any(c not in "0123456789abcdefABCDEF" for c in parts[0]):
            raise RuntimeError("Invalid remote vault manifest")
        file_path = parts[1]
        if any(ord(c) < 32 or ord(c) == 127 for c in file_path):
            raise RuntimeError("Invalid remote vault manifest")
        if not file_path.startswith(source_path.as_posix().rstrip('/') + '/'):
            raise RuntimeError("Invalid remote vault manifest")
        relative = file_path[len(source_path.as_posix().rstrip('/')) + 1:]
        if any(part in ('', '.', '..') for part in relative.split('/')) or file_path in manifest:
            raise RuntimeError("Invalid remote vault manifest")
        manifest[file_path] = {"sha256": parts[0].lower()}

    return manifest


def backup_vault(adb_path: str, serial: Optional[str], source: str, destination: Path) -> None:
    """Pull vault from device to destination."""
    source_path = validate_source_path(source)

    vault_dest = destination / "vault"
    vault_dest.mkdir(mode=0o700)

    cmd = [adb_path]
    if serial:
        cmd.extend(["-s", serial])
    cmd.extend(["pull", source, str(vault_dest)])

    result = subprocess.run(cmd, capture_output=True, text=True, check=False)

    if result.returncode != 0:
        raise RuntimeError("Unable to pull vault")


def quiesce_app(adb_path: str, serial: Optional[str]) -> None:
    """Stop the TyLog app without uninstalling or clearing data."""
    app_package = "org.tylog.tylog"
    result = run_adb(adb_path, serial, ["shell", "am", "force-stop", app_package], check=False)
    if result.returncode != 0:
        raise RuntimeError("Unable to stop TyLog app")


def compute_local_hashes(vault_path: Path, source: str = None) -> Dict[str, Dict[str, str]]:
    """Compute SHA256 hashes for local files without reading entire files."""
    hashes = {}
    source = source or "/sdcard/TyLog"
    root = vault_path / Path(source).name
    if not root.is_dir() or root.is_symlink():
        raise RuntimeError("Pulled vault layout is invalid")
    for file_path in root.rglob('*'):
        if file_path.is_symlink():
            raise RuntimeError("Symlinks are not allowed in backup")
        if file_path.is_file():
            # Construct relative path like remote: /sdcard/TyLog/subdir/file
            parts = list(file_path.relative_to(root).parts)
            if any('\n' in part or '\r' in part for part in parts):
                raise RuntimeError("Newline filenames are not supported")
            remote_style_path = source.rstrip('/') + '/' + '/'.join(parts)

            # Compute hash in chunks
            hasher = hashlib.sha256()
            try:
                with open(file_path, 'rb') as f:
                    while True:
                        chunk = f.read(1024 * 1024)  # 1MB chunks
                        if not chunk:
                            break
                        hasher.update(chunk)
                hashes[remote_style_path] = {"sha256": hasher.hexdigest()}
            except OSError as e:
                raise RuntimeError("Unable to hash pulled vault")

    return hashes


def backup_app_settings(adb_path: str, serial: Optional[str], destination: Path) -> Dict[str, Any]:
    """Backup app-local settings as best-effort."""
    settings_info = {"available": False, "error": None}

    app_package = "org.tylog.tylog"
    settings_dest = destination / "app_settings"

    # Try to backup app settings using tar
    cmd = [adb_path]
    if serial:
        cmd.extend(["-s", serial])
    cmd.extend(["exec-out", f"run-as {app_package} sh -c 'set --; for d in app_flutter files shared_prefs; do if test -d \"$d\"; then set -- \"$@\" \"$d\"; fi; done; test \"$#\" -gt 0 && tar -cf - \"$@\"'"])

    result = subprocess.run(cmd, capture_output=True, check=False)

    if result.returncode == 0 and result.stdout:
        settings_dest.mkdir(mode=0o700)
        tar_file = settings_dest / "app_settings.tar"
        try:
            with open(tar_file, 'wb') as f:
                f.write(result.stdout)
            # Set restrictive permissions
            os.chmod(tar_file, 0o600)
            settings_info["available"] = True
            settings_info["path"] = "app_settings/app_settings.tar"
        except OSError:
            settings_info["error"] = "App settings unavailable"
    else:
        settings_info["error"] = "App settings unavailable"

    return settings_info


def verify_backup(before_manifest: Dict[str, Dict[str, str]],
                  after_manifest: Dict[str, Dict[str, str]],
                  local_manifest: Dict[str, Dict[str, str]]) -> bool:
    """Verify that before/after/local manifests match."""
    if not before_manifest:
        return False
    before_paths = set(before_manifest.keys())
    after_paths = set(after_manifest.keys())
    local_paths = set(local_manifest.keys())

    # All three must have identical paths
    if before_paths != after_paths or before_paths != local_paths:
        return False

    # Check hashes are identical across all three
    for path in before_paths:
        before_hash = before_manifest[path].get("sha256")
        after_hash = after_manifest[path].get("sha256")
        local_hash = local_manifest[path].get("sha256")

        if before_hash != after_hash or before_hash != local_hash:
            return False

    return True


def _write_private(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    os.chmod(path, 0o600)


def main(argv=None):
    """Main entry point."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", help="Path to adb executable")
    parser.add_argument("--serial", help="Device serial number")
    parser.add_argument("--source", default="/sdcard/TyLog", help="Source path on device")
    parser.add_argument("--destination", required=True, help="Destination directory for backup")
    args = parser.parse_args(argv)

    result = {
        "success": False,
        "bytes": 0,
        "backup_size": 0,
        "settings": None,
        "error": None
    }

    try:
        # Validate arguments
        adb_path = get_adb_path(args.adb)
        destination = validate_destination(args.destination)
        validate_source_path(args.source)

        # Create destination directory
        destination.mkdir(mode=0o700)

        # Check device is available
        check_device(adb_path, args.serial)

        # Quiesce the app
        quiesce_app(adb_path, args.serial)

        # Get manifest before backup
        before_manifest = get_remote_manifest(adb_path, args.serial, args.source)
        if not before_manifest:
            raise RuntimeError("Source path does not exist or is empty on device")
        _write_private(destination / "manifest_before.json", before_manifest)

        # Backup vault
        backup_vault(adb_path, args.serial, args.source, destination)

        # Get manifest after backup
        after_manifest = get_remote_manifest(adb_path, args.serial, args.source)
        _write_private(destination / "manifest_after.json", after_manifest)

        # Compute local hashes
        vault_path = destination / "vault"
        local_manifest = compute_local_hashes(vault_path, args.source)
        _write_private(destination / "manifest_local.json", local_manifest)

        # Verify backup
        if not verify_backup(before_manifest, after_manifest, local_manifest):
            raise RuntimeError("Backup verification failed: file changes detected")

        # Backup app settings (best-effort)
        settings_info = backup_app_settings(adb_path, args.serial, destination)

        # Calculate total bytes
        total_bytes = 0
        for file_path in vault_path.rglob('*'):
            if file_path.is_file():
                total_bytes += file_path.stat().st_size

        # Create detailed manifest file (private, kept at destination only for auditing)
        manifest = {
            "source": args.source,
            "device_serial": args.serial,
            "files_count": len(local_manifest),
            "bytes": total_bytes,
            "settings": settings_info,
            "files": local_manifest
        }
        _write_private(destination / "manifest.json", manifest)
        _write_private(destination / "verified.json", {"verified": True})

        result["success"] = True
        result["bytes"] = total_bytes
        result["backup_size"] = total_bytes
        result["settings"] = settings_info

    except (ValueError, RuntimeError, OSError):
        result["error"] = "backup failed"

    print(json.dumps(result, sort_keys=True))
    return 0 if result["success"] else 1


if __name__ == "__main__":
    sys.exit(main())
