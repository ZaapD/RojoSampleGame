# Extended catalog: 10 more free inventories

Every source below has the same five-step adapter, so `find`, `sheet` and `prep` treat them all alike:

**(-1) expand → (0) search → (1) images → (2) pick → (3) download + extract**

Endpoints marked **(verify)** come from public docs or community use. The pilot has not hit them yet: run one search and one download per source before relying on it, then record the result in `pilot.md` → "Source checks".

---

## (-1) Query expansion (shared by all sources)

Before searching, turn the brief into **5–8 queries** and run all of them on each source. Merge the results by id.

1. **Literal:** the user's own noun ("street lamp").
2. **Synonyms:** lamp post, streetlight, light pole, lamppost.
3. **Parts or sub-types:** "victorian street lamp", "LED street light", "double arm lamp post".
4. **Category words that site uses:** Thingiverse "lamp"; Smithsonian "lantern"; Fuel tags "light".
5. **Style modifiers from the brief:** low poly, stylized, realistic, PBR, game ready.
6. **Creative neighbors:** objects that would also satisfy the goal (e.g. "bollard light", "gas lamp", "park light").
7. **Drop one word:** if a query returns < 5 results, retry it with the modifier removed.

Write the queries into `find.json` (`"queries": [...]`) so the contact sheet tile labels show which query found each hit. Cap the merged list at 60 before scoring, then show the top 12.

## Shared converter (step 3)

Many of these sources ship STL, OBJ, DAE, PLY, 3MF, FBX or zip files. `prep` adds **step a0** before the gltf-transform chain:

```bash
pip install trimesh[easy] pycollada   # one time
python -c "import trimesh,sys; trimesh.load(sys.argv[1], force='scene').export(sys.argv[2])" in.obj src.glb
```

- Unzip first. Pick the largest mesh file whose extension is one of glb, gltf, fbx, obj, dae, stl, 3mf or ply.
- OBJ and DAE keep their textures if the .mtl and image files are in the same folder.
- STL, 3MF and PLY have **no textures or UVs**. Give them one flat color in the glTF material (style "printable" in the score). Good for stylized games, weak for realistic ones.
- FBX: trimesh can't read it. Pass .fbx straight to Open Cloud (it accepts `model/fbx`) after a triangle check, or skip the candidate.
- `.blend` only: skip, since Blender isn't part of this setup.

## Shared license gate

Keep: CC0, Public Domain, CC-BY (any version), NASA media guidelines, Smithsonian CC0.
Reject: NC, ND, SA, GPL/LGPL art, "personal use", "standard digital file license" with no-redistribution terms, and unknown.
Printing-site licenses are set per model, so read the license on the model itself, never the site default.

---

## 1. Objaverse-XL (~10M objects: GitHub, Thingiverse, Sketchfab, Smithsonian)

- **Search:** HF `allenai/objaverse-xl` annotation parquet (`fileIdentifier`, `source`, `license`, `fileType`, `sha256`, metadata). Build a local index once with `objaverse.xl.get_annotations()`. Match queries against filename, repo path and metadata title.
- **Images:** none are provided. Render thumbnails **only for the top 24** (headless model-viewer, same as the kit thumbs), or use the source page's image (Thingiverse/Sketchfab ids).
- **Pick:** gate on license (the column is reliable for Sketchfab and Smithsonian rows, often empty for GitHub rows; treat empty as reject), then score.
- **Download:** `objaverse.xl.download_objects(objects=df)`, which handles git, Thingiverse and Sketchfab sources. Then use the shared converter.

## 2. Thingiverse (~2.5M+ things, mostly STL)

- **Search (verify):** `GET https://api.thingiverse.com/search/{query}?type=things&per_page=30&sort=popular` with `Authorization: Bearer $THINGIVERSE_TOKEN` (a free app token from thingiverse.com/developers).
- **Images:** each hit has `thumbnail` / `preview_image`; `GET /things/{id}/images` gives larger renders.
- **Pick:** license comes from `GET /things/{id}` → `license`. Score with a penalty for having no texture.
- **Download:** `GET /things/{id}/files` → `download_url` (needs the token), or `/things/{id}/package-url` for a zip. Then use the converter (STL → glb, flat color).

## 3. Printables (Prusa; ~1M+ models, STL/3MF)

- **Search (verify, unofficial GraphQL):** `POST https://api.printables.com/graphql/` with the `searchPrints` query (`query`, `limit`, `ordering`). There's no key, but send a User-Agent and stay under 1 request/s.
- **Images:** `image.filePath` → `https://media.printables.com/<filePath>`.
- **Pick:** `license.name` on the print. The default is often CC-BY-NC, so most get rejected; filter early.
- **Download:** the `getDownloadLink` mutation (verify) returns a signed URL for the file or zip. Then use the converter.
- **Fallback:** if the API changes, open the model page in a browser for a manual download into `cache/src/`.

## 4. MyMiniFactory (~150K+, STL; many free)

- **Search (verify):** `GET https://www.myminifactory.com/api/v2/search?q={q}&per_page=30&key=$MMF_API_KEY`.
- **Images:** `images[].thumbnail.url` / `images[].standard.url`.
- **Pick:** `license` per object. Keep only free items with an allowed license (many are "MyMiniFactory license": reject).
- **Download:** `GET /api/v2/objects/{id}` → `files.items[].download_url`. This may require OAuth: if a 401 comes back, mark the source as images + manual download. Then use the converter.

## 5. Cults3D (~1M+ listings; a free filter exists)

- **Search (verify):** GraphQL `POST https://cults3d.com/graphql`, basic auth `username:$CULTS_API_KEY`, `search(query:…, onlyFree:true)` returns `name`, `url`, `illustrationImageUrl`, `license { code }`.
- **Images:** `illustrationImageUrl`, plus `illustrations[]`.
- **Pick:** license code. Keep only `cc0`, `cc` (BY) and `public_domain`.
- **Download:** the API doesn't expose file URLs. This is a **manual-assisted** step: Claude prints the URL, the user clicks Download, and the zip lands in `cache/src/<id>/`. `prep` watches that folder.

## 6. Smithsonian Open Access 3D (~3,000+ scans, CC0)

- **Search:** `GET https://api.si.edu/openaccess/api/v1.0/search?q={q}+AND+online_media_type:"3D Images"&rows=30&api_key=$DATA_GOV_KEY` (a free api.data.gov key).
- **Images:** `content.descriptiveNonRepeating.online_media.media[].thumbnail` and `resources`.
- **Pick:** usage is `CC0` (check `media[].usage.access == "CC0"`). These are high-poly scans, so the budget-fit score is low and decimation does the work.
- **Download:** `media[].resources[]` with `.glb` or `.obj`, or the 3D package from `3d-api.si.edu` (verify the link in the record). Prefer the glb at "Medium"/"Low" quality, then use the converter if it's an OBJ.

## 7. NASA 3D Resources (~700+ models, public domain*)

- **Search:** sparse-clone `github.com/nasa/NASA-3D-Resources` (3D Models folder) once and index the folder names plus README text.
- **Images:** most folders include a `.jpg`/`.png` preview. Otherwise render it (top-N only).
- **Pick:** *these are not copyrighted, but NASA media guidelines forbid implying endorsement and using the logo. Reject anything containing the NASA "meatball"/"worm" insignia.
- **Download:** the files are already local (glb, obj, 3ds, fbx). Then use the converter (3ds → skip, or load via the trimesh+assimp backend if installed).

## 8. Gazebo Fuel (incl. ~1,000 Google Scanned Objects, CC-BY 4.0)

- **Search:** `GET https://fuel.gazebosim.org/1.0/models?q={q}&per_page=30`. Owner `GoogleResearch` holds the scanned household objects.
- **Images:** `https://fuel.gazebosim.org/1.0/{owner}/models/{name}/tip/files/thumbnails/1.png`.
- **Pick:** `license_name` per model. Keep CC-BY, CC0 and Apache (for meshes). Scanned objects are realistic with PBR-like albedo textures.
- **Download:** `GET https://fuel.gazebosim.org/1.0/{owner}/models/{name}.zip` → `meshes/*.obj|.dae` + textures. Then use the converter.

## 9. OpenGameArt (3D section, ~5,000+ entries)

- **Search:** `GET https://opengameart.org/art-search-advanced?keys={q}&field_art_type_tid[]=10&sort_by=count&sort_order=DESC` (type 10 = 3D Art), then parse the HTML result list (title, link, preview `<img>`).
- **Images:** the preview image on each art page (`.field-name-field-art-preview img`).
- **Pick:** parse `.field-name-field-art-licenses`. Keep CC0 and CC-BY only (reject GPL, OGA-BY is OK with credit, reject CC-BY-SA).
- **Download:** the file links in `.field-name-field-art-files a`, usually zip, blend, fbx or obj. Unzip, skip .blend-only entries, then use the converter.

## 10. itch.io free 3D asset packs (~20,000+ listings)

- **Search:** `GET https://itch.io/game-assets/free/tag-3d?q={q}` and parse the HTML grid (`.game_cell`: title, link, `data-lazy_src` cover image). No key is needed.
- **Images:** the cover image, plus screenshots on the product page (`.screenshot_list img`).
- **Pick:** itch has no structured license field. Read the description for "CC0", "public domain" or "commercial use OK, no attribution" and reject anything vague. Packs are often stylized/low-poly sets, so treat them like a kit (one download, many pieces indexed into `catalog/kits/`).
- **Download:** a free download often goes through a "No thanks, just take me to the downloads" page, so it's **manual-assisted** like Cults3D: the user downloads the zip into `cache/src/<slug>/`. Then index each mesh in it as a kit entry.

---

## Reliability summary

| # | Source | (-1) expand | (0) search | (1) images | (2) license field | (3) download |
|---|---|---|---|---|---|---|
| 1 | Objaverse-XL | ✔ | local index | render top-N | column (GitHub rows weak) | scripted |
| 2 | Thingiverse | ✔ | API + token | ✔ | ✔ | scripted (token) |
| 3 | Printables | ✔ | GraphQL (unofficial) | ✔ | ✔ | scripted (verify) / manual |
| 4 | MyMiniFactory | ✔ | API + key | ✔ | ✔ | scripted or manual if OAuth |
| 5 | Cults3D | ✔ | GraphQL + key | ✔ | ✔ | manual-assisted |
| 6 | Smithsonian | ✔ | API + data.gov key | ✔ | ✔ CC0 | scripted |
| 7 | NASA 3D | ✔ | local clone | folder previews | ✔ (guidelines) | local |
| 8 | Gazebo Fuel / GSO | ✔ | open API | ✔ | ✔ | scripted zip |
| 9 | OpenGameArt | ✔ | HTML parse | ✔ | ✔ (page field) | scripted |
| 10 | itch.io | ✔ | HTML parse | ✔ | description text | manual-assisted |

**Env vars, all optional and each set by the user:** `THINGIVERSE_TOKEN`, `MMF_API_KEY`, `CULTS_API_KEY`, `DATA_GOV_KEY`. A source with a missing key is skipped silently by `find`.
