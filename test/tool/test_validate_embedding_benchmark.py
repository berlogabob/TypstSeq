import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[2]
SPEC = importlib.util.spec_from_file_location(
    "validator", ROOT / "tool/validate_embedding_benchmark.py"
)
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)


def pack(**changes):
    records = []
    for lang in ("en", "pt", "ru"):
        for index in range(30):
            passage_lang = (
                "pt"
                if lang == "en" and index < 10
                else "en"
                if lang == "pt" and index < 10
                else "en"
                if lang == "ru" and index < 10
                else lang
            )
            records.append(
                {
                    "query_id": f"q-{lang}-{index}",
                    "query_language": lang,
                    "query": f"query {lang} {index}",
                    "relevant": [
                        {
                            "chunk_id": f"chunk-{index}",
                            "source_id": "source-1",
                            "start": 0,
                            "end": 4,
                            "language": passage_lang,
                        }
                    ],
                }
            )
    for index, value in changes.items():
        if isinstance(index, int):
            records[index] = value
    return records


class ValidateEmbeddingPackTest(unittest.TestCase):
    def run_pack(self, records):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "pack.jsonl"
            path.write_text(
                "\n".join(json.dumps(r) for r in records) + "\n", encoding="utf-8"
            )
            return validator.validate(path)

    def test_valid_pack_counts_and_digest(self):
        result = self.run_pack(pack())
        self.assertEqual(
            (result["queries"], result["en"], result["pt"], result["ru"]),
            (90, 30, 30, 30),
        )
        self.assertEqual(len(result["sha256"]), 64)

    def test_rejects_count_language_duplicate_offset_unsafe_no_relevant(self):
        with self.assertRaisesRegex(validator.PackError, "query_count"):
            self.run_pack(pack()[:-1])
        bad_language = pack()
        bad_language[0]["query_language"] = "fr"
        with self.assertRaisesRegex(validator.PackError, "invalid_query_language"):
            self.run_pack(bad_language)
        duplicate = pack()
        duplicate[1]["query_id"] = duplicate[0]["query_id"]
        with self.assertRaisesRegex(validator.PackError, "duplicate_query_id"):
            self.run_pack(duplicate)
        bad_offset = pack()
        bad_offset[0]["relevant"][0]["end"] = 0
        with self.assertRaisesRegex(validator.PackError, "invalid_offsets"):
            self.run_pack(bad_offset)
        unsafe = pack()
        unsafe[0]["relevant"][0]["source_id"] = "../secret"
        with self.assertRaisesRegex(validator.PackError, "unsafe_source_id"):
            self.run_pack(unsafe)
        no_relevant = pack()
        no_relevant[0]["relevant"] = []
        with self.assertRaisesRegex(validator.PackError, "no_relevant_passage"):
            self.run_pack(no_relevant)

    def test_rejects_cross_language_shortfall(self):
        records = pack()
        for record in records:
            record["relevant"][0]["language"] = record["query_language"]
        with self.assertRaisesRegex(validator.PackError, "cross_language_counts"):
            self.run_pack(records)

    def test_cli_output_contains_no_private_values(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "pack.jsonl"
            path.write_text(
                "\n".join(json.dumps(r) for r in pack()) + "\n", encoding="utf-8"
            )
            import subprocess
            import sys

            output = subprocess.check_output(
                [
                    sys.executable,
                    str(ROOT / "tool/validate_embedding_benchmark.py"),
                    str(path),
                ],
                text=True,
            )
            self.assertNotIn("query en 0", output)
            self.assertNotIn("q-en-0", output)
            self.assertNotIn(str(path), output)

    def test_cli_missing_path_does_not_echo_private_path(self):
        import subprocess
        import sys

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "private-secret-vault" / "missing.jsonl"
            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "tool/validate_embedding_benchmark.py"),
                    str(path),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 2)
            self.assertEqual(result.stderr.strip(), "error: input_unavailable")
            self.assertNotIn(str(path), result.stderr)


if __name__ == "__main__":
    unittest.main()
