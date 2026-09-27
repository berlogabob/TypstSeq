//! XLM-R Unigram tokenizer with a flat vocabulary map.
//!
//! `tokenizers`' own `Unigram` model keeps a per-byte `HashMap` trie that held
//! ~384 MiB for the 250k-token multilingual-e5 vocabulary, over half of the
//! A24 embedding memory budget. This model runs the same Viterbi search
//! (`Unigram::encode_optimized`) over a plain `HashMap`, and everything else —
//! normalizer, Metaspace pre-tokenizer, added/special tokens, truncation and
//! the `<s> … </s>` template — is `tokenizers`' own code built from the same
//! `tokenizer.json`. Token IDs must match `tokenizers::Tokenizer` exactly; see
//! the parity test below.

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use serde::Deserialize;
use tokenizers::{
    AddedToken, DecoderWrapper, Model, NormalizerWrapper, PostProcessorWrapper,
    PreTokenizerWrapper, Token, TokenizerImpl, Trainer, TruncationParams,
};

/// Same constant as `tokenizers::models::unigram::model::K_UNK_PENALTY`.
const UNK_PENALTY: f64 = 10.0;

pub type LeanTokenizer = TokenizerImpl<
    LeanUnigram,
    NormalizerWrapper,
    PreTokenizerWrapper,
    PostProcessorWrapper,
    DecoderWrapper,
>;

pub struct LeanUnigram {
    ids: HashMap<Box<str>, u32>,
    vocab: Vec<(Box<str>, f64)>,
    unk_id: u32,
    min_score: f64,
    max_token_bytes: usize,
}

impl LeanUnigram {
    fn new(vocab: Vec<(String, f64)>, unk_id: u32) -> Self {
        let mut ids = HashMap::with_capacity(vocab.len());
        let mut min_score = f64::INFINITY;
        let mut max_token_bytes = 0;
        let vocab: Vec<(Box<str>, f64)> = vocab
            .into_iter()
            .enumerate()
            .map(|(id, (token, score))| {
                // Later duplicates win, as in `Unigram::from`.
                ids.insert(token.clone().into_boxed_str(), id as u32);
                min_score = min_score.min(score);
                max_token_bytes = max_token_bytes.max(token.len());
                (token.into_boxed_str(), score)
            })
            .collect();
        Self {
            ids,
            vocab,
            unk_id,
            min_score,
            max_token_bytes,
        }
    }

    /// Port of `Unigram::encode_optimized` (with `fuse_unk`, no byte fallback).
    fn encode(&self, sentence: &str) -> Vec<(u32, String)> {
        if sentence.is_empty() {
            return Vec::new();
        }
        #[derive(Clone)]
        struct Node {
            id: u32,
            score: f64,
            starts_at: Option<usize>,
        }
        let size = sentence.len();
        let unk_score = self.min_score - UNK_PENALTY;
        let mut best = vec![
            Node {
                id: 0,
                score: 0.0,
                starts_at: None
            };
            size + 1
        ];
        let mut start = 0;
        while start < size {
            let here = best[start].score;
            let mblen = sentence[start..].chars().next().unwrap().len_utf8();
            let mut has_single_node = false;
            // Shortest prefix first, like the trie's common_prefix_search, so
            // equal scores resolve to the same node.
            let limit = (start + self.max_token_bytes).min(size);
            for end in start + 1..=limit {
                if !sentence.is_char_boundary(end) {
                    continue;
                }
                let Some(&id) = self.ids.get(&sentence[start..end]) else {
                    continue;
                };
                let candidate = self.vocab[id as usize].1 + here;
                let node = &mut best[end];
                if node.starts_at.is_none() || candidate > node.score {
                    *node = Node {
                        id,
                        score: candidate,
                        starts_at: Some(start),
                    };
                }
                if end - start == mblen {
                    has_single_node = true;
                }
            }
            if !has_single_node {
                let candidate = unk_score + here;
                let node = &mut best[start + mblen];
                if node.starts_at.is_none() || candidate > node.score {
                    *node = Node {
                        id: self.unk_id,
                        score: candidate,
                        starts_at: Some(start),
                    };
                }
            }
            start += mblen;
        }
        let mut pieces: Vec<String> = Vec::new();
        let mut unk_run: Vec<&str> = Vec::new();
        let mut end = size;
        while end > 0 {
            let node = &best[end];
            let start = node.starts_at.unwrap();
            if node.id == self.unk_id {
                unk_run.push(&sentence[start..end]);
            } else {
                if !unk_run.is_empty() {
                    unk_run.reverse();
                    pieces.push(unk_run.concat());
                    unk_run.clear();
                }
                pieces.push(sentence[start..end].to_string());
            }
            end = start;
        }
        if !unk_run.is_empty() {
            unk_run.reverse();
            pieces.push(unk_run.concat());
        }
        pieces.reverse();
        pieces
            .into_iter()
            .map(|piece| {
                let id = self.ids.get(piece.as_str()).copied().unwrap_or(self.unk_id);
                (id, piece)
            })
            .collect()
    }
}

impl Model for LeanUnigram {
    type Trainer = NoTrainer;

    fn tokenize(&self, sequence: &str) -> tokenizers::Result<Vec<Token>> {
        let mut offset = 0;
        Ok(self
            .encode(sequence)
            .into_iter()
            .map(|(id, piece)| {
                let offsets = (offset, offset + piece.len());
                offset += piece.len();
                Token::new(id, piece, offsets)
            })
            .collect())
    }

    fn token_to_id(&self, token: &str) -> Option<u32> {
        self.ids.get(token).copied()
    }

    fn id_to_token(&self, id: u32) -> Option<String> {
        self.vocab.get(id as usize).map(|(token, _)| token.to_string())
    }

    fn get_vocab(&self) -> HashMap<String, u32> {
        self.ids.iter().map(|(k, v)| (k.to_string(), *v)).collect()
    }

    fn get_vocab_size(&self) -> usize {
        self.vocab.len()
    }

    fn save(&self, _folder: &Path, _prefix: Option<&str>) -> tokenizers::Result<Vec<PathBuf>> {
        Err("LeanUnigram is load-only".into())
    }

    fn get_trainer(&self) -> NoTrainer {
        NoTrainer
    }
}

/// `Model` requires a trainer type; this model is inference-only.
pub struct NoTrainer;

impl Trainer for NoTrainer {
    type Model = LeanUnigram;

    fn should_show_progress(&self) -> bool {
        false
    }

    fn train(&self, _model: &mut LeanUnigram) -> tokenizers::Result<Vec<AddedToken>> {
        Err("LeanUnigram is load-only".into())
    }

    fn feed<I, S, F>(&mut self, _iterator: I, _process: F) -> tokenizers::Result<()>
    where
        I: Iterator<Item = S> + Send,
        S: AsRef<str> + Send,
        F: Fn(&str) -> tokenizers::Result<Vec<String>> + Sync,
    {
        Ok(())
    }
}

#[derive(Deserialize)]
struct TokenizerJson {
    normalizer: Option<NormalizerWrapper>,
    pre_tokenizer: Option<PreTokenizerWrapper>,
    post_processor: Option<PostProcessorWrapper>,
    added_tokens: Vec<AddedTokenJson>,
    model: ModelJson,
}

#[derive(Deserialize)]
struct ModelJson {
    #[serde(rename = "type")]
    kind: String,
    unk_id: Option<u32>,
    vocab: Vec<(String, f64)>,
}

#[derive(Deserialize)]
struct AddedTokenJson {
    content: String,
    single_word: bool,
    lstrip: bool,
    rstrip: bool,
    normalized: bool,
    special: bool,
}

/// Loads an XLM-R style Unigram `tokenizer.json` with truncation to
/// `max_length` tokens (special tokens included).
pub fn load(path: &str, max_length: usize) -> Result<LeanTokenizer, String> {
    let file = std::fs::File::open(path).map_err(|_| "tokenizer_load")?;
    let json: TokenizerJson =
        serde_json::from_reader(std::io::BufReader::new(file)).map_err(|_| "tokenizer_load")?;
    if json.model.kind != "Unigram" {
        return Err("tokenizer_model".into());
    }
    let unk_id = json.model.unk_id.ok_or("tokenizer_model")?;
    let mut tokenizer = TokenizerImpl::new(LeanUnigram::new(json.model.vocab, unk_id));
    tokenizer
        .with_normalizer(json.normalizer)
        .map_err(|_| "tokenizer_config")?;
    tokenizer.with_pre_tokenizer(json.pre_tokenizer);
    tokenizer.with_post_processor(json.post_processor);
    let added: Vec<AddedToken> = json
        .added_tokens
        .into_iter()
        .map(|t| {
            AddedToken::from(t.content, t.special)
                .single_word(t.single_word)
                .lstrip(t.lstrip)
                .rstrip(t.rstrip)
                .normalized(t.normalized)
        })
        .collect();
    let _ = tokenizer.add_special_tokens(added);
    tokenizer
        .with_truncation(Some(TruncationParams {
            max_length,
            ..Default::default()
        }))
        .map_err(|_| "tokenizer_config")?;
    Ok(tokenizer)
}

#[cfg(test)]
mod tests {
    use tokenizers::tokenizer::{Tokenizer, TruncationParams};

    /// Token-ID parity with `tokenizers::Tokenizer` on the real vocabulary.
    /// Set TYLOG_TOKENIZER_JSON (and optionally TYLOG_TOKENIZER_CASES, a JSON
    /// array of strings); skipped otherwise because the file is not in Git.
    #[test]
    fn matches_reference_tokenizer() {
        let Ok(path) = std::env::var("TYLOG_TOKENIZER_JSON") else {
            eprintln!("skipped: TYLOG_TOKENIZER_JSON not set");
            return;
        };
        let mut reference = Tokenizer::from_file(&path).unwrap();
        reference
            .with_truncation(Some(TruncationParams {
                max_length: 512,
                ..Default::default()
            }))
            .unwrap();
        let lean = super::load(&path, 512).unwrap();

        let mut cases: Vec<String> = vec![
            String::new(),
            " ".into(),
            "offline smoke text".into(),
            "a <s> b </s> c <unk><mask><pad>".into(),
            "tabs\tand\nnewlines\r\n  and   runs".into(),
            "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} family".into(),
            "e\u{0301} vs \u{00E9}; ﬁ ligature; ① ② ③".into(),
            "\u{0} control \u{7} chars \u{FEFF} bom".into(),
            "пример очень длинного предложения ".repeat(80),
            "Palavras portuguesas: ação, coração, pão ".repeat(60),
            "#strong[bold] = Heading\n- [ ] task @2026-09-27 #tag".into(),
        ];
        if let Ok(extra) = std::env::var("TYLOG_TOKENIZER_CASES") {
            let text = std::fs::read_to_string(extra).unwrap();
            cases.extend(serde_json::from_str::<Vec<String>>(&text).unwrap());
        }
        let mut checked = 0;
        for case in &cases {
            for kind in ["query", "passage"] {
                let input = format!("{kind}: {case}");
                let want = reference.encode(input.as_str(), true).unwrap();
                let got = lean.encode(input.as_str(), true).unwrap();
                assert_eq!(got.get_ids(), want.get_ids(), "ids differ for {input:?}");
                assert_eq!(
                    got.get_attention_mask(),
                    want.get_attention_mask(),
                    "mask differs for {input:?}"
                );
                checked += 1;
            }
        }
        eprintln!("tokenizer parity: {checked} encodings identical");
    }
}
