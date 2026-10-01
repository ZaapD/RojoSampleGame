# Sources: what to use, what to skip

Counts were **measured 2026-10-01** against the live APIs (see the research report). Re-measure if they look stale. Don't guess them.

## Use

| Source | License | Size | Access | Role | Quirks |
|---|---|---|---|---|---|
| **Poly Haven** | CC0 | 521 models | open API (send a User-Agent) | first stop for realistic props | Polycount is often > 20k, so it gets decimated. Packed ARM maps plus `nor_gl` normals (already OpenGL). They ask for a "Powered by Poly Haven" credit. The 39-model `hidden_alley` collection is urban. |
| **Kenney** city/urban kits | CC0 | kit packs | zip only, no API | low-poly and stylized | Flat-color materials, so `--palette` is required, otherwise you get 1 MeshPart per color. |
| **Quaternius** (Downtown City MegaKit 300+, Cyberpunk Game Kit 43) | CC0 | 340+ pieces | zip only | low-poly and stylized | Same palette note as Kenney. |
| **Objaverse 1.0** (`allenai/objaverse`) | per object: ~721K CC-BY, ~3.5K CC0 (plus NC/SA, which are rejected) | ~800K total; ≈160K pass gates (20% of a 5,000-object shard: CC0/BY, ≤ 20k faces, textures ≥ 1024) | HF download, no auth | the long tail of realistic props | 2022 Sketchfab snapshot. Join **Objaverse++** for quality and scene/figure flags. The dataset is ODC-By, so credit Objaverse once. |
| **Sketchfab live API** | CC0 rare; CC-BY common | ≥ 4,610 candidates across 30 urban queries; ≥ 2,314 with textures ≥ 1K and ≤ 20 MB | search is open; download needs auth (pilot P5) | only for post-2022 models | Download links expire in 300 s. The API returns no total count, so page with `next`. |
| **Roblox Creator Store** (MCP `search_asset` / `insert_asset`) | Roblox terms | huge | MCP, no upload | placeholders and speed | No polycount or texture metadata. May contain malicious scripts (`validate.luau` strips them). |
| **MCP `generate_mesh`** | yours | unlimited | MCP | last resort | Capped at 20k triangles. Select a Part first to use as the bounding box. |

## Optional

| Source | Why it's optional |
|---|---|
| **Poly Pizza** (10K+ low-poly, CC0/CC-BY) | Needs an `X-Auth-Token`. The API is free for hobby use only; commercial use is pay-as-you-go. Kenney and Quaternius cover the same style for free. |
| **ambientCG** (2,013 CC0 materials, 2,896 models) | Mostly materials. Use for MaterialVariants, not props. |

## Skip

| Source | Why |
|---|---|
| BlenderKit (~17K free) | Ships `.blend` files, so it needs Blender. That costs setup time and disk for little gain. |
| Fab | Manual claims only, no API. Only Standard-License items are allowed outside Unreal. |
| CGTrader / TurboSquid / Free3D | No API. Mixed licenses. Manual only. |
| Anything NC / ND / SA / "editorial" | A game can be monetized; SA would force your modified meshes to stay shareable. |

## Roblox limits the pipeline enforces

- ≤ 20,000 triangles per mesh. EditableMesh allows 60K vertices / 20K triangles.
- Textures up to 4096 are supported. Use ≤ 1024 for PBR maps (the docs suggest 256 per 2×2×2-stud space).
- Normal maps must be OpenGL tangent space. Metal and roughness must be separate 8-bit grayscale maps.
- 1 material per MeshPart. Open Cloud upload limit is 20 MB per file, 120 creates/min.
- 1 stud = 0.28 m.
