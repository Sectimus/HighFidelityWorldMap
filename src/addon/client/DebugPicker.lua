-------------------------------------------------------------------------------
-- HFWM-Forever Debug Picker
-- /hfwm debug picker [on|off]: while armed, a middle click on the world map
-- opens a copyable dialog with what this addon drew under that point: the
-- tile and its file, the textures stacked there, Blizzard's exploration art,
-- fog, and the backdrop. Session only; /reload disarms it.
-------------------------------------------------------------------------------
local addonName, ns = ...
local Config      = ns.Config
local Pool        = ns.Pool
local BaseArt     = ns.BaseArt
local MapFrameBg  = ns.MapFrameBg
local Exploration = ns.Exploration
local P           = ns.P

local DebugPicker   = ns.DebugPicker
local WorldMapFrame = _G.WorldMapFrame

local armed = false
local dialog            -- { frame, box } while the report window is open
local lines = {}        -- the report being built by Pick
local MAX_LIST = 12     -- textures listed per point; the rest are only counted

local function out(fmt, ...)
    lines[#lines + 1] = fmt:format(...)
end

local function Hex(rgb)
    return ("#%02X%02X%02X"):format(
        math.floor(rgb[1] * 255 + 0.5),
        math.floor(rgb[2] * 255 + 0.5),
        math.floor(rgb[3] * 255 + 0.5))
end

--- Is the normalized point (nx, ny) inside *obj*'s rect, measured over
--- *canvas*? Both rects come from the same Region getters, so this does not
--- depend on which unit system those getters use. Unrendered objects (nil
--- geometry) count as outside.
local function Inside(obj, canvas, nx, ny)
    local cl, cr, cb, ct = canvas:GetLeft(), canvas:GetRight(), canvas:GetBottom(), canvas:GetTop()
    local l, r, b, t = obj:GetLeft(), obj:GetRight(), obj:GetBottom(), obj:GetTop()
    if not (cl and l) then return false end
    local cw, ch = cr - cl, ct - cb
    if cw <= 0 or ch <= 0 then return false end
    local u0, u1 = (l - cl) / cw, (r - cl) / cw
    local v0, v1 = (ct - t) / ch, (ct - b) / ch  -- y measured from the top
    return nx >= u0 and nx <= u1 and ny >= v0 and ny <= v1
end

local function DescribeTexture(tex)
    local layer, sub = tex:GetDrawLayer()
    local coords = { tex:GetTexCoord() }
    for i, v in ipairs(coords) do coords[i] = ("%.3f"):format(v) end
    local masks = {}
    for i = 1, tex:GetNumMaskTextures() do
        masks[i] = tostring(tex:GetMaskTexture(i):GetTexture())
    end
    local vr, vg, vb, va = tex:GetVertexColor()
    return ("file=%s shown=%s alpha=%.2f layer=%s/%s size=%.0fx%.0f "
        .. "vcolor=%.2f,%.2f,%.2f,%.2f texcoord=%s masks=%d%s"):format(
        tostring(tex:GetTexture()), tostring(tex:IsShown()), tex:GetAlpha(),
        tostring(layer), tostring(sub), tex:GetWidth(), tex:GetHeight(),
        vr or 1, vg or 1, vb or 1, va or 1, table.concat(coords, ","),
        #masks, #masks > 0 and (" " .. table.concat(masks, " + ")) or "")
end

--- List every texture in *list* whose rect holds the point, in paint order.
local function ListHits(label, list, canvas, nx, ny)
    local hits = {}
    for _, tex in ipairs(list) do
        if Inside(tex, canvas, nx, ny) then hits[#hits + 1] = tex end
    end
    out("%s under point: %d", label, #hits)
    for i = 1, math.min(#hits, MAX_LIST) do
        out("  %d. %s", i, DescribeTexture(hits[i]))
    end
    if #hits > MAX_LIST then out("  ... %d more", #hits - MAX_LIST) end
end

--- What the tile at *idx* is: a bundled file of ours, a raw FileDataID the
--- client draws itself, or nothing.
local function DescribeSource(L, idx)
    local src  = L.tileSource[idx]
    local fdid = L.fdids and L.fdids[idx]
    if type(src) == "string" then
        local extra = ""
        if fdid then
            local lookup = L.useSubmerged and Config.FDID_MAP_SUB
                or Config:GetTileMap(L.background)
            extra = ("  (blizzard FDID %d -> %s)"):format(fdid, tostring(lookup[fdid]))
        end
        return "bundled " .. src .. extra
    elseif src ~= nil then
        return ("FDID %d, not bundled (%s)"):format(src,
            L.clientZone and "client minimap tile" or "Blizzard's own art")
    end
    return "none (empty cell)"
end

--- The overlay's own tile layout at (nx, ny): the cell, its source, and the
--- Fog of War state the refresh was built with.
local function PrintLayout(L, nx, ny)
    local bg = L.background
    out("overlay: enabled=%s active=%s background=%s tiles=%s mapType=%s layer=%d%s",
        tostring(Config.db and Config.db.enabled), tostring(Config.overlayActive),
        bg.key, bg.tiles or "bundled", tostring(L.mapType), L.layerIdx,
        L.useSubmerged and " submerged" or "")
    out("source: %s", L.clientZone and "client minimap tiles (clientZone)"
        or L.nativeZone and ("native zone " .. tostring(L.nativeZone.path))
        or L.useBundled and "bundled tiles"
        or "Blizzard's own tiles (no HFWM art on this map)")

    local px, py = nx * L.layerW, ny * L.layerH
    out("grid: %dx%d tiles of %gx%g px, origin (%g,%g), layer %gx%g, canvas %gx%g",
        L.cols, L.rows, L.tilePxW, L.tilePxH, L.gridX, L.gridY,
        L.layerW, L.layerH, L.canvasW, L.canvasH)

    local col = math.floor((px - L.gridX) / L.tilePxW)
    local row = math.floor((py - L.gridY) / L.tilePxH)
    if col < 0 or col >= L.cols or row < 0 or row >= L.rows then
        out("point: layer (%.1f,%.1f) is outside the tile grid", px, py)
        return
    end
    local idx = row * L.cols + col + 1
    out("point: layer (%.1f,%.1f)  cell col %d row %d  index %d  local (%.1f,%.1f)",
        px, py, col, row, idx,
        px - (L.gridX + col * L.tilePxW), py - (L.gridY + row * L.tilePxH))
    out("tile: %s", DescribeSource(L, idx))
end

--- Build the report for the point (nx, ny) over *canvas*, on map *mapID*.
local function Report(mapID, canvas, nx, ny)
    local info = C_Map.GetMapInfo(mapID)
    out('map %d "%s" (%s)  point %.4f, %.4f', mapID,
        info and info.name or "?", tostring(Config:ClassifyMapID(mapID)), nx, ny)

    local L = Config.lastLayout
    if L and L.mapID == mapID then
        PrintLayout(L, nx, ny)
    else
        out("no tile layout recorded for this map: overlay off, or not drawn "
            .. "since the map opened")
    end

    ListHits("HFWM textures", Pool:GetActive(), canvas, nx, ny)
    ListHits("blizzard exploration overlays", Exploration:EnumerateOverlayTextures(),
        canvas, nx, ny)

    if L then
        out("fog of war: armed=%s active=%s fullyExplored=%s",
            tostring(L.fogOfWar), tostring(L.fogActive), tostring(L.fullyExplored))
        if L.worldFogZones then
            local hits = {}
            for _, z in ipairs(L.worldFogZones) do
                if nx >= z[2] and nx <= z[4] and ny >= z[3] and ny <= z[5] then
                    hits[#hits + 1] = tostring(z[1])
                end
            end
            out("world fog zone boxes containing point: %s",
                #hits > 0 and table.concat(hits, ", ") or "none")
        end
        if L.blizzardLayerW then
            local bx, by = nx * L.blizzardLayerW, ny * L.blizzardLayerH
            local n = 0
            for _, t in ipairs(C_MapExplorationInfo.GetExploredMapTextures(mapID) or {}) do
                if bx >= t.offsetX and bx <= t.offsetX + t.textureWidth
                   and by >= t.offsetY and by <= t.offsetY + t.textureHeight then
                    n = n + 1
                    out("explored chunk: offset (%d,%d) size %dx%d", t.offsetX,
                        t.offsetY, t.textureWidth, t.textureHeight)
                end
            end
            out("explored chunks containing point: %d", n)
        end
    end

    local bg = L and L.background or Config:GetBackground()
    local backdrop = Config.backdropTexture
    out("backdrop: %s shown=%s  baseArt visible=%s  map frame backing visible=%s",
        bg.rgb and Hex(bg.rgb) or (bg.blizzardArt and "Blizzard art" or "none"),
        tostring(backdrop and backdrop:IsShown()), tostring(BaseArt.visible),
        tostring(MapFrameBg.visible))
    out("texel colour is not readable in-game: inspect the tile file above offline")
end

--- Show *text* in a copyable box. The window is reused while open, and
--- released (and forgotten) when the user closes it.
local function ShowDialog(text)
    if dialog then
        dialog.box:SetText(text)
        return
    end
    local AceGUI = LibStub("AceGUI-3.0")
    local frame = AceGUI:Create("Frame")
    frame:SetTitle("High Fidelity World Map: picked point")
    frame:SetStatusText("Copy this into your bug report. Middle-click the map again to refresh.")
    frame:SetWidth(760)
    frame:SetHeight(520)
    frame:SetLayout("Fill")
    frame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        dialog = nil
    end)

    local box = AceGUI:Create("MultiLineEditBox")
    box:SetLabel("Report")
    box:SetMaxLetters(0)
    box:SetNumLines(24)
    box:DisableButton(true)
    box:SetText(text)
    frame:AddChild(box)
    box:SetFocus()
    dialog = { frame = frame, box = box }
end

--- Middle click handler: report the point under the cursor, if on the map.
--- The cursor position comes from Blizzard's own canvas API, the same one
--- Questie and Leatrix Maps use; it is clamped to the canvas edges, so
--- hover is checked separately with IsMouseOver.
function DebugPicker:Pick()
    local canvas = WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
    local mapID = WorldMapFrame:GetMapID()
    if not canvas or not mapID then return P("picker: no map open") end

    if not WorldMapFrame:GetCanvas():IsMouseOver() then
        return P("picker: click was outside the map canvas")
    end
    local nx, ny = WorldMapFrame.ScrollContainer:GetNormalizedCursorPosition()
    if type(nx) ~= "number" or type(ny) ~= "number" then
        return P("picker: no cursor position from the map")
    end

    lines = {}
    Report(mapID, canvas, nx, ny)
    ShowDialog(table.concat(lines, "\n"))
end

--- /hfwm debug picker [on|off]: arm or disarm; no argument toggles.
function DebugPicker:Command(arg)
    if arg == nil then
        armed = not armed
    elseif arg == "on" or arg == "off" then
        armed = arg == "on"
    else
        return P("Usage: /hfwm debug picker [on|off]")
    end
    P(armed and "Picker armed: middle-click the world map. /hfwm debug picker off to stop."
        or "Picker disarmed.")
end

--- Called once from Core.lua. The overlay takes no mouse, so a middle click
--- lands on the scroll container; HookScript keeps Blizzard's own handler.
function DebugPicker:Start()
    local sc = WorldMapFrame.ScrollContainer
    if not sc then return end
    sc:HookScript("OnMouseDown", function(_, button)
        if armed and button == "MiddleButton" then self:Pick() end
    end)
end
