use ndarray::{Array2, Array3};
use ort::{session::{builder::GraphOptimizationLevel, Session}, value::Tensor};
use std::{env, fs, time::Instant};
use tokenizers::{tokenizer::TruncationParams, Tokenizer};

fn pool(hidden: &Array3<f32>, mask: &Array2<i64>) -> Vec<Vec<f32>> {
    (0..hidden.shape()[0]).map(|batch| {
        let mut out = vec![0.; hidden.shape()[2]];
        let mut count = 0.;
        for token in 0..hidden.shape()[1] {
            if mask[[batch, token]] != 0 {
                count += 1.;
                for dim in 0..out.len() { out[dim] += hidden[[batch, token, dim]]; }
            }
        }
        for value in &mut out { *value /= count; }
        let norm = out.iter().map(|x| x * x).sum::<f32>().sqrt();
        for value in &mut out { *value /= norm; }
        out
    }).collect()
}

fn inputs(tokenizer: &Tokenizer, texts: &[String], width: usize) -> (Array2<i64>, Array2<i64>, Array2<i64>, Vec<usize>) {
    let mut ids = vec![0; texts.len() * width];
    let mut mask = vec![0; texts.len() * width];
    let mut lengths = Vec::with_capacity(texts.len());
    for (row, text) in texts.iter().enumerate() {
        let encoding = tokenizer.encode(format!("passage: {text}"), true).unwrap();
        let length = encoding.len().min(width);
        lengths.push(length);
        ids[row * width..row * width + length].copy_from_slice(&encoding.get_ids()[..length].iter().map(|x| *x as i64).collect::<Vec<_>>());
        mask[row * width..row * width + length].copy_from_slice(&encoding.get_attention_mask()[..length].iter().map(|x| *x as i64).collect::<Vec<_>>());
    }
    (Array2::from_shape_vec((texts.len(), width), ids).unwrap(), Array2::from_shape_vec((texts.len(), width), mask).unwrap(), Array2::zeros((texts.len(), width)), lengths)
}

fn run(session: &mut Session, tokenizer: &Tokenizer, texts: &[String], batch: usize) -> (f64, Vec<Vec<f32>>, Vec<usize>) {
    let mut vectors = Vec::new();
    let mut lengths = Vec::new();
    let start = Instant::now();
    for group in texts.chunks(batch) {
        let (ids, mask, types, group_lengths) = inputs(tokenizer, group, 512);
        let outputs = session.run(ort::inputs![
            Tensor::<i64>::from_array((ids.shape().to_vec(), ids.as_slice().unwrap().to_vec())).unwrap(),
            Tensor::<i64>::from_array((mask.shape().to_vec(), mask.as_slice().unwrap().to_vec())).unwrap(),
            Tensor::<i64>::from_array((types.shape().to_vec(), types.as_slice().unwrap().to_vec())).unwrap(),
        ]).unwrap();
        let (shape, data) = outputs[0].try_extract_tensor::<f32>().unwrap();
        let hidden = Array3::from_shape_vec((shape[0] as usize, shape[1] as usize, shape[2] as usize), data.to_vec()).unwrap();
        vectors.extend(pool(&hidden, &mask));
        lengths.extend(group_lengths);
    }
    (start.elapsed().as_secs_f64() * 1000. / texts.len() as f64, vectors, lengths)
}

fn session(model: &str, threads: Option<usize>, level3: bool) -> Session {
    let mut builder = Session::builder().unwrap();
    if level3 { builder = builder.with_optimization_level(GraphOptimizationLevel::Level3).unwrap(); }
    if let Some(threads) = threads { builder = builder.with_intra_threads(threads).unwrap(); }
    builder.commit_from_file(model).unwrap()
}

fn main() {
    let args: Vec<_> = env::args().collect();
    let (model, tokenizer_file, root) = (&args[1], &args[2], &args[3]);
    let mut source = String::new();
    for file in ["README.md", "lib/retrieval/chunking.dart", "lib/retrieval/semantic_search_controller.dart", "packages/typst_flutter/rust/src/api/embedding.rs"] {
        source.push_str(&fs::read_to_string(format!("{root}/{file}")).unwrap());
        source.push('\n');
    }
    let chars: Vec<_> = source.chars().collect();
    let mut texts = Vec::new();
    let mut start = 0;
    while start < chars.len() && texts.len() < 200 {
        let end = (start + 800).min(chars.len());
        texts.push(chars[start..end].iter().collect());
        if end == chars.len() { break; }
        start = end - 120;
    }
    let seed = texts.clone();
    for index in texts.len()..200 {
        texts.push(format!("{}\nPassage variant {index}: this chunk records a realistic indexed note.", seed[index % seed.len()]));
    }
    let mut tokenizer = Tokenizer::from_file(tokenizer_file).unwrap();
    tokenizer.with_truncation(Some(TruncationParams { max_length: 512, ..Default::default() })).unwrap();
    let perf = std::process::Command::new("sysctl").args(["-n", "hw.perflevel0.logicalcpu"]).output().ok().and_then(|x| String::from_utf8(x.stdout).ok()).and_then(|x| x.trim().parse().ok());
    println!("texts={} chars={} perf_threads={perf:?}", texts.len(), texts.iter().map(String::len).sum::<usize>() / texts.len());
    for (name, threads, level3, batch) in [("default-b1", None, false, 1), ("level3-b1", None, true, 1), ("perf-b1", perf, false, 1), ("default-b16", None, false, 16)] {
        let mut session = session(model, threads, level3);
        let (_, _, lengths) = run(&mut session, &tokenizer, &texts[..16], batch);
        let (ms, vectors, _) = run(&mut session, &tokenizer, &texts, batch);
        let mean_tokens = lengths.iter().sum::<usize>() as f64 / lengths.len() as f64;
        println!("{name} ms_per_chunk={ms:.3} chunks_per_s={:.3} mean_tokens={mean_tokens:.1} vector0_norm={:.6}", 1000. / ms, vectors[0].iter().map(|x| x*x).sum::<f32>().sqrt());
    }
}
