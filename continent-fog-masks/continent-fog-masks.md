# Continent Fog of War: hand-traced zone masks

Issue: #35. At continent and World level the Fog of War edge is blocky and does not follow the painted zone borders.

Goal: replace the chunk-derived zone outlines with outlines traced by hand on the continent art. The runtime does not change: `ZoneFog.lua`, the mask drawing in `Renderer.lua`, the BLP mask format and the `ZoneShapes.lua` box format all stay.

## Why the current edges are blocky

- The outlines come from the game's per-chunk AreaIDs (`src/generator/scripts/emit_zone_shapes.py`, 33-yard chunks, `CHUNK = TILE_WORLD_SIZE / 16`). The data has no detail finer than that.
- `MIN_PX_PER_CHUNK = 1.0` stores each mask at one pixel per chunk, and the blur is one chunk. Tuning the blur cannot remove the staircase.
- The game's area borders are not the painted borders on the art.

## Reference art (this folder)

| File | Map (UiMapID) | Size (px) | Zones |
|---|---|---|---|
| `kalimdor-8192x5461.png` | Kalimdor (1414) | 8192 × 5461 | 20 |
| `eastern-kingdoms-8192x5461.png` | Eastern Kingdoms (1415) | 8192 × 5461 | 23 |
| `azeroth-world-8192x5461.png` | Azeroth world map (947) | 8192 × 5461 | 43 |
| `world-under-kalimdor-8192x5461.png` | World map cropped to Kalimdor's frame | 8192 × 5461 | 20 |
| `world-under-eastern-kingdoms-8192x5461.png` | World map cropped to Eastern Kingdoms' frame | 8192 × 5461 | 23 |

- Source: the Forever client, `_forever_/Interface/HighFidelityWorldMap_Art_Forever/WorldMap/KalimdorHD/` and `EasternKingdomsHD/`. Each folder has 704 BLP2 tiles of 256 × 256 (uncompressed BGRA), laid out 32 columns by 22 rows, row-major. Tile *n* is `<stem><n>.blp`, where `n = row * 32 + col + 1`.
- Stitched, then cropped to the art layer, 8192 × 5461. The full grid is 8192 × 5632, and the bottom 171 rows are padding.
- Transparent where the map has no art (erased sea, outside the coastline). Not flattened.
- **Coordinate convention:** `u = x / 8192`, `v = y / 5461`, origin top-left. This is the 0–1 space of `ZoneShapes.lua`.
- Checked: the Durotar mask (`z1411`) from the current build, placed with its `ZoneShapes.lua` box, lands on the Durotar landmass in the Kalimdor PNG.
- These are Blizzard art. Do not commit them. `continent-fog-masks/*.png` is gitignored.

### World map reference (same frame)

- `azeroth-world-8192x5461.png` is the in-game world map (UiMap 947), stitched from the `AzerothHD` tiles with the same grid and layer size as the continents.
- `world-under-kalimdor-8192x5461.png` and `world-under-eastern-kingdoms-8192x5461.png` are the world map cropped and resampled to each continent's frame. Each is pixel-aligned with its continent PNG, so it can sit behind the trace file as a reference layer.
- Alignment comes from a least-squares affine fit between each zone's continent box and world box in `ZoneShapes.lua`. Max corner error is 2 × 10⁻⁶ in 0–1 units. Checked: the Durotar mask lands on the Durotar landmass in the aligned world crop.
- The Kalimdor frame starts left of the world layer, so those pixels are transparent. The crops are upscaled about 1.2× (Kalimdor) and 1.3× (Eastern Kingdoms), so they are soft. Use them as reference only; trace on the continent PNG.
- To place the continent PNG on the full world PNG yourself (world canvas 8192 × 5461 px):

| Continent | Width | Height | Left | Top |
|---|---|---|---|---|
| Kalimdor | 6717 px (82.0%) | 4478 px (82.0%) | -1523 px | 370 px |
| Eastern Kingdoms | 6453 px (78.8%) | 4301 px (78.8%) | 3043 px | 445 px |

## Zones to trace (43)

| Layer name | Zone | Trace file |
|---|---|---|
| `z1411` | Durotar | `kalimdor-traces.psd` |
| `z1412` | Mulgore | `kalimdor-traces.psd` |
| `z1413` | The Barrens | `kalimdor-traces.psd` |
| `z1438` | Teldrassil | `kalimdor-traces.psd` |
| `z1439` | Darkshore | `kalimdor-traces.psd` |
| `z1440` | Ashenvale | `kalimdor-traces.psd` |
| `z1441` | Thousand Needles | `kalimdor-traces.psd` |
| `z1442` | Stonetalon Mountains | `kalimdor-traces.psd` |
| `z1443` | Desolace | `kalimdor-traces.psd` |
| `z1444` | Feralas | `kalimdor-traces.psd` |
| `z1445` | Dustwallow Marsh | `kalimdor-traces.psd` |
| `z1446` | Tanaris | `kalimdor-traces.psd` |
| `z1447` | Azshara | `kalimdor-traces.psd` |
| `z1448` | Felwood | `kalimdor-traces.psd` |
| `z1449` | Un'Goro Crater | `kalimdor-traces.psd` |
| `z1450` | Moonglade | `kalimdor-traces.psd` |
| `z1451` | Silithus | `kalimdor-traces.psd` |
| `z1452` | Winterspring | `kalimdor-traces.psd` |
| `z2482` | Mount Hyjal | `kalimdor-traces.psd` |
| `z2652` | Shen'dralas | `kalimdor-traces.psd` |
| `z1416` | Alterac Mountains | `eastern-kingdoms-traces.psd` |
| `z1417` | Arathi Highlands | `eastern-kingdoms-traces.psd` |
| `z1418` | Badlands | `eastern-kingdoms-traces.psd` |
| `z1419` | Blasted Lands | `eastern-kingdoms-traces.psd` |
| `z1420` | Tirisfal Glades | `eastern-kingdoms-traces.psd` |
| `z1421` | Silverpine Forest | `eastern-kingdoms-traces.psd` |
| `z1422` | Western Plaguelands | `eastern-kingdoms-traces.psd` |
| `z1423` | Eastern Plaguelands | `eastern-kingdoms-traces.psd` |
| `z1424` | Hillsbrad Foothills | `eastern-kingdoms-traces.psd` |
| `z1425` | The Hinterlands | `eastern-kingdoms-traces.psd` |
| `z1426` | Dun Morogh | `eastern-kingdoms-traces.psd` |
| `z1427` | Searing Gorge | `eastern-kingdoms-traces.psd` |
| `z1428` | Burning Steppes | `eastern-kingdoms-traces.psd` |
| `z1429` | Elwynn Forest | `eastern-kingdoms-traces.psd` |
| `z1430` | Deadwind Pass | `eastern-kingdoms-traces.psd` |
| `z1431` | Duskwood | `eastern-kingdoms-traces.psd` |
| `z1432` | Loch Modan | `eastern-kingdoms-traces.psd` |
| `z1433` | Redridge Mountains | `eastern-kingdoms-traces.psd` |
| `z1434` | Stranglethorn Vale | `eastern-kingdoms-traces.psd` |
| `z1435` | Swamp of Sorrows | `eastern-kingdoms-traces.psd` |
| `z1436` | Westfall | `eastern-kingdoms-traces.psd` |
| `z1437` | Wetlands | `eastern-kingdoms-traces.psd` |
| `z2548` | Riverglades | `eastern-kingdoms-traces.psd` |

Each zone is traced once, on the continent it sits on. Its World map (947) position is derived, not traced (see Agent steps, step 6).

---

## User steps (Photoshop CS6)

1. Open `kalimdor-8192x5461.png` and `eastern-kingdoms-8192x5461.png`. Do not resize, crop or change the canvas size. Keep the PNG as a layer named `reference`.
2. Create one layer per zone and name it exactly as in the table above (`z` plus the UiMapID, for example `z1411`). Layer names are the contract. Only `z<id>` layers and the `reference` layer may exist.
3. For each zone:
   - Select the zone's layer, then use the Pen tool (`P`) to trace the zone's outer border on the painted art. Click the first anchor again to close the path.
   - Trace the border on the painted art, not the blocky data. Trace the coastline where the art shows the coast.
   - Where two zones share a border, trace the shared line for each zone so they meet. The converter adds a small overlap to close seams.
   - Islands: make each island its own closed path and fill it on the same layer.
   - In the Paths panel (Window > Paths), right-click the path and choose **Fill Path**. Use Contents: Foreground Color, Opacity 100%, Anti-aliased on.
4. Before saving, delete the `reference` layer. This keeps the trace file small enough to commit. Keep a separate working copy with the reference if you want to continue editing.
5. Save as `kalimdor-traces.psd` and `eastern-kingdoms-traces.psd` with layers kept. Put them in `continent-fog-masks/`, next to the build scripts.
6. Check before handing off:
   - Each zone in the table above has exactly one layer, with the right name.
   - Each layer is filled and nothing is left as an open path.
   - At 50% zoom, each edge matches the painted border.
7. Tell the agent the traces are ready.

## Agent steps

Read first: `src/addon/client/ZoneFog.lua`, `Renderer.lua` (around the `worldFogZones` drawing, about line 1314), `src/generator/scripts/build_zone_masks.py` (`CONTINENTS`, `zone_mask`, `write_shapes`), and the sections of `docs/BUILDING.md` that mention the zone masks.

1. **Validate the PSDs.** Canvas must be exactly 8192 × 5461. Layer names must be `z<id>` for the zones listed for that file, with no duplicates, no extra zones and no empty layers. Stop and report anything else.
2. **Rasterize each zone.** Take the layer's alpha at canvas size, applying the layer offset.
3. **Close seams.** Dilate each zone's alpha by a few canvas pixels (start at 3). Keep the anti-aliased edge. Do not blur. The traces are already smooth.
4. **Set mask resolution.** Downscale each zone's crop so its longest side is at most 1024 px, rounded up to a power of two as `pow2()` does now. Encode with `hfwm.formats.blp.encode_blp2_bgra` as white RGB with the mask as alpha, the same as `zone_mask()`.
5. **Continent boxes (1414, 1415).** Compute each zone's box from its dilated crop, in 0–1 canvas coordinates. The crop is `(min_x / 8192, min_y / 5461, max_x / 8192, max_y / 5461)`.
6. **World boxes (947).** Derive these from the continent box, not from traces. Invert the generator's `map_box()`: convert the continent 0–1 point to world-yard coordinates using that terrain map's continent `UiMapAssignment` row, then convert to 0–1 using the 947 row for the same terrain `MapID`.
   - Check: the derived 947 boxes should agree closely with the 947 entries in the current `ZoneShapes.lua`, which came from the chunk pipeline. If they disagree for any zone, stop and report.
7. **Write outputs.**
   - Masks: `src/addon/client/ZoneMasks/z<id>.blp`. This folder is gitignored and built from the generator, as `Config.MASK_BASE` expects.
   - Shapes: rewrite `src/addon/client/data/ZoneShapes.lua` in the same format, one `{zone, u0, v0, u1, v1}` row per zone per map (1414/1415 and 947).
8. **Verify.**
   - Overlay every zone's outline on its continent PNG and review them as a contact sheet. Look for holes, misses and seam gaps. Zoom in on shared borders.
   - Run `.github/scripts/lint-lua.sh` if any Lua changed.
   - The agent cannot run the WoW client. The in-game check is the user's: `/hfwm`, continent view, Fog of War on, then `/reload` if needed.
9. **Wire the build (required, not optional).**
   - Release builds run the generator in CI (`.github/actions/generate-world-map-assets/action.yml`, `.github/scripts/world-map-assets-keys.sh`). The trace PSDs must be part of the cache keys and the build inputs there. Read those two files before changing anything. I have not read them yet.
   - Update `docs/BUILDING.md`.
10. **Clean cutover (done).** The chunk path is removed from the generator; `emit_zone_shapes.py` is deleted, and the trace builder is `src/generator/scripts/build_zone_masks.py`.

## Open decisions

- Dilation amount (default 3 canvas px) and mask resolution cap (default 1024 px). Both are tuned after the first in-game check.
- The chunk-based generator is removed only after the trace path is verified in game.
