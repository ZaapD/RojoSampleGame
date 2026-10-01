# Pipeline spec: build once, then reuse

All tools live in `tools/model-pipeline/`. Every command prints **one JSON line** (or ≤ 20 lines) and exits non-zero on failure.
No tool ever prints an API key.

```
tools/model-pipeline/
  package.json      # @gltf-transform/cli@4.5.1 (+ core/functions/extensions), sharp, meshoptimizer, draco3dgltf
  catalog/          # built once: polyhaven.jsonl, objaverse.jsonl, kits.jsonl (+ thumbs/)
  cache/src/        # downloaded originals (keep: re-prep is free)
  cache/out/        # prepped .glb + split PBR maps + prep.json
  find.mjs  sheet.py  prep.mjs  upload.mjs  serve.py (PBR fix-up only)
```

Install: `npm i -D @gltf-transform/cli@4.5.1 @gltf-transform/core @gltf-transform/functions @gltf-transform/extensions sharp meshoptimizer draco3dgltf`. Python needs Pillow and requests.

## 1. Catalog build (one time, ~0.6 GB metadata)

Each record: `id, source, name, tags[], category, faces, license, author, url, thumb, glbBytes, texRes, quality, flags{scene,multi,figure,transparent}, style`.

| Source | How | Filter at build time |
|---|---|---|
| Poly Haven | `GET https://api.polyhaven.com/assets?t=models` (send a User-Agent), files via `/files/{id}` (glTF at 1k) | all 521 (CC0) |
| Objaverse 1.0 | HF `allenai/objaverse`: `metadata/000-000.json.gz` … `000-159.json.gz`, `object-paths.json.gz`, optional `lvis-annotations.json.gz` for category labels | license ∈ {cc0, by}; faces ≤ 80k; not animated |
| Objaverse++ | HF `cindyxl/ObjaversePlusPlus` annotations, joined on uid | adds quality score, scene/multi/figure/transparent flags, style |
| Kenney / Quaternius | user downloads the zips once (no API) into `catalog/kits/<pack>/` | index file names; use pack preview PNGs as thumbs |
| Sketchfab live (optional) | `/v3/search?type=models&downloadable=true&licenses=cc0&licenses=by&max_face_count=…` | only for objects newer than the Objaverse snapshot |

Kit models without preview images: render thumbnails **once** at build time (headless browser + model-viewer). Never render per iteration.

## 2. `find "<query>" --style s --size studs --top 12`

Applies the hard gates and the metadata score from SKILL.md, then prints the top 12 as compact JSON lines: `{i, id, source, name, faces, license, score}`. It also downloads those 12 thumbs into `cache/thumbs/` (in parallel).

## 3. `sheet <find.json>`

Pillow builds a 4×3 grid with ~250 px tiles and an under-strip reading `#i source · faces · license`. The output is about 1000×800 px (≈1.1k tokens to view). It prints only the PNG path.

## 4. `prep <id> --budget <tris> --size <studs> [--up z]`

Fixed chain. Don't add steps unless the pilot says so.

```bash
# a. fetch original into cache/src (Objaverse: HF glb; Poly Haven: gltf 1k + its files; Sketchfab: download API)
# b. normalize container + decode any Draco/meshopt input
npx gltf-transform copy  src.glb  a.glb
# c. one optimize pass. Compression and instancing OFF: Roblox needs plain glTF.
#    The CLI defaults are --compress meshopt and --instance true, so both flags are mandatory.
npx gltf-transform optimize a.glb b.glb \
  --compress false --instance false \
  --texture-compress auto --texture-size 1024 \
  --simplify true --simplify-ratio <R> --simplify-error 0.001 \
  --palette true --flatten true --join true --weld true
#    R = min(1, budget / sourceTriangles); prep lowers R and retries until every mesh is ≤ budget
# d. pivot at the bottom center
npx gltf-transform center b.glb c.glb --pivot below
# e. tangents, only when a normal map exists and TANGENT is missing (Roblox normal maps need tangents)
npx gltf-transform tangents c.glb d.glb
```

Then, in `prep.mjs` (glTF-Transform API + sharp):

- **Up axis:** with `--up z`, rotate the root −90° about X.
- **Scale:** set the root scale so the height (or the longest side) equals `size × 0.28 m`. `validate.luau` corrects whatever is left with `ScaleTo`, so the importer's unit choice can't break the size.
- **Split ARM / metallicRoughness:** for each material's metallicRoughness texture, write `<id>_<mat>_rough.png` (G channel) and `<id>_<mat>_metal.png` (B channel) as 8-bit grayscale. Leave the glb untouched; these PNGs are only for the PBR fix-up.
- **Normal maps:** glTF and Poly Haven `nor_gl` are already OpenGL tangent space, which is what Roblox wants. Never flip G.
- **Self-check:** fail if any of these is true:
  - any mesh has more than 20,000 triangles
  - the file is over 20 MB
  - `extensionsUsed` contains `KHR_draco_mesh_compression`, `EXT_meshopt_compression`, `EXT_mesh_gpu_instancing`, `EXT_texture_webp`, `KHR_texture_basisu` or `KHR_mesh_quantization`
  - there are more than 8 materials
- **Output:** write `prep.json` with the credit fields (title, author, url, license, changes) and print the one-line summary.

## 5. `upload <file.glb> --name <displayName>`

```js
// Node ≥ 18. Values come from env only.
const form = new FormData();
form.append("request", JSON.stringify({
  assetType: "Model",
  displayName,                       // ≤ 50 ASCII chars, no brand words (moderation filters names)
  description,                       // credit line goes here too
  creationContext: { creator: { userId: process.env.ROBLOX_CREATOR_ID } },
}));
form.append("fileContent", new Blob([await readFile(file)], { type: "model/gltf-binary" }), basename(file));
const res = await fetch("https://apis.roblox.com/assets/v1/assets", {
  method: "POST", headers: { "x-api-key": process.env.ROBLOX_API_KEY }, body: form,
});
const { path } = await res.json();   // "operations/{id}"
// poll GET https://apis.roblox.com/assets/v1/operations/{id}, backing off 1s→2s→4s, up to 120 s, until done == true
// print {"assetId": response.assetId, "moderation": response.moderationResult?.moderationState}
```

Content types: `.glb` → `model/gltf-binary`, `.gltf` → `model/gltf+json`, `.fbx` → `model/fbx`.
Model uploads become **packages**. Only `.fbx` assets accept content updates, so a replacement is always a **new** asset.
The web API offers no import settings, which is why sizing and anchoring happen in `validate.luau`.

## 6. PBR fix-up (only when pilot P1 shows the metal/rough maps came in wrong)

1. `serve.py` serves `cache/out/` on `http://localhost:8765`.
2. MCP `upload_image([...rough/metal PNG URLs])` returns a URL → image asset id map.
3. If pilot P3 passed, use `execute_luau` (Edit): for each MeshPart's SurfaceAppearance set
   `RoughnessMapContent = Content.fromUri("rbxassetid://<id>")` and `MetalnessMapContent` the same way.
4. If P3 failed, remove the metallicRoughness texture during `prep` instead. Color and normal maps are enough for most non-metal props. Don't use runtime-only EditableImage tricks: they don't persist in a saved place.

## 7. Batch mode (fastest steady state)

```
find ×N (parallel) → sheet ×N → Claude views N sheets back to back, picks N
→ prep ×N (parallel, CPU-bound) → upload ×N (≤10 concurrent)
→ insert_asset + validate.luau, one model at a time → one screen_capture per model
```

While model k is being validated in Studio, model k+1 is already prepping. Studio is the only serial step.
