-------------------------------------------------------------------------------
-- HFWM-Forever Custom Labels
--
-- Hand-kept labels for places the SD map scrawls by hand but the game's own
-- data classes differently (or not at all). Read by AreaLabels.lua. Not
-- generated; edit freely.
--
-- [uiMapID] = { { name, kind, u, v [, text, h] }, ... }
--   name  the text shown when no text is given. Not matched against
--         AreaLabelData.lua: a same-named label there is shown alongside this one.
--   text  optional text shown in place of name, for choosing the line breaks:
--         "\n" starts a new line.
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
    [1429] = {
        { name = "Northshire", kind = "poi", u = 0.524, v = 0.393 },
        { name = "Forest's Edge", kind = "poi", u = 0.245, v = 0.797 },
        { name = "Eastvale Logging Camp", kind = "poi", u = 0.851, v = 0.653 },
        { name = "Stone Cairn Lake", kind = "poi", u = 0.745, v = 0.451 },
    },
    [1423] = {
        { name = "Corin's Crossing", kind = "poi", u = 0.533, v = 0.573 },
        { name = "Darrowshire", kind = "poi", u = 0.339, v = 0.770 },
        { name = "New Avalon", kind = "poi", u = 0.835, v = 0.631 },
        { name = "Plaguewood", kind = "poi", u = 0.246, v = 0.247 },
        { name = "Stratholme", kind = "poi", u = 0.262, v = 0.131 },
        { name = "Tyr's Hand", kind = "poi", u = 0.735, v = 0.701 },
        { name = "Zul'Mashar", kind = "poi", u = 0.611, v = 0.096 },
    },
    [1422] = {
        { name = "Caer Darrow", kind = "poi", u = 0.690, v = 0.750 },
        { name = "Hearthglen", kind = "poi", u = 0.442, v = 0.145 },
        { name = "Ruins of Andorhal", kind = "poi", u = 0.434, v = 0.669 },
        { name = "The Bulwark", kind = "poi", u = 0.310, v = 0.587 },
    },
    [1426] = {
        { name = "Brewnall Village", text = "Brewnall\nVillage", kind = "poi", u = 0.308, v = 0.479 },
        { name = "Coldridge Valley", text = "Coldridge\nValley", kind = "poi", u = 0.268, v = 0.735 },
        { name = "Gol'Bolar Quarry", text = "Gol'Bolar\nQuarry", kind = "poi", u = 0.687, v = 0.581 },
    },
    [1432] = {
        { name = "Ironband's Excavation Site", text = "Ironband's\nExcavation Site", kind = "poi", u = 0.685, v = 0.668 },
        { name = "Mo'grosh Stronghold", text = "Mo'grosh\nStronghold", kind = "poi", u = 0.709, v = 0.233 },
        { name = "The Loch", kind = "poi", u = 0.504, v = 0.451 },
        { name = "Stonewrought Dam", text = "Stonewrought\nDam", kind = "poi", u = 0.480, v = 0.125 },
    },
    [1437] = {
        { name = "Whelgar's Excavation Site", text = "Whelgar's\nExcavation Site", kind = "poi", u = 0.353, v = 0.472 },
        { name = "Dun Algaz", kind = "poi", u = 0.506, v = 0.775 },
        { name = "Grim Batol", kind = "poi", u = 0.748, v = 0.751 },
    },
    [1417] = {
        { name = "Witherbark Village", text = "Witherbark\nVillage", kind = "poi", u = 0.681, v = 0.701 },
        { name = "Faldir's Cove", kind = "poi", u = 0.292, v = 0.813 },
        { name = "Stromgarde Keep", text = "Stromgarde\nKeep", kind = "poi", u = 0.236, v = 0.632 },
    },
    [1424] = {
        { name = "Durnholde Keep", kind = "poi", u = 0.797, v = 0.398 },
        { name = "Dun Garok", kind = "poi", u = 0.693, v = 0.758 },
        { name = "Azurelode Mine", text = "Azurelode\nMine", kind = "poi", u = 0.276, v = 0.602 },
        { name = "Hillsbrad Fields", kind = "poi", u = 0.328, v = 0.367 },
    },
    [1421] = {
        { name = "Pyrewood Village", text = "Pyrewood\nVillage", kind = "poi", u = 0.452, v = 0.732 },
        { name = "Ambermill", kind = "poi", u = 0.619, v = 0.637 },
        { name = "Fenris Isle", kind = "poi", u = 0.675, v = 0.280 },
    },
    [1420] = {
        { name = "Shadowvale", kind = "poi", u = 0.122, v = 0.649 },
        { name = "Bandarion Keep", text = "Bandarion\nKeep", kind = "poi", u = 0.218, v = 0.461 },
        { name = "Agamand Mills", text = "Agamand\nMills", kind = "poi", u = 0.483, v = 0.339 },
        { name = "Scarlet Monastery", text = "Scarlet\nMonastery", kind = "poi", u = 0.841, v = 0.360 },
        { name = "Undercity", kind = "capital", u = 0.616, v = 0.726 },
    },
    [1416] = {
        { name = "Strahnbrad", kind = "poi", u = 0.595, v = 0.438 },
        { name = "Ruins of Alterac", kind = "poi", u = 0.369, v = 0.509 },
        { name = "Dalaran", kind = "capital", u = 0.179, v = 0.705 },
    },
    [1425] = {
        { name = "Aerie Peak", text = "Aerie\nPeak", kind = "poi", u = 0.144, v = 0.480 },
        { name = "Quel'Danil Lodge", text = "Quel'Danil\nLodge", kind = "poi", u = 0.314, v = 0.448 },
        { name = "The Altar of Zul", text = "The Altar\nof Zul", kind = "poi", u = 0.470, v = 0.669 },
        { name = "Jintha'Alor", kind = "poi", u = 0.626, v = 0.747 },
        { name = "Seradane", kind = "poi", u = 0.643, v = 0.240 },
        { name = "Skulk Rock", kind = "poi", u = 0.591, v = 0.422 },
    },
    [1427] = {
        { name = "The Cauldron", text = "The\nCauldron", kind = "poi", u = 0.550, v = 0.447 },
        { name = "Blackrock Mountain", text = "Blackrock\nMountain", kind = "poi", u = 0.452, v = 0.850 },
        { name = "Stonewrought Pass", text = "Stonewrought\nPass", kind = "poi", u = 0.800, v = 0.132 },
    },
    [1428] = {
        { name = "Blackrock Mountain", text = "Blackrock\nMountain", kind = "poi", u = 0.290, v = 0.368 },
        { name = "The Pillar of Ash", kind = "poi", u = 0.541, v = 0.539 },
        { name = "Ruins of Thaurissan", text = "Ruins of\nThaurissan", kind = "poi", u = 0.609, v = 0.368 },
        { name = "Dreadmaul Rock", text = "Dreadmaul\nRock", kind = "poi", u = 0.791, v = 0.419 },
    },
    [1418] = {
        { name = "Lethlor Ravine", text = "Lethlor\nRavine", kind = "poi", u = 0.806, v = 0.499 },
        { name = "Dustbelch Grotto", text = "Dustbelch\nGrotto", kind = "poi", u = 0.082, v = 0.861 },
    },
    [2548] = {
        { name = "Bolder'ok", kind = "poi", u = 0.651, v = 0.180 },
        { name = "Rog'mar", kind = "poi", u = 0.589, v = 0.459 },
        { name = "Powderfuse Port", text = "Powderfuse\nPort", kind = "poi", u = 0.775, v = 0.541 },
        { name = "Farholde Keep", text = "Farholde\nKeep", kind = "poi", u = 0.637, v = 0.840 },
        { name = "Wheeler's Grange", text = "Wheeler's\nGrange", kind = "poi", u = 0.541, v = 0.758 },
        { name = "Sunnyglade", kind = "poi", u = 0.473, v = 0.490 },
        { name = "Twilight's Shroud", text = "Twilight's\nShroud", kind = "poi", u = 0.287, v = 0.438 },
    },
    [1433] = {
        { name = "Stonewatch Keep", text = "Stonewatch\nKeep", kind = "poi", u = 0.631, v = 0.512 },
        { name = "Tower of Ilgalar", text = "Tower of\nIlgalar", kind = "poi", u = 0.753, v = 0.489 },
        { name = "Lake Everstill", text = "Lake\nEverstill", kind = "poi", u = 0.385, v = 0.581 },
    },
    [1431] = {
        { name = "Twilight Grove", text = "The\nTwilight\nGrove", kind = "poi", u = 0.475, v = 0.407 },
        { name = "Tranquil Gardens Cemetery", text = "The\nTranquil Gardens\nCemetery", kind = "poi", u = 0.796, v = 0.722 },
    },
    [1436] = {
        { name = "Jangolode Mine", text = "Jangolode\nMine", kind = "poi", u = 0.438, v = 0.207 },
        { name = "Saldean's Farm", text = "Saldean's\nFarm", kind = "poi", u = 0.543, v = 0.336 },
        { name = "Gold Coast Quarry", text = "Gold Coast\nQuarry", kind = "poi", u = 0.324, v = 0.421 },
        { name = "Westfall Lighthouse", text = "Westfall\nLighthouse", kind = "poi", u = 0.305, v = 0.864 },
    },
    [1435] = {
        { name = "Fallow Sanctuary", text = "Fallow\nSanctuary", kind = "poi", u = 0.593, v = 0.237 },
        { name = "Misty Valley", text = "Misty\nValley", kind = "poi", u = 0.114, v = 0.346 },
    },
    [1419] = {
        { name = "Dreadmaul Hold", text = "Dreadmaul\nHold", kind = "poi", u = 0.450, v = 0.157 },
        { name = "Nethergarde Keep", text = "Nethergarde\nKeep", kind = "poi", u = 0.629, v = 0.187 },
        { name = "The Dark Portal", text = "The\nDark Portal", kind = "poi", u = 0.590, v = 0.560 },
        { name = "The Tainted Scar", text = "The\nTainted Scar", kind = "poi", u = 0.381, v = 0.679 },
    },
    [1430] = {
        { name = "Karazhan", kind = "poi", u = 0.473, v = 0.750 },
        { name = "The Vice", text = "The\nVice", kind = "poi", u = 0.567, v = 0.650 },
    },
    [1434] = {
        { name = "Lake Nazferiti", text = "Lake\nNazferiti", kind = "poi", u = 0.408, v = 0.184 },
        { name = "Mosh'Ogg Ogre Mound", text = "Mosh'Ogg\nOgre Mound", kind = "poi", u = 0.497, v = 0.278 },
        { name = "Gurubashi Arena", text = "Gurubashi\nArena", kind = "poi", u = 0.314, v = 0.489 },
    },
}
