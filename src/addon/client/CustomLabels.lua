-------------------------------------------------------------------------------
-- HFWM-Forever Custom Labels
--
-- Hand-kept labels for places the SD map scrawls by hand but the game's own
-- data classes differently (or not at all). Read by AreaLabels.lua. Not
-- generated; edit freely.
--
-- [uiMapID] = { { name, kind, u, v [, text, h] }, ... }
--   name  the text shown when no text is given. Matched against AreaLabelData.lua
--         by name and kind: a shown custom label hides the same-named area label
--         of the same kind on that map. Different kinds are shown alongside.
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
--   hide  optional true: draws nothing, but hides the same-named same-kind area
--         label on that map (removes a generated label).
-- Example:
--   [1416] = {
--       { name = "Dalaran", kind = "capital", u = 0.179, v = 0.705 },
--   },
-------------------------------------------------------------------------------
HFWMF_CUSTOM_LABELS = {
    [2521] = {
        { name = "Ruins of Ban'aethal", text = "Ruins of\nBan'aethal", kind = "poi", u = 0.617, v = 0.248 },
        { name = "Thendal Village", text = "Thendal\nVillage", kind = "poi", u = 0.414, v = 0.185 },
        { name = "Shen'dar Village", text = "Shen'dar\nVillage", kind = "poi", u = 0.480, v = 0.436 },
        { name = "Falaath Village", text = "Falaath\nVillage", kind = "poi", u = 0.518, v = 0.535 },
        { name = "Shrine of Akir", text = "Shrine of\nAkir", kind = "poi", u = 0.634, v = 0.439 },
        { name = "Valanaar", kind = "poi", u = 0.637, v = 0.818 },
    },
    [1458] = {
        { name = "Canals", kind = "district", hide = true, u = 0.662, v = 0.435 },
    },
    [1429] = {
        { name = "Northshire", kind = "poi", u = 0.486, v = 0.433 },
        { name = "Forest's Edge", kind = "poi", u = 0.304, v = 0.804 },
        { name = "Eastvale Logging Camp", text = "Eastvale\nLogging Camp", kind = "poi", u = 0.815, v = 0.617 },
        { name = "Stone Cairn Lake", kind = "poi", u = 0.745, v = 0.451 },
    },
    [1423] = {
        { name = "Corin's Crossing", text = "Corin's\nCrossing", kind = "poi", u = 0.518, v = 0.529 },
        { name = "Darrowshire", kind = "poi", u = 0.332, v = 0.743 },
        { name = "New Avalon", text = "New\nAvalon", kind = "poi", u = 0.836, v = 0.765 },
        { name = "Plaguewood", kind = "poi", u = 0.292, v = 0.290 },
        { name = "Stratholme", kind = "poi", u = 0.260, v = 0.098 },
        { name = "Tyr's Hand", kind = "poi", u = 0.698, v = 0.763 },
        { name = "Zul'Mashar", kind = "poi", u = 0.648, v = 0.126 },
    },
    [1422] = {
        { name = "Caer Darrow", kind = "poi", u = 0.690, v = 0.750 },
        { name = "Hearthglen", kind = "poi", u = 0.437, v = 0.113 },
        { name = "Ruins of Andorhal", text = "Ruins of\nAndorhal", kind = "poi", u = 0.444, v = 0.695 },
        { name = "The Bulwark", text = "The\nBulwark", kind = "poi", u = 0.281, v = 0.596 },
    },
    [1426] = {
        { name = "Brewnall Village", text = "Brewnall\nVillage", kind = "poi", u = 0.296, v = 0.427 },
        { name = "Coldridge Valley", text = "Coldridge\nValley", kind = "poi", u = 0.281, v = 0.747 },
        { name = "Gol'Bolar Quarry", text = "Gol'Bolar\nQuarry", kind = "poi", u = 0.631, v = 0.576 },
    },
    [1432] = {
        { name = "Ironband's Excavation Site", text = "Ironband's\nExcavation Site", kind = "poi", u = 0.686, v = 0.618 },
        { name = "Mo'grosh Stronghold", text = "Mo'grosh\nStronghold", kind = "poi", u = 0.696, v = 0.226 },
        { name = "The Loch", text = "The\nLoch", kind = "poi", u = 0.514, v = 0.470 },
        { name = "Stonewrought Dam", text = "Stonewrought\nDam", kind = "poi", u = 0.482, v = 0.169 },
    },
    [1437] = {
        { name = "Whelgar's Excavation Site", text = "Whelgar's\nExcavation Site", kind = "poi", u = 0.352, v = 0.450 },
        { name = "Dun Algaz", kind = "poi", u = 0.537, v = 0.743 },
        { name = "Grim Batol", kind = "poi", u = 0.785, v = 0.678 },
    },
    [1417] = {
        { name = "Witherbark Village", text = "Witherbark\nVillage", kind = "poi", u = 0.662, v = 0.687 },
        { name = "Faldir's Cove", kind = "poi", u = 0.341, v = 0.767 },
        { name = "Stromgarde Keep", text = "Stromgarde\nKeep", kind = "poi", u = 0.249, v = 0.605 },
    },
    [1424] = {
        { name = "Durnholde Keep", kind = "poi", u = 0.772, v = 0.377 },
        { name = "Dun Garok", kind = "poi", u = 0.688, v = 0.735 },
        { name = "Azurelode Mine", text = "Azurelode\nMine", kind = "poi", u = 0.273, v = 0.617 },
        { name = "Hillsbrad Fields", kind = "poi", u = 0.331, v = 0.329 },
    },
    [1421] = {
        { name = "Pyrewood Village", text = "Pyrewood\nVillage", kind = "poi", u = 0.471, v = 0.774 },
        { name = "Ambermill", kind = "poi", u = 0.603, v = 0.657 },
        { name = "Fenris Isle", kind = "poi", u = 0.662, v = 0.221 },
    },
    [1420] = {
        { name = "Shadowvale", kind = "poi", u = 0.143, v = 0.648 },
        { name = "Bandarion Keep", text = "Bandarion\nKeep", kind = "poi", u = 0.226, v = 0.420 },
        { name = "Agamand Mills", text = "Agamand\nMills", kind = "poi", u = 0.478, v = 0.371 },
        { name = "Scarlet Monastery", text = "Scarlet\nMonastery", kind = "poi", u = 0.841, v = 0.360 },
        { name = "Undercity", kind = "capital", u = 0.616, v = 0.726 },
    },
    [1416] = {
        { name = "Strahnbrad", kind = "poi", u = 0.612, v = 0.414 },
        { name = "Ruins of Alterac", kind = "poi", u = 0.369, v = 0.509 },
        { name = "Dalaran", kind = "capital", u = 0.179, v = 0.705 },
    },
    [1425] = {
        { name = "Quel'Danil Lodge", text = "Quel'Danil\nLodge", kind = "poi", u = 0.331, v = 0.499 },
        { name = "The Altar of Zul", text = "The Altar\nof Zul", kind = "poi", u = 0.467, v = 0.644 },
        { name = "Jintha'Alor", kind = "poi", u = 0.626, v = 0.747 },
        { name = "Seradane", kind = "poi", u = 0.623, v = 0.193 },
        { name = "Skulk Rock", kind = "poi", u = 0.581, v = 0.414 },
    },
    [1427] = {
        { name = "The Cauldron", text = "The\nCauldron", kind = "poi", u = 0.550, v = 0.447 },
        { name = "Blackrock Mountain", text = "Blackrock\nMountain", kind = "poi", u = 0.452, v = 0.850 },
        { name = "Stonewrought Pass", text = "Stonewrought\nPass", kind = "poi", u = 0.800, v = 0.132 },
    },
    [1428] = {
        { name = "Blackrock Mountain", text = "Blackrock\nMountain", kind = "poi", u = 0.296, v = 0.336 },
        { name = "Pillar of Ash", kind = "poi", u = 0.488, v = 0.551 },
        { name = "Ruins of Thaurissan", text = "Ruins of\nThaurissan", kind = "poi", u = 0.658, v = 0.381 },
        { name = "Dreadmaul Rock", text = "Dreadmaul\nRock", kind = "poi", u = 0.814, v = 0.416 },
    },
    [1418] = {
        { name = "Lethlor Ravine", text = "Lethlor\nRavine", kind = "poi", u = 0.813, v = 0.533 },
        { name = "Dustbelch Grotto", text = "Dustbelch\nGrotto", kind = "poi", u = 0.122, v = 0.832 },
        { name = "Uldaman", kind = "poi", u = 0.480, v = 0.137 },
        { name = "Kargath", kind = "town", u = 0.099, v = 0.451 },
        { name = "Angor Fortress", text = "Angor\nFortress", kind = "town", u = 0.482, v = 0.312 },
    },
    [2548] = {
        { name = "Bolder'ok", kind = "poi", u = 0.653, v = 0.109 },
        { name = "Rog'mar", kind = "poi", u = 0.586, v = 0.470 },
        { name = "Powderfuse Port", text = "Powderfuse\nPort", kind = "poi", u = 0.775, v = 0.541 },
        { name = "Farholde Keep", text = "Farholde\nKeep", kind = "poi", u = 0.673, v = 0.776 },
        { name = "Wheeler's Grange", text = "Wheeler's\nGrange", kind = "poi", u = 0.541, v = 0.812 },
        { name = "Sunnyglade", kind = "poi", u = 0.466, v = 0.581 },
        { name = "Twilight's Shroud", text = "Twilight's\nShroud", kind = "poi", u = 0.264, v = 0.483 },
    },
    [1433] = {
        { name = "Stonewatch Keep", text = "Stonewatch\nKeep", kind = "poi", u = 0.624, v = 0.581 },
        { name = "Tower of Ilgalar", text = "Tower of\nIlgalar", kind = "poi", u = 0.743, v = 0.520 },
        { name = "Lake Everstill", text = "Lake\nEverstill", kind = "poi", u = 0.382, v = 0.572 },
    },
    [1431] = {
        { name = "Twilight Grove", text = "The\nTwilight\nGrove", kind = "poi", u = 0.480, v = 0.421 },
        { name = "Tranquil Gardens Cemetery", text = "The\nTranquil Gardens\nCemetery", kind = "poi", u = 0.772, v = 0.644 },
    },
    [1436] = {
        { name = "Jangolode Mine", text = "Jangolode\nMine", kind = "poi", u = 0.426, v = 0.271 },
        { name = "Saldean's Farm", text = "Saldean's\nFarm", kind = "poi", u = 0.534, v = 0.369 },
        { name = "Gold Coast Quarry", text = "Gold Coast\nQuarry", kind = "poi", u = 0.321, v = 0.486 },
        { name = "Westfall Lighthouse", text = "Westfall\nLighthouse", kind = "poi", u = 0.262, v = 0.878 },
    },
    [1435] = {
        { name = "Fallow Sanctuary", text = "Fallow\nSanctuary", kind = "poi", u = 0.626, v = 0.217 },
        { name = "Misty Valley", kind = "poi", u = 0.133, v = 0.316 },
        { name = "Temple of Atal'Hakkar", text = "Temple of\nAtal'Hakkar", kind = "poi", u = 0.704, v = 0.503 },
    },
    [1419] = {
        { name = "Dreadmaul Hold", text = "Dreadmaul\nHold", kind = "poi", u = 0.434, v = 0.163 },
        { name = "Nethergarde Keep", text = "Nethergarde\nKeep", kind = "poi", u = 0.642, v = 0.215 },
        { name = "The Dark Portal", text = "The\nDark Portal", kind = "poi", u = 0.579, v = 0.553 },
        { name = "The Tainted Scar", text = "The\nTainted Scar", kind = "poi", u = 0.385, v = 0.600 },
    },
    [1430] = {
        { name = "Karazhan", kind = "poi", u = 0.458, v = 0.687 },
        { name = "The Vice", text = "The\nVice", kind = "poi", u = 0.602, v = 0.663 },
    },
    [1434] = {
        { name = "Lake Nazferiti", text = "Lake\nNazferiti", kind = "poi", u = 0.408, v = 0.184 },
        { name = "Mosh'Ogg Ogre Mound", text = "Mosh'Ogg\nOgre Mound", kind = "poi", u = 0.496, v = 0.306 },
        { name = "Gurubashi Arena", text = "Gurubashi\nArena", kind = "poi", u = 0.304, v = 0.451 },
        { name = "Grom'gol Base Camp", text = "Grom'gol\nBase Camp", kind = "town", u = 0.319, v = 0.284 },
    },
    [1438] = {
        { name = "Shadowglen", kind = "poi", u = 0.607, v = 0.433 },
        { name = "Dolanaar", kind = "poi", u = 0.559, v = 0.613 },
        { name = "Starbreeze Village", text = "Starbreeze\nVillage", kind = "poi", u = 0.662, v = 0.628 },
        { name = "The Oracle Glade", text = "The Oracle\nGlade", kind = "poi", u = 0.380, v = 0.278 },
        { name = "Rut'theran Village", text = "Rut'theran\nVillage", kind = "poi", u = 0.559, v = 0.874 },
    },
    [1439] = {
        { name = "Ruins of Mathystra", text = "Ruins of\nMathystra", kind = "poi", u = 0.577, v = 0.168 },
        { name = "Bashal'Aran", kind = "poi", u = 0.443, v = 0.382 },
        { name = "Ameth'Aran", kind = "poi", u = 0.425, v = 0.554 },
        { name = "Grove of the Ancients", text = "Grove of\nThe Ancients", kind = "poi", u = 0.387, v = 0.778 },
    },
    [1448] = {
        { name = "Felpaw Village", text = "Felpaw\nVillage", kind = "poi", u = 0.630, v = 0.134 },
        { name = "Irontree Woods", text = "Irontree\nWoods", kind = "poi", u = 0.498, v = 0.252 },
        { name = "Bloodvenom Falls", text = "Bloodvenom\nFalls", kind = "poi", u = 0.433, v = 0.473 },
        { name = "Jaedenar", kind = "poi", u = 0.343, v = 0.601 },
        { name = "Emerald Sanctuary", text = "Emerald\nSanctuary", kind = "poi", u = 0.512, v = 0.794 },
    },
    [2482] = {
        { name = "Summit of Eternity", text = "Summit of\nEternity", kind = "poi", u = 0.761, v = 0.302 },
        { name = "Dae'gun", kind = "poi", u = 0.533, v = 0.439 },
        { name = "Cradle of Tranquility", text = "Cradle of\nTranquility", kind = "poi", u = 0.340, v = 0.398 },
        { name = "Shrine of Aviana", text = "Shrine of\nAviana", kind = "poi", u = 0.525, v = 0.584 },
        { name = "Malorne's Retreat", text = "Malorne's\nRetreat", kind = "poi", u = 0.288, v = 0.679 },
        { name = "Felblood Scar", text = "Felblood\nScar", kind = "poi", u = 0.457, v = 0.752 },
        { name = "Elderwild", kind = "poi", u = 0.156, v = 0.453 },
        { name = "Mourning's Rest", text = "Mourning's\nRest", kind = "poi", u = 0.245, v = 0.535 },
        { name = "Tainted Foothills", text = "Tainted\nFoothills", kind = "poi", u = 0.684, v = 0.684 },
    },
    [1452] = {
        { name = "Frostsaber Rock", text = "Frostsaber\nRock", kind = "poi", u = 0.497, v = 0.133 },
        { name = "Starfall Village", text = "Starfall\nVillage", kind = "poi", u = 0.482, v = 0.283 },
        { name = "Darkwhisper Gorge", text = "Darkwhisper\nGorge", kind = "poi", u = 0.577, v = 0.832 },
    },
    [1447] = {
        { name = "Temple of Arkkoran", text = "Temple of\nArkkoran", kind = "poi", u = 0.755, v = 0.459 },
        { name = "Bay of Storms", text = "The\nBay of Storms", kind = "poi", u = 0.585, v = 0.588 },
        { name = "Ruins of Eldarath", text = "Ruins of\nEldarath", kind = "poi", u = 0.368, v = 0.546 },
        { name = "Forlorn Ridge", text = "The\nForlorn Ridge", kind = "poi", u = 0.297, v = 0.745 },
    },
    [1442] = {
        { name = "The Charred Vale", text = "The\nCharred Vale", kind = "poi", u = 0.321, v = 0.677 },
        { name = "Windshear Crag", text = "Windshear\nCrag", kind = "poi", u = 0.717, v = 0.470 },
    },
    [1443] = {
        { name = "Sargeron", kind = "poi", u = 0.755, v = 0.211 },
        { name = "Thunder Axe Fortress", text = "Thunder Axe\nFortress", kind = "poi", u = 0.549, v = 0.308 },
        { name = "Kodo Graveyard", kind = "poi", u = 0.513, v = 0.590 },
        { name = "Mannoroc Coven", kind = "poi", u = 0.525, v = 0.783 },
        { name = "Valley of Spears", kind = "poi", u = 0.336, v = 0.571 },
    },
    [1440] = {
        { name = "Maestra's Post", text = "Maestra's\nPost", kind = "poi", u = 0.270, v = 0.381 },
        { name = "The Talondeep Path", kind = "poi", u = 0.426, v = 0.697 },
        { name = "Raynewood Retreat", kind = "poi", u = 0.613, v = 0.538 },
        { name = "Splintertree Post", text = "Splintertree\nPost", kind = "poi", u = 0.738, v = 0.645 },
        { name = "Satyrnaar", kind = "poi", u = 0.808, v = 0.508 },
        { name = "Warsong Lumber Camp", text = "Warsong\nLumber Camp", kind = "poi", u = 0.909, v = 0.608 },
        { name = "The Zoram Strand", text = "The\nZoram Strand", kind = "poi", u = 0.137, v = 0.231 },
    },
    [1412] = {
        { name = "Red Cloud Mesa", text = "Red Cloud\nMesa", kind = "poi", u = 0.489, v = 0.791 },
        { name = "Brambleblade Ravine", text = "Brambleblade\nRavine", kind = "poi", u = 0.636, v = 0.790 },
        { name = "Red Rocks", kind = "poi", u = 0.567, v = 0.326 },
        { name = "Skywatcher Plateau", text = "Skywatcher\nPlateau", kind = "poi", u = 0.315, v = 0.182 },
    },
    [1411] = {
        { name = "Valley of Trials", text = "Valley of\nTrials", kind = "poi", u = 0.438, v = 0.617 },
        { name = "Echo Isles", kind = "poi", u = 0.654, v = 0.855 },
    },
    [1413] = {
        { name = "The Sludge Fen", text = "The\nSludge Fen", kind = "poi", u = 0.564, v = 0.052 },
        { name = "Wailing Caverns", text = "Wailing\nCaverns", kind = "poi", u = 0.463, v = 0.349 },
        { name = "Northwatch Hold", text = "Northwatch\nHold", kind = "poi", u = 0.594, v = 0.582 },
        { name = "Razorfen Kraul", text = "Razorfen\nKraul", kind = "poi", u = 0.409, v = 0.868 },
        { name = "Razorfen Downs", text = "Razorfen\nDowns", kind = "poi", u = 0.489, v = 0.913 },
    },
    [1445] = {
        { name = "Alcaz Island", kind = "poi", u = 0.757, v = 0.179 },
        { name = "Stonemaul Ruins", text = "Stonemaul\nRuins", kind = "poi", u = 0.457, v = 0.666 },
        { name = "Wyrmbog", text = "The\nWyrmbog", kind = "poi", u = 0.525, v = 0.731 },
    },
    [1444] = {
        { name = "Lower Wilds", text = "The\nLower Wilds", kind = "poi", u = 0.866, v = 0.474 },
        { name = "The High Wilderness", text = "The\nHigh Wilderness", kind = "poi", u = 0.582, v = 0.582 },
        { name = "Dire Maul", kind = "poi", u = 0.588, v = 0.411 },
        { name = "The Twin Colossals", text = "The\nTwin Colossals", kind = "poi", u = 0.458, v = 0.257 },
        { name = "Feathermoon Stronghold", text = "Feathermoon\nStronghold", kind = "poi", u = 0.315, v = 0.483 },
        { name = "Isle of Dread", kind = "poi", u = 0.299, v = 0.785 },
    },
    [1451] = {
        { name = "Staghelm Point", text = "Staghelm\nPoint", kind = "poi", u = 0.707, v = 0.280 },
        { name = "Cenarion Hold", text = "Cenarion\nHold", kind = "poi", u = 0.508, v = 0.366 },
        { name = "Bronzebeard Encampment", text = "Bronzebeard\nEncampment", kind = "poi", u = 0.409, v = 0.908 },
    },
    [1449] = {
        { name = "Marshal's Refuge", text = "Marshal's\nRefuge", kind = "poi", u = 0.522, v = 0.150 },
        { name = "Fire Plume Ridge", text = "Fire Plume\nRidge", kind = "poi", u = 0.510, v = 0.578 },
    },
    [1446] = {
        { name = "Zul'farrak", kind = "poi", u = 0.378, v = 0.151 },
        { name = "Abyssal Sands", text = "Abyssal\nSands", kind = "poi", u = 0.457, v = 0.415 },
        { name = "Caverns of Time", text = "Caverns\nof\nTime", kind = "poi", u = 0.628, v = 0.479 },
        { name = "Steamwheedle Port", text = "Steamwheedle\nPort", kind = "poi", u = 0.668, v = 0.196 },
        { name = "Uldum", kind = "poi", u = 0.368, v = 0.783 },
    },
    [1441] = {
        { name = "The Shimmering Flats", text = "The\nShimmering Flats", kind = "poi", u = 0.793, v = 0.718 },
        { name = "The Great Lift", text = "The\nGreat Lift", kind = "poi", u = 0.332, v = 0.215 },
    },
    [2652] = {
        { name = "Valley of Bones", kind = "poi", u = 0.340, v = 0.265 },
        { name = "Evenshade's Overlook", text = "Evenshade's\nOverlook", kind = "poi", u = 0.321, v = 0.418 },
        { name = "Outcast Hideaway", text = "Outcast\nHideaway", kind = "poi", u = 0.301, v = 0.745 },
        { name = "Shen'dralas", kind = "poi", u = 0.486, v = 0.830 },
        { name = "Magram Front", kind = "poi", u = 0.612, v = 0.569 },
        { name = "Forlorn Gardens", text = "Forlorn\nGardens", kind = "poi", u = 0.742, v = 0.755 },
        { name = "Bristleback Retreat", text = "Bristleback\nRetreat", kind = "poi", u = 0.642, v = 0.228 },
    },
}
