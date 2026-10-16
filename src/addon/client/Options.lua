-------------------------------------------------------------------------------
-- HFWM-Forever Options
-- The options panel, as an AceConfig-3.0 table: enable toggle,
-- remember/zoom toggles, the Map Background section (Global
-- Background plus a per-map-type override each for Zone/Continent/World),
-- the cave map section, and a profiles tab (AceDBOptions-3.0).
--
-- AceConfigDialog handles the rest: drawing the client's Interface Options
-- page (registered by RegisterClientPanel below) and the standalone window
-- /hfwm options opens, across every client flavour this addon supports.
-------------------------------------------------------------------------------
local addonName, ns = ...
local Options = ns.Options
local Config  = ns.Config

local PANEL_TITLE = "High Fidelity World Map"

--- Blizzard's own colour for a Battle.net-linked friend's name, the
--- closest thing the client already defines to an official "Blizzard
--- cyan". Reused here for "Use Global" (see MapTypeBackgroundValues)
--- same as CaveRenderer.lua reuses it for its floor-picker's "All" entry.
--- Falls back to the literal hex on a client build that doesn't expose
--- the constant as a global.
local BLIZZARD_CYAN_HEX = FRIENDS_BNET_NAME_COLOR_CODE or "|cff82c5ff"

--- {key = label} for every background this install can actually draw.
--- Used by the Global Background dropdown.
local function BackgroundValues()
    local values = {}
    for _, bg in ipairs(Config:AvailableBackgrounds()) do
        values[bg.key] = bg.label
    end
    return values
end

--- Same as BackgroundValues, plus "Use Global" up front, in Blizzard cyan
--- so it reads as the inherited/default choice rather than an ordinary
--- background -- same treatment CaveRenderer's floor picker gives "All".
--- Used by the Zone/Continent/World Map dropdowns, which can each either
--- inherit the Global Background or name one of their own.
local function MapTypeBackgroundValues()
    local values = { global = BLIZZARD_CYAN_HEX .. "Use Global|r" }
    for _, bg in ipairs(Config:AvailableBackgrounds()) do
        values[bg.key] = bg.label
    end
    return values
end

--- Fog of War only works over Blizzard's own art, which only Hybrid leaves
--- showing. Each map type's checkbox is disabled (not hidden) otherwise,
--- with the reason appended to its tooltip.
local function NotHybrid(mapTypeKey)
    return function() return not Config:MapTypeBackgroundIsHybrid(mapTypeKey) end
end
local HYBRID_ONLY = "\n\n|cffff8800Fog of War is only supported with the "
    .. "Hybrid background type.|r"
local function FogDesc(base, mapTypeKey)
    return function()
        return Config:MapTypeBackgroundIsHybrid(mapTypeKey) and base
            or base .. HYBRID_ONLY
    end
end
local FOG_ZONE_DESC = "Fog of war hides unexplored areas on the map, and "
    .. "fills them in as you progress and explore."
local FOG_WORLD_DESC = "On the World map, only draws this addon's map over "
    .. "zones you have fully explored. A zone with any area still "
    .. "undiscovered stays as the game draws it."
local FOG_CONTINENT_DESC = "On the Continent maps, only draws this addon's "
    .. "map over zones you have fully explored. A zone with any area still "
    .. "undiscovered stays as the game draws it."

--- High Resolution World and continent maps come from the optional Art
--- addon. Without it that one Map Resolution entry is disabled (everything
--- else, low resolution included, ships with this addon) and explains why.
local ART_URL = "https://www.curseforge.com/wow/addons/high-fidelity-world-map-art"
local ART_NOTE = "Requires the High Fidelity World Map: Art addon, which is "
    .. "not installed or not enabled. Install it and reload the UI to "
    .. "unlock it."

-- The game can't open a browser, so the link goes in a popup's edit box,
-- selected for Ctrl+C. Edits are undone so it stays copy-only.
StaticPopupDialogs["HFWM_ART_URL"] = {
    text = "High Resolution needs the High Fidelity World Map: Art addon.\n"
        .. "Copy this link (Ctrl+C) and open it in your browser:",
    button1 = CLOSE,
    hasEditBox = true,
    editBoxWidth = 350,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnShow = function(self)
        self:SetFrameStrata("TOOLTIP")  -- above the options window
        local box = self.EditBox or self.editBox
        box:SetText(ART_URL)
        box:HighlightText()
        box:SetFocus()
    end,
    EditBoxOnTextChanged = function(box)
        if box:GetText() ~= ART_URL then
            box:SetText(ART_URL)
            box:HighlightText()
        end
    end,
    EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
}

--- Dropdown that disables its "high" entry, with a tooltip saying why,
--- while the Art addon is missing. AceConfig has no per-entry disable, so
--- the Map Resolution row asks for this through `dialogControl`.
local RESOLUTION_DROPDOWN = "HFWM-ResolutionDropdown"
do
    local AceGUI = LibStub("AceGUI-3.0")

    -- An open pullout and its items are moved to TOOLTIP strata (AceGUI
    -- Dropdown-Pullout Open) at levels above the options window's, so a
    -- tooltip left at its own level can draw underneath them. A tooltip of
    -- our own (as AceConfigDialog has) is raised over the hovered item each
    -- time without re-levelling or tainting the shared GameTooltip.
    local tooltip = CreateFrame("GameTooltip", "HFWMArtTooltip", UIParent, "GameTooltipTemplate")
    tooltip:SetFrameStrata("TOOLTIP")

    local function ShowArtTooltip(item)
        tooltip:SetOwner(item.frame, "ANCHOR_RIGHT")
        tooltip:SetFrameLevel(item.frame:GetFrameLevel() + 10)
        tooltip:SetText("High Resolution unavailable", 1, 1, 1)
        tooltip:AddLine(ART_NOTE, 1, 0.53, 0, true)
        tooltip:AddLine(" ")
        tooltip:AddLine("Click to show the CurseForge link for the Art addon.",
            0, 1, 1, true)
        tooltip:Show()
    end

    AceGUI:RegisterWidgetType(RESOLUTION_DROPDOWN, function()
        local dropdown = AceGUI.WidgetRegistry.Dropdown()
        dropdown.type = RESOLUTION_DROPDOWN  -- own pool, not Dropdown's
        local setList = dropdown.SetList
        function dropdown:SetList(...)
            setList(self, ...)
            if Config:IsArtInstalled() then return end
            for _, item in self.pullout:IterateItems() do
                if item.userdata.value == "high" then
                    item:SetDisabled(true)
                    item:SetCallback("OnEnter", ShowArtTooltip)
                    item:SetCallback("OnLeave", function() tooltip:Hide() end)
                    item.hfwmArt = true
                    -- A disabled item's own OnClick is skipped by AceGUI, so
                    -- hook the frame; hfwmArt/disabled stop pooled items
                    -- reused elsewhere from opening it.
                    if not item.frame.hfwmArtHooked then
                        item.frame.hfwmArtHooked = true
                        item.frame:HookScript("OnClick", function(frame)
                            local it = frame.obj
                            if it.hfwmArt and it.disabled then
                                tooltip:Hide()
                                it.pullout:Close()
                                StaticPopup_Show("HFWM_ART_URL")
                            end
                        end)
                    end
                end
            end
        end
        return dropdown
    end, 1)
end

--- Checkbox that keeps its tooltip while disabled. The stock one calls
--- frame:Disable(), after which this client sends no OnEnter, so the "only
--- supported with Hybrid" tooltip never showed. AceGUI's click handlers
--- already ignore clicks while `self.disabled`, so re-enabling the frame
--- only restores mouse-over.
local FOG_CHECKBOX = "HFWM-FogCheckBox"
do
    local AceGUI = LibStub("AceGUI-3.0")
    AceGUI:RegisterWidgetType(FOG_CHECKBOX, function()
        local checkbox = AceGUI.WidgetRegistry.CheckBox()
        checkbox.type = FOG_CHECKBOX  -- own pool, not CheckBox's
        local setDisabled = checkbox.SetDisabled
        function checkbox:SetDisabled(disabled)
            setDisabled(self, disabled)
            self.frame:Enable()
        end
        return checkbox
    end, 1)
end
-- Same StaticPopup pattern as HFWM_ART_URL above: confirmation before a
-- destructive action. ResetProfile resets the current profile in place and
-- fires OnProfileReset (-> Config:RefreshProfile); the rest is state that
-- RefreshProfile doesn't cover. mapFade is a game CVar, not in the profile.
local function RefreshAfterReset()
    ns.ToggleButton:Refresh()
    ns.Coords:Refresh()
    ns.KeepCentered:Refresh()
    ns.CaveRenderer:ApplyAlpha()
    ns.CaveRenderer:Relayout()
end
StaticPopupDialogs["HFWM_RESET_SETTINGS"] = {
    text = "Reset all High Fidelity World Map settings to their defaults?\n"
        .. "Any unsaved changes will be lost.",
    button1 = ACCEPT,
    button2 = CANCEL,
    OnAccept = function()
        _G.SetCVar("mapFade", "1")
        Config.dbObj:ResetProfile()
        RefreshAfterReset()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
-- One page's worth of the above: restores just that page's `keys` (see
-- MAIN_PAGE/SUB_PAGES), passed in as the popup's data.
StaticPopupDialogs["HFWM_RESET_PAGE"] = {
    text = "Reset the %s settings to their defaults?\n"
        .. "Settings on other pages are left alone.",
    button1 = ACCEPT,
    button2 = CANCEL,
    OnAccept = function(_, page)
        for _, key in ipairs(page.keys) do
            Config.db[key] = Config.DEFAULTS[key]
        end
        if page.onReset then page.onReset() end
        Config:RefreshProfile()
        RefreshAfterReset()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local options = {
    type = "group",
    name = PANEL_TITLE,
    args = {
        intro = {
            order = 1,
            type = "description",
            name = "Satellite world map stitched from the game's own "
                .. "minimap terrain tiles.\n",
        },
        enabled = {
            order = 10,
            type = "toggle",
            name = "Enable",
            desc = "Enables High Fidelity World Map",
            get = function() return Config.db.enabled end,
            set = function(_, value)
                Config.db.enabled = value
                ns.Renderer:ForceRefresh()
                ns.ToggleButton:Refresh()
                ns.Coords:Refresh()
                ns.MapLabels:Refresh()
            end,
        },
        rememberMapZoomPan = {
            order = 40,
            type = "toggle",
            name = "Remember zoom+pan",
            desc = "Keeps the world map at the zoom and pan you left it "
                .. "at when you reopen it on the same map. A different "
                .. "map (you travelled, or were looking elsewhere) opens "
                .. "on your current zone as usual.",
            get = function() return Config.db.rememberMapZoomPan end,
            set = function(_, value)
                Config.db.rememberMapZoomPan = value
                if not value then ns.MapMemory:Clear() end
            end,
        },
        additionalZoomLevels = {
            order = 50,
            type = "toggle",
            name = "Additional zoom levels",
            desc = "Lets the world map zoom eight steps closer than the "
                .. "client's own maximum.\n\n|cffff8800Does not currently work "
                .. "with the Gamepad UI: its map code uses a different "
                .. "Blizzard API, and adding zoom levels there causes "
                .. "taint.|r",
            get = function() return Config.db.additionalZoomLevels end,
            set = function(_, value)
                Config.db.additionalZoomLevels = value
                ns.ZoomLevels:Refresh()
            end,
        },
        keepCentered = {
            order = 55,
            type = "toggle",
            name = "Keep Centered",
            desc = "Pans the world map as you move so your arrow stays "
                .. "in the center of it.",
            get = function() return Config.db.keepCentered end,
            set = function(_, value)
                Config.db.keepCentered = value
                ns.KeepCentered:Refresh()
            end,
        },
        fadeWhenMoving = {
            order = 56,
            type = "toggle",
            name = "Fade when moving",
            desc = "Fades the map when you start moving for you to see the "
                .. "3d world more. Don't wanna buttpull anything!",
            -- Inverted from the mapFade console variable: checked (the
            -- default) means the game's own fade-while-moving stays on.
            get = function() return _G.GetCVar("mapFade") ~= "0" end,
            set = function(_, value)
                _G.SetCVar("mapFade", value and "1" or "0")
            end,
        },

        showPlayerCoords = {
            order = 57,
            type = "toggle",
            name = "Player Coordinates",
            desc = "Shows or hides the game's own player coordinates "
                .. "on the world map.",
            get = function() return Config.db.showPlayerCoords end,
            set = function(_, value)
                Config.db.showPlayerCoords = value
                ns.Coords:Refresh()
            end,
        },
        showMouseCoords = {
            order = 58,
            type = "toggle",
            name = "Mouse Coordinates",
            desc = "Shows or hides the game's own cursor coordinates "
                .. "on the world map.",
            get = function() return Config.db.showMouseCoords end,
            set = function(_, value)
                Config.db.showMouseCoords = value
                ns.Coords:Refresh()
            end,
        },

        toggleButtonEnabled = {
            order = 72,
            type = "toggle",
            name = "HD/SD Toggle",
            desc = "Adds a small red button to the top-right corner of the "
                .. "world map pane to switch between hfwm and vanilla map "
                .. "tiles",
            get = function() return Config.db.toggleButtonEnabled end,
            set = function(_, value)
                Config.db.toggleButtonEnabled = value
                ns.ToggleButton:Refresh()
            end,
        },
        toggleButtonMovable = {
            order = 73,
            type = "toggle",
            name = "Moveable toggle",
            desc = "Lets you click and drag the HD/SD button to another "
                .. "spot on the world map, for when another addon uses "
                .. "the same corner. It stays inside the map, and its "
                .. "position is remembered even if this is turned off. "
                .. "Reset to defaults puts it back.",
            disabled = function() return not Config.db.toggleButtonEnabled end,
            get = function() return Config.db.toggleButtonMovable end,
            set = function(_, value)
                Config.db.toggleButtonMovable = value
            end,
        },
        mapBackground = {
            order = 75,
            type = "group",
            inline = true,
            -- Boxed section, same treatment as Cave map just below it --
            -- not a tab under Profiles' tree, and placed above Cave map since
            -- it matters more.
            name = "Map Background",
            args = {
                globalBackground = {
                    order = 10,
                    type = "select",
                    -- width = "full": its own row, set apart from the
                    -- Zone/World/Continent rows below.
                    width = "full",
                    name = "Global Background",
                    desc = function() return Config:GetBackground().desc end,
                    values = BackgroundValues,
                    get = function() return Config:GetBackground().key end,
                    set = function(_, value) Config:SetBackground(value) end,
                },
                -- Zone/World/Continent Map dropdowns, stacked below Global
                -- Background, filled in just after this table from
                -- Config.MAP_TYPES.
            },
        },
        extraLabels = {
            order = 76,
            type = "group",
            inline = true,
            name = "Extra Labels",
            args = {
                showLocationNames = {
                    order = 10,
                    type = "toggle",
                    name = "Location Names",
                    desc = "Shows the names of towns and other places on "
                        .. "the world map, such as Ironforge.",
                    get = function() return Config.db.showLocationNames end,
                    set = function(_, value)
                        Config.db.showLocationNames = value
                        ns.MapLabels:Refresh()
                    end,
                },
                labelShowOnSD = {
                    order = 12,
                    type = "toggle",
                    name = "Show on SD",
                    desc = "Keeps the extra labels fully visible on SD maps, "
                        .. "not just HD. Off, they fade in as the HD/SD "
                        .. "slider passes 50%.",
                    disabled = function() return not Config.db.showLocationNames end,
                    get = function() return Config.db.labelShowOnSD end,
                    set = function(_, value)
                        Config.db.labelShowOnSD = value
                        ns.MapLabels:Refresh()
                    end,
                },
                labelAutoScale = {
                    order = 15,
                    type = "toggle",
                    name = "Auto-scale",
                    desc = "Grows the extra labels as you zoom out and shrinks "
                        .. "them as you zoom in, starting from the Label Scale "
                        .. "size at the loosest zoom.",
                    disabled = function() return not Config.db.showLocationNames end,
                    get = function() return Config.db.labelAutoScale end,
                    set = function(_, value)
                        Config.db.labelAutoScale = value
                        ns.MapLabels:Refresh()
                    end,
                },
                labelScale = {
                    order = 20,
                    type = "range",
                    name = "Label Scale",
                    desc = "Size of the extra map labels, such as Ironforge, "
                        .. "as a multiple of their default size.",
                    min = 0.5, max = 2, step = 0.05, isPercent = true,
                    disabled = function() return not Config.db.showLocationNames end,
                    get = function() return Config.db.labelScale end,
                    set = function(_, value)
                        Config.db.labelScale = value
                        ns.MapLabels:Refresh()
                    end,
                },
            },
        },
        cave = {
            order = 80,
            type = "group",
            inline = true,
            name = "Cave map",
            args = {
                intro = {
                    order = 1,
                    type = "description",
                    name = "Opens a small window over the world map for "
                        .. "caves and mines.\n",
                },
                caveEnabled = {
                    order = 10,
                    type = "toggle",
                    name = "Enable the cave map",
                    desc = "Turns the cave map window on or off.",
                    get = function() return Config.db.caveEnabled end,
                    set = function(_, value)
                        Config.db.caveEnabled = value
                        if value then
                            -- On a client with no interior maps, the
                            -- checkbox going green would otherwise be the
                            -- only feedback the user gets.
                            ns.Cave:WarnIfUnsupported()
                            ns.Cave:Unsuppress()
                            ns.Cave:UpdateState()
                        else
                            ns.Cave:UpdateState()
                        end
                    end,
                },
                caveAutoOpen = {
                    order = 20,
                    type = "toggle",
                    name = "Open automatically",
                    desc = "Opens the cave map the instant you enter a "
                        .. "tracked cave.",
                    disabled = function() return not (Config.db.enabled and Config.db.caveEnabled) end,
                    get = function() return Config.db.caveAutoOpen end,
                    set = function(_, value) Config.db.caveAutoOpen = value end,
                },
                caveRememberState = {
                    order = 30,
                    type = "toggle",
                    name = "Remember state",
                    desc = "Reopens the cave map only if it was open when "
                        .. "you last closed one. Takes over from Open "
                        .. "Automatically when the two disagree.",
                    disabled = function() return not (Config.db.enabled and Config.db.caveEnabled) end,
                    get = function() return Config.db.caveRememberState end,
                    set = function(_, value)
                        Config.db.caveRememberState = value
                    end,
                },
                caveKeepOpen = {
                    order = 35,
                    type = "toggle",
                    name = "Keep open",
                    desc = "Keeps the cave map open on its own when you "
                        .. "close the world map.",
                    disabled = function() return not (Config.db.enabled and Config.db.caveEnabled) end,
                    get = function() return Config.db.caveKeepOpen end,
                    set = function(_, value)
                        Config.db.caveKeepOpen = value
                        -- Re-parent an already-open window now.
                        ns.CaveRenderer:Relayout()
                    end,
                },
                caveWindowPlacement = {
                    order = 36,
                    type = "select",
                    name = "Default placement",
                    desc = "Where the cave map opens. Remember reopens it "
                        .. "wherever you last dragged it.",
                    values = {
                        inside = "Inside World Map Pane",
                        outside = "Outside World Map Pane",
                        remember = "Remember",
                    },
                    sorting = { "inside", "outside", "remember" },
                    disabled = function() return not (Config.db.enabled and Config.db.caveEnabled) end,
                    get = function() return Config.db.cavePlacement end,
                    set = function(_, value)
                        Config.db.cavePlacement = value
                        ns.CaveRenderer:Relayout()
                    end,
                },
                caveOtherIndoors = {
                    order = 37,
                    type = "toggle",
                    name = "Other indoors (beta)",
                    desc = "Also opens the cave map inside buildings, "
                        .. "houses and every other indoor area, not just "
                        .. "caves, mines and dungeons.",
                    disabled = function() return not (Config.db.enabled and Config.db.caveEnabled) end,
                    get = function() return Config.db.caveOtherIndoors end,
                    set = function(_, value)
                        Config.db.caveOtherIndoors = value
                        ns.Cave:Unsuppress()
                        ns.Cave:UpdateState()
                    end,
                },
                caveAlpha = {
                    order = 40,
                    type = "range",
                    name = "Cave map opacity",
                    desc = "Opacity of the cave map window background. At 0% only the border and map elements are visible.",
                    min = 0, max = 1, step = 0.05, isPercent = true,
                    disabled = function() return not (Config.db.enabled and Config.db.caveEnabled) end,
                    get = function() return Config:CaveAlpha() end,
                    set = function(_, value)
                        Config.db.caveAlpha = value
                        ns.CaveRenderer:ApplyAlpha()
                    end,
                },
                caveScale = {
                    order = 45,
                    type = "range",
                    name = "Cave map window scale",
                    desc = "Size of the cave map window, as a multiple of "
                        .. "its default size. Applied the next time it "
                        .. "opens or relayouts.",
                    min = 0.5, max = 2, step = 0.05, isPercent = true,
                    disabled = function() return not (Config.db.enabled and Config.db.caveEnabled) end,
                    get = function() return Config:CaveWindowScale() end,
                    set = function(_, value)
                        Config.db.caveWindowScale = value
                        ns.CaveRenderer:Relayout()
                    end,
                },
            },
        },
        instance = {
            order = 85,
            type = "group",
            inline = true,
            name = "Instance map (beta)",
            args = {
                instanceDungeonEnabled = {
                    order = 10,
                    type = "toggle",
                    name = "Dungeon",
                    desc = "Shows the instance map inside dungeons.",
                    disabled = function() return not Config.db.enabled end,
                    get = function() return Config.db.instanceDungeonEnabled end,
                    set = function(_, value)
                        Config.db.instanceDungeonEnabled = value
                        ns.Cave:UpdateState()
                    end,
                },
                instanceRaidEnabled = {
                    order = 20,
                    type = "toggle",
                    name = "Raid",
                    desc = "Shows the instance map inside raids.",
                    disabled = function() return not Config.db.enabled end,
                    get = function() return Config.db.instanceRaidEnabled end,
                    set = function(_, value)
                        Config.db.instanceRaidEnabled = value
                        ns.Cave:UpdateState()
                    end,
                },
            },
        },
    },
}
-- Zone/World/Continent Map dropdowns, one per Config.MAP_TYPES entry,
-- stacked vertically (each row: a relWidth 0.32 dropdown, then whatever
-- else belongs on its right). Built with a loop so the order/name/desc/
-- get/set/width wiring can't drift between them.
--
-- AceConfigDialog flows widgets left to right and wraps when one doesn't
-- fit, so a row is forced to end by padding it past 0.68 of the width with
-- a blank description -- otherwise the next dropdown would slide up beside
-- this one. Replace the filler with real widgets as the right-hand side
-- fills up; just keep each row's relWidths summing to 0.9-0.99.
--
-- Display order top to bottom is Zone, World, Continent -- Continent last
-- rather than in Config.MAP_TYPES' own zone/continent/world order, which
-- stays as-is since other code reads it independently of how Options lays
-- these out.
local MAP_TYPE_ORDER = { zone = 20, world = 30, continent = 40 }
local mapBackgroundArgs = options.args.mapBackground.args
for _, mapType in ipairs(Config.MAP_TYPES) do
    local desc = "Which background " .. mapType.label .. " draws with, "
        .. "or \"Use Global\" to just follow the Global Background above."
    local order = MAP_TYPE_ORDER[mapType.key]
    mapBackgroundArgs["mapType_" .. mapType.key] = {
        order = order,
        type = "select",
        width = "relative",
        relWidth = 0.32,
        name = mapType.label,
        desc = desc,
        values = MapTypeBackgroundValues,
        get = function() return Config:GetMapTypeBackgroundKey(mapType.key) end,
        set = function(_, value)
            Config:SetMapTypeBackground(mapType.key, value)
        end,
    }
end
mapBackgroundArgs.fogOfWarEnabled = {
    order = MAP_TYPE_ORDER.zone + 1,
    type = "toggle",
    width = "relative",
    relWidth = 0.3,
    name = "Fog of War",
    desc = FogDesc(FOG_ZONE_DESC, "zone"),
    -- Disabled, not hidden: a saved "on" picks back up by itself once Zone
    -- Map is Hybrid again, because Config:FogOfWarEnabled() checks the
    -- background too.
    disabled = NotHybrid("zone"),
    dialogControl = FOG_CHECKBOX,
    get = function() return Config.db.fogOfWarEnabled end,
    set = function(_, value)
        Config.db.fogOfWarEnabled = value
        ns.Renderer:ForceRefresh()
    end,
}
-- World/Continent Map's neighbour: Kalimdor / Eastern Kingdoms / Azeroth
-- resolution, one saved boolean per map type (Config.db.worldMapClarity /
-- continentMapClarity; `/hfwm clarity` sets both), so "high" is true and
-- "low" is false (high is the default, when the Art addon is present).
local function ResolutionOption(mapTypeKey, dbKey, what)
    return {
        order = MAP_TYPE_ORDER[mapTypeKey] + 1,
        type = "select",
        width = "relative",
        relWidth = 0.32,
        name = "Map Resolution",
        desc = "How sharply " .. what .. " drawn. High Resolution draws "
            .. "at much higher detail but may render slower.",
        dialogControl = RESOLUTION_DROPDOWN,
        values = { high = "High Resolution (slow)", low = "Low Resolution (fast)" },
        sorting = { "high", "low" },
        get = function() return Config:MapClarityEnabled(mapTypeKey) and "high" or "low" end,
        set = function(_, value)
            Config.db[dbKey] = (value == "high")
            ns.ZoomLevels:Refresh()
            ns.Renderer:ForceRefresh()
        end,
    }
end
mapBackgroundArgs.worldMapClarity =
    ResolutionOption("world", "worldMapClarity", "Azeroth is")
mapBackgroundArgs.continentMapClarity =
    ResolutionOption("continent", "continentMapClarity",
        "Kalimdor and Eastern Kingdoms are")
-- World Map's second neighbour, between it and Map Resolution: the World
-- Map version of Fog of War. Same rule as the Zone one, but keyed to the
-- World Map's own background and its own saved value;
-- Config:WorldFogOfWarEnabled() enforces the rule in code, and a saved "on"
-- picks back up when it holds.
mapBackgroundArgs.worldFogOfWar = {
    order = MAP_TYPE_ORDER.world + 0.5,
    type = "toggle",
    width = "relative",
    relWidth = 0.3,
    name = "Fog of War",
    desc = FogDesc(FOG_WORLD_DESC, "world"),
    disabled = NotHybrid("world"),
    dialogControl = FOG_CHECKBOX,
    get = function() return Config.db.worldFogOfWar end,
    set = function(_, value)
        Config.db.worldFogOfWar = value
        ns.Renderer:ForceRefresh()
    end,
}
-- Continent Map's own Fog of War, same rule, separate saved value.
mapBackgroundArgs.continentFogOfWar = {
    order = MAP_TYPE_ORDER.continent + 0.5,
    type = "toggle",
    width = "relative",
    relWidth = 0.3,
    name = "Fog of War",
    desc = FogDesc(FOG_CONTINENT_DESC, "continent"),
    disabled = NotHybrid("continent"),
    dialogControl = FOG_CHECKBOX,
    get = function() return Config.db.continentFogOfWar end,
    set = function(_, value)
        Config.db.continentFogOfWar = value
        ns.Renderer:ForceRefresh()
    end,
}
-- Pads the Zone row (0.32 + 0.3 + 0.3) like the other rows' two selects.
mapBackgroundArgs.fogFill = {
    order = MAP_TYPE_ORDER.zone + 2,
    type = "description",
    name = " ",
    width = "relative",
    relWidth = 0.3,
}
-- Everything but the Enable toggle (and the intro text) greys out while the
-- addon is off. `disabled` is inherited, but the deepest definition wins, so
-- the cave children (which have their own) repeat the check above, and the
-- Fog of War toggles' own Hybrid-only rule is combined in here.
-- Profiles is added later in Init, so it stays usable.
for key, option in pairs(options.args) do
    if key ~= "enabled" and key ~= "intro" then
        option.disabled = function() return not Config.db.enabled end
    end
end

-- The client's Settings panel splits this up: the main page keeps the
-- general settings, and Extra Labels, Cave Map, Instance Map and Profiles
-- each get their own sub page under it (registered in Init). `options`
-- itself stays the full table, which the standalone /hfwm options window
-- shows on one page. All of them share the same arg tables, so the
-- disabled rules above apply everywhere.
--
-- `keys` are the Config.db fields a page's Reset to Defaults restores (a
-- key with no DEFAULTS entry, like toggleButtonPoint, is cleared). Profiles
-- has none: it has its own reset.
local MAIN_APP = addonName .. "_Main"
local MAIN_PAGE = {
    title = PANEL_TITLE,
    keys = {
        "enabled", "rememberMapZoomPan", "additionalZoomLevels",
        "keepCentered", "showPlayerCoords", "showMouseCoords",
        "toggleButtonEnabled", "toggleButtonMovable", "toggleButtonPoint",
        "mapBackground", "zoneMapBackground", "continentMapBackground",
        "worldMapBackground", "worldMapClarity", "continentMapClarity",
        "fogOfWarEnabled", "worldFogOfWar", "continentFogOfWar",
    },
    -- mapFade is a game CVar, not a profile field.
    onReset = function() _G.SetCVar("mapFade", "1") end,
}
local SUB_PAGES = {
    { key = "extraLabels", title = "Extra Labels",
      keys = { "showLocationNames", "labelShowOnSD", "labelAutoScale",
               "labelScale" } },
    { key = "cave", title = "Cave Map",
      keys = { "caveEnabled", "caveAutoOpen", "caveRememberState",
               "caveKeepOpen", "cavePlacement", "caveOtherIndoors",
               "caveAlpha", "caveWindowScale", "caveWindowPoint" } },
    { key = "instance", title = "Instance Map (beta)",
      keys = { "instanceDungeonEnabled", "instanceRaidEnabled" } },
    { key = "profiles", title = "Profiles" },
}
for _, page in ipairs(SUB_PAGES) do page.app = addonName .. "_" .. page.key end
local mainOptions = { type = "group", name = PANEL_TITLE, args = {} }
for key, option in pairs(options.args) do
    mainOptions.args[key] = option
end
for _, page in ipairs(SUB_PAGES) do mainOptions.args[page.key] = nil end
for key, option in pairs(mapBackgroundArgs) do
    if option.disabled then
        local notHybrid = option.disabled
        option.disabled = function() return not Config.db.enabled or notHybrid() end
    end
end

Options.optionsTable = options

local LOGO = "Interface\\AddOns\\" .. addonName .. "\\Assets\\logo_lowres.dxt5.blp"

--- Replace the panel's title text with the logo (512x128 source, shown at 4:1)
--- and dock a "Reset to Defaults" button opposite it, top-right, vertically
--- centered on the logo. Title is hidden via alpha, not cleared:
--- AceConfigDialog re-sets its text on every redraw.
--- `reset`: a page (resets just its own settings), `true` (resets
--- everything, for the one-page standalone window) or nil (no button, for
--- Profiles, which has its own reset).
local function ShowLogo(frame, reset)
    frame.obj.label:SetAlpha(0)
    local logo = frame:CreateTexture(nil, "OVERLAY")
    logo:SetTexture(LOGO)
    logo:SetSize(144, 36)
    logo:SetPoint("TOPLEFT", 10, -4)
    if not (reset and (reset == true or reset.keys)) then return end

    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetText("Reset to Defaults")
    button:SetSize(140, 22)
    -- -11: vertically centered on the logo (TOPLEFT -4, height 36).
    button:SetPoint("TOPRIGHT", -10, -11)
    button:SetScript("OnClick", function()
        if reset == true then
            StaticPopup_Show("HFWM_RESET_SETTINGS")
        else
            StaticPopup_Show("HFWM_RESET_PAGE", reset.title, nil, reset)
        end
    end)
end

--- AceConfigDialog:AddToBlizOptions, minus one line: on clients without
--- C_SettingsUtil.OpenSettingsPanel (Forever) it overwrites the Blizzard
--- category's ID with the panel name. That addon write taints the Settings
--- panel, so closing it with the gamepad UI on gets blocked
--- (ADDON_ACTION_FORBIDDEN SetPreferredGamepadInteractTarget). Nothing here
--- opens the panel by name, so the client's own ID is kept. The widget is
--- still listed in AceConfigDialog.BlizOptions so NotifyChange redraws it.
--- With `parentCategory` the page is registered as a sub page under it.
--- Returns the canvas frame and the Settings category.
local function RegisterClientPanel(AceConfigDialog, appName, title, parentCategory)
    local group = LibStub("AceGUI-3.0"):Create("BlizOptionsGroup")
    group:SetTitle(title)
    group:SetUserData("appName", appName)
    group:SetCallback("OnShow", function(widget)
        AceConfigDialog:Open(appName, widget)
    end)
    group:SetCallback("OnHide", function(widget)
        -- Deferred: this runs inside Blizzard's Settings close chain, and addon
        -- code there taints it (blocks SetPreferredGamepadInteractTarget).
        C_Timer.After(0, function()
            AceConfigDialog:Close(addonName)  -- the standalone window, as upstream does
            if not widget.frame:IsVisible() then widget:ReleaseChildren() end
        end)
    end)

    local category
    if parentCategory then
        category = Settings.RegisterCanvasLayoutSubcategory(parentCategory, group.frame, title)
        group:SetName(category.ID, parentCategory.ID)
    else
        category = Settings.RegisterCanvasLayoutCategory(group.frame, title)
        group:SetName(category.ID)
        Settings.RegisterAddOnCategory(category)
    end

    AceConfigDialog.BlizOptions[appName] = AceConfigDialog.BlizOptions[appName] or {}
    AceConfigDialog.BlizOptions[appName][appName] = group
    AceConfigDialog.BlizOptionsIDMap[title] = category.ID
    return group.frame, category
end

local registered
--- Register the options tables and hook them into the client's own options
--- UI. Safe to call more than once.
function Options:Init()
    if not options.args.profiles then
        local profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(
            Config.dbObj)
        profiles.order = 100
        -- Inline: with no tab/tree child groups AceConfigDialog wraps the
        -- whole page in one ScrollFrame, instead of squeezing a tree
        -- under the settings above.
        profiles.inline = true
        options.args.profiles = profiles
    end

    local registry = LibStub("AceConfigRegistry-3.0")
    registry:RegisterOptionsTable(addonName, options)
    registry:RegisterOptionsTable(MAIN_APP, mainOptions)
    for _, page in ipairs(SUB_PAGES) do
        local src = options.args[page.key]
        -- The page itself is the section's group, so it isn't boxed twice.
        registry:RegisterOptionsTable(page.app, {
            type = "group", name = page.title, disabled = src.disabled,
            handler = src.handler, args = src.args,
        })
    end

    local AceConfigDialog = LibStub("AceConfigDialog-3.0")
    -- Standalone window only; the client's options panels set their own size.
    AceConfigDialog:SetDefaultSize(addonName, 700, 650)
    if registered then return end
    local frames = {}
    local ok, err = pcall(function()
        local frame, category = RegisterClientPanel(
            AceConfigDialog, MAIN_APP, PANEL_TITLE)
        frames[#frames + 1] = { frame, MAIN_PAGE }
        for _, page in ipairs(SUB_PAGES) do
            frame = RegisterClientPanel(
                AceConfigDialog, page.app, page.title, category)
            frames[#frames + 1] = { frame, page }
        end
    end)
    registered = ok
    self.clientRegistered = ok
    for _, f in ipairs(frames) do ShowLogo(f[1], f[2]) end
end
--- Open the options, wherever they ended up living. The standalone window
--- shows everything on one page, with the same logo + Reset to Defaults
--- treatment as the client's own options panel.
function Options:Open()
    local AceConfigDialog = LibStub("AceConfigDialog-3.0")
    AceConfigDialog:Open(addonName)
    local frame = AceConfigDialog.OpenFrames[addonName]
    if frame then ShowLogo(frame, true) end
end

--- Push a live setting change (from a slash command, say) out to any open
--- options window. Safe to call whether or not one is open.
function Options:Refresh()
    local registry = LibStub("AceConfigRegistry-3.0")
    registry:NotifyChange(addonName)
    registry:NotifyChange(MAIN_APP)
    for _, page in ipairs(SUB_PAGES) do registry:NotifyChange(page.app) end
end
