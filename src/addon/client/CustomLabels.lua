-------------------------------------------------------------------------------
-- HFWM-Forever Custom Labels
--
-- Hand-kept labels for places the SD map scrawls by hand but the game's own
-- data classes differently (or not at all). Read by AreaLabels.lua. Not
-- generated; edit freely.
--
-- [uiMapID] = { { name, kind, u, v [, text, h] }, ... }
--   name  the label's key: a label of the same name in AreaLabelData.lua on
--         that map is hidden while this entry shows, so the entry reclassifies
--         it rather than doubling it. Also the text shown when no text is given.
--   text  optional text shown in place of name, for choosing the line breaks:
--         "\n" starts a new line. Same-name matching still uses name.
--   kind  the category, which sets the style it takes and what shows it:
--           "continent", "capital", "town" (Towns/Hubs), "subzone" or
--           "district": shown when the Area Labels page's Include Custom
--           toggle for that type is on.
--           "poi" (Points of Interest): shown whenever that type is enabled.
--   u, v  the centre in 0-1 map coordinates from the map's top-left.
--   h     optional label height in canvas units at scale 1; defaults per kind
--         (AreaLabels.lua's DEFAULT_H).
-- Example:
--   [1416] = {
--       { name = "Dalaran", kind = "capital", u = 0.179, v = 0.705 },
--   },
-------------------------------------------------------------------------------
HFWMF_CUSTOM_LABELS = {
    [2521] = {
        { name = "Ruins of Ban'aethal", text = "Ruins of\nBan'aethal", kind = "poi", u = 0.578, v = 0.298 },
    },
}
