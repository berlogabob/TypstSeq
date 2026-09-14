import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch, MagicMock

sys.path.insert(0, str(Path(__file__).parents[2] / "tool"))
import backup_android_vault


class TestSourcePathValidation(unittest.TestCase):
    """Test source path validation."""

    def test_valid_sdcard_path(self):
        """Valid /sdcard path should be accepted."""
        result = backup_android_vault.validate_source_path("/sdcard/TyLog")
        self.assertEqual(result, Path("/sdcard/TyLog"))

    def test_valid_storage_emulated_path(self):
        """Valid /storage/emulated/0 path should be accepted."""
        result = backup_android_vault.validate_source_path("/storage/emulated/0/TyLog")
        self.assertEqual(result, Path("/storage/emulated/0/TyLog"))

    def test_source_path_with_spaces(self):
        self.assertEqual(backup_android_vault.validate_source_path("/sdcard/My Vault"), Path("/sdcard/My Vault"))

    def test_invalid_root_path(self):
        """Path outside allowed roots should be rejected."""
        with self.assertRaises(ValueError) as ctx:
            backup_android_vault.validate_source_path("/data/app")
        self.assertIn("must be under", str(ctx.exception))

    def test_path_with_pipe(self):
        """Path with pipe metacharacter should be rejected."""
        with self.assertRaises(ValueError) as ctx:
            backup_android_vault.validate_source_path("/sdcard/TyLog|cat")
        self.assertIn("unsafe characters", str(ctx.exception))

    def test_path_with_semicolon(self):
        """Path with semicolon should be rejected."""
        with self.assertRaises(ValueError) as ctx:
            backup_android_vault.validate_source_path("/sdcard/TyLog;rm -rf")
        self.assertIn("unsafe characters", str(ctx.exception))

    def test_path_with_dollar_sign(self):
        """Path with dollar sign should be rejected."""
        with self.assertRaises(ValueError) as ctx:
            backup_android_vault.validate_source_path("/sdcard/$TyLog")
        self.assertIn("unsafe characters", str(ctx.exception))

    def test_path_with_backtick(self):
        """Path with backtick should be rejected."""
        with self.assertRaises(ValueError) as ctx:
            backup_android_vault.validate_source_path("/sdcard/`TyLog`")
        self.assertIn("unsafe characters", str(ctx.exception))


class TestDestinationValidation(unittest.TestCase):
    """Test destination path validation."""

    @patch("backup_android_vault.get_repo_root")
    def test_destination_must_be_new(self, mock_repo):
        """Destination that already exists should be rejected."""
        mock_repo.return_value = Path("/tmp/repo")

        with tempfile.TemporaryDirectory() as tmpdir:
            existing = Path(tmpdir) / "existing"
            existing.mkdir()

            with self.assertRaises(ValueError) as ctx:
                backup_android_vault.validate_destination(str(existing))
            self.assertIn("must be new", str(ctx.exception))

    @patch("backup_android_vault.get_repo_root")
    def test_destination_cannot_be_in_repo(self, mock_repo):
        """Destination inside repository should be rejected."""
        with tempfile.TemporaryDirectory() as tmpdir:
            repo_root = Path(tmpdir) / "repo"
            repo_root.mkdir()
            mock_repo.return_value = repo_root

            with self.assertRaises(ValueError) as ctx:
                backup_android_vault.validate_destination(str(repo_root / "backup"))
            self.assertIn("must be outside repository", str(ctx.exception))

    @patch("backup_android_vault.get_repo_root")
    def test_destination_parent_must_exist(self, mock_repo):
        """Destination parent directory must exist."""
        mock_repo.return_value = Path("/tmp/repo")

        with self.assertRaises(ValueError) as ctx:
            backup_android_vault.validate_destination("/nonexistent/path/backup")
        self.assertIn("Parent directory does not exist", str(ctx.exception))

    @patch("backup_android_vault.get_repo_root")
    def test_valid_destination(self, mock_repo):
        """Valid new destination outside repo should be accepted."""
        with tempfile.TemporaryDirectory() as tmpdir:
            repo_root = Path(tmpdir) / "repo"
            repo_root.mkdir()
            mock_repo.return_value = repo_root

            backup_dir = Path(tmpdir) / "backups"
            backup_dir.mkdir()

            result = backup_android_vault.validate_destination(str(backup_dir / "new_backup"))
            self.assertTrue(str(result).startswith(str(backup_dir.resolve())))


class TestRemoteManifest(unittest.TestCase):
    """Test remote manifest retrieval."""

    @patch("subprocess.run")
    def test_get_remote_manifest_success(self, mock_run):
        """Successfully retrieve remote manifest."""
        mock_run.return_value = MagicMock(
            returncode=0,
            stdout="""%s  /sdcard/TyLog/file1.db
%s  /sdcard/TyLog/file2.txt
""" % ("a" * 64, "b" * 64),
            stderr=""
        )

        result = backup_android_vault.get_remote_manifest("adb", None, "/sdcard/TyLog")

        self.assertEqual(len(result), 2)
        self.assertIn("/sdcard/TyLog/file1.db", result)
        self.assertEqual(result["/sdcard/TyLog/file1.db"]["sha256"], "a" * 64)

    @patch("subprocess.run")
    def test_get_remote_manifest_empty_source(self, mock_run):
        """Handle empty source directory."""
        mock_run.return_value = MagicMock(
            returncode=0,
            stdout="",
            stderr=""
        )

        result = backup_android_vault.get_remote_manifest("adb", None, "/sdcard/TyLog")
        self.assertEqual(len(result), 0)

    @patch("subprocess.run")
    def test_get_remote_manifest_with_spaces(self, mock_run):
        """Handle files with spaces in path."""
        mock_run.return_value = MagicMock(
            returncode=0,
            stdout="%s  /sdcard/TyLog/my file.db\n" % ("a" * 64),
            stderr=""
        )

        result = backup_android_vault.get_remote_manifest("adb", None, "/sdcard/TyLog")

        self.assertIn("/sdcard/TyLog/my file.db", result)
        self.assertEqual(result["/sdcard/TyLog/my file.db"]["sha256"], "a" * 64)


class TestLocalHashes(unittest.TestCase):
    """Test local hash computation."""

    def test_compute_local_hashes(self):
        """Compute hashes for local files."""
        with tempfile.TemporaryDirectory() as tmpdir:
            vault_path = Path(tmpdir) / "vault"
            tylog_path = vault_path / "TyLog"
            tylog_path.mkdir(parents=True)

            # Create test files
            file1 = tylog_path / "file1.db"
            file1.write_bytes(b"content1")

            file2 = tylog_path / "file2.txt"
            file2.write_bytes(b"content2")

            result = backup_android_vault.compute_local_hashes(vault_path, "/sdcard/TyLog")

            self.assertEqual(len(result), 2)
            self.assertIn("/sdcard/TyLog/file1.db", result)
            self.assertIn("/sdcard/TyLog/file2.txt", result)

            # Verify hash values are correct
            expected_hash1 = hashlib.sha256(b"content1").hexdigest()
            self.assertEqual(result["/sdcard/TyLog/file1.db"]["sha256"], expected_hash1)

    def test_compute_local_hashes_with_spaces(self):
        """Handle files with spaces in names."""
        with tempfile.TemporaryDirectory() as tmpdir:
            vault_path = Path(tmpdir) / "vault"
            tylog_path = vault_path / "TyLog"
            tylog_path.mkdir(parents=True)

            file_with_spaces = tylog_path / "my file.db"
            file_with_spaces.write_bytes(b"content")

            result = backup_android_vault.compute_local_hashes(vault_path, "/sdcard/TyLog")

            self.assertIn("/sdcard/TyLog/my file.db", result)

    def test_compute_local_hashes_nested_dirs(self):
        """Handle nested directory structures."""
        with tempfile.TemporaryDirectory() as tmpdir:
            vault_path = Path(tmpdir) / "vault"
            tylog_path = vault_path / "TyLog" / "subdir"
            tylog_path.mkdir(parents=True)

            file1 = tylog_path / "nested.db"
            file1.write_bytes(b"nested_content")

            result = backup_android_vault.compute_local_hashes(vault_path, "/sdcard/TyLog")

            self.assertIn("/sdcard/TyLog/subdir/nested.db", result)


class TestBackupVerification(unittest.TestCase):
    """Test backup verification logic."""

    def test_verify_matching_manifests(self):
        """Verify succeeds when all manifests match."""
        manifest = {
            "/sdcard/TyLog/file1.db": {"sha256": "a" * 64},
            "/sdcard/TyLog/file2.txt": {"sha256": "b" * 64}
        }

        result = backup_android_vault.verify_backup(manifest, manifest, manifest)
        self.assertTrue(result)

    def test_verify_hash_mismatch(self):
        """Verify fails when hashes differ."""
        before = {
            "/sdcard/TyLog/file1.db": {"sha256": "a" * 64}
        }
        after = {
            "/sdcard/TyLog/file1.db": {"sha256": "c" * 64}
        }

        result = backup_android_vault.verify_backup(before, after, before)
        self.assertFalse(result)

    def test_verify_path_mismatch(self):
        """Verify fails when paths differ."""
        before = {
            "/sdcard/TyLog/file1.db": {"sha256": "a" * 64}
        }
        after = {
            "/sdcard/TyLog/file2.db": {"sha256": "a" * 64}
        }

        result = backup_android_vault.verify_backup(before, after, before)
        self.assertFalse(result)


class TestAppSettings(unittest.TestCase):
    """Test app settings backup."""

    @patch("subprocess.run")
    def test_backup_app_settings_success(self, mock_run):
        """Successfully backup app settings."""
        mock_run.return_value = MagicMock(
            returncode=0,
            stdout=b"fake tar data"
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            result = backup_android_vault.backup_app_settings("adb", None, Path(tmpdir))

            self.assertTrue(result["available"])
            self.assertIsNone(result.get("error"))

            # Verify file was created with correct permissions
            settings_tar = Path(tmpdir) / "app_settings" / "app_settings.tar"
            self.assertTrue(settings_tar.exists())
            self.assertEqual(oct(settings_tar.stat().st_mode)[-3:], "600")

    @patch("subprocess.run")
    def test_backup_app_settings_unavailable(self, mock_run):
        """Handle unavailable app settings gracefully."""
        mock_run.return_value = MagicMock(
            returncode=1,
            stdout=b"",
            stderr="error"
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            result = backup_android_vault.backup_app_settings("adb", None, Path(tmpdir))

            self.assertFalse(result["available"])
            self.assertIsNotNone(result.get("error"))


class TestMainIntegration(unittest.TestCase):
    """Integration tests for main function."""

    @patch("backup_android_vault.check_device")
    @patch("backup_android_vault.get_remote_manifest")
    @patch("backup_android_vault.backup_vault")
    @patch("backup_android_vault.quiesce_app")
    @patch("backup_android_vault.get_adb_path")
    @patch("backup_android_vault.validate_destination")
    @patch("subprocess.run")
    def test_main_missing_destination(self, mock_run, mock_dest, mock_adb, mock_quiesce,
                                     mock_backup, mock_manifest, mock_device):
        """Main should fail if destination is required but missing."""
        with self.assertRaises(SystemExit):
            backup_android_vault.main(["--source", "/sdcard/TyLog"])

    @patch("backup_android_vault.get_adb_path")
    def test_main_invalid_source_path(self, mock_adb):
        """Main should fail with invalid source path."""
        mock_adb.return_value = "/usr/bin/adb"

        with tempfile.TemporaryDirectory() as tmpdir:
            result = backup_android_vault.main([
                "--source", "/data/app",
                "--destination", tmpdir
            ])
            self.assertEqual(result, 1)

    @patch("backup_android_vault.check_device")
    @patch("backup_android_vault.get_remote_manifest")
    @patch("backup_android_vault.backup_app_settings")
    @patch("backup_android_vault.quiesce_app")
    @patch("backup_android_vault.get_adb_path")
    @patch("backup_android_vault.validate_destination")
    def test_main_successful_backup(self, mock_dest, mock_adb, mock_quiesce,
                                   mock_settings, mock_manifest, mock_device):
        """Main should succeed with valid arguments."""
        with tempfile.TemporaryDirectory() as tmpdir:
            backup_dir = Path(tmpdir) / "backup"
            mock_adb.return_value = "/usr/bin/adb"
            mock_dest.return_value = backup_dir
            content = b"test"
            test_manifest = {"/sdcard/TyLog/file1.db": {
                "sha256": hashlib.sha256(content).hexdigest()}}
            mock_manifest.return_value = test_manifest
            mock_settings.return_value = {"available": False}
            def fake_pull(_adb, _serial, _source, destination):
                vault_dir = destination / "vault" / "TyLog"
                vault_dir.mkdir(parents=True)
                (vault_dir / "file1.db").write_bytes(content)

            with patch("backup_android_vault.backup_vault", side_effect=fake_pull):
                result = backup_android_vault.main([
                    "--source", "/sdcard/TyLog",
                    "--destination", str(backup_dir)
                ])

            self.assertEqual(result, 0)
            self.assertTrue((backup_dir / "verified.json").exists())

    @patch("backup_android_vault.check_device")
    @patch("backup_android_vault.get_remote_manifest")
    @patch("backup_android_vault.backup_app_settings")
    @patch("backup_android_vault.quiesce_app")
    @patch("backup_android_vault.get_adb_path", return_value="/usr/bin/adb")
    @patch("backup_android_vault.validate_destination")
    def test_main_changed_source_leaves_no_verified_marker(self, mock_dest, _adb,
                                                           _quiesce, _settings,
                                                           mock_manifest, _device):
        with tempfile.TemporaryDirectory() as tmpdir:
            backup_dir = Path(tmpdir) / "backup"
            mock_dest.return_value = backup_dir
            path = "/sdcard/TyLog/file1.db"
            mock_manifest.side_effect = [
                {path: {"sha256": hashlib.sha256(b"before").hexdigest()}},
                {path: {"sha256": hashlib.sha256(b"after").hexdigest()}},
            ]

            def fake_pull(_adb, _serial, _source, destination):
                vault_dir = destination / "vault" / "TyLog"
                vault_dir.mkdir(parents=True)
                (vault_dir / "file1.db").write_bytes(b"before")

            with patch("backup_android_vault.backup_vault", side_effect=fake_pull):
                result = backup_android_vault.main([
                    "--source", "/sdcard/TyLog",
                    "--destination", str(backup_dir),
                ])

            self.assertEqual(result, 1)
            self.assertTrue((backup_dir / "vault" / "TyLog" / "file1.db").exists())
            self.assertFalse((backup_dir / "verified.json").exists())


class TestEdgeCases(unittest.TestCase):
    """Test edge cases and error handling."""

    def test_path_with_double_slash(self):
        """Path with double slash should still be valid."""
        with self.assertRaises(ValueError):
            backup_android_vault.validate_source_path("/sdcard/TyLog//nested")

    def test_truncated_local_file_detected(self):
        """Truncated local file during backup should be detected."""
        with tempfile.TemporaryDirectory() as tmpdir:
            vault_path = Path(tmpdir) / "vault"
            tylog_path = vault_path / "TyLog"
            tylog_path.mkdir(parents=True)

            # Create a truncated file
            file1 = tylog_path / "file1.db"
            file1.write_bytes(b"partial")

            # Simulate before manifest with larger file
            before_manifest = {
                "/sdcard/TyLog/file1.db": {"sha256": "original_hash"}
            }

            local_manifest = backup_android_vault.compute_local_hashes(vault_path, "/sdcard/TyLog")
            after_manifest = local_manifest

            # Verification should fail due to hash mismatch
            result = backup_android_vault.verify_backup(before_manifest, after_manifest, local_manifest)
            self.assertFalse(result)

    @patch("subprocess.run")
    def test_adb_command_with_serial(self, mock_run):
        """ADB command should include serial if provided."""
        mock_run.return_value = MagicMock(
            returncode=0,
            stdout="%s  /sdcard/TyLog/file1.db\n" % ("a" * 64),
            stderr=""
        )

        backup_android_vault.get_remote_manifest("adb", "device123", "/sdcard/TyLog")

        # Verify the command includes the serial
        call_args = mock_run.call_args[0][0]
        self.assertIn("-s", call_args)
        self.assertIn("device123", call_args)


if __name__ == "__main__":
    unittest.main()
