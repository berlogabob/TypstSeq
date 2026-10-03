use ndarray::{Array2, Array3};
use ort::{
    session::{builder::GraphOptimizationLevel, Session},
    value::Tensor,
};
use std::{env, fs, time::Instant};
use tokenizers::{tokenizer::TruncationParams, Tokenizer};

// Compile the production path directly, without pulling in the Typst compiler.
#[path = "../../../packages/typst_flutter/rust/src/api/embedding.rs"]
mod embedding;
#[cfg(all(target_os = "macos", target_arch = "aarch64"))]
#[path = "../../../packages/typst_flutter/rust/src/lean_tokenizer.rs"]
mod lean_tokenizer;

fn token_length(tokenizer: &Tokenizer, text: &str) -> usize {
    tokenizer
        .encode(format!("passage: {text}"), true)
        .unwrap()
        .len()
}

fn generated_text(tokenizer: &Tokenizer, target: usize, index: usize) -> String {
    assert!((8..=512).contains(&target), "--tokens must be 8..=512");
    let mut text = format!("Note {index}: ");
    while token_length(tokenizer, &text) < target {
        text.push_str("a ");
    }
    assert_eq!(
        token_length(tokenizer, &text),
        target,
        "cannot generate exact token length"
    );
    text
}

fn length_summary(lengths: &[usize]) -> String {
    let mut sorted = lengths.to_vec();
    sorted.sort_unstable();
    let percentile =
        |percent: usize| sorted[((sorted.len() * percent).div_ceil(100)).saturating_sub(1)];
    format!(
        "tokens_min={} tokens_p50={} tokens_p95={} tokens_max={} tokens_mean={:.1}",
        sorted[0],
        percentile(50),
        percentile(95),
        sorted[sorted.len() - 1],
        sorted.iter().sum::<usize>() as f64 / sorted.len() as f64
    )
}

fn pool(hidden: &Array3<f32>, mask: &Array2<i64>) -> Vec<Vec<f32>> {
    (0..hidden.shape()[0])
        .map(|batch| {
            let mut out = vec![0.; hidden.shape()[2]];
            let mut count = 0.;
            for token in 0..hidden.shape()[1] {
                if mask[[batch, token]] != 0 {
                    count += 1.;
                    for dim in 0..out.len() {
                        out[dim] += hidden[[batch, token, dim]];
                    }
                }
            }
            for value in &mut out {
                *value /= count;
            }
            let norm = out.iter().map(|x| x * x).sum::<f32>().sqrt();
            for value in &mut out {
                *value /= norm;
            }
            out
        })
        .collect()
}

fn inputs(
    tokenizer: &Tokenizer,
    texts: &[String],
    width: usize,
) -> (Array2<i64>, Array2<i64>, Array2<i64>, Vec<usize>) {
    let mut ids = vec![0; texts.len() * width];
    let mut mask = vec![0; texts.len() * width];
    let mut lengths = Vec::with_capacity(texts.len());
    for (row, text) in texts.iter().enumerate() {
        let encoding = tokenizer.encode(format!("passage: {text}"), true).unwrap();
        let length = encoding.len().min(width);
        lengths.push(length);
        ids[row * width..row * width + length].copy_from_slice(
            &encoding.get_ids()[..length]
                .iter()
                .map(|x| *x as i64)
                .collect::<Vec<_>>(),
        );
        mask[row * width..row * width + length].copy_from_slice(
            &encoding.get_attention_mask()[..length]
                .iter()
                .map(|x| *x as i64)
                .collect::<Vec<_>>(),
        );
    }
    (
        Array2::from_shape_vec((texts.len(), width), ids).unwrap(),
        Array2::from_shape_vec((texts.len(), width), mask).unwrap(),
        Array2::zeros((texts.len(), width)),
        lengths,
    )
}

fn run(
    session: &mut Session,
    tokenizer: &Tokenizer,
    texts: &[String],
    batch: usize,
    dynamic: bool,
) -> (f64, Vec<Vec<f32>>, Vec<usize>) {
    let mut vectors = Vec::new();
    let mut lengths = Vec::new();
    let start = Instant::now();
    for group in texts.chunks(batch) {
        let width = if dynamic {
            group
                .iter()
                .map(|text| token_length(tokenizer, text))
                .max()
                .unwrap()
        } else {
            512
        };
        let (ids, mask, types, group_lengths) = inputs(tokenizer, group, width);
        let outputs = session
            .run(ort::inputs![
                Tensor::<i64>::from_array((ids.shape().to_vec(), ids.as_slice().unwrap().to_vec()))
                    .unwrap(),
                Tensor::<i64>::from_array((
                    mask.shape().to_vec(),
                    mask.as_slice().unwrap().to_vec()
                ))
                .unwrap(),
                Tensor::<i64>::from_array((
                    types.shape().to_vec(),
                    types.as_slice().unwrap().to_vec()
                ))
                .unwrap(),
            ])
            .unwrap();
        let (shape, data) = outputs[0].try_extract_tensor::<f32>().unwrap();
        let hidden = Array3::from_shape_vec(
            (shape[0] as usize, shape[1] as usize, shape[2] as usize),
            data.to_vec(),
        )
        .unwrap();
        vectors.extend(pool(&hidden, &mask));
        lengths.extend(group_lengths);
    }
    (
        start.elapsed().as_secs_f64() * 1000. / texts.len() as f64,
        vectors,
        lengths,
    )
}

fn session(model: &str, threads: Option<usize>, level3: bool) -> Session {
    let mut builder = Session::builder().unwrap();
    if level3 {
        builder = builder
            .with_optimization_level(GraphOptimizationLevel::Level3)
            .unwrap();
    }
    if let Some(threads) = threads {
        builder = builder.with_intra_threads(threads).unwrap();
    }
    builder.commit_from_file(model).unwrap()
}

fn main() {
    let args: Vec<_> = env::args().collect();
    assert!(args.len() >= 4, "usage: p05-ort-bench MODEL TOKENIZER REPO [--tokens N] [--texts-json FILE] [--dynamic] [--app] [--tokenize-only]");
    let (model, tokenizer_file, root) = (&args[1], &args[2], &args[3]);
    let mut target_tokens = None;
    let mut texts_json = None;
    let (mut dynamic, mut app, mut tokenize_only) = (false, false, false);
    let mut options = args[4..].iter();
    while let Some(option) = options.next() {
        match option.as_str() {
            "--tokens" => {
                target_tokens = Some(
                    options
                        .next()
                        .expect("--tokens needs N")
                        .parse::<usize>()
                        .unwrap(),
                )
            }
            "--texts-json" => texts_json = Some(options.next().expect("--texts-json needs FILE")),
            "--dynamic" => dynamic = true,
            "--app" => app = true,
            "--tokenize-only" => tokenize_only = true,
            _ => panic!("unknown option: {option}"),
        }
    }
    assert!(
        target_tokens.is_none() || texts_json.is_none(),
        "choose --tokens or --texts-json"
    );
    let mut source = String::new();
    for file in [
        "README.md",
        "lib/retrieval/chunking.dart",
        "lib/retrieval/semantic_search_controller.dart",
        "packages/typst_flutter/rust/src/api/embedding.rs",
    ] {
        source.push_str(&fs::read_to_string(format!("{root}/{file}")).unwrap());
        source.push('\n');
    }
    let chars: Vec<_> = source.chars().collect();
    let mut texts = Vec::new();
    let mut start = 0;
    while start < chars.len() && texts.len() < 200 {
        let end = (start + 800).min(chars.len());
        texts.push(chars[start..end].iter().collect());
        if end == chars.len() {
            break;
        }
        start = end - 120;
    }
    let seed = texts.clone();
    for index in texts.len()..200 {
        texts.push(format!(
            "{}\nPassage variant {index}: this chunk records a realistic indexed note.",
            seed[index % seed.len()]
        ));
    }
    let mut tokenizer = Tokenizer::from_file(tokenizer_file).unwrap();
    tokenizer.with_padding(None);
    tokenizer
        .with_truncation(Some(TruncationParams {
            max_length: 512,
            ..Default::default()
        }))
        .unwrap();
    if let Some(tokens) = target_tokens {
        texts = (0..200)
            .map(|index| generated_text(&tokenizer, tokens, index))
            .collect();
    }
    if let Some(path) = texts_json {
        texts = serde_json::from_str(&fs::read_to_string(path).unwrap()).unwrap();
    }
    assert!(!texts.is_empty(), "input corpus is empty");
    tokenizer.with_truncation(None).unwrap();
    let raw_lengths: Vec<_> = texts
        .iter()
        .map(|text| token_length(&tokenizer, text))
        .collect();
    println!(
        "raw {} truncated_chunks={}",
        length_summary(&raw_lengths),
        raw_lengths.iter().filter(|&&length| length > 512).count()
    );
    tokenizer
        .with_truncation(Some(TruncationParams {
            max_length: 512,
            ..Default::default()
        }))
        .unwrap();
    let lengths: Vec<_> = texts
        .iter()
        .map(|text| token_length(&tokenizer, text))
        .collect();
    println!(
        "{} (prefix + special tokens included; capped at 512)",
        length_summary(&lengths)
    );
    let perf = std::process::Command::new("sysctl")
        .args(["-n", "hw.perflevel0.logicalcpu"])
        .output()
        .ok()
        .and_then(|x| String::from_utf8(x.stdout).ok())
        .and_then(|x| x.trim().parse().ok());
    println!(
        "texts={} utf16_mean={} perf_threads={perf:?}",
        texts.len(),
        texts
            .iter()
            .map(|text| text.encode_utf16().count())
            .sum::<usize>()
            / texts.len()
    );
    #[cfg(all(target_os = "macos", target_arch = "aarch64"))]
    {
        let lean = lean_tokenizer::load(tokenizer_file, 512).unwrap();
        let start = Instant::now();
        let reference_encodings: Vec<_> = texts
            .iter()
            .map(|text| tokenizer.encode(format!("passage: {text}"), true).unwrap())
            .collect();
        let reference_ms = start.elapsed().as_secs_f64() * 1000. / texts.len() as f64;
        let start = Instant::now();
        let lean_encodings: Vec<_> = texts
            .iter()
            .map(|text| lean.encode(format!("passage: {text}"), true).unwrap())
            .collect();
        let lean_ms = start.elapsed().as_secs_f64() * 1000. / texts.len() as f64;
        for (reference, actual) in reference_encodings.iter().zip(&lean_encodings) {
            assert_eq!(reference.get_ids(), actual.get_ids());
            assert_eq!(reference.get_attention_mask(), actual.get_attention_mask());
        }
        println!("tokenizer_reference_warm_ms={reference_ms:.3} tokenizer_app_ms={lean_ms:.3} parity_encodings={}", texts.len());
    }
    if tokenize_only {
        return;
    }
    if app {
        drop(tokenizer);
        let call = |text: &String| {
            embedding::embed(
                model.clone(),
                tokenizer_file.clone(),
                "passage".into(),
                text.clone(),
            )
            .unwrap()
        };
        let cold = Instant::now();
        let first = call(&texts[0]);
        println!("app_cold_ms={:.3}", cold.elapsed().as_secs_f64() * 1000.);
        assert_eq!(
            first
                .vector
                .iter()
                .map(|value| value.to_bits())
                .collect::<Vec<_>>(),
            call(&texts[0])
                .vector
                .iter()
                .map(|value| value.to_bits())
                .collect::<Vec<_>>(),
            "cached inference changed vector bits"
        );
        for text in texts.iter().take(16) {
            call(text);
        }
        let start = Instant::now();
        for text in &texts {
            let result = call(text);
            assert!(result.finite && result.dimension == 384 && (result.norm - 1.).abs() < 0.0001);
        }
        let ms = start.elapsed().as_secs_f64() * 1000. / texts.len() as f64;
        println!("app-b1 ms_per_chunk={ms:.3} chunks_per_s={:.3}", 1000. / ms);
        return;
    }
    for (name, threads, level3, batch) in [
        ("default-b1", None, false, 1),
        ("level3-b1", None, true, 1),
        ("perf-b1", perf, false, 1),
        ("default-b16", None, false, 16),
    ] {
        let mut session = session(model, threads, level3);
        run(
            &mut session,
            &tokenizer,
            &texts[..16.min(texts.len())],
            batch,
            dynamic,
        );
        let (ms, vectors, _) = run(&mut session, &tokenizer, &texts, batch, dynamic);
        println!(
            "{name} dynamic={dynamic} ms_per_chunk={ms:.3} chunks_per_s={:.3} vector0_norm={:.6}",
            1000. / ms,
            vectors[0].iter().map(|x| x * x).sum::<f32>().sqrt()
        );
    }
}

#[cfg(test)]
mod tests {
    #[cfg(all(target_os = "macos", target_arch = "aarch64"))]
    #[test]
    fn synthetic_lean_tokenizer_parity() {
        use tokenizers::{models::unigram::Unigram, Tokenizer};
        let model = Unigram::from(
            vec![
                ("<unk>".into(), -10.),
                ("a".into(), -1.),
                ("aa".into(), -1.9),
                ("é".into(), -1.),
                ("研究".into(), -1.),
            ],
            Some(0),
            false,
        )
        .unwrap();
        let mut reference = Tokenizer::new(model);
        reference
            .with_truncation(Some(tokenizers::TruncationParams {
                max_length: 512,
                ..Default::default()
            }))
            .unwrap();
        let directory = std::path::Path::new(file!())
            .parent()
            .unwrap()
            .parent()
            .unwrap()
            .join("target");
        std::fs::create_dir_all(&directory).unwrap();
        let path = directory.join("bench-tokenizer-fixture.json");
        reference.save(&path, false).unwrap();
        let lean = super::lean_tokenizer::load(path.to_str().unwrap(), 512).unwrap();
        for text in [
            String::new(),
            "aa a é研究 👩‍👩‍👧".into(),
            "a".repeat(1200),
            "unknown symbols ?!".into(),
        ] {
            for kind in ["query", "passage"] {
                let input = format!("{kind}: {text}");
                let expected = reference.encode(input.as_str(), true).unwrap();
                let actual = lean.encode(input.as_str(), true).unwrap();
                assert_eq!(actual.get_ids(), expected.get_ids());
                assert_eq!(actual.get_attention_mask(), expected.get_attention_mask());
            }
        }
    }

    #[test]
    fn generated_lengths_and_summary() {
        use tokenizers::{
            models::wordlevel::WordLevel, pre_tokenizers::whitespace::Whitespace, Tokenizer,
        };
        let model = WordLevel::builder()
            .vocab([("[UNK]".into(), 0), ("a".into(), 1)].into_iter().collect())
            .unk_token("[UNK]".into())
            .build()
            .unwrap();
        let mut tokenizer = Tokenizer::new(model);
        tokenizer.with_pre_tokenizer(Some(Whitespace));
        for target in [8, 128, 256, 512] {
            let text = super::generated_text(&tokenizer, target, 17);
            assert_eq!(super::token_length(&tokenizer, &text), target);
        }
        let texts: Vec<String> = vec!["a".into(), "a a a".into()];
        let lengths: Vec<_> = texts
            .iter()
            .map(|text| super::token_length(&tokenizer, text))
            .collect();
        let width = *lengths.iter().max().unwrap();
        let (_, masks, types, actual_lengths) = super::inputs(&tokenizer, &texts, width);
        assert_eq!(actual_lengths, lengths);
        assert_eq!(
            masks.sum_axis(ndarray::Axis(1)).to_vec(),
            lengths
                .iter()
                .map(|&length| length as i64)
                .collect::<Vec<_>>()
        );
        assert!(types.iter().all(|&value| value == 0));
        assert_eq!(
            super::length_summary(&[512, 8, 256, 128]),
            "tokens_min=8 tokens_p50=128 tokens_p95=512 tokens_max=512 tokens_mean=226.0"
        );
    }
}
