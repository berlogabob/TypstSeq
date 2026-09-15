use ndarray::{Array2, Array3};
use ort::{session::Session, value::Tensor};
use std::{env, process, time::Instant};
use tokenizers::{tokenizer::TruncationParams, Tokenizer};

fn pool_normalize(hidden: &Array3<f32>, mask: &Array2<i64>) -> Result<Vec<f32>, &'static str> {
    let dim = hidden.shape()[2];
    let mut out = vec![0.0; dim];
    let mut count = 0.0;
    for token in 0..hidden.shape()[1] {
        if mask[[0, token]] != 0 {
            count += 1.0;
            for d in 0..dim {
                out[d] += hidden[[0, token, d]];
            }
        }
    }
    if count == 0.0 {
        return Err("zero_attention");
    }
    let norm = out
        .iter()
        .map(|x| x / count)
        .map(|x| x * x)
        .sum::<f32>()
        .sqrt();
    if !norm.is_finite() || norm == 0.0 {
        return Err("invalid_norm");
    }
    for x in &mut out {
        *x /= count * norm;
    }
    Ok(out)
}

fn run(model: &str, tokenizer_file: &str, kind: &str, text: &str) -> Result<(), &'static str> {
    if kind != "query" && kind != "passage" {
        return Err("invalid_kind");
    }
    let mut tokenizer = Tokenizer::from_file(tokenizer_file).map_err(|_| "tokenizer_load")?;
    tokenizer
        .with_truncation(Some(TruncationParams {
            max_length: 512,
            ..Default::default()
        }))
        .map_err(|_| "tokenizer_config")?;
    let encoding = tokenizer
        .encode(format!("{kind}: {text}"), true)
        .map_err(|_| "tokenize")?;
    let ids: Vec<i64> = encoding.get_ids().iter().map(|x| *x as i64).collect();
    let mask: Vec<i64> = encoding
        .get_attention_mask()
        .iter()
        .map(|x| *x as i64)
        .collect();
    if ids.len() > 512 {
        return Err("sequence_too_long");
    }
    let ids = Array2::from_shape_vec((1, ids.len()), ids).map_err(|_| "input_shape")?;
    let mask = Array2::from_shape_vec((1, mask.len()), mask).map_err(|_| "input_shape")?;
    let types = Array2::<i64>::zeros(ids.raw_dim());
    let mut session = Session::builder()
        .map_err(|_| "session_builder")?
        .commit_from_file(model)
        .map_err(|_| "model_load")?;
    let start = Instant::now();
    let outputs = session
        .run(ort::inputs![
            Tensor::<i64>::from_array((ids.shape().to_vec(), ids.as_slice().unwrap().to_vec()))
                .map_err(|_| "input_tensor")?,
            Tensor::<i64>::from_array((mask.shape().to_vec(), mask.as_slice().unwrap().to_vec()))
                .map_err(|_| "input_tensor")?,
            Tensor::<i64>::from_array((types.shape().to_vec(), types.as_slice().unwrap().to_vec()))
                .map_err(|_| "input_tensor")?,
        ])
        .map_err(|_| "inference")?;
    let (shape, data) = outputs[0]
        .try_extract_tensor::<f32>()
        .map_err(|_| "output_tensor")?;
    if shape.len() != 3 {
        return Err("output_shape");
    }
    let hidden = Array3::from_shape_vec(
        (shape[0] as usize, shape[1] as usize, shape[2] as usize),
        data.to_vec(),
    )
    .map_err(|_| "output_shape")?;
    let vector = pool_normalize(&hidden, &mask)?;
    if vector.len() != 384 {
        return Err("invalid_dimension");
    }
    println!(
        "dimension={} norm={:.6} finite={} elapsed_ms={}",
        vector.len(),
        vector.iter().map(|x| x * x).sum::<f32>().sqrt(),
        vector.iter().all(|x| x.is_finite()),
        start.elapsed().as_secs_f64() * 1000.0
    );
    Ok(())
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 5 {
        eprintln!("error: usage");
        process::exit(2);
    }
    if let Err(error) = run(&args[1], &args[2], &args[3], &args[4]) {
        eprintln!("error: {error}");
        process::exit(2);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn pooling_and_normalization() {
        let hidden = Array3::from_shape_vec((1, 2, 2), vec![1., 0., 0., 1.]).unwrap();
        let mask = Array2::from_shape_vec((1, 2), vec![1, 1]).unwrap();
        let v = pool_normalize(&hidden, &mask).unwrap();
        assert!((v[0] - 0.7071067).abs() < 0.00001);
        assert!((v[1] - 0.7071067).abs() < 0.00001);
    }
}
