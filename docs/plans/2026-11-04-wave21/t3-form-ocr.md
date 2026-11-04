# T3: P5 form OCR module (new repo, reusable)

Create `~/Documents/GitHub/tylog-form-ocr` (git init, Python, `uv` only, pyproject). Purpose: digitize paper forms (OpenLabTwin student requests). Real templates come later; build and test with synthetic ones.

- Template = blank scan image + `fields.json` (name, box [x,y,w,h] in template pixels, type: text|date|checkbox|number).
- Align a photo of a filled form to the template: OpenCV ORB features + RANSAC homography; reject with a clear error when inliers are too few. Then crop each field.
- Read each field through a pluggable reader: `StudioVisionReader` (OpenAI-compatible chat/completions with image, base URL + key from env, never logged), `NullReader` for tests. Checkbox = ink ratio, no model. Each value gets a confidence.
- Output a dataset container dir: `manifest.json` (template id, version, created, reader), `rows.jsonl` (one row per form: source photo hash, fields {value, confidence, crop path}), `crops/`. Rows below a confidence threshold get `review: true`.
- CLI: `form-ocr run --template DIR --photos DIR --out DIR`.
- Tests: generate a synthetic template with Pillow (boxes + labels), "fill" it with text, rotate/perspective-warp/blur it as a phone photo, assert alignment error < 5 px and crops contain the ink; checkbox ink detection; manifest/rows schema. Keep images small (Mac must not overload; no model downloads).
- README: how to add a real template, how rows will link to OLT people/places/items and reach TyLog's review queue (Incoming) later.
