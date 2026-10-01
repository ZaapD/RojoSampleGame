---
name: roblox-3d-model-import
description: Find, compare, import, validate and swap free 3D models in Roblox Studio through the Roblox Studio MCP, using the cheapest reliable route (Poly Haven, Kenney, Quaternius, Objaverse/Sketchfab, Creator Store, or generate_mesh as a last resort). Use whenever the user wants a 3D prop, model or mesh added to or replaced in a Roblox place; asks to find free models; mentions glb/gltf/fbx import, Sketchfab, Poly Haven, Objaverse, Kenney, Quaternius, Open Cloud asset upload, SurfaceAppearance or MeshPart; or says an imported model looks wrong, is the wrong size, or needs swapping.
---

# Roblox 3D model import

The job, per model: **find, gate, score, look once, prep, upload, insert, validate, look once.**
Everything except the two "look" steps is scripted, so Claude reads short JSON instead of screenshots.

Budget per model: about **2 minutes** and **2 images** (one contact sheet, one Studio screenshot).
If you are about to spend a third image on the same model, stop and follow the failure table at the bottom instead.

## 0. Preconditions (check once per session)

1. **Pilot done?** Open `references/pilot.md`. If any row in its results table is still `?`, run that pilot test first. The pilot answers decide steps 5 to 7.
2. **Toolkit present?** The project needs `tools/model-pipeline/` with `find`, `sheet`, `prep` and `upload` commands. If it is missing, build it from `references/pipeline.md` (specs plus the exact commands). Don't improvise a different pipeline.
3. **Env vars set by the user** (never ask for the values, never print them): `ROBLOX_API_KEY` (Open Cloud, Assets read+write) and `ROBLOX_CREATOR_ID`. Optional: `SKETCHFAB_API_TOKEN`.
4. **Studio MCP connected:** call `get_studio_state` once. If it fails, tell the user to enable "Studio as MCP server" in Assistant, then Manage MCP Servers.

## 1. Pick the route

Write down a one-line **brief** first: object, style (low-poly, stylized or realistic), target size in studs, and whether it emits light.

| Brief says | Route | Why |
|---|---|---|
| placeholder, blockout, "anything for now" | **A. Creator Store**: `search_asset` then `insert_asset` | No upload and no moderation wait. Quality is unknown, so always validate. |
| low-poly or stylized | **B. Kits**: Kenney / Quaternius local catalog | CC0, consistent style, clean topology. |
| realistic | **C. Poly Haven**, then **D. Objaverse** | Poly Haven is CC0 with high quality but only ~521 models. Objaverse has ~160K usable. |
| nothing scores ≥ 0.60 after B–D | **E. `generate_mesh`** with a bounding Part selected | AI fallback, capped at 20k triangles. |

Run B, C and D together in one `find` call. Only fall through to E after `find` comes back empty.

## 2. Find + hard gates (script, no images)

`find "<query>" --style <s> --size <studs> --top 12` searches the local catalogs (`references/sources.md`) and drops anything that fails a gate:

- **License:** keep `CC0` or `CC-BY 4.0` only. Reject NC, ND, SA, "Editorial", Standard-Fab, unknown.
- **Brand/IP:** reject names or tags that hit the brand list (car makes, sodas, sports teams, game/film IP, "replica", "fan art").
- **Geometry:** source faces ≤ 4× the triangle budget (budget: small prop 2k, medium 5k, large 10k, hero 18k; hard cap 20k per mesh).
- **Download:** glb archive ≤ 50 MB before prep (≤ 20 MB after prep is required for upload).
- **Content (Objaverse++ flags):** reject `is_scene`, `is_multi_object` (unless the brief is a set), `is_figure` for props, quality score below "High".
- **Animated/rigged:** reject for static props.

## 3. Metadata score (script)

Each term is 0–1. The total is a weighted sum. Ranking happens before any image is shown.

| Term | Weight | How |
|---|---|---|
| Relevance | 0.30 | Query vs name/tags/category; exact category hit = 1 |
| Quality signal | 0.25 | Curated source = 1.0; Objaverse++ Superior 1.0 / High 0.7; else log-scaled likes |
| Budget fit | 0.15 | 1 if faces ≤ budget, falls linearly to 0 at 4× |
| Texture fit | 0.10 | PBR with color map ≥ 1024 = 1; flat-color low-poly = 1 when style is low-poly |
| Style fit | 0.10 | Source style / Objaverse++ style tag matches brief |
| License friction | 0.10 | CC0 = 1, CC-BY = 0.7 |

## 4. Look once: the contact sheet (1 image)

`sheet <find-output>` writes one PNG: a 4×3 grid, ~1000 px wide. Each tile shows **index, source, faces, license**. View it once, then reply in one line:
`pick: 3 (backup 7), because silhouette matches the brief and it has no ground plane`.

Visual rubric, 0–5 each: **silhouette fits the brief** ×0.35, **style matches the scene** ×0.25, **texture quality** ×0.20, **clean** (no base plate, floor, or props glued on) ×0.20.
**Early exit:** take the first tile that scores ≥ 4.0. Don't rank the rest.
If none reaches 3.5, re-query with different words once, then go to route E.

Don't build a three.js or model-viewer render bench. Studio itself is the bench (step 7).

## 5. Prep the winner (script)

`prep <id> --budget <tris> --size <studs>` runs the fixed chain in `references/pipeline.md`:
decompress, then `optimize` with **compression off and instancing off**, palette on, simplify to budget, textures ≤ 1024, then center at the bottom pivot, scale (1 stud = 0.28 m), and split the ARM texture into roughness/metalness PNGs. Last comes a self-check.

It prints one JSON line. Proceed only if `ok: true`:
`{"ok":true,"file":"cache/out/x.glb","bytes":3.1e6,"meshes":2,"maxTrisPerMesh":4800,"materials":2,"textures":3,"credit":{...}}`

## 6. Upload (script) and insert (MCP)

1. `upload <file.glb> --name <Brief_Source_Id>` POSTs to Open Cloud with assetType `Model`, polls the operation, and prints `{"assetId":"...","moderation":"..."}`.
   Never batch more than 10 at once; the limit is 120/min, so it is never the bottleneck.
2. MCP `insert_asset(assetId)`. The model arrives as a **package**.
3. If pilot P1 says the PBR maps import wrong, run the fix-up from `references/pipeline.md#pbr-fixup`.

## 7. Validate (1 MCP call + 1 image)

1. **Once per place:** install `references/validate.luau` as the ModuleScript `ServerStorage.ModelTools.Validate`. Use `execute_luau` to create it and set its `Source` if pilot P3 passed; otherwise use `multi_edit` or a Rojo sync.
   **Every model:** make one tiny `execute_luau` call (`datamodel_type: "Edit"`):
   `return require(game.ServerStorage.ModelTools.Validate)({path="Workspace.Lamp", target=14, axis="Y", needsLight=true, assetId="…", credit={…}})`
   It strips scripts and `PackageLink`, anchors parts, sets collision fidelity, scales to the target ±10% with `Model:ScaleTo`, writes credit attributes, and returns **one JSON line**.
   Re-sending the 200-line source on every model would cost ~2.5k output tokens and ~30 s each time. The `require` call costs ~100.
2. Accept only if `ok: true`. Read `warnings`. `needsLight but 0 lights` means add a `PointLight` (emissive surfaces glow but don't light the scene).
3. `screen_capture` with the camera aimed at the model. This is the only Studio image. Judge it against the brief: right object, upright, sensible size next to a character, textures present.
4. Optional for batches: run the user's `rbx-scene-analysis` skill before and after to catch performance regressions.

## 8. Replace and roll back

Call the same module with `mode = "replace"` and `old = "<path>"`. It moves the old model to `ServerStorage.ModelArchive` with `ArchivedAt` and `ArchivedFrom` attributes, places the new model on the old one's footprint (bottom-aligned), and gives it the old name.
To undo, run `mode = "rollback"`. Never `Destroy()` an old model during an iteration.

## 9. Credits (required for CC-BY)

`validate.luau` writes `Credit_Title`, `Credit_Author`, `Credit_Source`, `Credit_License` and `Credit_Changes` onto the model.
Also append one line to `CREDITS.md` in the repo: `Title by Author (URL), CC BY 4.0, modified: decimated/rescaled/retextured.`
For Poly Haven, add "Powered by Poly Haven" once. For Objaverse picks, also credit "Objaverse (ODC-By)" once.
If the game has a credits screen, it reads these attributes.

## 10. Keep it cheap

- Scripts print ≤ 20 lines of JSON. Never dump catalogs, glTF JSON or full instance trees into the conversation.
- Never use `search_game_tree` or `inspect_instance` on an imported model. `validate.luau` already reports what matters.
- Batch work: run `find` for every brief first, then view the sheets back to back, then `prep` and `upload` in parallel, then `insert` and `validate` one by one.
- Fast mode costs more per token. Turn it off for long batch runs.

## Failure table

| Symptom | Action |
|---|---|
| `prep` says maxTrisPerMesh > 20000 | Rerun with a lower `--budget`. If still too high, take the backup pick. |
| Upload `FAILED` / moderation rejected | Rename (no brand words) and retry once, then take the backup pick. |
| Inserted model is invisible or grey | Asset may still be in moderation; check `moderation`. Missing SurfaceAppearance: run the PBR fix-up. |
| Size wrong after validate | Check `axis` in CONFIG (Y for height, "max" for longest side). |
| Lying on its side | Rotate 90° in `prep` (`--up z`). Some sources are Z-up. |
| Screenshot shows wrong object | Take the backup pick. Don't re-run `find`. |
| Creator Store model has scripts | `validate.luau` already removed them. Check `removed` in the report and mention it to the user. |
