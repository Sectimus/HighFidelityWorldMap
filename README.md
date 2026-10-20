![High-Fidelity World Map logo](assets/images/logo_lowres.png)

# High-Fidelity World Map (HFWM)

[![CurseForge Downloads](https://img.shields.io/curseforge/dt/1701034?color=orange&logo=curseforge&style=flat-square)](https://www.curseforge.com/projects/1701034)

Adds a "HD/SD" toggle to view the world map pane with a detailed, high-resolution map constructed by stitching together minimap satellite imagery across entire zones. The result is a seamless, richly detailed world map that shows all the finer details of the world of Azeroth with far greater clarity than the game's default map ever could.

![HD/SD Toggle](https://i.postimg.cc/3kXr2BBY/hd-sd-toggle.jpg)

## FAQ:

### Who is the artist?
My lil' sis designed the logo :3 notice the kitties? She draws cats. Go pay her to draw your cat. We LOVE cats here.

The base hfwm visual assets are read from the game file data in real time and do not require any additional downloads, so, Blizzard?

### Why do some parts of the map look wrong / glitched?

![Glitch 1](https://i.postimg.cc/cvR1fmmt/glitch-1.png)

This kind of visual eyesore is just… how it actually looks on the minimap, I'm afraid.

![Glitch 2](https://i.postimg.cc/v4r85zz6/glitch-2.png)

This happens a lot throughout the game, and so I do actually want to go through and fix each issue by hand eventually. This will make its way into the companion "art" addon as a secondary selectable map.

### Gamepad

With the native Gamepad UI on, while the map and a cave window are open: L1/R1 step the floor up/down, L2/R2 zoom out/in, R3 resets the view. "Toggle cave window" (Key Bindings > High Fidelity World Map) can be put on any pad button.

# Features

## Fog of War support:

Exploration is at the heart of WoW. To keep the spirit of mystery alive going into forever, HFWM also comes with complete, native fog of war support!

![Fog of War](https://i.postimg.cc/0zY57ff8/fog-of-war.jpg)

On the World and Continent maps a separate "Fog of War" checkbox (next to the World Map background in the settings) draws the high-fidelity map only over zones you have explored in full. Miss one area of a zone and the whole zone stays as the game draws it.

## Offers optional replacements for *all* maps

Not just individual zones, continents too! With full control and various customization options. (Continent and World maps work out of the box at low resolution; the optional High Fidelity World Map: Art companion addon unlocks the High Resolution option.)

![Continents](https://i.postimg.cc/ZW8Y6ccq/continents.jpg)

## Increased zoom distance:

With all this new fidelity, the game's base zoom modifier becomes somewhat limiting, so additional zoom levels are now included!

![Zoom 1](https://i.postimg.cc/3kXr6cc5/zoom-1.jpg)

![Zoom 2](https://i.postimg.cc/WdGp0nnp/zoom-2.jpg)

## Optional Cave & Dungeon Art

Overlays interior cave and dungeon layouts in a classic-style, movable frame to help orient yourself below ground.

![Cave 1](https://i.postimg.cc/cvR1fmmC/cave-1.jpg)

A slider on the side can be adjusted to change the slice of cave depth you are currently viewing. Super helpful for traversing deep, winding caves!

![Cave 2](https://i.postimg.cc/Mn7Z1DDc/cave-2.jpg)

An optional **Other indoors** toggle extends the same window to buildings, houses and every other indoor area.

Ironforge and Undercity always open their underground interior map from inside the city, whether or not **Other indoors** is on, as long as the cave map is on.

The **Instance map (beta)** section's **Dungeon** and **Raid** toggles control the window inside dungeon and raid instances, independently of the cave map toggle. Both are off by default; with one off, nothing extra shows inside that kind of instance.

## Area Labels

Area names optionally drawn over the map, in five types (including city districts, such as Stormwind's Mage Quarter, on each capital's own map), each with its own configurable settings.
Also supports fog of war exploration. Explore and unlock labelled areas of your map as you progress.

![Area Labels](https://i.postimg.cc/90pqTN40/area-labels-gif.gif)

# Building High Fidelity World Map: Forever

This project is split into three parts:

- `src/addon/client/` — the addon (`HighFidelityWorldMap`) that hooks into the
  in-game world map. Zone and cave views are drawn from the game's own map
  textures; the World and continent views ship with it at low resolution
  (`WorldMap/`) plus the Fog of War zone masks (`ZoneMasks/`), both built by
  CI, not committed.
- `src/addon/art/` — the optional Art addon (`HighFidelityWorldMap_Art_Forever`):
  just the high-resolution (`*HD`) World, Eastern Kingdoms and Kalimdor map
  tiles and a TOC, kept separate so a client update is not a 1 GB download.
  The client works without it, at low resolution.
- `src/generator/` — the Python pipeline that generates the art and the Lua
  tables. It writes into `src/addon/art/` and `src/addon/client/`.

Everything else (`docs/`, `assets/`, `.github/`) is repository machinery and is not packaged.

The addon itself is not a traditional "build" in the sense of compiling a binary. The real work is:

1. fetching Ace3 libraries for local dev
2. generating cave tile data and any required stitched assets
3. packaging the addon for release

## Prerequisites

- Git
- Python 3.12+
- Lua 5.1 (for syntax checks)
- A working World of Warcraft Forever beta environment for in-game testing

## 1) Clone and initialize

```sh
git clone https://github.com/Sectimus/HighFidelityWorldMap.git
cd HighFidelityWorldMap
```

## 2) Fetch Ace3 dependencies

The repo does not commit the Ace3 libraries. Fetch them before testing locally:

```sh
./src/addon/client/dev/fetch-libs.sh
```

This populates the `src/addon/client/Libs/` folders required for the addon to load.

To load the addon in the game, the client needs a folder named after the
addon with its TOC directly inside it. Link `src/addon/client/` into your
AddOns directory under that name:

```sh
ADDONS="<WoW install>/_classic_beta_/Interface/AddOns"
ln -s "$PWD/src/addon/client" "$ADDONS/HighFidelityWorldMap"
```

The client works on its own: zone and cave maps use the game's built-in assets
and the World and continent maps use the low-resolution art it ships. The
High Resolution option needs the optional Art addon: link it the same way, or
install [hfwm-art](https://www.curseforge.com/wow/addons/hfwm-art) from CurseForge:

```sh
ln -s "$PWD/src/addon/art" "$ADDONS/HighFidelityWorldMap_Art_Forever"
```

## 3) Install Python dependencies

```sh
python -m pip install --upgrade pip
python -m pip install -r src/generator/requirements.txt
```

## 4) Generate cave tile data and custom assets

The generated data is not tracked in Git and is rebuilt from source data.

```sh
python src/generator/generateHFWM.py
```

The generator writes the high-resolution art (`WorldMap/`) into
`src/addon/art/`, the low-resolution art into `src/addon/client/WorldMap/`
(`--lowres-dir`) and the Lua tables (`FDIDMap.lua`, cave tile data) into
`src/addon/client/data/`. Only the World, Eastern Kingdoms and Kalimdor views
are stitched; a full run takes about 40 minutes, or about 3 with
`--lowres-only`. Downloads are cached under `src/generator/.cache-*/`. Pass
`--no-caves` to skip `CaveData.lua` and `--skip-fdid-map` to skip
`FDIDMap.lua`. Nothing under `WorldMap/` is committed; CI builds and caches
it at release time.

If you only need to refresh the cave tile data, you can run the relevant emit
script directly from the cached zone DB:

```sh
python src/generator/scripts/emit_cave_tiles.py
```

`IndoorData.lua` and `IndoorTiles.lua` (every other indoor area: houses, inns, towers, unnamed caves; about 1.2 MB together) come from `python src/generator/scripts/emit_indoors.py`. It finds every placed WMO with baked minimap art in the Eastern Kingdoms and Kalimdor object files (`hfwm/caves/indoors.py`, using the community listfile, downloaded once into the cache, about 150 MB) and bakes each like a mine; a couple of minutes once the files are cached. The addon only uses them while **Other indoors** is on. The same script also writes `SubMaps.lua`: the Ironforge and Undercity canvases (`SUBMAPS` in the script), placed on those cities' own world maps instead of being cave-window places.

Two more tables are not part of the full run; both feed the World/Continent Fog of War checkbox. `ZoneOverlays.lua` (how many exploration overlays each zone has) comes from `python src/generator/scripts/emit_zone_overlays.py`, which downloads three small DB2 tables. `ZoneShapes.lua` and `src/addon/client/ZoneMasks/` (one smoothed outline mask per zone, 6 MB, not committed — CI builds both at release time) come from `python src/generator/scripts/emit_zone_shapes.py`. It reads the area ID of every terrain chunk from the game's ADT files (about 1,700 downloads, a couple of minutes, cached as 512 bytes each), so the borders are the game's own and follow the stitched art. The masks sit outside `WorldMap/` so regenerating that folder never touches them.

Useful flags include:

- `--zones` to process only selected maps
- `--dry-run` to test the pipeline without writing output
- `--lowres-only` to skip the HD maps and build only the client's low-resolution ones
- `--refresh` to re-download cached inputs
- `--threads` to parallelize generation
- `--skip-fdid-map` for focused local testing runs

## 5) Local smoke tests

You can run a quick validation pass without a full world build:

```sh
python src/generator/generateHFWM.py ./smoke --zones Kalimdor --skip-fdid-map --no-caves
```

This runs one continent through the generation pipeline and checks the output is created correctly.

## 6) Lua syntax validation

You can validate the Lua files directly:

```sh
(cd addon && luac5.1 -p *.lua)
```

or, with a loop over the addon TOC:

```sh
while IFS= read -r file; do
  [[ "$file" == *.lua ]] || continue
  luac5.1 -p "$file" || exit 1
done < <(grep -E '^[^#[:space:]].*\.(lua|xml)[[:space:]]*$' src/addon/client/HighFidelityWorldMap.toc | tr -d '\r')
```

## 7) CI checks

The repo includes a GitHub Actions workflow that runs linting and smoke-test generation, and dry-runs the packager for both addons (`.pkgmeta` and `.pkgmeta-art`). This is the same rough validation path contributors should run locally before sending changes.

## 8) Release packaging

Release packaging is handled by GitHub Actions workflows and the packager tool, not by a local manual compile step.

There are two packages, released separately so a UI or settings update does not mean re-downloading the art:

- `HighFidelityWorldMap`, the client addon, tag series `v1.2.3`. It contains the Lua, the committed tables (`FDIDMap.lua`, `CaveData.lua`, `MinimapTiles.lua`, `CaveTiles.lua`), the low-resolution World and continent map tiles (`WorldMap/`, about 23 MB) and the Fog of War zone masks (`ZoneMasks/`, about 6 MB), all the generated ones built by CI at release time.
- `HighFidelityWorldMap_Art_Forever` (title **High Fidelity World Map: Art**), the optional Art addon (the [hfwm-art](https://www.curseforge.com/wow/addons/hfwm-art) CurseForge project), tag series `art-v1.2.3`. It is only the high-resolution `WorldMap/` tiles (`*HD`) for the **World**, **Eastern Kingdoms** and **Kalimdor** views and a TOC: no Lua. Zone and cave maps are drawn from the game's own files and ship no art. Its TOC lists the client under `Dependencies`; the client does not depend on it, and without it everything still works, but World and continent maps stay at low resolution and the High Resolution option is disabled with a tooltip pointing at the Art addon.

The Art addon used to be called `HighFidelityWorldMap_MapData_Forever` with `mapdata-v*` tags. Those tags are retired and hidden from the packager; a leftover `HighFidelityWorldMap_MapData_Forever` folder in an AddOns directory can be deleted.

When ready to publish:

- run **Create Release: Client** (or push a `v*` tag to `main`) to package the client, create the GitHub release (one asset, `hfwm-forever-client-v1.2.3.zip`) and then start **Publish Client Release to CurseForge**.
- run **Create Release: Art** (or push an `art-v*` tag to `main`) to generate the art, package `.pkgmeta-art`, create the GitHub release (one asset, `hfwm-forever-art-v1.2.3.zip`) and then start **Publish Art Release to CurseForge**.
- run either **Publish ... Release to CurseForge** workflow yourself with a release's tag to retry or redo that upload.

The `generate-world-map-assets` workflow builds and caches every generated tree on `main` — the HD art (`mapart-v3-<hash>`), the low-resolution maps (`maplow-v1-<hash>`) and the zone masks (`zonemasks-v1-<hash>`) — so a release only regenerates what the generator changed. Each release workflow's package step ignores the other series' tags.

## Notes

- Generated cave tile data is a build artifact and is not normally committed.
- `src/addon/client/data/` holds the committed generator-produced tables (`FDIDMap.lua`, `CaveData.lua`, `ZoneShapes.lua` and the rest); none of them is a hand-edited file.
- None of the generated map art is committed. `src/addon/client/WorldMap/`, `src/addon/client/ZoneMasks/` and `src/addon/art/WorldMap/` are all gitignored and built by CI (the `generate-world-map-assets` action), cached per tree. Regenerate locally with `python src/generator/generateHFWM.py` and `python src/generator/scripts/emit_zone_shapes.py`.
- `src/addon/client/Libs/` is fetched during local dev and CI; none of its contents are committed.
