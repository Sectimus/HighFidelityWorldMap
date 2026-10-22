-------------------------------------------------------------------------------
-- HFWM-Forever Renderer
-- Core tile layout: resolves tile source, lays out textures on the canvas.
-------------------------------------------------------------------------------
local addonName, ns = ...
local Renderer    = ns.Renderer
local Config      = ns.Config
local Pool        = ns.Pool
local MaskPool    = ns.MaskPool
local BaseArt     = ns.BaseArt
local MapFrameBg  = ns.MapFrameBg
local Exploration = ns.Exploration
local Watchdog    = ns.Watchdog
local P           = ns.P

-- UiMapID -> overlay count (ZoneOverlays.lua). Maps missing from it have no
-- exploration overlays at all (cities, battlegrounds, Darkspear Islands), so
-- Blizzard never fogs them and neither does Fog of War.
local ZONE_OVERLAYS = HFWMF_ZONE_OVERLAYS or {}

-------------------------------------------------------------------------------
-- Backdrop
--
-- The bundled BLPs ship with their sea and their uncovered cells
-- transparent (pipeline art pass "alpha-sea"), so *something* has to be
-- behind them. What that something is, is the map-background setting:
--
--   Ocean Blue   a flat colour drawn here, Blizzard's art hidden
--   Hybrid       no backdrop at all, Blizzard's art left visible so it
--                shows through the transparent sea
--   Transparent  no backdrop, no Blizzard's art, and the map frame's own
--                backing hidden too (MapFrameBg) so the holes go through the
--                UI and onto the world rather than onto a panel. Without
--                that last layer it differs from Hybrid only in whether
--                Blizzard's art shows, which is not much of a choice.
--   Raw          a separate, opaque tile set; nothing could show through
--                it, so again no backdrop
--
-- One texture on the overlay frame, at the BACKGROUND draw layer so it sits
-- under the tiles (TexturePool creates those at ARTWORK sublevel 2). It
-- covers the whole frame, which is exactly the tile grid: the frame is
-- SetAllPoints to the canvas, and the grid is laid out at
-- layerW*scaleX x layerH*scaleY == canvasW x canvasH.
-------------------------------------------------------------------------------
-- Created once and kept. Refresh() can re-parent the overlay frame when the
-- client swaps the canvas out from under it, but the frame object itself is
-- never replaced, so the texture on it stays good.
local function GetBackdrop()
    if not Config.overlayFrame then return nil end
    if not Config.backdropTexture then
        local tex = Config.overlayFrame:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints(Config.overlayFrame)
        Config.backdropTexture = tex
    end
    return Config.backdropTexture
end

--- Apply the chosen background: colour the backdrop, stand aside for
--- Blizzard's art, or need nothing behind the tiles at all. Returns the
--- entry applied.
---@param bg table entry from Config.BACKGROUNDS
local function ApplyBackground(bg)
    local tex = GetBackdrop()
    if bg.rgb then
        if tex then
            tex:SetColorTexture(bg.rgb[1], bg.rgb[2], bg.rgb[3], 1)
            tex:Show()
        end
        BaseArt:SetVisible(false)
    elseif bg.blizzardArt then
        if tex then tex:Hide() end
        BaseArt:SetVisible(true)
    else
        -- Transparent and Raw: nothing of ours behind the tiles, and
        -- nothing of Blizzard's either.
        if tex then tex:Hide() end
        BaseArt:SetVisible(false)
    end
    -- Orthogonal to the three branches above, and only Transparent wants it:
    -- the other entries all put something opaque in front of the frame's own
    -- backing, so hiding it would change nothing but could still be seen at
    -- the map's edges.
    MapFrameBg:SetVisible(not bg.seeThrough)
    return bg
end

--- Restore default map art and release HFWM textures.
local function RestoreDefaults()
    Config.overlayActive = false
    if Config.backdropTexture then Config.backdropTexture:Hide() end
    BaseArt:SetVisible(true)
    MapFrameBg:SetVisible(true)
    Exploration:SetVisible(true)
    Exploration:ApplyLevels()
end

--- Fog of War: draw the slice of this addon's own tile grid that falls
--- under one of Blizzard's own, currently-active exploration reveal
--- textures (Exploration:EnumerateOverlayTextures), cropped to that exact
--- texture's own alpha shape (the same torn, irregular edge Blizzard's
--- own map uses right now) instead of a hard rectangle.
---
--- Blizzard's own client code (MapExplorationPinMixin:RefreshOverlays, in
--- Blizzard_SharedMapDataProviders/MapExplorationDataProvider.lua) draws
--- *blizTex*'s file plainly, with no masking of its own. That does not
--- mean the file is flat, though: a texture's own alpha channel still
--- applies when it's simply drawn. `/hfwm testmask` (Commands.lua)
--- confirmed on a live client that *blizTex*'s file is a real irregular
--- shape, with parchment visible through it where it's transparent.
--- Fragmentation seen on an earlier attempt was wrongly blamed on this
--- masking approach; the real cause was an unrelated SetGradient call
--- elsewhere in this file (since fixed) that fragmented piece alpha.
---
--- A later attempt came out misaligned instead, because it rebuilt
--- blizTex's screen rect and texture-coordinate rect by hand: read once,
--- converted into this function's own layer-pixel space, then sliced
--- into a fractional texcoord sub-rect per piece. Any rounding, wrong
--- axis, or frame movement between that read and the draw shows up as a
--- wrong-shaped edge. The fix is to stop rebuilding blizTex's rect at
--- all: one MaskTexture is anchored directly to blizTex itself with
--- SetPoint (TOPLEFT/BOTTOMRIGHT, no coordinates of our own) and given
--- blizTex's own file and its exact, unmodified GetTexCoord(), so its
--- screen rect and mapping stay blizTex's own, continuously, rather than
--- a snapshot computed once. That single mask is then handed to every
--- piece that overlaps it via AddMaskTexture; the client works out the
--- overlap itself, so nothing here can drift.
---
--- *blizTex* is read directly (GetLeft/Top/Right/Bottom, GetTexture,
--- GetTexCoord) rather than reconstructed from raw offsets, since it is a
--- live Texture Blizzard's own client already positioned, sized, textured
--- and cropped correctly this very frame (HidePins only zeroes its alpha;
--- otherwise it behaves like a normal, undisturbed exploration overlay).
--- Its screen rect rarely lines up with this addon's own tile grid, so it
--- is usually split across several tiles, each getting its own texture
--- but sharing the one mask anchored to *blizTex*, so the pieces still
--- line up into that one true shape once drawn.
---
--- Not a complete picture on its own: tracing showed explored ground with
--- no live reveal texture behind it at all. See DrawFillPiece below (and
--- the *filled* param this writes into) for the pass that plugs that gap;
--- it has no comparable mask to borrow, so it stays hard-edged. Only this
--- pass's pieces get the organic edge.
---@param blizTex table live Texture from Exploration:EnumerateOverlayTextures
---@param frameLeft number Config.overlayFrame:GetLeft(), screen space
---@param frameTop number Config.overlayFrame:GetTop(), screen space
---@param layerW number
---@param layerH number
---@param tilePxW number
---@param tilePxH number
---@param cols number
---@param rows number
---@param tileSource table
---@param scaleX number
---@param scaleY number
---@param filled table cell (row*cols+col) -> true, shared across every
---                     call this Refresh; lets the C_MapExplorationInfo
---                     gap-filling pass (see Refresh) know which cells
---                     already got an organically-masked piece here, so
---                     it only ever plugs the ones this left uncovered.
---@param pieceTex table cell (row*cols+col) -> the Texture drawn for it,
---                      shared across every call this Refresh; lets
---                      SoftenFogEdges (see Refresh) come back afterwards
---                      and fade whichever of these end up on the outer
---                      boundary of the final, fully-assembled shape,
---                      once every pass has run and that boundary is
---                      actually known.
---@param trace boolean|nil
---@return number piecesDrawn
local function DrawExploredPiece(
    blizTex, frameLeft, frameTop,
    layerW, layerH, tilePxW, tilePxH, cols, rows, tileSource, scaleX, scaleY,
    gridX, gridY,
    filled, pieceTex, trace)

    -- isShownByMouseOver pieces (Blizzard's own RefreshOverlays) start
    -- Hidden, and only Blizzard's own mouse-over handling ever Shows them;
    -- nothing this addon does touches that. So an unshown texture here
    -- means Blizzard itself is not currently revealing anything with it,
    -- same as if it were not in the list at all.
    if not blizTex:IsShown() then
        if trace then P("  fog piece SKIPPED: not shown") end
        return 0
    end

    -- Leatrix Maps' and MapUtils' "show unexplored areas" add their own
    -- reveal textures to this same pin, tinted (vertex colour or
    -- desaturation); Blizzard's own explored ones never are. A tinted one
    -- is unexplored ground: draw the HD art under it with the same tint,
    -- one sublevel below the explored pieces (as both addons layer theirs),
    -- and leave filled/pieceTex alone so the explored-only passes after
    -- this still fill every explored cell it overlaps. Untinted ones (tint
    -- turned off in those addons) reveal in full, as those addons do.
    -- Alpha is ignored: HidePins zeroes it on every one of these textures,
    -- explored or not, so it says nothing about the tint.
    local r, g, b = blizTex:GetVertexColor()
    local desat = blizTex:IsDesaturated() and true or false
    local tinted = desat or r < 1 or g < 1 or b < 1

    local texLeft, texTop = blizTex:GetLeft(), blizTex:GetTop()
    local texRight, texBottom = blizTex:GetRight(), blizTex:GetBottom()
    if not (texLeft and texTop and texRight and texBottom
        and frameLeft and frameTop) then
        -- GetLeft/Top/Right/Bottom return nil until a region has actually
        -- been laid out on screen at least once; shown is not the same as
        -- laid out. The first time this addon lets Blizzard's exploration
        -- provider populate on a given map (previously always suppressed
        -- via RemoveAllData), that first frame's freshly (re)acquired
        -- chunk textures can still read nil here even though IsShown() is
        -- already true; see the retry in the caller.
        if trace then
            P(("  fog piece SKIPPED: not laid out yet (left=%s top=%s "
               .. "right=%s bottom=%s frameLeft=%s frameTop=%s)"):format(
                tostring(texLeft), tostring(texTop), tostring(texRight),
                tostring(texBottom), tostring(frameLeft), tostring(frameTop)))
        end
        return 0
    end

    -- Blizzard's screen-space rect, remapped into this addon's own
    -- layer-pixel space by the same scale this refresh already uses for
    -- its own tiles. GetTop/GetBottom count up from the bottom of the
    -- screen (WoW's usual convention), so frameTop - texTop is the
    -- distance *down* from the frame's own top edge, matching the sign
    -- the ordinary tile-layout loop already uses for cellY.
    local chunkX0 = (texLeft - frameLeft) / scaleX
    local chunkX1 = (texRight - frameLeft) / scaleX
    local chunkY0 = (frameTop - texTop) / scaleY
    local chunkY1 = (frameTop - texBottom) / scaleY

    local chunkW = chunkX1 - chunkX0
    local chunkH = chunkY1 - chunkY0
    if chunkW <= 0 or chunkH <= 0 then
        if trace then
            P(("  fog piece SKIPPED: degenerate chunk %.2fx%.2f"):format(
                chunkW, chunkH))
        end
        return 0
    end

    if trace then
        P(("  fog piece: screen=[%.1f,%.1f]-[%.1f,%.1f]  chunk(layerpx)="
           .. "[%.1f,%.1f]-[%.1f,%.1f] (%.1fx%.1f)"):format(
            texLeft, texTop, texRight, texBottom,
            chunkX0, chunkY0, chunkX1, chunkY1, chunkW, chunkH))
    end

    local colStart = math.max(0, math.floor((chunkX0 - gridX) / tilePxW))
    local colEnd   = math.min(cols - 1, math.ceil((chunkX1 - gridX) / tilePxW) - 1)
    local rowStart = math.max(0, math.floor((chunkY0 - gridY) / tilePxH))
    local rowEnd   = math.min(rows - 1, math.ceil((chunkY1 - gridY) / tilePxH) - 1)

    if trace then
        P(("    tiles touched: cols=%d rows=%d tilePx=%dx%d  colStart=%d "
           .. "colEnd=%d rowStart=%d rowEnd=%d (%d cell(s))"):format(
            cols, rows, tilePxW, tilePxH, colStart, colEnd, rowStart, rowEnd,
            (colEnd - colStart + 1) * (rowEnd - rowStart + 1)))
    end

    -- The mask here is not a copy: it's anchored directly to blizTex's
    -- own corners via SetPoint and uses its exact, unmodified
    -- GetTexCoord(), so it tracks blizTex's real layout instead of a
    -- reconstruction (see this function's doc comment for why rebuilding
    -- it went wrong before). Built once per blizTex, then handed to every
    -- overlapping piece via AddMaskTexture; the client does the per-piece
    -- overlap math.
    local maskFile = blizTex:GetTexture()
    if not maskFile then
        if trace then P("  fog piece SKIPPED: no texture file") end
        return 0
    end

    local mulX, mulY, mllX, mllY, murX, murY, mlrX, mlrY =
        blizTex:GetTexCoord()

    -- CLAMPTOBLACKADDITIVE (the usual mask choice) is wrong here and was
    -- the cause of seams users reported. Each chunk's mask edge normally
    -- sits exactly on the seam against the next chunk's mask. GPU texture
    -- filtering blends the texel at texcoord 0.0/1.0 with whatever lies
    -- just past it, and CLAMPTOBLACKADDITIVE makes that "just past it"
    -- pure black, so every chunk faded slightly toward masked-out right
    -- at its border, and two adjoining chunks doing that produced a
    -- visible seam. Plain "CLAMP" repeats the true edge texel's alpha
    -- instead, which removes the seam: this addon's pieces never sample
    -- outside a mask's 0..1 range anyway (each is clipped to its chunk's
    -- own screen rect before drawing), so there was nothing for
    -- CLAMPTOBLACKADDITIVE to protect here.
    local mask = MaskPool:Acquire()
    mask:ClearAllPoints()
    mask:SetPoint("TOPLEFT", blizTex, "TOPLEFT")
    mask:SetPoint("BOTTOMRIGHT", blizTex, "BOTTOMRIGHT")
    mask:SetTexture(maskFile, "CLAMP", "CLAMP")
    mask:SetTexCoord(mulX, mulY, mllX, mllY, murX, murY, mlrX, mlrY)

    local piecesDrawn, nilSrcSkipped, degenerateSkipped = 0, 0, 0
    for row = rowStart, rowEnd do
        for col = colStart, colEnd do
            local src = tileSource[row * cols + col + 1]
            if not src then nilSrcSkipped = nilSrcSkipped + 1 end
            if src then
                local tileX0 = gridX + col * tilePxW
                local tileY0 = gridY + row * tilePxH
                local tileX1 = tileX0 + math.min(tilePxW, layerW - tileX0)
                local tileY1 = tileY0 + math.min(tilePxH, layerH - tileY0)

                local ix0 = math.max(tileX0, chunkX0)
                local ix1 = math.min(tileX1, chunkX1)
                local iy0 = math.max(tileY0, chunkY0)
                local iy1 = math.min(tileY1, chunkY1)

                if not (ix1 > ix0 and iy1 > iy0) then
                    degenerateSkipped = degenerateSkipped + 1
                end
                if ix1 > ix0 and iy1 > iy0 then
                    local screenW = (ix1 - ix0) * scaleX
                    local screenH = (iy1 - iy0) * scaleY
                    local screenX = ix0 * scaleX
                    local screenY = iy0 * scaleY

                    local tex = Pool:Acquire()
                    tex:SetSize(screenW, screenH)
                    tex:SetPoint("TOPLEFT", Config.overlayFrame, "TOPLEFT",
                        screenX, -screenY)
                    tex:SetTexCoord(
                        (ix0 - tileX0) / tilePxW, (ix1 - tileX0) / tilePxW,
                        (iy0 - tileY0) / tilePxH, (iy1 - tileY0) / tilePxH)
                    tex:SetTexture(src)

                    -- Crop to blizTex's own live shape. One shared mask
                    -- (built once above, anchored to blizTex itself) is
                    -- added to every piece that overlaps it; the client
                    -- works out the actual overlap between this piece's
                    -- own screen rect and the mask's -- which is
                    -- blizTex's real rect, not a reconstruction of it --
                    -- so there is no fraction math here to get wrong.
                    tex:AddMaskTexture(mask)

                    piecesDrawn = piecesDrawn + 1
                    if tinted then
                        tex:SetDrawLayer("ARTWORK", 1)
                        tex:SetVertexColor(r, g, b, 1)
                        tex:SetDesaturated(desat)
                    else
                        if filled then filled[row * cols + col] = true end
                        if pieceTex then pieceTex[row * cols + col] = tex end
                    end
                end
            end
        end
    end

    if trace then
        P(("    -> %d piece(s) drawn  (%d skipped: no tileSource entry  "
           .. "%d skipped: degenerate intersection)"):format(
            piecesDrawn, nilSrcSkipped, degenerateSkipped))
    end
    return piecesDrawn
end

--- Fade one edge of *tex* to transparent, keeping the opposite edge fully
--- opaque, on whichever gradient API this client build actually has.
---
--- `Texture:SetGradientAlpha(orientation, r,g,b,a, r,g,b,a)` was the
--- classic signature; Patch 10.0.0 merged it into
--- `TextureBase:SetGradient(orientation, minColor, maxColor)`, taking two
--- ColorMixin objects instead of eight raw floats. This client is
--- missing SetGradientAlpha entirely (confirmed by the crash that
--- motivated this function), so it always takes the SetGradient branch.
---
--- Signature and orientation are confirmed against
--- https://warcraft.wiki.gg/wiki/API:TextureBase_SetGradient rather than
--- guessed: for "VERTICAL", minColor applies at the BOTTOM and maxColor
--- at the TOP; for "HORIZONTAL", minColor is on the LEFT and maxColor on
--- the RIGHT, same convention SetGradientAlpha used. A first attempt
--- assumed "start" meant whichever edge was being faded from regardless
--- of orientation, which is backwards for two of the four directions, and
--- also broke solid ground into scattered fragments for reasons never
--- fully isolated. This version follows the documented mapping literally,
--- spelled out per *transparentSide* instead of a generic "fadeAtStart".
---@param tex table
---@param transparentSide "TOP"|"BOTTOM"|"LEFT"|"RIGHT" which edge of *tex*
---                        fades to transparent; the opposite edge stays
---                        fully opaque
local function FadeEdge(tex, transparentSide)
    if tex.SetGradientAlpha then
        if transparentSide == "TOP" then
            tex:SetGradientAlpha("VERTICAL", 1, 1, 1, 1, 1, 1, 1, 0)
        elseif transparentSide == "BOTTOM" then
            tex:SetGradientAlpha("VERTICAL", 1, 1, 1, 0, 1, 1, 1, 1)
        elseif transparentSide == "LEFT" then
            tex:SetGradientAlpha("HORIZONTAL", 1, 1, 1, 0, 1, 1, 1, 1)
        elseif transparentSide == "RIGHT" then
            tex:SetGradientAlpha("HORIZONTAL", 1, 1, 1, 1, 1, 1, 1, 0)
        end
    elseif tex.SetGradient and CreateColor then
        local opaque = CreateColor(1, 1, 1, 1)
        local clear  = CreateColor(1, 1, 1, 0)
        if transparentSide == "TOP" then
            tex:SetGradient("VERTICAL", opaque, clear)
        elseif transparentSide == "BOTTOM" then
            tex:SetGradient("VERTICAL", clear, opaque)
        elseif transparentSide == "LEFT" then
            tex:SetGradient("HORIZONTAL", clear, opaque)
        elseif transparentSide == "RIGHT" then
            tex:SetGradient("HORIZONTAL", opaque, clear)
        end
    end
    -- Neither API: leave tex at whatever alpha it already has (full
    -- opacity from Pool:Acquire) rather than risk a wrong call.
end

--- Fog of War gap-filler: C_MapExplorationInfo.GetExploredMapTextures'
--- own top-level rects (offsetX, offsetY, textureWidth, textureHeight),
--- used WHOLE rather than split into Blizzard's internal per-chunk
--- pieces. An earlier version tried recomputing that internal chunking
--- from these same rects and got it visibly wrong (scattered, misplaced
--- squares), since it needed assumptions about tile size, file padding
--- and chunk order this addon has no way to verify. The plain rect
--- needed none of that, and was already confirmed correctly placed back
--- when this addon only ever drew rects, before any masking existed.
---
--- Live Blizzard reveal textures (DrawExploredPiece above) cover most of
--- the explored area with a real mask borrowed off Blizzard's own live
--- objects, but tracing proved they are not a complete raster of it:
--- each one gives full, zero-gap coverage of its OWN bounds, yet real
--- gaps still show up BETWEEN them, meaning some explored ground simply
--- has no live reveal-pin object behind it any more (pruned, never
--- created this session, or otherwise not currently live). This plugs
--- exactly those gaps: any explored cell DrawExploredPiece didn't already
--- mark in *filled* gets drawn here as a plain, unmasked full tile, left
--- at a hard edge on purpose. On this client Blizzard's own live reveal
--- texture turned out to carry no organic tear of its own at all
--- (tracing showed a plain 0,0-1,1 texture-coordinate crop, mask file
--- notwithstanding), so SoftenFogEdges, once both passes finish, is what
--- decides which cells sit on the outer boundary and fades only those,
--- instead of each piece fading its own edge.
---@param offsetX number rect.offsetX, in Blizzard's OWN art-layer pixels
---@param offsetY number rect.offsetY
---@param rectW number rect.textureWidth
---@param rectH number rect.textureHeight
---@param blizzardLayerW number the layer size those offsets are relative
---                             to -- NOT layerW/layerH below, which a
---                             native zone (see Refresh) may have
---                             swapped out for this addon's own finer
---                             grid entirely.
---@param blizzardLayerH number
---@param layerW number this addon's own grid, in its own pixel space
---@param layerH number
---@param tilePxW number
---@param tilePxH number
---@param cols number
---@param rows number
---@param tileSource table
---@param scaleX number
---@param scaleY number
---@param filled table cell (row*cols+col) -> true already drawn; this
---                     both reads it (to skip already-covered cells) and
---                     writes it (so a second, overlapping rect in this
---                     same pass does not double-draw a cell either)
---@param pieceTex table cell (row*cols+col) -> the Texture drawn for it;
---                      see DrawExploredPiece's own @param for why.
---@param trace boolean|nil
---@return number piecesDrawn
local function DrawFillPiece(
    offsetX, offsetY, rectW, rectH, blizzardLayerW, blizzardLayerH,
    layerW, layerH, tilePxW, tilePxH, cols, rows, tileSource, scaleX, scaleY,
    gridX, gridY,
    filled, pieceTex, trace)

    if blizzardLayerW <= 0 or blizzardLayerH <= 0 then return 0 end

    -- Fraction-of-map first, then into whichever grid this refresh is
    -- actually using -- identical to blizzardLayerW/H, and so a no-op,
    -- on every map that is not a native zone (see hfwm/gamedata/db2.py's
    -- _hires_geometry, which keeps the same normalized bounding box
    -- between Blizzard's own layer and this addon's native one).
    local chunkX0 = (offsetX            / blizzardLayerW) * layerW
    local chunkX1 = ((offsetX + rectW)  / blizzardLayerW) * layerW
    local chunkY0 = (offsetY            / blizzardLayerH) * layerH
    local chunkY1 = ((offsetY + rectH)  / blizzardLayerH) * layerH

    local chunkW = chunkX1 - chunkX0
    local chunkH = chunkY1 - chunkY0
    if chunkW <= 0 or chunkH <= 0 then return 0 end

    local colStart = math.max(0, math.floor((chunkX0 - gridX) / tilePxW))
    local colEnd   = math.min(cols - 1, math.ceil((chunkX1 - gridX) / tilePxW) - 1)
    local rowStart = math.max(0, math.floor((chunkY0 - gridY) / tilePxH))
    local rowEnd   = math.min(rows - 1, math.ceil((chunkY1 - gridY) / tilePxH) - 1)

    -- A hard-edged rectangle is what "very square" meant the first time
    -- this addon tried plain rects, before any masking existed. There is
    -- no per-file organic art to borrow for a cell nothing else covers
    -- (that is the whole reason this pass exists); softening the outer
    -- edge is SoftenFogEdges' job now, once every pass has run and the
    -- true outer boundary is known. Doing it per-rect here used to fade a
    -- cell on both sides of a seam between two adjacent rects, and fade
    -- cells that only looked like a rect's edge but were actually
    -- interior once the full shape was assembled.
    --
    -- A cell with NO already-filled neighbour (see hasFilledNeighbour
    -- below) is different from the case this pass exists for: it isn't a
    -- hole inside a solid patch of this addon's own hi-res tiles, it's a
    -- standalone explored patch with nothing beside it to seam against.
    -- Renderer:Activate() leaves Blizzard's own BaseArt detail layer
    -- visible underneath on purpose, already correctly grayscale/colored
    -- per real exploration state, for exactly this reason: skip drawing
    -- here and that layer shows through unchanged, identical to what the
    -- default map already shows at that spot. Drawing our own tile there
    -- instead would only add a visible resolution/style seam that isn't
    -- there on the default map. A cell that DOES have a filled neighbour
    -- keeps the old hard-fill behaviour, since leaving that one bare would
    -- instead punch a hole of mismatched BaseArt into the middle of solid
    -- hi-res ground -- the "checkerboard of one-tile holes" CloseFogGaps'
    -- own doc comment describes, which is worse than a hard edge.
    local piecesDrawn, isolatedSkipped = 0, 0
    for row = rowStart, rowEnd do
        for col = colStart, colEnd do
            local idx = row * cols + col
            if not filled[idx] then
                local src = tileSource[idx + 1]
                if src then
                    local tileX0 = gridX + col * tilePxW
                    local tileY0 = gridY + row * tilePxH
                    local tileX1 = tileX0 + math.min(tilePxW, layerW - tileX0)
                    local tileY1 = tileY0 + math.min(tilePxH, layerH - tileY0)

                    local ix0 = math.max(tileX0, chunkX0)
                    local ix1 = math.min(tileX1, chunkX1)
                    local iy0 = math.max(tileY0, chunkY0)
                    local iy1 = math.min(tileY1, chunkY1)

                    if ix1 > ix0 and iy1 > iy0 then
                        local hasFilledNeighbour =
                            (row > 0        and filled[idx - cols]) or
                            (row < rows - 1 and filled[idx + cols]) or
                            (col > 0        and filled[idx - 1]) or
                            (col < cols - 1 and filled[idx + 1])

                        if hasFilledNeighbour then
                            local screenW = (ix1 - ix0) * scaleX
                            local screenH = (iy1 - iy0) * scaleY
                            local screenX = ix0 * scaleX
                            local screenY = iy0 * scaleY

                            local tex = Pool:Acquire()
                            tex:SetSize(screenW, screenH)
                            tex:SetPoint("TOPLEFT", Config.overlayFrame, "TOPLEFT",
                                screenX, -screenY)
                            tex:SetTexCoord(
                                (ix0 - tileX0) / tilePxW, (ix1 - tileX0) / tilePxW,
                                (iy0 - tileY0) / tilePxH, (iy1 - tileY0) / tilePxH)
                            tex:SetTexture(src)

                            -- No mask: nothing softer covers this exact
                            -- cell, so it draws as a plain filled tile
                            -- instead of leaving the gap DrawExploredPiece
                            -- couldn't reach. Left at full alpha regardless
                            -- of where it sits in *this* rect -- see
                            -- SoftenFogEdges for why.
                            filled[idx] = true
                            if pieceTex then pieceTex[idx] = tex end
                            piecesDrawn = piecesDrawn + 1
                        else
                            -- Deliberately NOT marked filled: leaving it
                            -- false is what lets BaseArt keep showing
                            -- through, and lets a later rect in this same
                            -- pass (or CloseFogGaps after it) still pick
                            -- this cell up if something adjacent to it
                            -- does end up filled first.
                            isolatedSkipped = isolatedSkipped + 1
                        end
                    end
                end
            end
        end
    end

    if trace then
        P(("  fill rect: offset=%d,%d size=%dx%d -> chunk(layerpx)="
           .. "[%.1f,%.1f]-[%.1f,%.1f]  %d piece(s) drawn (gap-filled)  "
           .. "%d isolated cell(s) skipped (BaseArt shows through)"):format(
            offsetX, offsetY, rectW, rectH, chunkX0, chunkY0, chunkX1, chunkY1,
            piecesDrawn, isolatedSkipped))
    end

    return piecesDrawn
end

--- Fog of War's last pass: close one-tile pinholes left after both passes
--- above.
---
--- DrawExploredPiece and DrawFillPiece both chunk the world at whatever
--- granularity Blizzard's exploration data uses, which on this client is
--- coarser and raggeder than this addon's own tile grid. A solidly
--- explored stretch can still come back with scattered single tiles that
--- never got a piece of their own, because neither pass's source data
--- drew a boundary through that tile specifically. Tracing confirmed
--- this: piece counts fell short throughout the explored footprint, not
--- just at its edges, as a checkerboard of one-tile holes rather than a
--- ragged coastline.
---
--- Filling a hole only when EVERY one of its neighbours is already
--- filled keeps this safe. An `n >= 3` threshold (three sides filled)
--- was tried first, on the assumption that a real unexplored region
--- borders filled ground on at most one or two sides, never three or
--- four -- which held for the scattered chunk-boundary pinholes this
--- pass was built for, but not in general: a winding outdoor path (e.g.
--- a mountain trail that loops close to itself, or wraps around a spur
--- of unwalkable rock) can leave a real, never-visited pocket bordered
--- on three sides by ground the player actually explored walking the
--- loop, with the fourth side opening onto more unexplored territory.
--- `n >= 3` force-fills that pocket as if it were explored, hard-edged,
--- even though neither a live Blizzard reveal texture nor
--- C_MapExplorationInfo ever said so -- confirmed live in Mulgore, where
--- this drew a small square with no exploration data behind it at all,
--- beside the Fargodeep Mine outdoor path. Requiring all four sides
--- (`n == 4`, a cell fully boxed in on every edge) keeps closing genuine
--- one-tile chunk-boundary holes -- those really are surrounded on every
--- side, that's what made them look like pinholes -- while leaving a
--- three-sided real gap alone; Renderer:Activate() already leaves
--- Blizzard's own BaseArt layer showing through anything left unfilled,
--- so an unclosed three-sided gap looks like the default map there
--- rather than a visible hole. A single pass suffices since every hole
--- this catches is already fully surrounded by the time it runs.
---@param cols number
---@param rows number
---@param tileSource table
---@param filled table cell (row*cols+col) -> true; read AND extended here
---@param pieceTex table cell (row*cols+col) -> the Texture drawn for it;
---                      see DrawExploredPiece's own @param for why.
---@param layerW number
---@param layerH number
---@param tilePxW number
---@param tilePxH number
---@param scaleX number
---@param scaleY number
---@param trace boolean|nil
---@return number piecesDrawn
local function CloseFogGaps(cols, rows, tileSource, filled, pieceTex,
    layerW, layerH, tilePxW, tilePxH, scaleX, scaleY, gridX, gridY, trace)

    -- Collected first, rather than filled in place as they're found: this
    -- pass is only meant to close holes the two passes above left behind,
    -- not to chain off holes it closes itself, which -- for a hole sitting
    -- right next to another hole -- filling in loop order could otherwise
    -- let happen.
    local toFill = {}
    for row = 0, rows - 1 do
        for col = 0, cols - 1 do
            local idx = row * cols + col
            if not filled[idx] and tileSource[idx + 1] then
                local n = 0
                if row > 0          and filled[idx - cols] then n = n + 1 end
                if row < rows - 1   and filled[idx + cols] then n = n + 1 end
                if col > 0          and filled[idx - 1]    then n = n + 1 end
                if col < cols - 1   and filled[idx + 1]    then n = n + 1 end
                if n >= 4 then
                    toFill[#toFill + 1] = idx
                end
            end
        end
    end

    local piecesDrawn = 0
    for _, idx in ipairs(toFill) do
        local row = math.floor(idx / cols)
        local col = idx % cols
        local src = tileSource[idx + 1]

        local x0 = gridX + col * tilePxW
        local y0 = gridY + row * tilePxH
        local cx0, cx1 = math.max(x0, 0), math.min(x0 + tilePxW, layerW)
        local cy0, cy1 = math.max(y0, 0), math.min(y0 + tilePxH, layerH)

        local tex = Pool:Acquire()
        tex:SetSize((cx1 - cx0) * scaleX, (cy1 - cy0) * scaleY)
        tex:SetPoint("TOPLEFT", Config.overlayFrame, "TOPLEFT",
            cx0 * scaleX, -(cy0 * scaleY))
        tex:SetTexCoord((cx0 - x0) / tilePxW, (cx1 - x0) / tilePxW,
            (cy0 - y0) / tilePxH, (cy1 - y0) / tilePxH)
        tex:SetTexture(src)

        filled[idx] = true
        if pieceTex then pieceTex[idx] = tex end
        piecesDrawn = piecesDrawn + 1
    end

    if trace and piecesDrawn > 0 then
        P(("  fog: closed %d one-tile pinhole(s)"):format(piecesDrawn))
    end

    return piecesDrawn
end

--- Fog of War's final pass: fade the outer boundary of the whole,
--- now-fully-assembled explored shape, rather than trusting any one piece
--- above to have already brought its own soft edge.
---
--- DrawExploredPiece and DrawFillPiece used to fade their own outer edges
--- as they went, assuming DrawExploredPiece's mask brought a real organic
--- tear. Tracing disproved that on this client (the mask turned out to be
--- a plain, uncropped 0,0-1,1 rectangle; see its call site's comment) and
--- exposed a deeper problem with fading per-piece at all: each piece only
--- knows its own local rect, not the shape of what ends up next to it, so
--- an interior cell could get faded for no reason, and a boundary cell
--- covered by two overlapping pieces could end up faded by one and
--- redrawn solid by the other depending on draw order. Waiting until
--- every cell is filled, then looking at each one's actual neighbours, is
--- the only way to get a boundary for the whole shape rather than any one
--- piece's contribution.
---
--- Same safety property as CloseFogGaps: a cell's own neighbours decide
--- whether and how it fades, so this can only soften the true edge of
--- ground already marked explored; it cannot dim interior cells or
--- invent a fade along ground nothing above ever drew.
---@param cols number
---@param rows number
---@param filled table cell (row*cols+col) -> true; read only here
---@param pieceTex table cell (row*cols+col) -> the Texture drawn for it
---@param trace boolean|nil
local function SoftenFogEdges(cols, rows, filled, pieceTex, trace)
    local faded = 0
    for row = 0, rows - 1 do
        for col = 0, cols - 1 do
            local idx = row * cols + col
            local tex = filled[idx] and pieceTex[idx]
            if tex then
                -- Same convention as the rect-edge fade this replaces:
                -- there is no fog beyond the map's own edge to fade into,
                -- so a cell at row/col 0 or cols-1/rows-1 is never treated
                -- as a boundary on that side purely for being at the map's
                -- edge -- only an actual unfilled neighbour counts.
                local hasTop    = row > 0         and not filled[idx - cols]
                local hasBottom = row < rows - 1  and not filled[idx + cols]
                local hasLeft   = col > 0         and not filled[idx - 1]
                local hasRight  = col < cols - 1  and not filled[idx + 1]

                -- Same row-wins-column tie-break DrawFillPiece's own fade
                -- used to make, for the cells (rect/chunk corners) that
                -- would otherwise qualify on two sides at once -- a
                -- gradient only ever fades along one axis at a time.
                if hasTop then
                    FadeEdge(tex, "TOP")
                    faded = faded + 1
                elseif hasBottom then
                    FadeEdge(tex, "BOTTOM")
                    faded = faded + 1
                elseif hasLeft then
                    FadeEdge(tex, "LEFT")
                    faded = faded + 1
                elseif hasRight then
                    FadeEdge(tex, "RIGHT")
                    faded = faded + 1
                end
            end
        end
    end

    if trace and faded > 0 then
        P(("  fog: softened %d boundary tile(s)"):format(faded))
    end
end

--- Draw the part of this addon's tile grid inside one rectangle, given in
--- layer pixels, clipping the tiles that straddle its edges. *mask*, when
--- given, crops every piece to its shape.
local function DrawLayerRect(x0, y0, x1, y1, layerW, layerH, tilePxW, tilePxH,
    cols, rows, tileSource, scaleX, scaleY, mask)
    for row = math.max(0, math.floor(y0 / tilePxH)),
        math.min(rows - 1, math.ceil(y1 / tilePxH) - 1) do
        for col = math.max(0, math.floor(x0 / tilePxW)),
            math.min(cols - 1, math.ceil(x1 / tilePxW) - 1) do
            local src = tileSource[row * cols + col + 1]
            if src then
                local tileX, tileY = col * tilePxW, row * tilePxH
                local ix0, ix1 = math.max(tileX, x0),
                    math.min(tileX + tilePxW, layerW, x1)
                local iy0, iy1 = math.max(tileY, y0),
                    math.min(tileY + tilePxH, layerH, y1)
                if ix1 > ix0 and iy1 > iy0 then
                    local tex = Pool:Acquire()
                    tex:SetSize((ix1 - ix0) * scaleX, (iy1 - iy0) * scaleY)
                    tex:SetPoint("TOPLEFT", Config.overlayFrame, "TOPLEFT",
                        ix0 * scaleX, -iy0 * scaleY)
                    tex:SetTexCoord((ix0 - tileX) / tilePxW, (ix1 - tileX) / tilePxW,
                        (iy0 - tileY) / tilePxH, (iy1 - tileY) / tilePxH)
                    tex:SetTexture(src)
                    if mask then tex:AddMaskTexture(mask) end
                end
            end
        end
    end
end

--- The actual work of a refresh, wrapped and guarded by Renderer:Refresh
--- below against being re-entered while already running.
---@param force boolean|nil
local function DoRefresh(force)
    if not Config.overlayFrame then return end

    local mapID = WorldMapFrame:GetMapID()
    if not mapID then
        Config.overlayActive = false
        Pool:ReleaseAll()
        MaskPool:ReleaseAll()
        Config.lastMapID = nil
        return
    end

    local canvas = WorldMapFrame.ScrollContainer
        and WorldMapFrame.ScrollContainer.Child
    if not canvas then return end

    -- Re-parent overlay frame if canvas was replaced (WoW 12.0+)
    if Config.overlayFrame:GetParent() ~= canvas then
        Config.overlayFrame:SetParent(canvas)
        Config.overlayFrame:ClearAllPoints()
        Config.overlayFrame:SetAllPoints(canvas)
        Config.overlayFrame:SetFrameLevel(canvas:GetFrameLevel() + 500)
        Config.overlayFrame:EnableMouse(false)
    end

    -- A replaced canvas doesn't just need re-parenting: MapFrameBg's
    -- Transparent-mode concealment (and BaseArt's) is keyed off specific
    -- region objects it found and hid, including
    -- WorldMapFrame.ScrollContainer.Child.TiledBackground, the wood-grain
    -- placeholder the canvas paints behind everything else. A *new*
    -- canvas object means a brand new TiledBackground region that was
    -- never found, hidden or hooked, and it stays visible until something
    -- forces a fresh concealment pass. Without this, "canvasChanged" was
    -- silently absorbed by the "skip if nothing changed" check below
    -- whenever the swap didn't also change mapID/size/layerIdx, the
    -- ordinary case, so Transparent could come back from a canvas swap
    -- permanently showing Blizzard's wood backing with no further Refresh
    -- ever re-checking it.
    local canvasChanged = (canvas ~= Config.lastCanvas)

    local canvasW, canvasH = canvas:GetSize()

    -- Determine art layer (surface vs. underwater)
    local allLayers = C_Map.GetMapArtLayers(mapID)
    local numLayers = allLayers and #allLayers or 0
    local submerged = IsSubmerged() and true or false
    local layerIdx  = 1
    if numLayers >= 2 and submerged then
        layerIdx = 2
    end

    -- Trace logging during forced refresh
    local trace = force and Config.tracing
    if trace then
        P(("Refresh: mapID=%s  canvas=%dx%d  layers=%d  sub=%s  layerIdx=%d"):format(
            tostring(mapID), canvasW, canvasH, numLayers,
            tostring(submerged), layerIdx))
        P(("  parent match=%s  overlayFrame parent=%s"):format(
            tostring(Config.overlayFrame:GetParent() == canvas),
            tostring(Config.overlayFrame:GetParent())))
    end

    -- Skip if nothing changed. canvasChanged is deliberately its own term
    -- here rather than folded into a change to canvasW/canvasH: a replaced
    -- canvas at the *same* size would otherwise still look unchanged to
    -- this check (see the canvasChanged comment above) and skip the
    -- MapFrameBg/BaseArt re-application a swap requires.
    if not force and not canvasChanged and mapID == Config.lastMapID
       and canvasW == Config.lastCanvasW
       and canvasH == Config.lastCanvasH
       and layerIdx == Config.lastLayerIdx
       and Pool:ActiveCount() > 0 then
        return
    end

    -- Captured before Config.lastMapID is overwritten just below, and used
    -- much later, in the Fog of War block, to decide whether this is the
    -- very first draw for this particular map/canvas -- see the mask
    -- streaming retry there for why that specific moment needs its own
    -- extra care.
    local isFreshMapOpen = (mapID ~= Config.lastMapID) or canvasChanged

    Pool:ReleaseAll()
    MaskPool:ReleaseAll()
    Config.lastCanvas    = canvas
    Config.lastMapID     = mapID
    Config.lastCanvasW   = canvasW
    Config.lastCanvasH   = canvasH
    Config.lastLayerIdx  = layerIdx
    Config.lastSubmerged = submerged

    if not Config.db or not Config.db.enabled then
        if trace then P("  BAIL: disabled") end
        RestoreDefaults()
        return
    end
    if not mapID then
        if trace then P("  BAIL: no mapID") end
        return
    end

    if numLayers == 0 then
        if trace then P("  BAIL: numLayers=0") end
        RestoreDefaults()
        return
    end

    local layer   = allLayers[layerIdx]
    local layerW  = layer.layerWidth
    local layerH  = layer.layerHeight
    -- Kept alongside layerW/layerH rather than instead of them: Fog of
    -- War's gap-filling pass (DrawFillPiece) reads exploration rects from
    -- C_MapExplorationInfo.GetExploredMapTextures, which are always
    -- expressed in Blizzard's own art-layer pixel space, no matter what
    -- this refresh ends up actually drawing tiles in. That stays true
    -- even when a native zone (below) overwrites layerW/layerH with this
    -- addon's own finer grid, so the two have to be told apart.
    local blizzardLayerW = layerW
    local blizzardLayerH = layerH
    local tilePxW = layer.tileWidth  or 256
    local tilePxH = layer.tileHeight or 256
    local cols    = math.ceil(layerW / tilePxW)
    local rows    = math.ceil(layerH / tilePxH)

    -- The background decides which tile set to draw, not just what goes
    -- behind it: Raw has its own dump under WorldMap/Original/ and
    -- therefore its own lookup table. Everything else draws the bundled
    -- transparent art. Resolved before ApplyBackground so both see the same
    -- entry, and before fogOfWar below, which needs to know it.
    --
    -- GetBackgroundForMap, not GetBackground: Zone Map, Continent Map and
    -- World Map (Config.MAP_TYPES) can each override the Global Background
    -- for their own kind of map, and this is the one place that override
    -- has to take effect -- everything below this line already just reads
    -- `background`, same as when there was only ever one setting.
    local background   = Config:GetBackgroundForMap(mapID)
    local FDID_MAP     = Config:GetTileMap(background)
    local FDID_MAP_SUB = Config.FDID_MAP_SUB
    local FDID_BASE    = Config.FDID_BASE
    local HD_BASE      = Config.HD_BASE

    -- Hoisted above Activate() (which used to compute this itself) because
    -- the tile-layout section below needs it too, to decide whether to draw
    -- the ordinary unconditional grid or Fog of War's explored-only subset.
    --
    -- Config:FogOfWarEnabled() only answers whether the FEATURE is armed at
    -- all (the toggle is on and the Zone Map background resolves to
    -- Hybrid) -- it has no idea what map is actually on screen right now.
    -- Without the `background.key == "hybrid"` check below, turning Fog of
    -- War on with Zone Map set to Hybrid used to force Blizzard's detail
    -- layer visible (see Activate()'s BaseArt:SetVisible(true) override)
    -- on EVERY map for the rest of the session, Continent/World included,
    -- even when their own background was explicitly set to something else
    -- like Transparent -- exactly backwards, and the bug reported as
    -- "still see the original map on continent/world even though those
    -- are set to Transparent". This map's own resolved `background` is
    -- what Activate() is about to draw with, so that -- not the Zone Map
    -- setting elsewhere -- has to be what gates overriding it back to
    -- Blizzard's art.
    local clientZone = Config:GetClientZone(mapID)
    local gridX, gridY = 0, 0
    -- Fog of War is a Zone Map feature (Config:FogOfWarEnabled keys off the
    -- Zone background). Without the map-type check, a Hybrid World/Continent
    -- map with Fog of War on took the explored-only path and drew just the
    -- subset of tiles under whatever exploration textures it found.
    --
    -- A Hybrid zone takes this path with Fog of War off too, as a fully
    -- explored map: Exploration reveals every overlay (not just the
    -- explored ones), and HD is cut to those shapes, so Blizzard's own art
    -- still shows wherever the game has nothing to explore.
    local mapType = Config:ClassifyMapID(mapID)
    local fogOfWar = background.key == "hybrid"
        and mapType ~= "world" and mapType ~= "continent"
        and ZONE_OVERLAYS[mapID] ~= nil
    local fullyExplored = fogOfWar and not Config:FogOfWarEnabled()

    -- World/Continent Fog of War (Options' checkbox beside World Map): the
    -- zones fully explored, each { zone, u0, v0, u1, v1 } (the box its mask
    -- covers, 0-1 over the map), or nil to draw the map whole.
    local worldFogZones
    if Config:WorldFogOfWarEnabled(mapID) then
        worldFogZones = ns.ZoneFog:Explored(mapID)
    end

    local tileSource = {}
    local useBundled = false
    local useNative  = false

    -- Higher-resolution maps (see hfwm/gamedata/db2.py's _hires_geometry) bypass
    -- Blizzard's fixed art-layer geometry entirely: every Type=Zone map,
    -- uncapped, plus Kalimdor/Eastern Kingdoms/the top-level Azeroth map,
    -- capped (see HIRES_CONTINENT_MAPS). Our own bundled grid is finer
    -- than anything a Classic-era UiMapArtStyleLayer can describe for
    -- these, so cols/rows/tile size/layer size all come from the
    -- pipeline's own output instead of C_Map.GetMapArtLayers, and the
    -- tile source is built straight from a path prefix rather than
    -- looked up per Blizzard FileDataID.
    -- clientZone's tiles are the client's own minimap files, laid on a grid
    -- that starts at (gridX, gridY) in layer pixels (negative: the first
    -- tile overhangs the map). Native zones and the legacy path start at 0,0.
    local nativeZone = not clientZone and Config:GetNativeZone(mapID, background)
    if clientZone then
        local reg = clientZone.regions[1]
        layerW, layerH = clientZone.layerW, clientZone.layerH
        if reg then
            tilePxW, tilePxH = reg.tw, reg.th
            cols, rows = reg.cols, reg.rows
            gridX, gridY = reg.ox, reg.oy
        end
        for i, fdid in ipairs(reg and reg.f or {}) do
            if fdid ~= 0 then tileSource[i] = fdid end
        end
        useBundled, useNative = true, true
    elseif nativeZone then
        layerW, layerH = nativeZone.layerW, nativeZone.layerH
        tilePxW, tilePxH = nativeZone.tileW, nativeZone.tileH
        cols, rows = nativeZone.cols, nativeZone.rows
        for i = 1, cols * rows do
            tileSource[i] = HD_BASE .. nativeZone.path .. i
        end
        useBundled, useNative = true, true
    end

    -- Resolve tile source (legacy path: only when this map has no native
    -- geometry above, i.e. continent/world maps, or a native zone whose
    -- art wasn't actually built, in which case this safely falls back to
    -- Blizzard's own client art rather than erroring).
    local fdids
    if not useNative then
        fdids = C_Map.GetMapArtLayerTextures(mapID, layerIdx)
        if not fdids or #fdids == 0 then
            if trace then P("  BAIL: no FDIDs from C_Map") end
            RestoreDefaults()
            return
        end
        useBundled = FDID_MAP[fdids[1]] ~= nil
    end

    if trace then
        P(("  useNative=%s  fdids=%s  useBundled=%s  background=%s  "
           .. "tileMap_size=%d"):format(
            tostring(useNative), fdids and #fdids or "n/a",
            tostring(useBundled), background.key,
            background.tiles == "original"
                and (Config._fdidMapOriginalSize or -1)
                or (Config._fdidMapSize or -1)))
    end
    local useSubmerged = false

    if useNative then
        -- tileSource already built above.
    elseif useBundled and FDID_MAP_SUB[fdids[1]] then
        local playerMap = C_Map.GetBestMapForUnit("player")
        local inVashjir = playerMap and Config.VASHJIR_MAPS[playerMap]
        if not (inVashjir and not submerged) then
            useSubmerged = true
        end
    elseif useBundled and layerIdx >= 2 then
        useBundled = false
    end

    if not useNative then
        if useBundled then
            local lookup = useSubmerged and FDID_MAP_SUB or FDID_MAP
            for i, fdid in ipairs(fdids) do
                local rel = lookup[fdid]
                tileSource[i] = rel and (FDID_BASE .. rel) or fdid
            end
        else
            tileSource = fdids
        end
    end

    -- Fog of War only applies when this map actually has explored-data to
    -- honor. Some maps (or some areas within a map) have no live
    -- exploration textures at all, and stale overlay textures from a prior
    -- zone can otherwise keep the SD base art visible after the user
    -- navigates back. If the current map reports zero explored chunks, treat
    -- the stale textures as irrelevant and keep the full HD grid active.
    local explored = fogOfWar and useBundled
        and C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures(mapID)
    local blizExploredTextures = fogOfWar and useBundled and Exploration:EnumerateOverlayTextures()
    local hasExploredChunks = explored and #explored > 0
    local hasLiveBlizTextures = blizExploredTextures and #blizExploredTextures > 0
    local fogActive = fogOfWar and useBundled and (
        fullyExplored or hasExploredChunks or (not explored and hasLiveBlizTextures)
    )

    if trace then
        P(("  tileSource[1]=%s"):format(tostring(tileSource[1])))
        if type(tileSource[1]) == "string" then
            P(("  tileSource[1] type=string (bundled path)"))
        else
            P(("  tileSource[1] type=%s (raw FDID)"):format(type(tileSource[1])))
        end
    end

    --- Switch the overlay on, and return the background entry in force.
    ---
    --- The *tile* half of the background setting only matters where we
    --- draw our own transparent tiles: on a map with no bundled BLPs the
    --- tiles are the client's own opaque art regardless of background, so
    --- this skips ApplyBackground's tile/backdrop branches, hides the
    --- detail layer, draws no backdrop, and returns nil.
    ---
    --- The map-frame-backing half used to get this wrong by calling
    --- MapFrameBg:SetVisible(true) unconditionally. Nothing here draws
    --- over that backing on this kind of map, so Transparent still needs
    --- it hidden for the same reason ApplyBackground hides it: otherwise
    --- Transparent would show Blizzard's wood-grain map-frame backing on
    --- every map this addon has no replacement art for.
    local function Activate()
        Config.overlayActive = true
        local bg
        if useBundled then
            bg = ApplyBackground(background)
            -- ApplyBackground already chose BaseArt's visibility from the
            -- background: shown for Hybrid (which Fog of War requires),
            -- hidden for everything else. Don't second-guess it here.
        else
            if Config.backdropTexture then Config.backdropTexture:Hide() end
            BaseArt:SetVisible(false)
            MapFrameBg:SetVisible(not background.seeThrough)
        end
        if Config:IsMixing() then
            -- HD/SD blend: Blizzard's own map has to stay fully visible
            -- under the overlay (which draws at the slider's alpha, see
            -- the SetAlpha below), so none of the suppression above or
            -- below applies. Alpha b of HD over SD is exactly b*HD +
            -- (1-b)*SD, wherever the overlay is opaque.
            BaseArt:SetVisible(true)
            MapFrameBg:SetVisible(true)
            if fogActive and useBundled then
                -- Fog of War is reading these pins' textures; see ShowPins.
                Exploration:ShowPins()
            else
                Exploration:SetVisible(true)
            end
        elseif fogActive and useBundled then
            -- Fog of War's own tiles below are drawn FROM Blizzard's live
            -- exploration textures (Exploration:EnumerateOverlayTextures /
            -- DrawExploredPiece), so unlike the plain-suppression case,
            -- that data has to stay populated and enumerable rather than
            -- released -- HidePins only zeroes alpha on the originals,
            -- which has no bearing on the separate MaskTexture objects
            -- DrawExploredPiece points at the same underlying files.
            Exploration:HidePins()
        else
            -- No Fog of War reveal to build from here (feature off, or
            -- this map has no bundled art of ours to selectively show), so
            -- Blizzard's own reveal pins would only ever redundantly
            -- restate what this addon's own tiles (or their absence)
            -- already show -- suppressed the ordinary, full way.
            Exploration:SetVisible(false)
        end
        Watchdog:Start()
        return bg
    end

    if canvasW == 0 or canvasH == 0 then
        Activate()
        return
    end

    -- Activate overlay
    local bg = Activate()

    if trace then
        P(("  background=%s  baseArtVisible=%s"):format(
            bg and bg.key or "n/a", tostring(BaseArt.visible)))
    end

    local currentLevel = canvas:GetFrameLevel()
    Config.overlayFrame:SetFrameLevel(currentLevel + 500)
    -- Blizzard's exploration art (the explored, coloured part of the SD
    -- map) lives on pins at frame level ~2000, well above this overlay, so
    -- while mixing it would cover the HD map completely wherever the player
    -- has explored. Tuck those pins just under the overlay instead.
    Exploration:ApplyLevels()
    Config.overlayFrame:SetAlpha(Config:GetAlpha())

    -- Tile layout
    local scaleX = canvasW / layerW
    local scaleY = canvasH / layerH

    -- Fog of War: swap the ordinary unconditional grid for just the tiles
    -- (or slices of tiles) that fall under one of Blizzard's own, live
    -- exploration reveal textures. `fogActive` is deliberately the gate
    -- for which loop below runs, not a separate flag next to it, so every
    -- way this can end up unusable (feature off, or this map having no
    -- bundled art of ours to selectively show, or no explored data at all)
    -- falls back to the ordinary full grid rather than leaving the SD base
    -- art visible through the map.
    local fogPiecesDrawn = 0

    if fogActive then
        -- Shared between both passes below: DrawExploredPiece (live,
        -- organically-masked reveal textures) marks every cell it fills,
        -- and DrawFillPiece (the complete-but-unmasked
        -- C_MapExplorationInfo cross-check) only ever touches cells this
        -- left untouched -- see both functions' own doc comments for why
        -- neither pass alone is both complete and organically-edged.
        local filled = {}
        local pieceTex = {}

        -- Fully explored: the reveal textures are only created once the
        -- overlay is active (Activate above), after the enumeration that
        -- chose this path, so look again.
        if fullyExplored then
            blizExploredTextures = Exploration:EnumerateOverlayTextures()
        end

        local frameLeft = Config.overlayFrame:GetLeft()
        local frameTop  = Config.overlayFrame:GetTop()
        if trace then
            P(("  fog: %d live Blizzard texture(s) found  frameLeft=%s "
               .. "frameTop=%s"):format(
                #blizExploredTextures, tostring(frameLeft), tostring(frameTop)))
        end
        for _, blizTex in ipairs(blizExploredTextures) do
            fogPiecesDrawn = fogPiecesDrawn
                + DrawExploredPiece(
                    blizTex, frameLeft, frameTop,
                    layerW, layerH, tilePxW, tilePxH, cols, rows, tileSource,
                    scaleX, scaleY, gridX, gridY, filled, pieceTex, trace)
        end

        -- GetLeft/Top/Right/Bottom on a region only resolve once it has
        -- actually rendered at least one frame after being (re)shown or
        -- repositioned. The first time this addon lets Blizzard's own
        -- exploration provider populate on a given map (previously always
        -- pre-empted by RemoveAllData), its freshly (re)acquired chunk
        -- textures can still be mid-layout this same tick even though
        -- EnumerateOverlayTextures() just returned them. That shows
        -- up as real entries but zero usable geometry, not Fog of War's
        -- legitimate "nothing explored yet", so retry exactly once next
        -- frame rather than leaving the map blank until something else
        -- triggers another refresh.
        if fogPiecesDrawn == 0 and #blizExploredTextures > 0
            and not Config._fogRetryPending then
            if trace then P("  fog: 0 pieces from real entries -- retrying next frame") end
            Config._fogRetryPending = true
            C_Timer.After(0, function()
                Config._fogRetryPending = false
                if Config.overlayActive and fogOfWar then
                    Renderer:ForceRefresh()
                end
            end)
        end

        -- Separate issue: the very first Fog of War draw after a map opens
        -- (or its canvas swaps) could come out hard-edged and blocky, as
        -- if drawn with no mask, even with real pieces drawn and valid
        -- blizTex geometry. The cause is not blizTex's layout but this
        -- addon's own MaskTexture: SetTexture(maskFile, ...) on a freshly
        -- acquired mask points at the same file blizTex already displays,
        -- but as its own separate texture resource, which reads back
        -- fully opaque (no crop, i.e. "blocky") until that resource
        -- actually finishes loading, regardless of whether blizTex's own
        -- copy is already ready. Panning or zooming "fixed" this by
        -- accident, since both trigger a later Refresh past that load
        -- latency. This forces one more refresh, a beat (not just a
        -- frame) after the first, whenever Fog of War draws for the first
        -- time on a map that just (re)opened or swapped canvases.
        if isFreshMapOpen and not Config._fogStreamRetryPending then
            Config._fogStreamRetryPending = true
            C_Timer.After(0.2, function()
                Config._fogStreamRetryPending = false
                if Config.overlayActive and fogOfWar then
                    Renderer:ForceRefresh()
                end
            end)
        end

        -- Gap fill: C_MapExplorationInfo is the authoritative,
        -- always-complete source for "which ground is explored" (see
        -- DrawFillPiece's doc comment for why it's used as whole rects).
        -- filled already has every cell the pass above covered, so this
        -- only plugs what that pass could not reach.
        local explored = C_MapExplorationInfo
            and C_MapExplorationInfo.GetExploredMapTextures(mapID)
        if explored then
            local fillPieces = 0
            for _, rect in ipairs(explored) do
                fillPieces = fillPieces + DrawFillPiece(
                    rect.offsetX, rect.offsetY,
                    rect.textureWidth, rect.textureHeight,
                    blizzardLayerW, blizzardLayerH,
                    layerW, layerH, tilePxW, tilePxH, cols, rows, tileSource,
                    scaleX, scaleY, gridX, gridY, filled, pieceTex, trace)
            end
            fogPiecesDrawn = fogPiecesDrawn + fillPieces
            if trace then
                P(("  fog: gap-fill added %d piece(s) across %d rect(s)"):format(
                    fillPieces, #explored))
            end
        end

        -- Then: close whatever one-tile pinholes both passes above still
        -- left sitting inside otherwise-solid ground (see CloseFogGaps).
        fogPiecesDrawn = fogPiecesDrawn + CloseFogGaps(
            cols, rows, tileSource, filled, pieceTex, layerW, layerH,
            tilePxW, tilePxH, scaleX, scaleY, gridX, gridY, trace)

        -- SoftenFogEdges is deliberately NOT called here. Blizzard's own
        -- client (MapExplorationPinMixin:RefreshOverlays) draws these
        -- hard-edged with no gradient, and fading the boundary live just
        -- turned a correctly-shaped area blurry, a worse match for
        -- Blizzard's look. The irregular look this addon wants comes from
        -- the SHAPE of the explored-chunk data itself, not a per-edge
        -- fade; there's no post-processing trick that turns a hard
        -- rectangle into an organic outline. Left in place, unused, in
        -- case a future data source calls for it.
        -- SoftenFogEdges(cols, rows, filled, pieceTex, trace)
    elseif worldFogZones then
        -- World/Continent Fog of War: this addon's tiles only over the
        -- zones the player has fully explored (ZoneFog.lua), each cropped
        -- to its own outline by a mask baked from the game's zone borders.
        for _, shape in ipairs(worldFogZones) do
            local x0, y0 = shape[2] * layerW, shape[3] * layerH
            local x1, y1 = shape[4] * layerW, shape[5] * layerH
            local mask = MaskPool:Acquire()
            mask:ClearAllPoints()
            mask:SetPoint("TOPLEFT", Config.overlayFrame, "TOPLEFT",
                x0 * scaleX, -y0 * scaleY)
            mask:SetSize((x1 - x0) * scaleX, (y1 - y0) * scaleY)
            mask:SetTexture(Config.MASK_BASE .. "z" .. shape[1], "CLAMP", "CLAMP")
            DrawLayerRect(x0, y0, x1, y1, layerW, layerH, tilePxW, tilePxH,
                cols, rows, tileSource, scaleX, scaleY, mask)
        end
        -- A mask file read for the first time is opaque until it finishes
        -- loading (same as Fog of War's masks), so draw once more shortly
        -- after the first draw of a map.
        if isFreshMapOpen and not Config._zoneMaskRetryPending then
            Config._zoneMaskRetryPending = true
            C_Timer.After(0.2, function()
                Config._zoneMaskRetryPending = false
                if Config.overlayActive then Renderer:ForceRefresh() end
            end)
        end
    elseif clientZone then
        -- An underground capital: its baked canvas, cut to the box of it this
        -- map shows. clientZone.submap is that box in canvas pixels.
        local submap = clientZone.submap
        local comp = submap and Config:GetCaveComposite(submap.fdid)
        if comp then
            local kx = layerW * scaleX / (submap.x1 - submap.x0)
            local ky = layerH * scaleY / (submap.y1 - submap.y0)
            Config:DrawComposite(comp, Config.overlayFrame, kx, ky,
                -submap.x0 * kx, -submap.y0 * ky,
                function(sub)
                    local tex = Pool:Acquire()
                    if sub then tex:SetDrawLayer("ARTWORK", sub - 8) end
                    return tex
                end,
                { submap.x0, submap.y0, submap.x1, submap.y1 })
        end
        -- Experiment: every other zone's tiles are the client's own minimap
        -- files, placed in art-layer pixels (see MinimapTiles.lua). Tiles that
        -- overhang the layer are clipped with SetTexCoord.
        for _, reg in ipairs(clientZone.regions) do
            local f, tw, th = reg.f, reg.tw, reg.th
            local i = 0
            for row = 0, reg.rows - 1 do
                local y0 = reg.oy + row * th
                local cy0, cy1 = math.max(y0, 0), math.min(y0 + th, layerH)
                for col = 0, reg.cols - 1 do
                    i = i + 1
                    local x0 = reg.ox + col * tw
                    local cx0, cx1 = math.max(x0, 0), math.min(x0 + tw, layerW)
                    if f[i] ~= 0 and cx1 > cx0 and cy1 > cy0 then
                        local tex = Pool:Acquire()
                        tex:SetSize((cx1 - cx0) * scaleX, (cy1 - cy0) * scaleY)
                        tex:SetPoint("TOPLEFT", Config.overlayFrame, "TOPLEFT",
                            cx0 * scaleX, -cy0 * scaleY)
                        tex:SetTexCoord((cx0 - x0) / tw, (cx1 - x0) / tw,
                            (cy0 - y0) / th, (cy1 - y0) / th)
                        tex:SetTexture(f[i])
                    end
                end
            end
        end
    else
        local tileIdx = 1
        for row = 0, rows - 1 do
            for col = 0, cols - 1 do
                local src = tileSource[tileIdx]
                if not src then break end

                local artTileW = math.min(tilePxW, layerW - col * tilePxW)
                local artTileH = math.min(tilePxH, layerH - row * tilePxH)

                local cellW = artTileW * scaleX
                local cellH = artTileH * scaleY
                local cellX = col * tilePxW * scaleX
                local cellY = row * tilePxH * scaleY

                local texRight  = artTileW / tilePxW
                local texBottom = artTileH / tilePxH

                local tex = Pool:Acquire()
                tex:SetSize(cellW, cellH)
                tex:SetPoint(
                    "TOPLEFT", Config.overlayFrame, "TOPLEFT", cellX, -cellY)
                tex:SetTexCoord(0, texRight, 0, texBottom)
                tex:SetTexture(src)
                tileIdx = tileIdx + 1
            end
        end
    end

    -- Fog of War genuinely can mean zero tiles here: a map the player has
    -- not explored yet, or one with no live reveal textures to read this
    -- particular refresh. That's not the failure this check is meant to
    -- catch, since fogActive being true already means this is Fog of
    -- War's own intentionally-partial grid, not a lookup that came back
    -- empty by mistake, so there is nothing to fall back from.
    if Pool:ActiveCount() == 0 and not fogActive and not worldFogZones then
        P("No textures for mapID " .. mapID .. ", restoring default map art")
        RestoreDefaults()
    end
end

-- Set for the duration of DoRefresh, cleared no matter how it exits (the
-- pcall below is what makes that unconditional -- a bare `return` deep
-- inside DoRefresh would otherwise skip a plain post-call reset).
local refreshing = false

--- Main overlay refresh.
---
--- Guards DoRefresh against being re-entered while it is already running.
--- Not theoretical: DoRefresh's Fog of War section used to call
--- WorldMapFrame:RefreshAllDataProviders (via
--- Exploration:EnumerateOverlayTextures), which on this client can
--- synchronously fire MAP_EXPLORATION_UPDATED, whose handler (Core.lua)
--- called this same Refresh again before the outer call returned. Letting
--- that inner call proceed used to run Pool:ReleaseAll()/
--- MaskPool:ReleaseAll() out from under the outer call's in-progress
--- drawing, discarding some pieces and orphaning others: tiles went
--- silently missing at seemingly regular intervals even though each
--- piece's own math was correct, because the pool bookkeeping one call
--- relied on had been swept out from under it by the other. The inner
--- call is redundant anyway: the outer call is about to finish drawing
--- the current state fresh regardless.
---@param force boolean|nil
function Renderer:Refresh(force)
    if refreshing then
        -- Dropped, not just ignored: the outer call is about to draw the
        -- current state fresh regardless, but schedule a debounced
        -- follow-up anyway in case this call raced ahead of that; cheap
        -- insurance against dropping a real update instead of only the
        -- redundant ones this guard exists for.
        self:ScheduleRefresh()
        return
    end
    refreshing = true
    local ok, err = pcall(DoRefresh, force)
    refreshing = false
    if not ok then
        error(err, 0)
    end
end

--- Debounced refresh for OnSizeChanged thrashing.
function Renderer:ScheduleRefresh()
    if Config.refreshPending then return end
    Config.refreshPending = true
    C_Timer.After(0.05, function()
        Config.refreshPending = false
        self:Refresh()
    end)
end

--- Force a full refresh (clears all cached state).
function Renderer:ForceRefresh()
    Config.lastCanvas    = nil
    Config.lastMapID     = nil
    Config.lastCanvasW   = 0
    Config.lastCanvasH   = 0
    Config.lastLayerIdx  = nil
    Config.lastSubmerged = nil
    Config.refreshPending = false
    self:Refresh(true)
    -- Fog of War and the backgrounds decide which labels show; see AreaLabels.
    ns.AreaLabels:Refresh()
end

-- Offscreen-ish 1px holder for Renderer:Preload; built on first use, reused.
local preloadFrame
local preloadTiles, preloadMasks = {}, {}
local retried = false

--- Warm the client's texture cache for the zone the player is standing in,
--- so the first world-map open doesn't stream the tiles (and Fog of War
--- mask files, which read opaque -- "blocky" -- until loaded) on demand.
--- A texture only loads once something actually draws it, and the client
--- frees one nothing references, so each file sits on a 1x1 near-invisible
--- texture in a corner for as long as it stays the player's zone (the next
--- Preload, on a zone change, repoints them). Covers that zone only.
--- ponytail: drawn-pixel trick, swap for a preload API if the client gains one.
function Renderer:Preload()
    if not (Config.db and Config.db.enabled) then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then
        -- Not resolved yet right at the loading screen's end; try once more.
        if not retried then C_Timer.After(1, function() retried = true; Renderer:Preload() end) end
        return
    end

    local tiles, masks = {}, {}
    local clientZone = Config:GetClientZone(mapID)
    if clientZone then
        for _, reg in ipairs(clientZone.regions) do
            for _, fdid in ipairs(reg.f) do
                if fdid ~= 0 then tiles[#tiles + 1] = fdid end
            end
        end
    else
        local zone = Config:GetNativeZone(mapID, Config:GetBackgroundForMap(mapID))
        if zone then
            for i = 1, zone.cols * zone.rows do
                tiles[i] = Config.HD_BASE .. zone.path .. i
            end
        end
    end
    if Config:FogOfWarEnabled() then
        local explored = C_MapExplorationInfo.GetExploredMapTextures(mapID)
        for _, rect in ipairs(explored or {}) do
            for _, fdid in ipairs(rect.fileDataIDs or {}) do
                masks[#masks + 1] = fdid
            end
        end
    end
    if #tiles == 0 and #masks == 0 then return end

    if not preloadFrame then
        preloadFrame = CreateFrame("Frame", nil, UIParent)
        preloadFrame:SetSize(1, 1)
        preloadFrame:SetPoint("BOTTOMLEFT")
        preloadFrame:SetFrameStrata("BACKGROUND")
        preloadFrame:SetAlpha(0.05)
    end

    for i, src in ipairs(tiles) do
        local tex = preloadTiles[i]
        if not tex then
            tex = preloadFrame:CreateTexture(nil, "BACKGROUND")
            tex:SetSize(1, 1)
            tex:SetPoint("BOTTOMLEFT")
            preloadTiles[i] = tex
        end
        tex:SetTexture(src)
        tex:Show()
    end
    for i = #tiles + 1, #preloadTiles do preloadTiles[i]:Hide() end

    -- A mask only loads while applied to a drawn texture, and has to be
    -- set up like the real ones (CLAMP) to be the same resource.
    for i, fdid in ipairs(masks) do
        local m = preloadMasks[i]
        if not m then
            m = { tex = preloadFrame:CreateTexture(nil, "BACKGROUND"),
                  mask = preloadFrame:CreateMaskTexture() }
            m.tex:SetSize(1, 1)
            m.tex:SetPoint("BOTTOMLEFT")
            m.tex:SetColorTexture(1, 1, 1, 1)
            m.mask:SetAllPoints(m.tex)
            m.tex:AddMaskTexture(m.mask)
            preloadMasks[i] = m
        end
        m.mask:SetTexture(fdid, "CLAMP", "CLAMP")
        m.tex:Show()
    end
    for i = #masks + 1, #preloadMasks do preloadMasks[i].tex:Hide() end

    preloadFrame:Show()
    if Config.tracing then
        P(("preload: map %d, %d tile(s), %d mask(s)"):format(
            mapID, #tiles, #masks))
    end
end
