#[derive(Debug, Clone)]
pub struct EmbeddingResult {
    pub vector: Vec<f32>,
    pub dimension: u32,
    pub norm: f32,
    pub finite: bool,
}

#[cfg(any(all(target_os = "android", target_arch = "aarch64"), all(target_os = "macos", target_arch = "aarch64")))]
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

#[cfg(any(all(target_os = "android", target_arch = "aarch64"), all(target_os = "macos", target_arch = "aarch64")))]
struct Loaded {
    model_path: String,
    tokenizer_path: String,
    tokenizer: crate::lean_tokenizer::LeanTokenizer,
    session: ort::session::Session,
}

// ponytail: one cached model behind a global lock — loading costs seconds, so
// load once per (model, tokenizer) and serialize inference (the plan allows one
// embedding at a time). Per-path cache if several models ever coexist.
#[cfg(any(all(target_os = "android", target_arch = "aarch64"), all(target_os = "macos", target_arch = "aarch64")))]
static LOADED: std::sync::Mutex<Option<Loaded>> = std::sync::Mutex::new(None);

#[cfg(any(all(target_os = "android", target_arch = "aarch64"), all(target_os = "macos", target_arch = "aarch64")))]
pub fn embed(
    model_path: String,
    tokenizer_path: String,
    kind: String,
    text: String,
) -> Result<EmbeddingResult, String> {
    use ndarray::{Array2, Array3};
    use ort::{session::Session, value::Tensor};

    if kind != "query" && kind != "passage" {
        return Err("invalid_kind".into());
    }
    let mut guard = LOADED.lock().map_err(|_| "model_lock")?;
    let stale = match guard.as_ref() {
        Some(l) => l.model_path != model_path || l.tokenizer_path != tokenizer_path,
        None => true,
    };
    if stale {
        *guard = None;
        // Lean vocabulary map: the stock Unigram trie held ~384 MiB.
        let tokenizer = crate::lean_tokenizer::load(&tokenizer_path, 512)?;
        let session = Session::builder()
            .map_err(|_| "session_builder")?
            .commit_from_file(&model_path)
            .map_err(|_| "model_load")?;
        *guard = Some(Loaded {
            model_path: model_path.clone(),
            tokenizer_path: tokenizer_path.clone(),
            tokenizer,
            session,
        });
    }
    let loaded = guard.as_mut().ok_or("model_lock")?;
    let encoding = loaded
        .tokenizer
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
    let outputs = loaded
        .session
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

#[cfg(not(any(all(target_os = "android", target_arch = "aarch64"), all(target_os = "macos", target_arch = "aarch64"))))]
pub fn embed(
    _model_path: String,
    _tokenizer_path: String,
    _kind: String,
    _text: String,
) -> Result<EmbeddingResult, String> {
    Err("embedding_unsupported_platform".into())
}
