#[derive(Debug, Clone)]
pub struct EmbeddingResult {
    pub vector: Vec<f32>,
    pub dimension: u32,
    pub norm: f32,
    pub finite: bool,
}

#[cfg(target_os = "android")]
fn pool_normalize(
    hidden: &ndarray::Array3<f32>,
    mask: &ndarray::Array2<i64>,
) -> Result<Vec<f32>, String> {
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
        return Err("zero_attention".into());
    }
    let norm = out
        .iter()
        .map(|x| x / count)
        .map(|x| x * x)
        .sum::<f32>()
        .sqrt();
    if !norm.is_finite() || norm == 0.0 {
        return Err("invalid_norm".into());
    }
    for x in &mut out {
        *x /= count * norm;
    }
    Ok(out)
}

#[cfg(target_os = "android")]
pub fn embed(
    model_path: String,
    tokenizer_path: String,
    kind: String,
    text: String,
) -> Result<EmbeddingResult, String> {
    use ndarray::{Array2, Array3};
    use ort::{session::Session, value::Tensor};
    use tokenizers::{tokenizer::TruncationParams, Tokenizer};

    if kind != "query" && kind != "passage" {
        return Err("invalid_kind".into());
    }
    let mut tokenizer = Tokenizer::from_file(tokenizer_path).map_err(|_| "tokenizer_load")?;
    tokenizer
        .with_truncation(Some(TruncationParams {
            max_length: 512,
            ..Default::default()
        }))
        .map_err(|_| "tokenizer_config")?;
    let encoding = tokenizer
        .encode(format!("{kind}: {text}"), true)
        .map_err(|_| "tokenize")?;
    let ids: Vec<i64> = encoding.get_ids().iter().map(|id| *id as i64).collect();
    let mask: Vec<i64> = encoding
        .get_attention_mask()
        .iter()
        .map(|value| *value as i64)
        .collect();
    if ids.len() > 512 {
        return Err("sequence_too_long".into());
    }
    let ids = Array2::from_shape_vec((1, ids.len()), ids).map_err(|_| "input_shape")?;
    let mask = Array2::from_shape_vec((1, mask.len()), mask).map_err(|_| "input_shape")?;
    let types = Array2::<i64>::zeros(ids.raw_dim());
    let mut session = Session::builder()
        .map_err(|_| "session_builder")?
        .commit_from_file(model_path)
        .map_err(|_| "model_load")?;
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
        return Err("output_shape".into());
    }
    let hidden = Array3::from_shape_vec(
        (shape[0] as usize, shape[1] as usize, shape[2] as usize),
        data.to_vec(),
    )
    .map_err(|_| "output_shape")?;
    let vector = pool_normalize(&hidden, &mask)?;
    if vector.len() != 384 {
        return Err("invalid_dimension".into());
    }
    let norm = vector.iter().map(|x| x * x).sum::<f32>().sqrt();
    Ok(EmbeddingResult {
        dimension: vector.len() as u32,
        norm,
        finite: vector.iter().all(|x| x.is_finite()),
        vector,
    })
}

#[cfg(not(target_os = "android"))]
pub fn embed(
    _model_path: String,
    _tokenizer_path: String,
    _kind: String,
    _text: String,
) -> Result<EmbeddingResult, String> {
    Err("embedding_requires_android".into())
}
