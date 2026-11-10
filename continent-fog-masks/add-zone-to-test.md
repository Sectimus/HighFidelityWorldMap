# Adding a hand-traced zone to the continent fog test

Use this to turn one traced zone layer in a PSD into a live Fog of War mask and
update its boxes, so it can be checked in game. Background and the full spec are
in `continent-fog-masks.md`; this note is the short path for one zone.

Eastern Kingdoms by default, or Kalimdor with the `kalimdor` argument. Each continent's
UiMapID, terrain MapID and PSD are in `CONTINENTS` in `build_zone_mask.py`. Kalimdor's
1414 row (terrain MapID 1) was checked against `UiMapAssignment`.

## Inputs

- The zone's layer is in `continent-fog-masks/eastern-kingdoms-traces.psd`,
  named exactly `z<UiMapID>` (for example `z1436`). Check the zone is in the table
  in `continent-fog-masks.md`.
- The layer must be filled, with no open paths.
- The build needs `psd-tools`, `numpy`, `pillow` and `scipy`, plus the generator's
  `hfwm` package and network access for the DB2 table `UiMapAssignment`. If there is
  no venv, create one:

  ```sh
  python3 -m venv /tmp/hfwm-venv
  /tmp/hfwm-venv/bin/pip install psd-tools numpy pillow scipy
  ```

## Steps

1. Build the mask and print the boxes:

   ```sh
   /tmp/hfwm-venv/bin/python continent-fog-masks/build_zone_mask.py <zoneUiMapID> [eastern|kalimdor]
   ```

   This writes `src/addon/client/ZoneMasks/z<id>.blp` (BLP2 BGRA, longest side 1024) and
   prints two `RESULT` lines: the continent box and the 947 box.

2. Check the trace against the art:

   ```sh
   /tmp/hfwm-venv/bin/python continent-fog-masks/overlay_zone.py <id> <u0> <v0> <u1> <v1> [eastern|kalimdor]
   ```

   Pass the continent box from step 1. It writes `/tmp/z<id>_overlay.png`. Look at it
   with the image viewer. The red outline should sit on the painted border.

3. Compare the new 1415 box with the current row in
   `src/addon/client/data/ZoneShapes.lua`. The z1429 trace agreed with its chunk box
   to about 0.004. A large disagreement, like z1436's, is not automatically wrong: the
   art decides. Report the difference to the user, and do not hide it.

4. Update the two rows in `src/addon/client/data/ZoneShapes.lua`, one under `[1415]`
   and one under `[947]`. Replace only the lines starting `{<id>,`. Keep the old
   values for a revert. Then check the file:

   ```sh
   luac5.1 -p src/addon/client/data/ZoneShapes.lua
   ```

5. Test in game. The live `AddOns/HighFidelityWorldMap` is a symlink to
   `src/addon/client`, so the new mask is picked up without a copy. Run `/reload`,
   fully explore the zone, open the Eastern Kingdoms continent map and turn Fog of
   War on. The addon only draws masks for fully explored zones.

## Rules

- Do not run `src/generator/scripts/emit_zone_shapes.py` until all 43 zones are
  traced. It rewrites `ZoneShapes.lua` and regenerates the chunk masks, which drops
  the hand-traced rows.
- `ZoneMasks/` only has the zones traced so far. A fully explored zone with no mask
  file shows wrong fog in game, so keep untested zones unexplored when testing.
- Each zone's box is in 0–1 coordinates. Do not edit the 1415 and 947 rows by hand
  without re-running step 1.
- Shared borders need both neighbouring zones traced to meet. The Westfall (z1436)
  and Elwynn (z1429) boxes overlap around x 0.417–0.466, y 0.724–0.757. Check that
  seam in game before tracing more neighbours.
- `src/addon/client/WorldMap/` and `Libs/` are gitignored copies of the dist build.
  They are needed by the addon's fallback path and the Ace3 loader. Do not commit them.
- Generated and gitignored files (`ZoneMasks/`, `WorldMap/`, `Libs/`) must not be
  added to git. Check `git status` before committing.
