import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[2] / "tool"))
import tylog_scale_fixture


class TyLogScaleFixtureTest(unittest.TestCase):
    def test_reproducible_and_references_are_valid(self):
        with tempfile.TemporaryDirectory() as root:
            first = Path(root) / "first"
            second = Path(root) / "second"
            a = tylog_scale_fixture.generate(first, nodes=12, edges=40, chunks=20, seed=7)
            b = tylog_scale_fixture.generate(second, nodes=12, edges=40, chunks=20, seed=7)
            self.assertEqual(a, b)
            for name in ("nodes", "edges", "chunks"):
                self.assertEqual((first / (name + ".jsonl")).read_bytes(), (second / (name + ".jsonl")).read_bytes())
            node_ids = {json.loads(line)["id"] for line in (first / "nodes.jsonl").read_text().splitlines()}
            for line in (first / "edges.jsonl").read_text().splitlines():
                edge = json.loads(line)
                self.assertIn(edge["from"], node_ids)
                self.assertIn(edge["to"], node_ids)
            for line in (first / "chunks.jsonl").read_text().splitlines():
                self.assertIn(json.loads(line)["node_id"], node_ids)
            digest = hashlib.sha256((first / "nodes.jsonl").read_bytes()).hexdigest()
            self.assertEqual(digest, a["files"]["nodes"]["sha256"])

    def test_rejects_nonempty_directory_and_invalid_counts(self):
        with tempfile.TemporaryDirectory() as root:
            output = Path(root) / "fixture"
            output.mkdir()
            (output / "keep").write_text("x")
            with self.assertRaises(FileExistsError):
                tylog_scale_fixture.generate(output, nodes=1, edges=0, chunks=0)
            with self.assertRaises(ValueError):
                tylog_scale_fixture.generate(Path(root) / "bad", nodes=-1)

    def test_chunks_follow_parent_content_and_seed_changes_content(self):
        with tempfile.TemporaryDirectory() as root:
            first = Path(root) / "first"
            changed = Path(root) / "changed"
            manifest = tylog_scale_fixture.generate(first, nodes=7, edges=0, chunks=7, seed=3)
            tylog_scale_fixture.generate(changed, nodes=7, edges=0, chunks=7, seed=4)
            nodes = {json.loads(line)["id"]: json.loads(line) for line in (first / "nodes.jsonl").read_text().splitlines()}
            for line in (first / "chunks.jsonl").read_text().splitlines():
                chunk = json.loads(line)
                parent = nodes[chunk["node_id"]]
                self.assertEqual(chunk["language"], parent["language"])
                self.assertEqual(chunk["text"], parent["content"][chunk["offset"]:chunk["offset"] + len(chunk["text"])])
                self.assertEqual(chunk["source_content_sha256"], parent["content_sha256"])
            self.assertNotEqual((first / "nodes.jsonl").read_bytes(), (changed / "nodes.jsonl").read_bytes())
            self.assertEqual(manifest["counts"], {"nodes": 7, "edges": 0, "chunks": 7})
            self.assertEqual(sum(manifest["distribution"]["languages"].values()), 7)
            self.assertEqual(sum(manifest["distribution"]["types"].values()), 7)

    def test_zero_counts_create_hashed_empty_jsonl_files(self):
        with tempfile.TemporaryDirectory() as root:
            output = Path(root) / "empty"
            manifest = tylog_scale_fixture.generate(output, nodes=0, edges=0, chunks=0)
            self.assertEqual(manifest["counts"], {"nodes": 0, "edges": 0, "chunks": 0})
            for name, metadata in manifest["files"].items():
                self.assertEqual(metadata["bytes"], 0)
                self.assertEqual(metadata["sha256"], hashlib.sha256(b"").hexdigest())


if __name__ == "__main__":
    unittest.main()
