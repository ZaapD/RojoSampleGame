# Pilot: settle the unknowns before the first real run (~20 min)

Use two test models:
- **PH:** one Poly Haven model from the `hidden_alley` collection. It has a color map, an ARM map and an OpenGL normal map.
- **OBJ:** one Objaverse CC-BY prop under 5k faces.

Prep both with `prep`, upload with `upload`, then run each test below.
Fill in the results table at the bottom. SKILL.md step 0 refuses to run while any result is still `?`.

| # | Question | Test | Pass means | Fail means |
|---|---|---|---|---|
| P1 | Does a glb upload carry PBR into SurfaceAppearance correctly? | Insert PH. `execute_luau`: for each SurfaceAppearance, return which of ColorMap/NormalMap/RoughnessMap/MetalnessMap are non-empty (pcall the reads). Then one `screen_capture`. | All four maps are set, and the surface doesn't look pink or chrome. Skip the fix-up forever. | Use the PBR fix-up (pipeline.md §6). Which variant depends on P3. |
| P2 | Moderation latency; can the owner insert while pending? | Time from POST to `done`, and record `moderationState`. Run `insert_asset` immediately and check it renders. | It renders while pending, so insert right away. | The pipeline waits for APPROVED: upload the whole batch first, insert later. |
| P3 | Can `execute_luau` write PluginSecurity props (`RoughnessMapContent`, `ModuleScript.Source`)? | `pcall` setting `RoughnessMapContent = Content.fromUri("rbxassetid://<any image id you own>")` on a scratch SurfaceAppearance, and `pcall` creating `ServerStorage.ModelTools.Validate` with its `Source` set. | Fix-up variant (a): upload_image, then assign. Install the validator module through `execute_luau`. | Fix-up variant (b): drop metallicRoughness in `prep`. Install the validator with `multi_edit` or Rojo. |
| P4 | Does deleting PackageLink leave a stable plain model? | `validate.luau` removes it. Edit something, save, reopen the place. | The edit persists and there's no package badge. Keep the current behavior. | Keep the PackageLink, set `AutoUpdate=false`, and make edits inside the package copy. |
| P5 | Does a Sketchfab personal token work on `/v3/models/{uid}/download`? | `GET` with header `Authorization: Token $SKETCHFAB_API_TOKEN`. | HTTP 200 with a `glb.url` means live Sketchfab can serve as a source for post-2022 models. | Stay on Objaverse, which needs no auth, for Sketchfab content. |
| P6 | Can `execute_luau` call `AssetService:CreateAssetAsync`? | Build a one-triangle EditableMesh and `pcall` `CreateAssetAsync(mesh, Enum.AssetType.Mesh, {Name = "pilot"})`. | A no-API-key upload path exists. Note it, but keep Open Cloud as the default. | Open Cloud is the only upload path. The docs say "locally loaded plugins" only, so this is the expected result. |
| P7 | What unit does the Open Cloud glTF import assume? | Upload PH with its known real dimensions and compare `GetExtentsSize()` to them. | ≈ ×3.57 means meters become studs. ≈ ×1 means units are read as studs. Record it. `ScaleTo` fixes either case. | Not applicable. |
| P8 | Do glTF lights (KHR_lights_punctual) survive? | Upload any glb with a light. | Lights survive, so `needsLight` checks are automatic. | Expected. Add PointLights in Studio (the validate warning covers this). |
| P9 | Does `screen_capture` work in Edit mode with a camera target? | Call it with a position and look-at. | The validation screenshot needs no playtest. | `start_stop_play` first. It's slower, so capture several models per play session. |
| P10 | Is `CollisionFidelity` writable from `execute_luau`? | Check `validate.luau`'s warnings. | Good. | Leave Default. Box is cheaper, but this only matters for large batches. |

## Results

| # | Result | Date | Notes |
|---|---|---|---|
| P1 | ? | | |
| P2 | ? | | latency: ? s |
| P3 | ? | | |
| P4 | ? | | |
| P5 | ? | | skip if no token; counts as fail |
| P6 | ? | | |
| P7 | ? | | factor: ? |
| P8 | ? | | |
| P9 | ? | | |
| P10 | ? | | |
