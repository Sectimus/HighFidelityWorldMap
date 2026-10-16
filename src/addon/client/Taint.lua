-------------------------------------------------------------------------------
-- HFWM-Forever Taint containment
--
-- Remember zoom/pan (MapMemory), additional zoom levels (ZoomLevels), reset
-- view (ResetView) and keep centered (KeepCentered) can only work by writing
-- Blizzard's scroll container from addon code: the zoom ladder and the
-- scale/scroll fields. There is no clean way to do that, and the taint never
-- clears: Blizzard's own ResetZoom and SetZoomTarget read the old values
-- before rewriting them. MarkCanvasDirty reads those fields on every pin
-- add/remove, so from then on pins are acquired (and their owningMap and
-- other fields written) in tainted execution, and tainted code reaches the
-- restricted calls listed below (ADDON_ACTION_BLOCKED / _FORBIDDEN, #20).
--
-- WorldMapFrame.mapID is NOT written (no SetMapID from addon code): every
-- data provider reads it, and Blizzard's OnMapChanged and quest-log refresh
-- carry that taint into far more than pins. Check with
-- issecurevariable(WorldMapFrame, "mapID").
--
-- Contained the way PersistentWorldMap's taintPrevent.lua does it: the taint
-- is accepted, and every restricted call tainted code can reach from a pin is
-- neutralised on the pin itself.
--
-- PROTECTED (blocked in combat, ADDON_ACTION_BLOCKED): shadowed to skip while
-- in combat, remembering what they were asked to set; once combat ends the
-- last request of each is applied. Until then a skipped pin keeps its old
-- mouse setup (e.g. a right click on it doesn't zoom the map out).
--
-- NEUTRALISED (forbidden outright, ADDON_ACTION_FORBIDDEN, even out of
-- combat): a pin acquired while a scroll field is tainted (Blizzard's
-- RemoveAllData -> MarkCanvasDirty reads it before AcquirePin) gets a tainted
-- owningMap, so its click handlers run tainted. Replaced with a no-op.
-- CopySlashCommandToClipboard (waypoint pin, shift-click "share in chat"):
-- the link still goes into chat, only the /mappin clipboard copy is lost.
--
-- Both lists are every restricted call in this client's map code, found by
-- intersecting the wiki's restricted-API category with the functions called
-- in Blizzard_MapCanvas, Blizzard_SharedMapDataProviders, Blizzard_WorldMap,
-- Blizzard_FlightMap and Blizzard_BattlefieldMap: SetPassThroughButtons
-- (MapCanvas_DataProviderBase.lua, CheckMouseButtonPassthrough),
-- SetPropagateMouseClicks (SharedMapPoiTemplates.lua, UpdateMousePropagation)
-- and CopyToClipboard (WaypointLocationDataProvider.lua). Re-run that
-- intersection when a client patch changes the map code.
--
-- Only post-hooks (hooksecurefunc) find the pins. Never replace
-- pool.Acquire or put a metatable on WorldMapFrame.pinPools: Blizzard's
-- AcquirePin would read that addon function/entry and run the rest of its
-- body tainted, including SetOwningMap. A brand-new pool (the first pin of
-- a template, e.g. the first waypoint) is found from a post-hook on
-- ScrollContainer:MarkCanvasDirty, which AcquirePin calls after the pin
-- exists and before OnAcquired / CheckMouseButtonPassthrough.
--
-- Engaged lazily, by the first tainting write: until one of those features
-- has touched the map nothing here touches Blizzard's tables.
-------------------------------------------------------------------------------
local addonName, ns = ...
local Taint = ns.Taint

local WorldMapFrame    = _G.WorldMapFrame
local InCombatLockdown = _G.InCombatLockdown

local PROTECTED   = { "SetPassThroughButtons", "SetPropagateMouseClicks" }
local NEUTRALISED = { "CopySlashCommandToClipboard" }

local engaged = false
local patched = {}   -- [pin] = true
local hooked  = {}   -- [pool] = true
local pending = {}   -- [pin] = { [method] = { n = argc, ... } }, skipped in combat

local function Shadow(pin, name)
    local original = pin[name]
    if not original then return end
    pin[name] = function(self, ...)
        if InCombatLockdown() then
            local calls = pending[self]
            if not calls then
                calls = {}
                pending[self] = calls
            end
            calls[name] = { n = select("#", ...), ... }
            return
        end
        return original(self, ...)
    end
end

local function PatchPin(pin)
    if patched[pin] then return end
    patched[pin] = true
    for _, name in ipairs(PROTECTED) do Shadow(pin, name) end
    for _, name in ipairs(NEUTRALISED) do
        if pin[name] then pin[name] = function() end end
    end
end

local function PatchPins(pool)
    for pin in pool:EnumerateActive() do PatchPin(pin) end
    if pool.EnumerateInactive then
        for pin in pool:EnumerateInactive() do PatchPin(pin) end
    end
end

--- Hook every pool not hooked yet and patch the pins it holds. Runs after
--- each MarkCanvasDirty (new pools appear there); new pins of known pools
--- are patched by the Acquire hook set here.
local function ScanPools()
    for _, pool in pairs(WorldMapFrame.pinPools) do
        if not hooked[pool] then
            hooked[pool] = true
            hooksecurefunc(pool, "Acquire", function() PatchPins(pool) end)
            PatchPins(pool)
        end
    end
end

--- Call before any write to Blizzard's map state. Idempotent.
function Taint:Engage()
    if engaged or not WorldMapFrame.pinPools then return end
    engaged = true

    ScanPools()
    hooksecurefunc(WorldMapFrame.ScrollContainer, "MarkCanvasDirty", ScanPools)

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function()
        local todo = pending
        pending = {}
        for pin, calls in pairs(todo) do
            -- Out of combat now, so the shadow forwards to the real method.
            for name, args in pairs(calls) do
                pin[name](pin, unpack(args, 1, args.n))
            end
        end
    end)
end
