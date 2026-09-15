import importlib.util
import unittest
import numpy as np
import tempfile
import hashlib
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "embedding_reference", Path(__file__).parents[2] / "tool/embedding_reference.py"
)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class EmbeddingReferenceTest(unittest.TestCase):
    def test_pool_and_normalize(self):
        pooled = mod.mean_pool([[[1, 2], [3, 4]]], [[1, 0]])
        np.testing.assert_allclose(pooled, [[1, 2]])
        np.testing.assert_allclose(mod.normalize([[3, 4]]), [[0.6, 0.8]])

    def test_rejects_zero_and_nan(self):
        with self.assertRaisesRegex(ValueError, "zero_attention"):
            mod.mean_pool(np.ones((1, 2, 2)), [[0, 0]])
        with self.assertRaisesRegex(ValueError, "nonfinite_vector"):
            mod.normalize([[np.nan, 1]])
        with self.assertRaisesRegex(ValueError, "zero_or_nonfinite_norm"):
            mod.normalize([[0, 0]])

    def test_exact_order_and_ties_are_deterministic(self):
        vectors = np.array([[1, 0], [0, 1], [1, 0]], dtype=np.float32)
        self.assertEqual(
            [i for i, _ in mod.exact_cosine_top_k([1, 0], vectors, 3)], [0, 2, 1]
        )
        self.assertEqual(
            mod.exact_cosine_top_k([1, 0], vectors, 3),
            mod.exact_cosine_top_k([1, 0], vectors, 3),
        )
        with self.assertRaisesRegex(ValueError, "invalid_k"):
            mod.exact_cosine_top_k([1, 0], vectors, 0)
        with self.assertRaisesRegex(ValueError, "invalid_k"):
            mod.exact_cosine_top_k([1, 0], vectors, 4)

    def test_rejects_non_384_dimensions(self):
        with self.assertRaisesRegex(ValueError, "invalid_embedding_dimension"):
            mod.ensure_embedding_dimension(np.zeros((1, 2)))
        self.assertEqual(
            mod.ensure_embedding_dimension(np.zeros((1, 384))).shape, (1, 384)
        )

    def test_embed_supplies_missing_token_types(self):
        class Input:
            def __init__(self, name):
                self.name = name

        class Tokenizer:
            def __call__(self, texts, **kwargs):
                self.texts = texts
                return {
                    "input_ids": np.array([[1, 2]]),
                    "attention_mask": np.array([[1, 1]]),
                }

        class Session:
            def get_inputs(self):
                return [
                    Input("input_ids"),
                    Input("attention_mask"),
                    Input("token_type_ids"),
                ]

            def run(self, _, feed):
                self.feed = feed
                return [np.array([[[1.0, 0.0], [0.0, 1.0]]])]

        tokenizer, session = Tokenizer(), Session()
        result = mod.embed_texts(["hello"], "query", tokenizer, session)
        self.assertEqual(tokenizer.texts, ["query: hello"])
        self.assertIn("token_type_ids", session.feed)
        self.assertEqual(result.dtype, np.float32)

    def test_fake_runtime_is_deterministic(self):
        class Input:
            def __init__(self, name):
                self.name = name

        class Tokenizer:
            def __call__(self, texts, **_kwargs):
                return {
                    "input_ids": np.array([[1, 2]]),
                    "attention_mask": np.array([[1, 1]]),
                }

        class Session:
            def get_inputs(self):
                return [Input("input_ids"), Input("attention_mask")]

            def run(self, *_args):
                return [np.array([[[3.0, 4.0], [3.0, 4.0]]], dtype=np.float32)]

        first = mod.embed_texts(["same"], "passage", Tokenizer(), Session())
        second = mod.embed_texts(["same"], "passage", Tokenizer(), Session())
        np.testing.assert_array_equal(first, second)
        with tempfile.TemporaryDirectory() as directory:
            a, b = Path(directory) / "a.npz", Path(directory) / "b.npz"
            ids = np.asarray(["safe-id"])
            np.savez_compressed(a, ids=ids, vectors=first)
            np.savez_compressed(b, ids=ids, vectors=second)
            self.assertEqual(
                hashlib.sha256(a.read_bytes()).digest(),
                hashlib.sha256(b.read_bytes()).digest(),
            )


if __name__ == "__main__":
    unittest.main()
