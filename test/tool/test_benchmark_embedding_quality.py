import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np


ROOT = Path(__file__).parents[2]
SPEC = importlib.util.spec_from_file_location(
    "quality", ROOT / "tool/benchmark_embedding_quality.py"
)
quality = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(quality)


class EmbeddingQualityTest(unittest.TestCase):
    def test_recall_at_ten_and_missing_judged_vector(self):
        records = []
        ids = []
        vectors = []
        for lang_index, lang in enumerate(("en", "pt", "ru")):
            for index in range(30):
                query_id = f"q-{lang}-{index}"
                chunk_id = f"c-{lang}-{index}"
                passage_lang = (
                    {"en": "pt", "pt": "en", "ru": "en"}[lang]
                    if index < 10
                    else lang
                )
                vector = np.zeros(384, dtype=np.float32)
                vector[lang_index * 30 + index] = 1
                ids.extend((query_id, chunk_id))
                vectors.extend((vector.copy(), vector.copy()))
                records.append({
                    "query_id": query_id,
                    "query_language": lang,
                    "query": "private query text",
                    "relevant": [{
                        "chunk_id": chunk_id,
                        "source_id": f"s-{lang}-{index}",
                        "start": 0,
                        "end": 1,
                        "language": passage_lang,
                    }],
                })

        result = quality.evaluate(records, np.asarray(ids), np.asarray(vectors))
        self.assertEqual((result["status"], result["hits"]), ("PASS", 90))
        self.assertEqual(result["cross_language"]["queries"], 30)
        with self.assertRaisesRegex(ValueError, "missing_relevant_vectors"):
            quality.evaluate(records, np.asarray(ids[:-1]), np.asarray(vectors[:-1]))

        with tempfile.TemporaryDirectory() as directory:
            pack_path = Path(directory) / "private-pack.jsonl"
            vectors_path = Path(directory) / "private-vectors.npz"
            pack_path.write_text(
                "\n".join(json.dumps(record) for record in records) + "\n",
                encoding="utf-8",
            )
            np.savez_compressed(
                vectors_path, ids=np.asarray(ids), vectors=np.asarray(vectors)
            )
            result = quality.run(pack_path, vectors_path)
            self.assertEqual(result["status"], "PASS")
            self.assertEqual(len(result["pack_sha256"]), 64)


if __name__ == "__main__":
    unittest.main()
