import json
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[2] / "tool"))
import tylog_corpus_manifest


class TyLogCorpusManifestTest(unittest.TestCase):
    def _make_test_corpus(self, root, files_dict):
        """Helper to create test corpus with given files."""
        root.mkdir(parents=True, exist_ok=True)
        for rel_path, content in files_dict.items():
            path = root / rel_path
            path.parent.mkdir(parents=True, exist_ok=True)
            if isinstance(content, bytes):
                path.write_bytes(content)
            else:
                path.write_text(content)

    def test_deterministic_digest_same_seed(self):
        """Digest should be reproducible for same corpus."""
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir) / "corpus"
            files = {
                "file1.txt": "content1",
                "file2.txt": "content2",
                "subdir/file3.txt": "content3"
            }
            self._make_test_corpus(root, files)

            output1 = Path(tmpdir) / "manifest1.json"
            output2 = Path(tmpdir) / "manifest2.json"

            tylog_corpus_manifest.manifest(str(root), str(output1))
            tylog_corpus_manifest.manifest(str(root), str(output2))

            manifest1 = json.loads(output1.read_text())
            manifest2 = json.loads(output2.read_text())

            self.assertEqual(manifest1["corpus_digest"], manifest2["corpus_digest"])

    def test_digest_changes_with_content(self):
        """Digest should change when file content changes."""
        with tempfile.TemporaryDirectory() as tmpdir:
            root1 = Path(tmpdir) / "corpus1"
            root2 = Path(tmpdir) / "corpus2"

            self._make_test_corpus(root1, {"file.txt": "original"})
            self._make_test_corpus(root2, {"file.txt": "modified"})

            output1 = Path(tmpdir) / "manifest1.json"
            output2 = Path(tmpdir) / "manifest2.json"

            tylog_corpus_manifest.manifest(str(root1), str(output1))
            tylog_corpus_manifest.manifest(str(root2), str(output2))

            digest1 = json.loads(output1.read_text())["corpus_digest"]
            digest2 = json.loads(output2.read_text())["corpus_digest"]

            self.assertNotEqual(digest1, digest2)

    def test_no_paths_in_json_output(self):
        """JSON output should not contain file paths."""
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir) / "corpus"
            self._make_test_corpus(root, {
                "secret_file.txt": "secret",
                "subdir/hidden.py": "code"
            })

            output = Path(tmpdir) / "manifest.json"
            tylog_corpus_manifest.manifest(str(root), str(output))

            manifest_text = output.read_text()
            self.assertNotIn("secret_file", manifest_text)
            self.assertNotIn("hidden", manifest_text)
            self.assertNotIn("subdir", manifest_text)

    def test_output_file_permissions(self):
        """Output file should have mode 0600."""
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir) / "corpus"
            self._make_test_corpus(root, {"file.txt": "content"})

            output = Path(tmpdir) / "manifest.json"
            tylog_corpus_manifest.manifest(str(root), str(output))

            mode = stat.S_IMODE(output.stat().st_mode)
            self.assertEqual(mode, 0o600)

    def test_aggregate_contains_expected_fields(self):
        """Manifest should contain required aggregate fields."""
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir) / "corpus"
            self._make_test_corpus(root, {
                "file1.txt": "x",
                "file2.typ": "y",
                "subdir/file3.py": "z" * 100
            })

            output = Path(tmpdir) / "manifest.json"
            tylog_corpus_manifest.manifest(str(root), str(output))

            manifest = json.loads(output.read_text())

            self.assertIn("schema_version", manifest)
            self.assertIn("generated_utc", manifest)
            self.assertIn("corpus_digest", manifest)
            self.assertIn("aggregate", manifest)

            agg = manifest["aggregate"]
            self.assertIn("total_files", agg)
            self.assertIn("total_bytes", agg)
            self.assertIn("typ_file_count", agg)
            self.assertIn("extensions", agg)
            self.assertIn("size_buckets", agg)

            self.assertEqual(agg["total_files"], 3)
            self.assertEqual(agg["typ_file_count"], 1)

    def test_symlink_rejection(self):
        """Symlinks should be rejected during walk."""
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir) / "corpus"
            root.mkdir()
            (root / "file.txt").write_text("content")
            (root / "link.txt").symlink_to(root / "file.txt")

            output = Path(tmpdir) / "manifest.json"
            tylog_corpus_manifest.manifest(str(root), str(output))

            manifest = json.loads(output.read_text())
            self.assertEqual(manifest["aggregate"]["total_files"], 1)

    def test_control_char_rejection(self):
        """Files with control chars should be skipped."""
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir) / "corpus"
            root.mkdir()

            valid_file = root / "valid.txt"
            valid_file.write_text("content")

            try:
                invalid_file = root / "invalid\nname.txt"
                invalid_file.write_text("should be skipped")
            except (OSError, ValueError):
                pass

            output = Path(tmpdir) / "manifest.json"
            tylog_corpus_manifest.manifest(str(root), str(output))

            manifest = json.loads(output.read_text())
            self.assertEqual(manifest["aggregate"]["total_files"], 1)

    def test_rejects_missing_root(self):
        """Should reject missing root directory."""
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir) / "nonexistent"
            output = Path(tmpdir) / "manifest.json"

            with self.assertRaises(ValueError):
                tylog_corpus_manifest.manifest(str(root), str(output))

    def test_rejects_output_inside_root(self):
        """Should reject output file inside root directory."""
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir) / "corpus"
            root.mkdir()

            output = root / "manifest.json"

            with self.assertRaises(ValueError):
                tylog_corpus_manifest.manifest(str(root), str(output))

    def test_rejects_existing_output(self):
        """Should reject existing output file."""
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir) / "corpus"
            self._make_test_corpus(root, {"file.txt": "content"})

            output = Path(tmpdir) / "manifest.json"
            output.write_text("{}")

            with self.assertRaises(ValueError):
                tylog_corpus_manifest.manifest(str(root), str(output))

    def test_extension_counting(self):
        """Should count extensions correctly."""
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir) / "corpus"
            self._make_test_corpus(root, {
                "file1.txt": "a",
                "file2.txt": "b",
                "file3.py": "c",
                "no_ext": "d"
            })

            output = Path(tmpdir) / "manifest.json"
            tylog_corpus_manifest.manifest(str(root), str(output))

            manifest = json.loads(output.read_text())
            exts = manifest["aggregate"]["extensions"]

            self.assertEqual(exts.get(".txt"), 2)
            self.assertEqual(exts.get(".py"), 1)
            self.assertEqual(exts.get("(none)"), 1)

    def test_size_bucket_distribution(self):
        """Should distribute files into correct size buckets."""
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir) / "corpus"
            files = {
                "tiny.txt": "x",
                "small.txt": "x" * 5 * 1024,
                "medium.txt": "x" * 50 * 1024,
                "large.txt": "x" * 500 * 1024,
                "xlarge.txt": "x" * 5 * 1024 * 1024,
            }
            self._make_test_corpus(root, files)

            output = Path(tmpdir) / "manifest.json"
            tylog_corpus_manifest.manifest(str(root), str(output))

            manifest = json.loads(output.read_text())
            buckets = manifest["aggregate"]["size_buckets"]

            self.assertGreater(buckets["0-1k"], 0)
            self.assertGreater(buckets["1k-10k"], 0)
            self.assertGreater(buckets["100k-1m"], 0)
            self.assertGreater(buckets["1m-10m"], 0)

    def test_py_compile(self):
        """Module should compile without syntax errors."""
        import py_compile
        tool_path = Path(__file__).parents[2] / "tool" / "tylog_corpus_manifest.py"
        py_compile.compile(str(tool_path), doraise=True)


if __name__ == "__main__":
    unittest.main()
