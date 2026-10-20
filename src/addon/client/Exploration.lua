-------------------------------------------------------------------------------
-- HFWM-Forever Exploration
-- Hide / show exploration overlay ("fog of war cleared" textures), and (for
-- Fog of War, see EnumerateOverlayTextures) hand their live geometry back
-- to Renderer.lua instead of just hiding them.
-- Searches pin pools and data providers directly on WorldMapFrame.
--
-- Mouse state is saved and restored rather than forced.  Exploration pins
-- are pure art stretched over the whole canvas and Blizzard leaves them
-- mouse-disabled; calling EnableMouse(true) on them turns the overlay into
-- an invisible sheet that eats every click on the map, so zone clicks,
-- drag-panning and pin tooltips all stop working.  Pins are pooled, so a
-- forced-on flag also survives release and comes back on the next acquire.
--
-- Fog of War off, Hybrid zone map, HD/SD blend: the HD map shows the whole
-- zone, so the native art underneath must too, or "SD" looks different from
-- HD. Blizzard's pin only draws the overlays the player has explored, so
-- RevealUnexplored (hooked onto its RefreshOverlays) draws the rest from the
-- baked ZoneOverlayTiles.lua, the same way other fog-removal addons do.
-------------------------------------------------------------------------------
local addonName, ns = ...
local Exploration = ns.Exploration
local Config      = ns.Config

local hookedDPs = {}

--- Run *fn* over every exploration pin, optionally including pooled-but-
--- inactive ones (their state carries over when they are re-acquired).
local function ForEachPin(fn, includeInactive)
    if not WorldMapFrame.pinPools then return end
    for templateName, pinPool in next, WorldMapFrame.pinPools do
        if templateName:lower():find("exploration") then
            for pin in pinPool:EnumerateActive() do fn(pin) end
            if includeInactive and pinPool.EnumerateInactive then
                for pin in pinPool:EnumerateInactive() do fn(pin) end
            end
        end
    end
end

--- Disable mouse input, remembering whether it was on to begin with.
local function SuppressMouse(pin)
    if pin._hfwmMouseWasEnabled == nil then
        pin._hfwmMouseWasEnabled = pin:IsMouseEnabled() and true or false
    end
    pin:EnableMouse(false)
end

--- Put mouse input back exactly how Blizzard had it.
local function RestoreMouse(pin)
    if pin._hfwmMouseWasEnabled ~= nil then
        pin:EnableMouse(pin._hfwmMouseWasEnabled)
        pin._hfwmMouseWasEnabled = nil
    end
end

local function IsExplorationDP(dp)
    if dp.overlayTexturePool then return true end
    local tmpl = dp.pinTemplate
    return type(tmpl) == "string" and tmpl:find("Exploration") and true or false
end

local ZONE_OVERLAYS = HFWMF_ZONE_OVERLAY_TILES or {}

--- Should the native map show every overlay of *mapID*, explored or not?
--- Yes while the zone map is being drawn by this addon with Fog of War off
--- and the native art shows under the HD overlay (the HD/SD blend): HD shows
--- the whole zone then, so the native art must too.
local function Revealing(mapID)
    return Config.db and Config.db.enabled and Config.overlayActive
        and Config:IsMixing() and not Config:FogOfWarEnabled()
        and (Config:ClassifyMapID(mapID) == "zone" or Config:ClassifyMapID(mapID) == "city")
        and Config:GetClientZone(mapID) ~= nil
end

-- Reveal textures per pin. Our own, not the pin's overlayTexturePool:
-- acquiring from Blizzard's pool in addon code taints it, and the pin's next
-- refresh then runs tainted (ADDON_ACTION_BLOCKED in combat, issue #20).
local revealTextures = {}  -- [pin] = { Texture, ... }

--- After Blizzard's pin has drawn the explored overlays, draw the rest: the
--- same loop as MapExplorationPinMixin:RefreshOverlays, over the baked list
--- of every overlay, skipping the geometry the client already gave us.
--- Hides them all when not revealing; safe to re-run any time.
local function RevealUnexplored(pin)
    local texs = revealTextures[pin]
    if not texs then
        texs = {}
        revealTextures[pin] = texs
    end
    for _, tex in ipairs(texs) do tex:Hide() end

    local mapID = WorldMapFrame:GetMapID()
    local all = ZONE_OVERLAYS[mapID]
    if not all or not Revealing(mapID) then return end

    local layerIndex = WorldMapFrame:GetCanvasContainer():GetCurrentLayerIndex()
    local layer = C_Map.GetMapArtLayers(mapID)[layerIndex]
    local tileW, tileH = layer.tileWidth, layer.tileHeight

    local explored = {}
    for _, t in ipairs(C_MapExplorationInfo.GetExploredMapTextures(mapID) or {}) do
        explored[t.offsetX .. "," .. t.offsetY .. "," .. t.textureWidth .. "," .. t.textureHeight] = true
    end

    local n = 0
    for _, o in ipairs(all) do
        local offX, offY, w, h, cols, fdids = unpack(o)
        if not explored[offX .. "," .. offY .. "," .. w .. "," .. h] then
            local rows = math.ceil(#fdids / cols)
            for j = 1, rows do
                local pixH = j < rows and tileH or (h % tileH ~= 0 and h % tileH or tileH)
                local fileH = 16
                if j < rows then fileH = tileH else while fileH < pixH do fileH = fileH * 2 end end
                for k = 1, cols do
                    local pixW = k < cols and tileW or (w % tileW ~= 0 and w % tileW or tileW)
                    local fileW = 16
                    if k < cols then fileW = tileW else while fileW < pixW do fileW = fileW * 2 end end
                    n = n + 1
                    local tex = texs[n]
                    if not tex then
                        tex = pin:CreateTexture(nil, "ARTWORK", nil, 0)
                        texs[n] = tex
                    end
                    tex:SetSize(pixW, pixH)
                    tex:SetTexCoord(0, pixW / fileW, 0, pixH / fileH)
                    tex:ClearAllPoints()
                    tex:SetPoint("TOPLEFT", offX + tileW * (k - 1), -(offY + tileH * (j - 1)))
                    tex:SetTexture(fdids[(j - 1) * cols + k], nil, nil, "TRILINEAR")
                    tex:Show()
                end
            end
        end
    end
end

local hookedPins = {}

local function HookDPs()
    if not WorldMapFrame.dataProviders then return end
    for dp in next, WorldMapFrame.dataProviders do
        if not hookedDPs[dp] and dp.RefreshAllData and IsExplorationDP(dp) then
            hookedDPs[dp] = true
            hooksecurefunc(dp, "RefreshAllData", function()
                -- Always re-hidden, Fog of War included: Renderer.lua's own
                -- tiles (see DrawExploredPiece) reuse the same geometry and
                -- art, but as a separate MaskTexture object, so alpha 0 here
                -- has no bearing on those.
                if Config.db and Config.db.enabled and Config.overlayActive
                    and not Config:IsMixing() then
                    Exploration:HidePins()
                end
            end)
        end
        -- Map changes and zoom-layer changes call the pin's RefreshOverlays
        -- directly, bypassing RefreshAllData, so hook the pin itself.
        local pin = dp.pin
        if pin and not hookedPins[pin] and pin.RefreshOverlays and pin.overlayTexturePool then
            hookedPins[pin] = true
            hooksecurefunc(pin, "RefreshOverlays", RevealUnexplored)
        end
    end
end

--- Re-sync the reveal with the current state. Blizzard's refreshes re-run
--- it through the RefreshOverlays hook; this covers state changes (blend,
--- Fog of War) between them, without forcing a Blizzard refresh.
local function RevealAll()
    for pin in pairs(hookedPins) do RevealUnexplored(pin) end
end

function Exploration:HidePins()
    HookDPs()
    RevealAll()

    ForEachPin(function(pin)
        pin:SetAlpha(0)
        SuppressMouse(pin)
        for _, region in ipairs({pin:GetRegions()}) do
            region:SetAlpha(0)
        end
    end)

    if WorldMapFrame.dataProviders then
        for dp in next, WorldMapFrame.dataProviders do
            if dp.overlayTexturePool then
                for tex in dp.overlayTexturePool:EnumerateActive() do
                    tex:SetAlpha(0)
                end
            end
        end
    end
end

--- Undo HidePins' alpha and mouse changes. For the HD/SD blend with Fog of
--- War on: Blizzard's own explored art has to show under the overlay while
--- those same textures stay enumerable.
function Exploration:ShowPins()
    HookDPs()
    RevealAll()

    ForEachPin(function(pin)
        pin:SetAlpha(1)
        RestoreMouse(pin)
        for _, region in ipairs({pin:GetRegions()}) do
            region:SetAlpha(1)
        end
    end)

    if WorldMapFrame.dataProviders then
        for dp in next, WorldMapFrame.dataProviders do
            if dp.overlayTexturePool then
                for tex in dp.overlayTexturePool:EnumerateActive() do
                    tex:SetAlpha(1)
                end
            end
        end
    end
end

local function UnderOverlay()
    return Config:IsMixing() and Config.overlayActive and Config.overlayFrame
end

local function TuckUnderOverlay(pin)
    pin:SetFrameLevel(math.max(Config.overlayFrame:GetFrameLevel() - 1, 0))
end

local levelDriver

--- While the HD/SD blend is below 100% (Config:IsMixing()), put the
--- exploration pins one frame level under the overlay, so Blizzard's
--- explored art draws beneath the HD map's alpha instead of on top of it.
--- Otherwise give them back Blizzard's own level. Blizzard re-asserts a
--- pin's level whenever it re-applies pin levels, so while mixing a per-frame
--- driver tucks them back down. (Not a hooksecurefunc on each pin's
--- ApplyFrameLevel: on this client that left pins whose ApplyFrameLevel
--- Blizzard's ApplyPinPosition then failed to call, "attempt to call a nil
--- value".)
function Exploration:ApplyLevels()
    if not levelDriver then
        levelDriver = CreateFrame("Frame", nil, Config:MapWidgetParent())  -- runs while the map is shown
        levelDriver:SetScript("OnUpdate", function()
            if UnderOverlay() then ForEachPin(TuckUnderOverlay) end
        end)
    end
    ForEachPin(function(pin)
        if UnderOverlay() then
            TuckUnderOverlay(pin)
        elseif pin.ApplyFrameLevel then
            pin:ApplyFrameLevel()
        end
    end, true)
end

--- Show or hide Blizzard's exploration art. Pins are only hidden/shown,
--- never rebuilt: RefreshAllDataProviders / RemoveAllData called from addon
--- code run every provider tainted, and the pins, pools and map state they
--- write then taint Blizzard's own later refreshes -- ADDON_ACTION_BLOCKED
--- on SetPassThroughButtons in combat (issue #20), and the gamepad UI's
--- focus/binding flows.
---@param visible boolean
function Exploration:SetVisible(visible)
    if not visible then
        self:HidePins()
        return
    end

    HookDPs()
    RevealAll()
    -- Includes inactive pins: their alpha carries over when re-acquired.
    ForEachPin(function(pin)
        pin:SetAlpha(1)
        RestoreMouse(pin)
        pin:Show()
        for _, region in ipairs({pin:GetRegions()}) do
            -- Alpha only, never Show(): a hidden region is one its owner
            -- cleared on purpose (Blizzard's released overlay textures,
            -- MapUtils' ClearPin), holding last map's art and anchors.
            -- Showing it paints that zone over the continent/world map.
            region:SetAlpha(1)
        end
    end, true)
    if WorldMapFrame.dataProviders then
        for dp in next, WorldMapFrame.dataProviders do
            if dp.overlayTexturePool then
                for tex in dp.overlayTexturePool:EnumerateActive() do
                    tex:SetAlpha(1)
                    tex:Show()
                end
            end
        end
    end
end

--- Every currently-active "explored" reveal texture Blizzard's own
--- exploration data provider is drawing right now: hidden (see HidePins)
--- but still real Texture objects with correct position, size, texture and
--- coordinates.
---
--- This is how Fog of War finds what to reveal (see Renderer's
--- DrawExploredPiece): read the real geometry the client already computed,
--- rather than recompute it from C_MapExplorationInfo, which would need
--- assumptions (tile size, file padding, coordinate space) this addon has
--- no way to verify hold on every client. Read as Blizzard last left it,
--- never refreshed from here (see SetVisible): callers run after Blizzard's
--- own refresh (map change/open hooks, MAP_EXPLORATION_UPDATED a frame on).
---
--- Two client implementations are covered, since this addon has no way to
--- know in advance which one it's talking to:
---   - Retail-style: the data provider pools plain Texture objects directly
---     (dp.overlayTexturePool); each pooled object already IS the reveal
---     texture.
---   - Pin-style (the one this addon actually ships on, confirmed by
---     tracing): there is exactly ONE active "MapExplorationPinTemplate"
---     pin per map, sized to the *entire canvas*, not one pin per explored
---     area. Blizzard papers that single pin with one child Texture region
---     PER real explored area, each individually positioned/sized to its
---     own true rect rather than to the pin's whole-canvas bounds. Taking
---     only the first such region (an earlier version of this function)
---     threw away every explored area but one; this collects all of them.
---@return table[] textures
function Exploration:EnumerateOverlayTextures()
    -- Closed map: nothing to reveal. WorldMapFrame's OnShow hook in Core.lua
    -- runs a full Refresh when it opens.
    if not WorldMapFrame:IsShown() then return {} end

    HookDPs()

    local out = {}
    local dpPoolCount, dpPoolTotal = 0, 0
    if WorldMapFrame.dataProviders then
        for dp in next, WorldMapFrame.dataProviders do
            if dp.overlayTexturePool then
                dpPoolCount = dpPoolCount + 1
                for tex in dp.overlayTexturePool:EnumerateActive() do
                    out[#out + 1] = tex
                    dpPoolTotal = dpPoolTotal + 1
                end
            end
        end
    end

    -- Per-template breakdown, trace-only: "exploration" as a substring can
    -- match a thin boundary-line pin template as well as the real
    -- fill-chunk template. If more than one template shows up here, the one
    -- with much smaller pin sizes than a map chunk is probably not real
    -- reveal art.
    if Config.tracing and WorldMapFrame.pinPools then
        for templateName, pinPool in next, WorldMapFrame.pinPools do
            if templateName:lower():find("exploration") then
                local n, wSum, hSum, wMin, hMin, wMax, hMax = 0, 0, 0, nil, nil, nil, nil
                for pin in pinPool:EnumerateActive() do
                    n = n + 1
                    local w, h = pin:GetSize()
                    w, h = w or 0, h or 0
                    wSum, hSum = wSum + w, hSum + h
                    wMin = wMin and math.min(wMin, w) or w
                    hMin = hMin and math.min(hMin, h) or h
                    wMax = wMax and math.max(wMax, w) or w
                    hMax = hMax and math.max(hMax, h) or h
                end
                ns.P(("  template %q: active=%d  size avg=%.1fx%.1f  "
                    .. "min=%.1fx%.1f  max=%.1fx%.1f"):format(
                    templateName, n,
                    n > 0 and wSum / n or 0, n > 0 and hSum / n or 0,
                    wMin or 0, hMin or 0, wMax or 0, hMax or 0))
            end
        end
    end

    -- One pin per map, not one per explored area (confirmed by tracing).
    -- The real per-area reveal pieces are its CHILD regions, each
    -- positioned/sized to its own explored rect. pin.Texture, when the pin
    -- exposes one, is already one of these regions, so there's no separate
    -- case for it here to avoid double-counting.
    local pinCount, pinTexCount = 0, 0
    ForEachPin(function(pin)
        pinCount = pinCount + 1
        for _, region in ipairs({ pin:GetRegions() }) do
            if region.GetTexture and region.GetObjectType
                and region:GetObjectType() == "Texture" then
                out[#out + 1] = region
                pinTexCount = pinTexCount + 1
                if Config.tracing then
                    local texLeft, texTop = region:GetLeft(), region:GetTop()
                    local texRight, texBottom = region:GetRight(), region:GetBottom()
                    local texFile = region:GetTexture()
                    ns.P(("    pin texture: screen=[%s,%s]-[%s,%s]  file=%s"):format(
                        tostring(texLeft), tostring(texTop),
                        tostring(texRight), tostring(texBottom), tostring(texFile)))
                end
            end
        end
    end)

    if Config.tracing then
        ns.P(("  Exploration:EnumerateOverlayTextures: overlayTexturePool "
            .. "dp(s)=%d texture(s)=%d  pins seen=%d pin texture(s)=%d  "
            .. "total=%d"):format(
            dpPoolCount, dpPoolTotal, pinCount, pinTexCount, #out))
    end

    return out
end
