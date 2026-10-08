# Local embedding benchmark (2026-10-08)

Seed 7. Models: G = unsloth/embeddinggemma-2-GGUF (768/256 dims); e5 = intfloat/multilingual-e5-small (384 dims). Retrieval corpus 2994; eligible screenshots 2286. Body prefix: 1,600 characters; Gemma additionally 6,000. Retrieval documents exclude title for ALL query kinds.
Folder counts (selected/scanned): notes 518/545, ideas 51/51, projects 1/2, daily 924/972, articles 1500/4956, screenshots 2286/2385.
Detected retrieval languages: {'ru': 2571, 'en': 416, 'pt': 7}. Screenshot languages: {'en': 1795, 'pt': 31, 'ru': 460}.
Skip counts: {'path/content privacy': 126, 'empty body': 47, 'no header': 12, 'parse/read ValueError': 3, 'financial screenshots': 99, 'articles not sampled': 3344}.

## Experiment 1 — known-item retrieval
| Kind / query language (n) | e5 R1/R5/R10/MRR10 | Model | R1/R5/R10/MRR10 | Δ vs e5 | Paired 95% CI Δ (R1;R5;R10;MRR) | W/L/T |
|---|---|---|---|---|---|---|
| title/all (300) | 0.583/0.743/0.793/0.657 | G768-1600 | 0.730/0.857/0.873/0.783 | 0.147/0.113/0.080/0.126 | [0.103,0.193]; [0.073,0.150]; [0.047,0.113]; [0.091,0.161] | 90/27/183 |
| title/all (300) | 0.583/0.743/0.793/0.657 | G256-1600 | 0.710/0.843/0.863/0.770 | 0.127/0.100/0.070/0.113 | [0.080,0.177]; [0.063,0.137]; [0.037,0.107]; [0.078,0.148] | 85/35/180 |
| title/all (300) | 0.583/0.743/0.793/0.657 | G768-6000 | 0.733/0.860/0.873/0.786 | 0.150/0.117/0.080/0.129 | [0.103,0.197]; [0.080,0.153]; [0.043,0.117]; [0.093,0.165] | 89/28/183 |
| title/all (300) | 0.583/0.743/0.793/0.657 | G256-6000 | 0.707/0.843/0.867/0.770 | 0.123/0.100/0.073/0.113 | [0.077,0.173]; [0.063,0.137]; [0.040,0.110]; [0.078,0.149] | 89/36/175 |
| title/ru (274) | 0.588/0.745/0.796/0.660 | G768-1600 | 0.737/0.861/0.880/0.789 | 0.150/0.117/0.084/0.129 | [0.102,0.197]; [0.077,0.161]; [0.047,0.120]; [0.094,0.165] | 83/23/168 |
| title/ru (274) | 0.588/0.745/0.796/0.660 | G256-1600 | 0.719/0.847/0.869/0.777 | 0.131/0.102/0.073/0.117 | [0.084,0.179]; [0.062,0.142]; [0.036,0.113]; [0.081,0.155] | 77/30/167 |
| title/ru (274) | 0.588/0.745/0.796/0.660 | G768-6000 | 0.741/0.865/0.880/0.793 | 0.153/0.120/0.084/0.133 | [0.106,0.197]; [0.080,0.164]; [0.047,0.124]; [0.097,0.169] | 82/24/168 |
| title/ru (274) | 0.588/0.745/0.796/0.660 | G256-6000 | 0.715/0.847/0.872/0.777 | 0.128/0.102/0.077/0.117 | [0.080,0.175]; [0.062,0.142]; [0.040,0.117]; [0.082,0.155] | 81/31/162 |
| title/en (26) | 0.538/0.731/0.769/0.624 | G768-1600 | 0.654/0.808/0.808/0.715 | 0.115/0.077/0.038/0.091 | [-0.038,0.269]; [0.000,0.192]; [0.000,0.115]; [-0.026,0.221] | 7/4/15 |
| title/en (26) | 0.538/0.731/0.769/0.624 | G256-1600 | 0.615/0.808/0.808/0.696 | 0.077/0.077/0.038/0.071 | [-0.077,0.269]; [0.000,0.192]; [0.000,0.115]; [-0.054,0.212] | 8/5/13 |
| title/en (26) | 0.538/0.731/0.769/0.624 | G768-6000 | 0.654/0.808/0.808/0.715 | 0.115/0.077/0.038/0.091 | [-0.038,0.269]; [0.000,0.192]; [0.000,0.115]; [-0.026,0.221] | 7/4/15 |
| title/en (26) | 0.538/0.731/0.769/0.624 | G256-6000 | 0.615/0.808/0.808/0.696 | 0.077/0.077/0.038/0.071 | [-0.077,0.269]; [0.000,0.192]; [0.000,0.115]; [-0.054,0.212] | 8/5/13 |
| question/all (150) | 0.620/0.800/0.840/0.692 | G768-1600 | 0.760/0.893/0.933/0.820 | 0.140/0.093/0.093/0.128 | [0.073,0.207]; [0.033,0.153]; [0.040,0.147]; [0.079,0.177] | 49/12/89 |
| question/all (150) | 0.620/0.800/0.840/0.692 | G256-1600 | 0.767/0.887/0.920/0.822 | 0.147/0.087/0.080/0.131 | [0.080,0.213]; [0.027,0.147]; [0.033,0.133]; [0.082,0.182] | 47/14/89 |
| question/all (150) | 0.620/0.800/0.840/0.692 | G768-6000 | 0.760/0.893/0.920/0.815 | 0.140/0.093/0.080/0.123 | [0.073,0.207]; [0.033,0.153]; [0.033,0.133]; [0.073,0.174] | 48/13/89 |
| question/all (150) | 0.620/0.800/0.840/0.692 | G256-6000 | 0.747/0.893/0.920/0.808 | 0.127/0.093/0.080/0.116 | [0.060,0.193]; [0.040,0.153]; [0.033,0.133]; [0.068,0.166] | 45/15/90 |
| question/ru (60) | 0.600/0.850/0.900/0.701 | G768-1600 | 0.767/0.933/0.967/0.843 | 0.167/0.083/0.067/0.142 | [0.067,0.283]; [-0.017,0.183]; [0.000,0.150]; [0.071,0.223] | 20/5/35 |
| question/ru (60) | 0.600/0.850/0.900/0.701 | G256-1600 | 0.783/0.900/0.967/0.846 | 0.183/0.050/0.067/0.145 | [0.100,0.283]; [-0.050,0.150]; [0.000,0.150]; [0.071,0.223] | 19/5/36 |
| question/ru (60) | 0.600/0.850/0.900/0.701 | G768-6000 | 0.767/0.933/0.967/0.838 | 0.167/0.083/0.067/0.136 | [0.067,0.283]; [-0.017,0.183]; [0.000,0.150]; [0.063,0.216] | 19/6/35 |
| question/ru (60) | 0.600/0.850/0.900/0.701 | G256-6000 | 0.750/0.933/0.967/0.822 | 0.150/0.083/0.067/0.120 | [0.067,0.250]; [-0.017,0.183]; [0.000,0.150]; [0.054,0.190] | 17/6/37 |
| question/pt (7) | 0.571/0.571/0.714/0.586 | G768-1600 | 0.429/0.857/1.000/0.621 | -0.143/0.286/0.286/0.036 | [-0.429,0.000]; [0.000,0.714]; [0.000,0.571]; [-0.179,0.236] | 3/1/3 |
| question/pt (7) | 0.571/0.571/0.714/0.586 | G256-1600 | 0.429/1.000/1.000/0.588 | -0.143/0.429/0.286/0.002 | [-0.429,0.000]; [0.143,0.857]; [0.000,0.571]; [-0.264,0.205] | 3/1/3 |
| question/pt (7) | 0.571/0.571/0.714/0.586 | G768-6000 | 0.429/0.857/0.857/0.607 | -0.143/0.286/0.143/0.021 | [-0.429,0.000]; [0.000,0.714]; [0.000,0.429]; [-0.193,0.236] | 3/1/3 |
| question/pt (7) | 0.571/0.571/0.714/0.586 | G256-6000 | 0.429/0.857/1.000/0.583 | -0.143/0.286/0.286/-0.002 | [-0.429,0.000]; [0.000,0.714]; [0.000,0.571]; [-0.274,0.200] | 3/1/3 |
| question/en (83) | 0.639/0.783/0.807/0.693 | G768-1600 | 0.783/0.867/0.904/0.819 | 0.145/0.084/0.096/0.126 | [0.060,0.241]; [0.012,0.169]; [0.036,0.169]; [0.057,0.200] | 26/6/51 |
| question/en (83) | 0.639/0.783/0.807/0.693 | G256-1600 | 0.783/0.867/0.880/0.825 | 0.145/0.084/0.072/0.131 | [0.048,0.241]; [0.024,0.157]; [0.012,0.145]; [0.059,0.207] | 25/8/50 |
| question/en (83) | 0.639/0.783/0.807/0.693 | G768-6000 | 0.783/0.867/0.892/0.816 | 0.145/0.084/0.084/0.122 | [0.060,0.241]; [0.012,0.169]; [0.024,0.157]; [0.054,0.197] | 26/6/51 |
| question/en (83) | 0.639/0.783/0.807/0.693 | G256-6000 | 0.771/0.867/0.880/0.816 | 0.133/0.084/0.072/0.123 | [0.036,0.229]; [0.024,0.157]; [0.012,0.145]; [0.053,0.199] | 25/8/50 |
| cross/all (150) | 0.353/0.480/0.527/0.408 | G768-1600 | 0.747/0.853/0.887/0.795 | 0.393/0.373/0.360/0.386 | [0.307,0.487]; [0.293,0.453]; [0.280,0.440]; [0.314,0.462] | 92/9/49 |
| cross/all (150) | 0.353/0.480/0.527/0.408 | G256-1600 | 0.687/0.833/0.853/0.746 | 0.333/0.353/0.327/0.338 | [0.247,0.420]; [0.273,0.433]; [0.247,0.407]; [0.265,0.415] | 90/12/48 |
| cross/all (150) | 0.353/0.480/0.527/0.408 | G768-6000 | 0.727/0.860/0.893/0.785 | 0.373/0.380/0.367/0.377 | [0.293,0.460]; [0.300,0.460]; [0.287,0.447]; [0.306,0.451] | 91/8/51 |
| cross/all (150) | 0.353/0.480/0.527/0.408 | G256-6000 | 0.680/0.833/0.853/0.742 | 0.327/0.353/0.327/0.334 | [0.240,0.413]; [0.273,0.433]; [0.247,0.407]; [0.262,0.410] | 88/12/50 |
| cross/ru (83) | 0.157/0.253/0.301/0.202 | G768-1600 | 0.699/0.807/0.831/0.743 | 0.542/0.554/0.530/0.542 | [0.434,0.651]; [0.446,0.663]; [0.422,0.639]; [0.452,0.636] | 67/3/13 |
| cross/ru (83) | 0.157/0.253/0.301/0.202 | G256-1600 | 0.639/0.771/0.795/0.693 | 0.482/0.518/0.494/0.491 | [0.373,0.602]; [0.410,0.627]; [0.386,0.602]; [0.401,0.591] | 67/4/12 |
| cross/ru (83) | 0.157/0.253/0.301/0.202 | G768-6000 | 0.663/0.819/0.843/0.727 | 0.506/0.566/0.542/0.526 | [0.398,0.614]; [0.458,0.675]; [0.434,0.651]; [0.435,0.618] | 67/3/13 |
| cross/ru (83) | 0.157/0.253/0.301/0.202 | G256-6000 | 0.614/0.771/0.795/0.677 | 0.458/0.518/0.494/0.475 | [0.349,0.578]; [0.410,0.627]; [0.386,0.602]; [0.383,0.576] | 67/4/12 |
| cross/en (67) | 0.597/0.761/0.806/0.664 | G768-1600 | 0.806/0.910/0.955/0.858 | 0.209/0.149/0.149/0.194 | [0.075,0.329]; [0.060,0.239]; [0.060,0.239]; [0.099,0.292] | 25/6/36 |
| cross/en (67) | 0.597/0.761/0.806/0.664 | G256-1600 | 0.746/0.910/0.925/0.813 | 0.149/0.149/0.119/0.149 | [0.029,0.269]; [0.060,0.239]; [0.030,0.209]; [0.051,0.246] | 23/8/36 |
| cross/en (67) | 0.597/0.761/0.806/0.664 | G768-6000 | 0.806/0.910/0.955/0.856 | 0.209/0.149/0.149/0.192 | [0.090,0.328]; [0.060,0.239]; [0.060,0.239]; [0.099,0.290] | 24/5/38 |
| cross/en (67) | 0.597/0.761/0.806/0.664 | G256-6000 | 0.761/0.910/0.925/0.823 | 0.164/0.149/0.119/0.158 | [0.045,0.284]; [0.060,0.239]; [0.030,0.209]; [0.065,0.253] | 21/8/38 |
Bootstrap: 2,000 paired query resamples, seed 7; ties share rank (tolerance 1e-7). Cross-language rows refer to QUERY language; language detection is a script heuristic. Synthetic questions see the same first 1,600 body characters.
Question target languages: {'ru': 60, 'pt': 7, 'en': 83}. Generation cache models: {'unsloth/Qwen3.5-4B-MTP-GGUF': 289, 'unsloth/gemma-4-26B-A4B-it-qat-GGUF': 11}.

## Experiment 2 — screenshots (text only)
| Model | Category kNN / majority (n) | App kNN / majority (n) | ≥.95 pairs / proxy (n labeled) | ≥.90 pairs / proxy (n labeled) | Category purity |
|---|---|---|---|---|---|
| e5 | 0.668/0.205 (2285) | 0.542/0.443 (2283) | 644/0.370 (644) | 4099/0.183 (4098) | 0.611 |
| G768-1600 | 0.719/0.205 (2285) | 0.585/0.443 (2283) | 658/0.413 (658) | 3218/0.235 (3218) | 0.614 |
| G256-1600 | 0.717/0.205 (2285) | 0.582/0.443 (2283) | 760/0.397 (760) | 3988/0.201 (3988) | 0.588 |
| G768-6000 | 0.719/0.205 (2285) | 0.585/0.443 (2283) | 657/0.414 (657) | 3207/0.235 (3207) | 0.614 |
| G256-6000 | 0.718/0.205 (2285) | 0.582/0.443 (2283) | 759/0.397 (759) | 3982/0.201 (3982) | 0.588 |
Metadata labels excluded; each source_app string also removed from its title/body. kNN uses only labeled candidates for the respective label, excludes self. Majority baseline = largest class fraction.
Duplicate proxy measured over ALL qualifying pairs with both date/app labels; it is not human precision. Category k-means: Euclidean on L2 vectors, k=21, seed 7, 20 iterations; labeled notes only.
## Timing
| Model | Corpus seconds (n) | Query ms/query (n) | Screens similarity / clustering seconds | Fresh vectors this run |
|---|---|---|---|---|
| e5 | 129.31 (2994) | 2.75 (600) | 75.43 / reused similarity | 0 |
| G768-1600 | 51.29 (2994) | 11.55 (600) | 44.55 / 53.75 | 0 |
| G768-6000 | 132.42 (2994) | 5.50 (600) | 21.16 / 20.79 | 0 |
Timing sums successful batch latency from resumable cache; excludes retries, model download/load and query generation; query latency is batched ms/query, not single-request latency. Gemma: GPU PC over LAN; e5: Mac CPU. These are not phone timing comparisons.
Runtime: onnxruntime 1.30.0, CPUExecutionProvider, exact ONNX O4 at ccc66d3bcd826f577e26b9a4072cc5fe3a7ad6a3; tokenizers; masked mean pooling, L2; 512 tokens.

## Templates, failures and limits
Gemma retrieval: `task: search result | query: {q}`; document: `title: none | text: {body}`. Screenshot kNN/duplicates: `task: sentence similarity | query: {title} | {body}`; k-means: `task: clustering | query: {title} | {body}`.
e5: `query: {q}` / `passage: {body}`; screenshots: `passage: {title} | {body}`. Gemma 256 = first 256 components then L2 renormalize (both queries and documents); 768 also L2 normalized.
Templates: [EmbeddingGemma 2 config](https://huggingface.co/google/embeddinggemma-2/blob/main/config_sentence_transformers.json); [e5 exact O4 revision](https://huggingface.co/intfloat/multilingual-e5-small/tree/ccc66d3bcd826f577e26b9a4072cc5fe3a7ad6a3).
Query generator: Qwen3.5-4B-MTP, fallback Gemma-4-26B-A4B-it-qat; temperature 0, max_tokens 80; reject source four-word spans and wrong script. Cyrillic wins language detection; Portuguese vs English stopwords otherwise.
Failures: none.

## Five-line verdict
- Numbers: overall Gemma-768 fair-window MRR10 0.795 vs e5 0.603 (Δ +0.192); consider a controlled search trial.
- Window/dimensions: Gemma-6000 MRR10 0.793; Gemma-256/1600 0.777.
- Screenshot numbers: Gemma category kNN 0.719 vs e5 0.668; purity 0.614 vs 0.611; supports trying Gemma for text-based organisation.
- Limits: synthetic queries, heuristic languages, article-heavy corpus and pipeline screenshot labels are proxies; duplicate date/app agreement needs human validation.
- Deployment: no phone timing, memory/battery measurements or image embeddings; remote GPU results alone cannot justify replacing an on-device model.

## Recommendation

Run a phone trial of EmbeddingGemma at 256 dimensions before switching from
e5. Measure retrieval quality, latency, peak memory and battery use on the
phone. The desktop and remote GPU results do not establish phone suitability.

Only aggregate results and method are retained here. The benchmark script,
data, note titles, file names and example queries are not included.
