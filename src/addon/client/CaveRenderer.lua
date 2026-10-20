-------------------------------------------------------------------------------
-- HFWM-Forever CaveRenderer
--
-- The cave map: a small window that floats over the world map and draws the
-- art for the cave, micro dungeon, or indoor area the player is actually
-- standing in, since the world map itself has nothing to show for the hole
-- you walked into.
--
-- It is a *window*, not a full-canvas overlay:
--
--   * Parented to WorldMapFrame rather than to the scroll container's child,
--     so it doesn't pan or zoom with the map underneath it (a cave map that
--     slid off screen when you dragged the zone would be useless), and it
--     hides and shows with the map for free.
--   * Built on AceGUI-3.0's own "Frame" dialog widget: the standard Ace3
--     ornate-border popup every other Ace3 addon's options/dialog windows
--     use, rather than a bespoke clone of the world map's own chrome. Its
--     title bar carries the area name, its status bar the floor readout,
--     and its own close button is hidden in favour of this window's X (see
--     EnsureWindow), so a close stays a statement about *this* cave the
--     same way it always has.
--   * Sized from the cave art's own aspect ratio, clamped to leave the
--     world map visible around it. A cave stretched to the shape of the
--     canvas is unreadable.
--   * Pinned by default, but draggable: its own bottom-left corner is
--     anchored to the world map's bottom-right (see PositionWindow), but the
--     window can still be moved anywhere on screen to suit the player's
--     preference.
--   * The art inside the window can also be zoomed and panned in its own
--     right: mouse wheel over the content area zooms toward the cursor,
--     left-drag over it pans, independently of the window's own position
--     and of whatever the world map underneath is doing. See the "Zoom &
--     pan" section below.
--
-- Multi-level caves get a vertical depth slider down the left-hand side,
-- one notch per floor, top floor at the top. It's hand-built rather than
-- borrowed from FrameXML: the stock slider templates are horizontal only
-- and have no notion of discrete stops, and "between two floors" is a
-- meaningless value for a dungeon depth to drag to.
-------------------------------------------------------------------------------
local addonName, ns = ...
local CaveRenderer = ns.CaveRenderer
local Config       = ns.Config
local P            = ns.P
local ResetView    = ns.ResetView
local IsShiftKeyDown = _G.IsShiftKeyDown
local AceGUI       = LibStub("AceGUI-3.0")

-------------------------------------------------------------------------------
-- Geometry
-------------------------------------------------------------------------------
--- AceGUI-3.0's "Frame" container widget (see EnsureWindow) reserves a
--- fixed amount of its own chrome -- title bar, status bar, border --
--- around the content region it hands back via `.content`. Mirrored here
--- from AceGUIContainer-Frame.lua's own Constructor, so LayoutWindow can go
--- the other way: given how big the cave art itself needs to be, how big
--- to make the whole dialog frame to get exactly that much content area
--- back. These are the anchor offsets on `.content` itself (TOPLEFT 17,-27
--- / BOTTOMRIGHT -17,40: 17+17 wide, 27+40 tall), not the OnWidthSet/
--- OnHeightSet functions next to them in that file -- `.content` is
--- anchored on *both* opposing edges on each axis, so those two functions'
--- own SetWidth/SetHeight calls are no-ops (a frame with two points fully
--- determining a dimension ignores explicit sizing on that axis) and their
--- "34"/"57" are stale relative to the anchors that actually govern it.
--- Getting the height wrong here previously undersized the whole dialog by
--- 10px, so the cave art's own `content` (sized outright to the height
--- this computes) overflowed 10px past the bottom of the real content
--- area and covered the status bar's "Level X of Y" text.
---
--- The bottom inset is no longer a single fixed number, though: LayoutWindow
--- re-anchors `.content`'s own BOTTOMRIGHT point every call (overriding the
--- library's fixed 40 there) to whichever of the two below actually applies,
--- so the window shrinks by the difference when the status pane has nothing
--- to show (see ShowCave's "All floors" case) instead of leaving a dead gap
--- where it would have been.
local ACE_FRAME_WIDTH_OVERHEAD  = 34
local ACE_FRAME_TOP_INSET       = 27  -- library's own `.content` TOPLEFT y
local ACE_FRAME_BOTTOM_INSET_STATUS    = 40  -- library's own inset: room for the status pane
local ACE_FRAME_BOTTOM_INSET_NO_STATUS = 20  -- tighter: no pane to leave room for
--- How far clear of the world map's own right edge the cave window's
--- pinned corner sits; see PositionWindow.
local PIN_GAP = 6
local SLIDER_COL_W = 30   -- depth slider gutter, only when there are floors
local SLIDER_W     = 16   -- the track itself: a stock scroll bar's width
-- The thumb never reaches the very ends of a vertical Slider's track (half
-- its height is always inside it), so anything else meant to track a
-- fraction of the track (the height-window rectangle) has to live inside the
-- same inset range, or it won't agree with where the thumb itself can land.
local SLIDER_INSET = 12
-- cave-satellite-v2 Phase 2's height-window rectangle: height of each drag
-- handle, which sits inside the window's top/bottom edge. Purely cosmetic
-- grab room, not part of the elevation math.
local HEIGHT_WINDOW_HANDLE_H = 8
-- Fixed cosmetic smoothing for a piece just outside the height window: fades
-- to invisible over this many yards rather than popping, same as the old
-- fixed per-piece margin. Not user-adjustable; the window rectangle itself
-- is the adjustable control now.
local EDGE_FADE_YARDS = 2
-- Fraction of the map frame the content is allowed to eat. A cave map that
-- covers the zone it is a hole in defeats the point of being a window, so
-- this is what governs that: the window grows and shrinks with the map, so
-- it looks the same whether the map is windowed or maximised on a 4K
-- display.
local MAP_FRACTION_W = 0.46
local MAP_FRACTION_H = 0.58

-- Floor and ceiling on top of that fraction. The floor is legibility: below
-- about 200px a cave's corridors are a smudge. The ceiling covers the case
-- the fraction can't reason about, a map stretched across an ultrawide,
-- where 46% is still more window than anyone wants, so it's set well clear
-- of ordinary resolutions instead of at a size that would quietly override
-- MAP_FRACTION on every normal one. At 460 it did exactly that: a 1024-wide
-- map already wants 471, so every map from a default-sized one upwards got
-- the identical window and maximising did nothing.
local MIN_CONTENT  = 200
local MAX_CONTENT  = 640

-- Zoom range for the content area's own picture (see the "Zoom & pan"
-- section below). FIT_ZOOM is exactly the fit LayoutWindow already computes:
-- the whole cave visible and nothing cropped. MIN_ZOOM sits below that so
-- the user can zoom out for the bigger picture even when the cave already
-- fills the canvas; at those scales the canvas is smaller than the viewport
-- and ClampPan just holds it centered, so there is no backdrop to reveal
-- and no pan to lose. MAX_ZOOM is capped well short of the point where the
-- base layer's own tile resolution would stretch into an obvious blurry
-- blob, since this magnifies the art already drawn rather than fetching a
-- sharper source layer (see ArtLayer below).
local FIT_ZOOM  = 1
local MIN_ZOOM  = 0.25
local MAX_ZOOM  = 4
-- Multiplicative step per wheel notch, so a handful of notches carries the
-- user from MIN_ZOOM to MAX_ZOOM at a comfortable rate rather than a single
-- jarring jump or a fifty-notch crawl.
local ZOOM_STEP = 1.25
-- How far the cursor has to move, in content-local pixels, before ZoomBy
-- treats it as "moved" and re-samples a new zoom anchor instead of reusing
-- the one from the last notch (see the module comment above zoomAnchorX).
-- Comfortably above the sub-pixel jitter GetCursorPosition can report while
-- the physical mouse hasn't moved at all, comfortably below any deliberate
-- mouse movement.
local ZOOM_ANCHOR_EPSILON = 1.5

local PIN_TEXTURE = "Interface\\Minimap\\MinimapArrow"
local PIN_SIZE    = 26

-- The world map's own corpse pin (CorpsePinTemplate): POIIcons' tombstone.
local CORPSE_TEXTURE   = "Interface\\Minimap\\POIIcons"
local CORPSE_TEXCOORDS = { 0.56640625, 0.6328125, 0.001953125, 0.03515625 }
local CORPSE_PIN_SIZE  = 24

local PIN_UPDATE_INTERVAL = 0.05  -- 20fps is plenty for a map pin

-- Other group members: a class-coloured dot, like the world map's, ringed in
-- black. Each circle is a white square under the stock round portrait mask;
-- the ring is a slightly bigger black one behind it.
local GROUP_PIN_SIZE   = 7
local GROUP_PIN_BORDER = 1  -- px of black showing past the fill, each side
local GROUP_PIN_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local GROUP_PIN_FALLBACK = { r = 0.62, g = 0.62, b = 0.62 }

-- Floor picker (dropdown); see the "Floor picker" section below. Passed to
-- UIDropDownMenu_SetWidth, which sizes the *visible* text/button area; the
-- template's own frame ends up wider than this (see EnsureFloorPicker's
-- -40 note).
local FLOOR_PICKER_W = 120

--- Blizzard's own colour for a Battle.net-linked friend's name (Friends
--- List, whispers), the closest thing the client already defines to an
--- official "Blizzard cyan". Reused here for the "All" entry's text rather
--- than a colour this addon picked itself. Falls back to the literal hex on
--- a client build that doesn't expose the constant as a global.
local BLIZZARD_CYAN_HEX = FRIENDS_BNET_NAME_COLOR_CODE or "|cff82c5ff"

-------------------------------------------------------------------------------
-- Widget handles, all created lazily on first show
-------------------------------------------------------------------------------
local aceWindow     -- the AceGUI-3.0 Frame widget itself
local window        -- aceWindow.frame: the actual frame, pinned in place
local closeBtn      -- the x, in the top-right corner (Ace's own "Close"
                    -- button is hidden; see EnsureWindow)
local content       -- clipping frame the tiles and the pin live in
local canvasScale   -- child of content: zoomed/panned, holds tiles + pin
local playerPin
local corpsePin
local groupPins = {}  -- class-coloured dots for the rest of the group, grown on demand; each fill has its ring at .border
local function HideGroupPins(from)
    for i = from, #groupPins do
        groupPins[i]:Hide()
        groupPins[i].border:Hide()
    end
end
local sliderCol     -- gutter frame, hidden on single-floor caves
local sliderTrack   -- the trough (a Slider, for real drag behaviour)
local statusbg      -- aceWindow.statustext's own parent frame (the pane
                    -- behind it); hidden along with the text itself when
                    -- "All" floors is selected (see ShowCave) since there's
                    -- no single current level left to report.

-- Zoom/pan runtime state (see the "Zoom & pan" section below, just above
-- EnsureWindow). `zoomScale` and `panX`/`panY` describe canvasScale's
-- current transform and deliberately persist across floor switches and
-- window relayouts within the same cave: both funnel through ShowCave, and
-- resetting these on every call would throw away the user's zoom the
-- instant they touched the depth slider or resized the map. HideCave
-- resets them, so a freshly opened cave (this one again, or a different one
-- entirely) always starts at fit-to-window.
--
-- `contentDrag`, when non-nil, is `{ startX, startY, startPanX, startPanY }`
-- for a pan drag in progress, the same hand-polled pattern as
-- `heightWindowDrag` below (OnMouseDown to start, OnUpdate plus a live
-- IsMouseButtonDown check to follow and to notice release).
local zoomScale    = FIT_ZOOM
local panX, panY   = 0, 0
local contentDrag

-- `zoomAnchorX`/`zoomAnchorY`: the canvas-local point (see ContentCursorXY
-- for the coordinate convention) that ZoomBy is currently zooming toward
-- centering. Set from wherever the cursor is the first time it's needed,
-- then deliberately *not* recomputed on every notch: see ZoomBy's own
-- comment for why re-sampling "what's under the cursor" fresh each notch,
-- while the cursor sits still and the picture moves underneath it, is
-- exactly what made a stationary scroll drift onto a different part of
-- the map. `zoomAnchorCursorX`/`zoomAnchorCursorY` are the cursor position
-- the anchor was last sampled at, purely so the next notch can tell
-- whether the cursor has actually moved since. All four go back to nil
-- whenever the anchor would no longer mean anything (the content area
-- being resized by LayoutWindow, or the cave window closing via HideCave),
-- so the next notch always samples fresh rather than centering a point
-- left over from a different layout.
local zoomAnchorX, zoomAnchorY
local zoomAnchorCursorX, zoomAnchorCursorY

-- Floor picker (dropdown), top-left of the content frame; see the "Floor
-- picker" section below. A real UIDropDownMenuTemplate frame, built lazily;
-- `floorPickerUnavailable` is set once and for all if that template turns
-- out not to exist on this client, so EnsureFloorPicker stops retrying.

-- cave-satellite-v2 Phase 2's height-window rectangle: a draggable/resizable
-- overlay on the depth slider itself (see EnsureHeightWindow), replacing a
-- single slider point with a range the user can both move and resize.
-- `windowBody` is the whole rectangle (drag to move); `windowTopHandle`/
-- `windowBottomHandle` are grab strips at its edges (drag to resize).
-- `heightWindowDrag`, when non-nil, is `{ kind = "top"|"bottom"|"body",
-- startFrac, startTop, startBottom }` for whichever of the three is
-- currently being dragged.
local windowBody
local windowTopHandle, windowBottomHandle
local windowCapTop, windowCapBottom   -- the rectangle's knob end caps
local heightWindowDrag

-- Reopen icon: shown in place of the window when Cave.lua has a cave to
-- display but the window is closed (the player clicked the close button, or
-- it hasn't been opened yet this visit). See EnsureReopenButton and
-- CaveRenderer:SetReopenAvailable below.
local reopenBtn

-- Cave-only chrome copied from GameMenuFrame's templates (see ApplyGameMenuChrome).
local caveBorder, caveHeader

-- Content dimensions from the last layout pass. Kept rather than read back
-- with GetHeight(): a frame sized purely by its anchors does not always have
-- a resolved height in the same frame it was anchored, and the height
-- window has to line up with the slider thumb exactly or the widget looks
-- broken.
local contentW, contentH = 0, 0

-------------------------------------------------------------------------------
-- Inline texture pool (owned by the content frame)
--
-- Separate from the main HFWM Pool on purpose: those textures belong to the
-- world-map canvas and are released wholesale on every zone change, which is
-- exactly the wrong lifecycle for a window that outlives the map underneath
-- it changing.
-------------------------------------------------------------------------------
local cavePool        = {}
local activeCaveTiles = {}

-- Continuous-depth crossfade state (see the "Depth slider" section below for
-- the alpha math). `continuousActive` is true only while the currently
-- shown place has ns.Cave:HasContinuousDepth() for its floors (currently
-- just Fargodeep Mine) *and* has more than one floor; every other cave keeps
-- the original hard-swap behaviour. `continuousTileGroups` holds every
-- floor's tiles simultaneously in that mode (index i is floor i of
-- Config.caveAllFloors), so their alpha can be pushed independently as the
-- slider moves, rather than the single floor's worth `activeCaveTiles` holds
-- the rest of the time.
local continuousActive     = false
local continuousTileGroups = {}

-- cave-satellite-v2 Phase 2: per-piece continuous fade state. `piecesActive`
-- is true only while the currently shown place has ns.Cave:GetPieces() for
-- its floors (currently just Fargodeep Mine), a finer-grained replacement
-- for `continuousActive`'s whole-floor crossfade, not an addition to it, so
-- the two are mutually exclusive (see ShowCave). `continuousPieceGroups`
-- holds every piece's texture and its own {zMin, zMax} simultaneously, so
-- each can fade independently by real elevation as the slider moves.
-- `piecesZMin`/`piecesZMax` are the aggregate real-world-Z range spanned by
-- every piece currently rendered (not any one floor's own zMin/zMax), which
-- is what lets a 2-notch floor slider sweep continuously through every
-- piece's height in between rather than just the two floor labels the
-- notches are drawn at; see ElevationForValue.
local piecesActive         = false
local continuousPieceGroups = {}
local piecesZMin, piecesZMax

-- Snapshot of the most recent RenderTiles call, for /hfwm debug. Not used
-- for rendering itself, purely so Commands.lua can report, per tile,
-- whether the FDID_MAP lookup hit (real baked art) or fell through to a
-- raw client FDID, without recomputing any of RenderTiles's own state. In
-- continuous mode RenderTiles runs once per floor, so this ends up holding
-- whichever floor rendered last (the deepest); Commands.lua reports
-- per-floor alpha separately via CaveRenderer:DebugContinuous().
local lastRenderInfo = nil

--- `group`, when given, also collects the acquired texture so its caller can
--- drive its alpha independently later (the continuous crossfade path).
local function PoolAcquire(group)
    local tex = tremove(cavePool)
    if not tex then
        -- On canvasScale, not `content` directly: see the "Zoom & pan"
        -- section below EnsureReopenButton. This is what makes the tile
        -- grid zoom and pan instead of sitting fixed in the viewport.
        tex = canvasScale:CreateTexture(nil, "ARTWORK", nil, 3)
    end
    tex:SetVertexColor(1, 1, 1, 1)
    tex:Show()
    activeCaveTiles[#activeCaveTiles + 1] = tex
    if group then group[#group + 1] = tex end
    return tex
end

local function PoolReleaseAll()
    for i = #activeCaveTiles, 1, -1 do
        local tex = activeCaveTiles[i]
        tex:Hide()
        tex:ClearAllPoints()
        -- Reset to the default sublevel so a tile last used in a continuous
        -- fade (see RenderContinuousFloors) doesn't carry that draw order
        -- into whatever reuses it next.
        tex:SetDrawLayer("ARTWORK", 3)
        activeCaveTiles[i] = nil
        cavePool[#cavePool + 1] = tex
    end
    for i = #continuousTileGroups, 1, -1 do
        continuousTileGroups[i] = nil
    end
    for i = #continuousPieceGroups, 1, -1 do
        continuousPieceGroups[i] = nil
    end
end

--- Config:DrawComposite, onto the cave canvas and its texture pool.
---@param sublevel number|nil
---@param group table|nil  also collects the textures, as PoolAcquire does
---@return table textures  everything drawn, in paint order
local function DrawComposite(comp, scaleX, scaleY, offX, offY, sublevel, group)
    return Config:DrawComposite(comp, canvasScale, scaleX, scaleY, offX, offY,
        function()
            local tex = PoolAcquire(group)
            tex:SetDrawLayer("ARTWORK", sublevel or 3)
            return tex
        end)
end

-------------------------------------------------------------------------------
-- Small widget helpers
-------------------------------------------------------------------------------

local ACE_HEADER_FDID = 131080  -- Interface\DialogFrame\UI-DialogBox-Header, as AceGUI-3.0 sets it
local DIALOG_FILL = "Interface\\DialogFrame\\UI-DialogBox-Background"  -- DialogBorderTemplate's Bg

local dialogFill   -- the dialog's tiled background, behind the art too

--- The dialog background, as DialogBorderTemplate's Bg lays it out (7px
--- inside the window). Spans the whole window, so the transparent canvas
--- shows it. Fades with the cave opacity setting, so at 0% only the
--- border and map elements remain.
local function LayoutDialogFill()
    if not window then return end
    if not dialogFill then
        dialogFill = window:CreateTexture(nil, "BACKGROUND", nil, -8)
        dialogFill:SetTexture(DIALOG_FILL, "REPEAT", "REPEAT")
        dialogFill:SetHorizTile(true)
        dialogFill:SetVertTile(true)
        dialogFill:SetPoint("TOPLEFT", 7, -7)
        dialogFill:SetPoint("BOTTOMRIGHT", -7, 7)
    end
    dialogFill:SetAlpha(Config:CaveAlpha())
end

--- Give the cave window the same chrome as Forever's own GameMenuFrame:
--- the NineSlice "Dialog" layout (DiamondMetal atlases) behind
--- GameMenuFrame.Border, and DialogHeaderTemplate's header plate. AceGUI's
--- Frame ships the retail DialogBox border, header art and backdrop
--- instead, so those are stripped; its layout (content insets, title and
--- status bar) is left alone.
local function ApplyGameMenuChrome()
    if not window then return end

    if not caveBorder then
        window:SetBackdrop(nil)
        -- AceGUI's header plate is three DialogBox-Header textures; only
        -- the middle one is exposed on the widget.
        for _, region in ipairs({ window:GetRegions() }) do
            if region:GetObjectType() == "Texture" and region:GetTexture() == ACE_HEADER_FDID then
                region:Hide()
            end
        end
        caveBorder = CreateFrame("Frame", nil, window, "DialogBorderNoCenterTemplate")
        caveBorder:SetAllPoints(window)
        caveHeader = CreateFrame("Frame", nil, window, "DialogHeaderTemplate")
        caveHeader.Text:Hide()  -- the Ace title text below is drawn instead
    end

    LayoutDialogFill()

    local title = aceWindow.titletext
    title:SetFontObject("GameFontNormalMed1")  -- GameMenuFrame's dialogHeaderFont
    caveHeader:SetWidth(title:GetStringWidth() + caveHeader.headerTextPadding)
    title:ClearAllPoints()
    title:SetPoint("TOP", caveHeader, "TOP", 0, -13)
    title:SetAlpha(1)
    title:Show()
    -- The title lives on a child frame of the window; keep that frame
    -- above the cave art and chrome so nothing paints over it.
    local titleFrame = title:GetParent()
    if titleFrame and titleFrame ~= window then
        titleFrame:SetFrameLevel(window:GetFrameLevel() + 50)
    end
end

--- What the title FontString is actually doing, for /hfwm cavetitle.
function CaveRenderer:DebugTitle()
    local t = aceWindow and aceWindow.titletext
    if not t then return nil end
    local p, relTo, rp, x, y = t:GetPoint(1)
    local f1, f2, f3 = t:GetFont()
    local r, g, b, a = t:GetTextColor()
    local parent = t:GetParent()
    return {
        text = t:GetText(), shown = t:IsShown(), visible = t:IsVisible(),
        alpha = t:GetAlpha(), effAlpha = t:GetEffectiveAlpha(),
        font = f1, size = f2, flags = f3, color = { r, g, b, a },
        point = { p, relTo and (relTo.GetName and relTo:GetName() or relTo:GetObjectType()), rp, x, y },
        rect = { t:GetLeft(), t:GetBottom(), t:GetWidth(), t:GetHeight() },
        windowRect = window and { window:GetLeft(), window:GetBottom(), window:GetWidth(), window:GetHeight() },
        levels = { parent and parent:GetFrameLevel(), window and window:GetFrameLevel() },
        header = caveHeader and { shown = caveHeader:IsShown(), w = caveHeader:GetWidth(), h = caveHeader:GetHeight() },
    }
end

--- Zoom/pan state and where content sits in the frame stack, for
--- /hfwm cavefocus.
function CaveRenderer:DebugPan()
    if not content then return nil end
    return {
        zoom = zoomScale, panX = panX, panY = panY,
        contentW = contentW, contentH = contentH,
        dragging = contentDrag ~= nil,
        mouse = content:IsMouseEnabled(), wheel = content:IsMouseWheelEnabled(),
        hasDown = content:GetScript("OnMouseDown") ~= nil,
        hasUpdate = content:GetScript("OnUpdate") ~= nil,
        level = content:GetFrameLevel(), strata = content:GetFrameStrata(),
        windowLevel = window and window:GetFrameLevel(),
        shown = content:IsShown(), visible = content:IsVisible(),
    }
end

--- CreateFrame against the first template that actually exists. Same reason
--- as in Options.lua: CreateFrame *errors* on an unknown template rather than
--- returning nil, and which FrameXML templates this beta client ships is not
--- something the addon can ask about.
local function CreateFrameTry(kind, name, parent, ...)
    for i = 1, select("#", ...) do
        local ok, frame = pcall(CreateFrame, kind, name, parent, (select(i, ...)))
        if ok and frame then return frame end
    end
    return CreateFrame(kind, name, parent)
end

-------------------------------------------------------------------------------
-- Floor helpers
-------------------------------------------------------------------------------

--- Index into Config.caveAllFloors of a given mapID.
local function FloorIndex(mapID)
    local floors = Config.caveAllFloors
    if not floors then return nil end
    for i, f in ipairs(floors) do
        if f.mapID == mapID then return i end
    end
    return nil
end

local function FloorCount()
    return Config.caveAllFloors and #Config.caveAllFloors or 0
end

--- Whether the status bar has anything worth showing: "All" (see
--- InitFloorPickerMenu) layers every floor together, so there's no single
--- current level left to report once it's selected. Shared by LayoutWindow
--- (which shrinks the window's own bottom inset to match) and ShowCave
--- (which hides the status pane itself) so the two can never disagree
--- about which state the window is in.
local function StatusBarNeeded()
    return not (FloorCount() > 1 and Config.caveFloorFilterAll)
end

--- Step the active floor by `delta` indices, clamped. Index 1 is the topmost
--- floor, so a positive delta goes *down* into the cave.
local function StepFloor(delta)
    local n = FloorCount()
    if n <= 1 then return end
    local idx = FloorIndex(Config.caveCurrentFloorMapID) or 1
    local want = math.max(1, math.min(n, idx + delta))
    if want == idx then return end
    CaveRenderer:SelectFloor(Config.caveAllFloors[want].mapID)
end

-------------------------------------------------------------------------------
-- Depth slider
--
-- Slider value is the *notch number counted from the bottom*, so that the
-- deepest floor sits at the bottom of the track and the surface at the top,
-- which is the way a vertical WoW slider runs and also the way a cave does.
-- Floor indices run the other way (1 = topmost), hence the two conversions.
-------------------------------------------------------------------------------

local function ValueToIndex(value)
    return FloorCount() - math.floor(value + 0.5) + 1
end

local function IndexToValue(index)
    return FloorCount() - index + 1
end

--- Like ValueToIndex, but without the rounding: "floor 2.3" for a value
--- three-tenths of the way from floor 2 towards floor 3. This is what the
--- continuous crossfade drags along; ValueToIndex's rounding is exactly the
--- snap-to-nearest-floor behaviour a hard-swap cave wants instead.
local function ValueToFractionalIndex(value)
    return FloorCount() - value + 1
end

--- The native Slider widget always renders its minimum at the TOP of a
--- VERTICAL track and its maximum at the BOTTOM (confirmed via
--- https://warcraft.wiki.gg/wiki/API_Slider_SetOrientation: "Slider thumb
--- moves from top to bottom as the slider's value increases"), the
--- opposite of the "value" scale the rest of this section uses, which puts
--- the minimum at the bottom of the track (deepest) and the maximum at the
--- top (topmost), to match ElevationForValue, ValueToFractionalIndex,
--- IndexToValue and ValueToIndex above. This converts between the two; it's
--- its own inverse (same mirror-around-the-range shape as IndexToValue), so
--- it is used both to translate the raw value OnValueChanged receives, and
--- to translate the value SyncSlider hands to SetValue.
local function MirrorSliderValue(v)
    return FloorCount() - v + 1
end

--- Triangular falloff around a fractional floor position: 1 at that floor's
--- own index, fading linearly to 0 by the time the slider reaches either
--- neighbour, and 0 beyond that. At most two floors are ever partially
--- visible at once, the same as a real crossfade dissolve.
local function ContinuousAlpha(index, fractionalIndex)
    return math.max(0, 1 - math.abs(index - fractionalIndex))
end

--- cave-satellite-v2 Phase 2: real-world elevation the slider's raw value
--- corresponds to, spanning the aggregate zMin/zMax of every piece currently
--- rendered (piecesZMin/piecesZMax, set by RenderContinuousPieces, not any
--- one floor's own range) so that dragging between the two floor notches
--- sweeps continuously through every piece's real height in between, which
--- is the whole point of the per-piece rework (see the module-state comment
--- above continuousPieceGroups). Runs the same direction as the floor index:
--- 1 (the bottom of the track, the deepest floor) is the lowest elevation,
--- FloorCount() (the top, the topmost floor) is the highest.
local function ElevationForValue(value)
    if not piecesZMin or not piecesZMax then return 0 end
    local n = FloorCount()
    if n <= 1 then return piecesZMax end
    local frac = (value - 1) / (n - 1)
    return piecesZMin + frac * (piecesZMax - piecesZMin)
end

--- The height-window rectangle's own real-world elevation bounds: its two
--- 0..1 fractions (Config:CaveHeightWindow) scaled against the aggregate
--- zMin/zMax of every piece currently rendered (piecesZMin/piecesZMax, set
--- by RenderContinuousPieces), the same span ElevationForValue scales
--- against. Returns nil, nil before any piece has been rendered.
---@return number|nil windowBottomZ, number|nil windowTopZ
local function HeightWindowElevationBounds()
    if not piecesZMin or not piecesZMax then return nil, nil end
    local top, bottom = Config:CaveHeightWindow()
    local span = piecesZMax - piecesZMin
    return piecesZMin + bottom * span, piecesZMin + top * span
end

--- Overlap-based alpha for a piece against the height-window rectangle's
--- real elevation bounds: 1 if any part of the piece's own [zMin, zMax]
--- falls inside [windowBottomZ, windowTopZ], fading linearly to 0 over
--- EDGE_FADE_YARDS beyond whichever edge is nearer, and 0 past that. Unlike
--- a single-point falloff, any number of pieces can be simultaneously fully
--- visible, partially faded, or invisible at once: there is no fixed
--- neighbour count once "floors" stop being the unit the fade is keyed on.
local function PieceWindowAlpha(zMin, zMax, windowBottomZ, windowTopZ)
    if not windowBottomZ then return 1 end
    if zMax >= windowBottomZ and zMin <= windowTopZ then return 1 end
    local d = (zMin > windowTopZ) and (zMin - windowTopZ)
        or (windowBottomZ - zMax)
    return math.max(0, 1 - d / EDGE_FADE_YARDS)
end

local function EnsureSlider()
    if sliderCol then return end

    sliderCol = CreateFrame("Frame", nil, window)
    sliderCol:SetWidth(SLIDER_COL_W)

    -- The track. A real Slider rather than a texture moved by hand, so that
    -- thumb dragging, click-on-track and the step snapping all come from the
    -- widget rather than from this file.
    -- BackdropTemplate for the trough (see below); CreateFrameTry falls back
    -- to a plain Slider on a client without it.
    sliderTrack = CreateFrameTry("Slider", nil, sliderCol, "BackdropTemplate")
    sliderTrack:SetOrientation("VERTICAL")
    sliderTrack:SetWidth(SLIDER_W)
    -- Anchored at the top only, with the height set explicitly by
    -- LayoutWindow: anchoring both ends would make the height anchor-derived
    -- and therefore not reliably readable when the height window is placed.
    sliderTrack:SetPoint("TOP", sliderCol, "TOP", 0, 0)
    sliderTrack:SetValueStep(1)
    if sliderTrack.SetObeyStepOnDrag then
        sliderTrack:SetObeyStepOnDrag(true)
    end
    -- The stock scroll bar's knob, at its native 18x24 and texcoords: the
    -- vertical control every WoW player already knows how to grab.
    sliderTrack:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    local thumb = sliderTrack:GetThumbTexture()
    if thumb then
        thumb:SetSize(18, 24)
        thumb:SetTexCoord(0.20, 0.80, 0.125, 0.875)
    end

    -- Trough: the same backdrop FrameXML's OptionsSliderTemplate gives every
    -- stock slider (SliderBar-Border edge, tiled SliderBar-Background), with
    -- its insets turned 90 degrees for a vertical track. Edge pieces are
    -- 8px, so the 16px SLIDER_W is the narrowest it can be without the
    -- corners crossing. Stretching the border *texture* over the track, as
    -- this used to, smeared a horizontal 3-slice across a vertical frame.
    if sliderTrack.SetBackdrop then
        sliderTrack:SetBackdrop({
            bgFile   = "Interface\\Buttons\\UI-SliderBar-Background",
            edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 6, right = 6, top = 3, bottom = 3 },
        })
    end

    sliderTrack:SetScript("OnValueChanged", function(self, rawValue)
        if self._syncing then return end
        -- rawValue is the native widget's own value (min at the top of the
        -- track, max at the bottom); mirror it onto this file's value scale
        -- (min at the bottom, max at the top) before any of the math below,
        -- which all assumes the latter. See MirrorSliderValue.
        local value = MirrorSliderValue(rawValue)
        if piecesActive then
            -- The height-window rectangle (EnsureHeightWindow) replaces the
            -- plain thumb-drag entirely for a per-piece place; the track's
            -- own mouse and wheel are disabled to match (see
            -- SyncHeightWindow), so this never actually fires from user
            -- input, but stays a safe no-op rather than falling through to
            -- the floor-select branch below with a value that has no floor
            -- meaning here.
            return
        end
        if continuousActive then
            -- A shared-canvas cave: drag freely between floors, fading
            -- their art and the pin as the value moves, without tearing
            -- down and rebuilding the window on every pixel of drag.
            CaveRenderer:UpdateContinuousAlphas(ValueToFractionalIndex(value))
            return
        end
        local floors = Config.caveAllFloors
        if not floors then return end
        local floor = floors[ValueToIndex(value)]
        if floor and floor.mapID ~= Config.caveCurrentFloorMapID then
            CaveRenderer:SelectFloor(floor.mapID)
        end
    end)

    sliderTrack:EnableMouseWheel(true)
    sliderTrack:SetScript("OnMouseWheel", function(_, dir)
        -- Wheel up = up a floor = towards index 1.
        StepFloor(-dir)
    end)

    sliderTrack:SetScript("OnEnter", function(self)
        local floors = Config.caveAllFloors
        if not floors then return end
        local idx = FloorIndex(Config.caveCurrentFloorMapID) or 1
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Depth", 1, 1, 1)
        for i, f in ipairs(floors) do
            local on = (i == idx)
            -- Gold for the current floor, plain light gray otherwise: the
            -- same selected-vs-normal convention Blizzard's own list UIs
            -- (spellbook, quest log, dropdown menus) use throughout.
            GameTooltip:AddLine(
                ("%s %s"):format(on and "»" or " ", f.name or ("Level " .. i)),
                on and 1 or 0.8, on and 0.82 or 0.8, on and 0 or 0.8)
        end
        if continuousActive then
            GameTooltip:AddLine("Drag to fade between levels, scroll to jump",
                0.5, 0.5, 0.5)
        else
            GameTooltip:AddLine("Drag, click or scroll to change level",
                0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    sliderTrack:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- For /hfwm debug and the test harness; built lazily, so it cannot be
    -- published alongside the window itself.
    Config.caveSliderCol   = sliderCol
    Config.caveSliderTrack = sliderTrack
end

--- Pull the slider's displayed position back from the active floor.
---@param continuous boolean  true for a shared-canvas place: free-drag
--- between floors rather than snapping to each one in turn.
local function SyncSlider(floors, currentMapID, continuous)
    local n = floors and #floors or 0
    -- A single floor with no active pieces has nothing to slide between at
    -- all -- the ordinary case, and every generic single-floor mine in the
    -- game hits it. But a single floor *with* pieces (Echo Ridge Mine, and
    -- any future single-floor cave-satellite-v2 place) still has a real
    -- piece elevation range worth scrubbing through by hand via the height
    -- window (see SyncHeightWindow/EnsureHeightWindow) -- `continuous` is
    -- already `continuousActive or piecesActive` from the caller, so it is
    -- true in exactly that case. Everything below already tolerates n == 1:
    -- SetMinMaxValues(1, 1) just freezes the (hidden, once pieces are
    -- active -- see SyncHeightWindow) thumb.
    if n <= 1 and not continuous then
        if sliderCol then sliderCol:Hide() end
        return
    end

    EnsureSlider()

    local idx = FloorIndex(currentMapID) or 1
    -- Both calls are guarded: narrowing the range clamps the current value,
    -- which fires OnValueChanged just as surely as setting it does, and a
    -- cave with fewer floors than the last one would otherwise reselect a
    -- floor behind the user's back.
    sliderTrack._syncing = true
    sliderTrack:SetMinMaxValues(1, n)
    -- Mirror the same way OnValueChanged does: index 1 (topmost) at the top
    -- of the track, index n (deepest) at the bottom.
    sliderTrack:SetValue(MirrorSliderValue(IndexToValue(idx)))
    -- Discrete caves snap to whole floors; a shared-canvas cave drags
    -- smoothly between them so the opacity crossfade has something
    -- fractional to work with.
    sliderTrack:SetValueStep(continuous and 0.01 or 1)
    if sliderTrack.SetObeyStepOnDrag then
        sliderTrack:SetObeyStepOnDrag(not continuous)
    end
    sliderTrack._syncing = false

    sliderCol:Show()
end

-------------------------------------------------------------------------------
-- Height-window widget (cave-satellite-v2 Phase 2)
--
-- A rectangle dragged directly on the depth slider, replacing a single
-- slider point with a range: dragging the body moves the whole window up
-- or down the track (which elevation range is shown); dragging either edge
-- resizes it (how wide a range is shown). At the loosest setting (the
-- rectangle spanning the whole track) every piece is visible at once; at
-- the tightest (Config.HEIGHT_WINDOW_MIN_SPAN) only a narrow band around
-- wherever the user left it is.
--
-- Built as one Button (`windowBody`, the whole rectangle, for the move
-- drag) with two child Buttons (`windowTopHandle`/`windowBottomHandle`,
-- thin grab strips overlapping its top and bottom edges, for the resize
-- drags). The handles sit at a higher frame level than the body so a
-- click on the edge strip reaches the handle first, and a click anywhere
-- else in the rectangle falls through to the body.
--
-- Dragging is hand-polled (OnMouseDown to start, OnUpdate + a live
-- IsMouseButtonDown check to follow, release detected the same way rather
-- than from an OnMouseUp) instead of the frame's own StartSizing/
-- StartMoving: this is a custom two-edge range, not a single movable/
-- resizable frame, and polling behaves the same across client flavours.
-------------------------------------------------------------------------------

--- Cursor's current position along the track, as the same 0..1 fraction
--- HeightWindowElevationBounds use (0 at the bottom of the
--- track's usable range, 1 at the top), clamped to stay on the track even
--- if the cursor has strayed outside it.
local function CursorTrackFrac()
    if not sliderTrack then return 0 end
    local trackH = contentH
    if trackH <= 0 then return 0 end
    local usable = trackH - SLIDER_INSET * 2
    if usable <= 0 then return 0 end

    local scale = sliderTrack:GetEffectiveScale()
    local _, cursorY = GetCursorPosition()
    cursorY = cursorY / scale

    local bottom = sliderTrack:GetBottom() or 0
    local frac = (cursorY - bottom - SLIDER_INSET) / usable
    return math.max(0, math.min(1, frac))
end

--- Place the rectangle from Config's current window fractions.
local function LayoutHeightWindow()
    if not windowBody then return end
    local trackH = contentH
    local usable = trackH - SLIDER_INSET * 2
    if usable <= 0 then
        windowBody:Hide()
        return
    end

    local top, bottom = Config:CaveHeightWindow()
    local topOffset    = SLIDER_INSET + usable * top
    local bottomOffset = SLIDER_INSET + usable * bottom

    windowBody:ClearAllPoints()
    windowBody:SetPoint("BOTTOM", sliderTrack, "BOTTOM", 0, bottomOffset)
    local height = math.max(1, topOffset - bottomOffset)
    windowBody:SetHeight(height)
    -- Caps are each half the knob, but never more than half the window, so
    -- a squeezed window stays a knob rather than overlapping itself.
    local cap = math.min(12, height / 2)
    windowCapTop:SetHeight(cap)
    windowCapBottom:SetHeight(cap)
    windowBody:Show()
end

--- Recompute and redraw every piece's alpha from the window's current
--- elevation bounds. The whole of what dragging the rectangle does; it
--- never tears down or re-renders the pieces themselves.
function CaveRenderer:UpdatePieceWindowAlphas()
    local windowBottomZ, windowTopZ = HeightWindowElevationBounds()
    for _, grp in ipairs(continuousPieceGroups) do
        local alpha = PieceWindowAlpha(grp.zMin, grp.zMax, windowBottomZ, windowTopZ)
        grp.alpha = alpha
        for _, tex in ipairs(grp.textures) do tex:SetAlpha(alpha) end
    end
end

--- Start tracking a drag of one of the three controls.
---@param kind "top"|"bottom"|"body"
local function BeginHeightWindowDrag(kind)
    local top, bottom = Config:CaveHeightWindow()
    heightWindowDrag = {
        kind        = kind,
        startFrac   = CursorTrackFrac(),
        startTop    = top,
        startBottom = bottom,
    }
end

--- Polled every frame windowBody is shown; a no-op unless a drag is live,
--- and self-stops the instant the mouse button is no longer down (rather
--- than relying on an OnMouseUp, which a fast drag can carry the cursor
--- right off of the handle before firing).
local function HeightWindowDragUpdate()
    if not heightWindowDrag then return end
    if not IsMouseButtonDown("LeftButton") then
        heightWindowDrag = nil
        return
    end

    local frac = CursorTrackFrac()
    -- Edges move by how far the cursor has travelled since the press, not to
    -- where it is: a click a few pixels off an edge's exact position would
    -- otherwise snap the edge to the cursor before any actual drag.
    local delta = frac - heightWindowDrag.startFrac
    if heightWindowDrag.kind == "top" then
        Config:SetCaveHeightWindow(heightWindowDrag.startTop + delta,
            heightWindowDrag.startBottom)
    elseif heightWindowDrag.kind == "bottom" then
        Config:SetCaveHeightWindow(heightWindowDrag.startTop,
            heightWindowDrag.startBottom + delta)
    else -- "body": both edges move together, preserving the span
        local span  = heightWindowDrag.startTop - heightWindowDrag.startBottom
        local top, bottom = heightWindowDrag.startTop + delta,
            heightWindowDrag.startBottom + delta
        if top > 1 then top, bottom = 1, 1 - span end
        if bottom < 0 then top, bottom = span, 0 end
        Config:SetCaveHeightWindow(top, bottom)
    end

    LayoutHeightWindow()
    CaveRenderer:UpdatePieceWindowAlphas()
end

local GLOW_FADE   = 0.15   -- seconds for an edge glow to fade fully in or out
-- The glow is centred on its handle, which sits flush inside the window edge.
local GLOW_HALF_H = 10     -- px each side of the glow's centre line

--- Gold glow on a resize handle: fades in while the cursor is over it or
--- while it is the edge being dragged (the cursor often outruns the strip
--- mid-drag), and back out otherwise. Driven from the handle's own OnUpdate,
--- which only runs while the handle is shown.
---@param handle Button
---@param kind "top"|"bottom"
local function AddEdgeGlow(handle, kind)
    -- A soft band centred on the handle. Gold is built from two gradient
    -- halves (bright at the centre line, clear at both ends) because
    -- tinting a stock highlight texture read green.
    local y = 0
    local bright = CreateColor(1.00, 0.80, 0.15, 0.85)
    local clear  = CreateColor(1.00, 0.80, 0.15, 0)

    -- anchor: which edge of the half sits on the centre line. The half
    -- above the line is bright at its bottom; the half below, at its top.
    local function Half(anchor, minColor, maxColor)
        local t = handle:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 1, 1, 1)
        t:SetBlendMode("ADD")
        t:SetGradient("VERTICAL", minColor, maxColor)
        t:SetHeight(GLOW_HALF_H)
        t:SetPoint(anchor .. "LEFT", handle, "LEFT", -2, y)
        t:SetPoint(anchor .. "RIGHT", handle, "RIGHT", 2, y)
        return t
    end
    local halves = {
        Half("BOTTOM", bright, clear),   -- above the line
        Half("TOP", clear, bright),      -- below the line
    }

    local level = 0
    local function SetLevel(a)
        level = a
        for _, t in ipairs(halves) do
            t:SetAlpha(a)
            t:SetShown(a > 0)
        end
    end
    SetLevel(0)

    handle:SetScript("OnUpdate", function(self, elapsed)
        local lit = self:IsMouseOver()
            or (heightWindowDrag and heightWindowDrag.kind == kind)
        local step = elapsed / GLOW_FADE
        SetLevel(lit and math.min(1, level + step) or math.max(0, level - step))
    end)
end

--- Build the rectangle and its two resize handles, lazily on first use,
--- same pattern as EnsureSlider, which this calls first since the widget
--- is anchored to the slider track it overlays.
local function EnsureHeightWindow()
    if windowBody then return end
    EnsureSlider()

    -- The rectangle is the stock scroll bar knob (the same art the plain
    -- thumb uses) stretched to the window: its top and bottom halves as end
    -- caps and a one-row slice of its middle repeated between them, so a
    -- resized window is a longer knob rather than a different widget.
    local widgetW = 18
    local KNOB = "Interface\\Buttons\\UI-ScrollBar-Knob"

    windowBody = CreateFrame("Button", nil, sliderCol)
    windowBody:SetWidth(widgetW)
    windowBody:SetPoint("TOP", sliderTrack, "TOP", 0, 0)
    windowBody:EnableMouse(true)
    windowBody:SetScript("OnMouseDown", function()
        BeginHeightWindowDrag("body")
    end)
    windowBody:SetScript("OnUpdate", HeightWindowDragUpdate)
    windowBody:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Height window", 1, 1, 1)
        GameTooltip:AddLine("Drag to move the visible range up or down",
            0.5, 0.5, 0.5)
        GameTooltip:AddLine("Drag an edge to widen or narrow it",
            0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    windowBody:SetScript("OnLeave", function() GameTooltip:Hide() end)

    windowCapTop = windowBody:CreateTexture(nil, "ARTWORK", nil, 2)
    windowCapTop:SetTexture(KNOB)
    windowCapTop:SetTexCoord(0.20, 0.80, 0.125, 0.50)
    windowCapTop:SetPoint("TOPLEFT", windowBody, "TOPLEFT", 0, 0)
    windowCapTop:SetPoint("TOPRIGHT", windowBody, "TOPRIGHT", 0, 0)

    windowCapBottom = windowBody:CreateTexture(nil, "ARTWORK", nil, 2)
    windowCapBottom:SetTexture(KNOB)
    windowCapBottom:SetTexCoord(0.20, 0.80, 0.50, 0.875)
    windowCapBottom:SetPoint("BOTTOMLEFT", windowBody, "BOTTOMLEFT", 0, 0)
    windowCapBottom:SetPoint("BOTTOMRIGHT", windowBody, "BOTTOMRIGHT", 0, 0)

    local middle = windowBody:CreateTexture(nil, "ARTWORK", nil, 1)
    middle:SetTexture(KNOB)
    middle:SetTexCoord(0.20, 0.80, 0.49, 0.51)
    middle:SetPoint("TOPLEFT", windowCapTop, "BOTTOMLEFT", 0, 0)
    middle:SetPoint("BOTTOMRIGHT", windowCapBottom, "TOPRIGHT", 0, 0)

    -- Handles sit flush inside the body's edge, not straddling it: a strip
    -- reaching past the rectangle made the hover (and its glow) trigger
    -- over bare track.
    windowTopHandle = CreateFrame("Button", nil, windowBody)
    windowTopHandle:SetHeight(HEIGHT_WINDOW_HANDLE_H)
    windowTopHandle:SetPoint("TOPLEFT", windowBody, "TOPLEFT", 0, 0)
    windowTopHandle:SetPoint("TOPRIGHT", windowBody, "TOPRIGHT", 0, 0)
    windowTopHandle:SetFrameLevel(windowBody:GetFrameLevel() + 2)
    windowTopHandle:EnableMouse(true)
    windowTopHandle:SetScript("OnMouseDown", function()
        BeginHeightWindowDrag("top")
    end)
    windowTopHandle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Drag to widen or narrow the top of the "
            .. "visible range", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    windowTopHandle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    AddEdgeGlow(windowTopHandle, "top")

    windowBottomHandle = CreateFrame("Button", nil, windowBody)
    windowBottomHandle:SetHeight(HEIGHT_WINDOW_HANDLE_H)
    windowBottomHandle:SetPoint("BOTTOMLEFT", windowBody, "BOTTOMLEFT",
        0, 0)
    windowBottomHandle:SetPoint("BOTTOMRIGHT", windowBody, "BOTTOMRIGHT",
        0, 0)
    windowBottomHandle:SetFrameLevel(windowBody:GetFrameLevel() + 2)
    windowBottomHandle:EnableMouse(true)
    windowBottomHandle:SetScript("OnMouseDown", function()
        BeginHeightWindowDrag("bottom")
    end)
    windowBottomHandle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Drag to widen or narrow the bottom of the "
            .. "visible range", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    windowBottomHandle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    AddEdgeGlow(windowBottomHandle, "bottom")
end

--- Show/position the rectangle for a per-piece place, or hide it (and give
--- the plain thumb back its usual mouse/wheel interaction) for anything
--- else. Called from ShowCave right after SyncSlider.
---@param active boolean  CaveRenderer:IsPiecesActive()'s value for the
--- place just shown.
local function SyncHeightWindow(active)
    if not active then
        heightWindowDrag = nil
        if windowBody then windowBody:Hide() end
        if sliderTrack then
            local thumb = sliderTrack:GetThumbTexture()
            if thumb then thumb:SetShown(true) end
            sliderTrack:EnableMouse(true)
            sliderTrack:EnableMouseWheel(true)
        end
        return
    end

    EnsureHeightWindow()
    -- The rectangle fully replaces the thumb's role while active: showing
    -- both would be two controls claiming to do the same job.
    local thumb = sliderTrack:GetThumbTexture()
    if thumb then thumb:SetShown(false) end
    sliderTrack:EnableMouse(false)
    sliderTrack:EnableMouseWheel(false)
    LayoutHeightWindow()
    windowBody:Show()
end

-------------------------------------------------------------------------------
-- Floor picker (dropdown)
--
-- Top-right, in a strip above the art (LayoutWindow pads the art down by
-- the picker's own height) rather than
-- in the title bar (already carrying the area name and the close button) or
-- the footer (already carrying the "Level X of Y" readout).
--
-- Built from the client's own UIDropDownMenuTemplate, the same "long-lived"
-- dropdown Options.lua's TryLegacyDropdown reaches for and reliably present
-- on every flavour from vanilla through Dragonflight per that file's own
-- comment, rather than a hand-built button and popup list. Reading and
-- behaving exactly like every other dropdown in the default UI is the point:
-- the native checkmark marks the active entry, the native highlight and
-- click sound come for free, and there is no bespoke popup-list/click-away
-- plumbing here to keep in sync with the real thing.
--
-- InitFloorPickerMenu reads Config.caveAllFloors / Config.caveFloorFilterAll
-- / Config.caveCurrentFloorMapID live, each time the menu opens.
-- UIDropDownMenu_Initialize already means "call this again whenever the
-- list needs to be current," so unlike the depth slider's hand-drawn
-- notches there is nothing here that needs rebuilding ahead of time by a
-- Sync function; SyncFloorPicker below only has the closed-state text left
-- to do.
-------------------------------------------------------------------------------

--- The menu list: "All" first, in Blizzard's own cyan (see
--- BLIZZARD_CYAN_HEX), then every floor, topmost first, in plain default
--- text. The native checkmark (info.checked) is what marks whichever one
--- is active, the same as every other Blizzard dropdown, so neither entry
--- needs its own hand-picked highlight colour on top of that. Selecting
--- either hands straight off to CaveRenderer:SelectAllFloors/
--- SelectFloorFilter, which is also what the depth slider and the
--- mouse-wheel step already call, so none of the three can ever disagree
--- about which floor is current.
local function InitFloorPickerMenu(_, level)
    local floors = Config.caveAllFloors
    if not floors then return end

    local allInfo = UIDropDownMenu_CreateInfo()
    allInfo.text            = BLIZZARD_CYAN_HEX .. "All|r"
    allInfo.checked         = Config.caveFloorFilterAll and true or false
    allInfo.tooltipTitle    = "All"
    allInfo.tooltipText     = "Layer every floor together (the default)."
    allInfo.tooltipOnButton = true
    allInfo.func = function() CaveRenderer:SelectAllFloors() end
    UIDropDownMenu_AddButton(allInfo, level)

    for i, floor in ipairs(floors) do
        local name = floor.name or ("Level " .. i)
        local info = UIDropDownMenu_CreateInfo()
        info.text            = name
        info.checked         = (not Config.caveFloorFilterAll)
            and floor.mapID == Config.caveCurrentFloorMapID
        info.tooltipTitle    = name
        info.tooltipText     = "Show only this floor, and scope the depth "
            .. "slider to its own range."
        info.tooltipOnButton = true
        info.func = function() CaveRenderer:SelectFloorFilter(floor.mapID) end
        UIDropDownMenu_AddButton(info, level)
    end
end

--- Build the dropdown, lazily on first use, same pattern as EnsureSlider/
--- EnsureHeightWindow. `floorPickerUnavailable` is set once and for all if
--- this client turns out not to expose the UIDropDownMenuTemplate API,
--- vanishingly unlikely (see the section comment above) but checked anyway,
--- matching every other template lookup in this addon. There is
--- deliberately no hand-built fallback this time: going without a floor
--- picker is a smaller gap than shipping a second, differently-styled
--- widget for the same job on the rare client that lacks it.
local function EnsureFloorPicker()
    if floorPicker or floorPickerUnavailable then return end

    if not (UIDropDownMenu_Initialize and UIDropDownMenu_CreateInfo
            and UIDropDownMenu_AddButton and UIDropDownMenu_SetText) then
        floorPickerUnavailable = true
        return
    end

    local ok, dd = pcall(CreateFrame, "Frame", "HFWMForeverCaveFloorDropdown",
        window, "UIDropDownMenuTemplate")
    if not ok or not dd then
        floorPickerUnavailable = true
        return
    end

    local built = pcall(UIDropDownMenu_Initialize, dd, InitFloorPickerMenu)
    if not built then
        dd:Hide()
        floorPickerUnavailable = true
        return
    end

    if UIDropDownMenu_SetWidth then
        -- -40: the template's own frame is wider than its visible
        -- text/button area on both ends (see Options.lua's identical -40
        -- on its own background dropdown's DROPDOWN_WIDTH), so this keeps
        -- the *visible* widget close to FLOOR_PICKER_W rather than that
        -- much wider again.
        pcall(UIDropDownMenu_SetWidth, dd, FLOOR_PICKER_W - 40)
    end

    dd:ClearAllPoints()
    -- +14, not flush: the template's own end-cap art sits inset from the
    -- frame's true edges, so anchoring flush would leave the *visible*
    -- widget floating short of content's own left edge. This is a
    -- by-eye nudge, not a measured one; worth another look in-game.
    dd:SetPoint("BOTTOMLEFT", content, "TOPLEFT", -14, 0)
    -- Above content's own tiles: both are plain children of `window` and
    -- would otherwise share its default child level, which draw-order
    -- ties in creation order rather than anything this file controls.
    dd:SetFrameLevel(content:GetFrameLevel() + 5)

    floorPicker = dd
end

--- Pull the closed dropdown's own text back from the current filter/floor,
--- and hide the whole control for a single-floor place, same gate the
--- depth slider itself uses (FloorCount() <= 1): a picker with only "All"
--- and one floor to choose between has nothing to offer that showing the
--- floor already didn't.
---@param floors table[]|nil  Config.caveAllFloors
---@param currentMapID number|nil
local function SyncFloorPicker(floors, currentMapID)
    local n = floors and #floors or 0
    if n <= 1 then
        if floorPicker then
            floorPicker:Hide()
            if CloseDropDownMenus then pcall(CloseDropDownMenus) end
        end
        return
    end

    EnsureFloorPicker()
    if not floorPicker then return end

    if Config.caveFloorFilterAll then
        UIDropDownMenu_SetText(floorPicker, BLIZZARD_CYAN_HEX .. "All|r")
    else
        local cur
        for _, f in ipairs(floors) do
            if f.mapID == currentMapID then cur = f break end
        end
        UIDropDownMenu_SetText(floorPicker, cur and cur.name or "Floor")
    end

    floorPicker:Show()
end

-------------------------------------------------------------------------------
-- Reopen icon
--
-- The window's own close button (see EnsureWindow) hides the cave map for
-- the rest of the visit; without this, there is then no way back into it
-- short of the /hfwm slash command. This is a small icon button that sits
-- in the bottom-right of the map, above the side-panel toggle's open
-- button, and reappears whenever Cave.lua has a cave available but closed.
-------------------------------------------------------------------------------
-- Sized so the Dialog border's corner art doesn't overlap itself, with the
local REOPEN_BTN_SIZE = 44
local REOPEN_ICON_INSET = 6
--- How much the Dialog border art is shrunk on the reopen button: the same
--- sprites the cave window gets, scaled down so the stroke is thinner.
local REOPEN_BORDER_SCALE = 0.75

local function EnsureReopenButton()
    if reopenBtn then return end

    local btn = CreateFrame("Button", "HFWMForeverCaveReopenButton", Config:MapWidgetParent())
    btn:SetSize(REOPEN_BTN_SIZE, REOPEN_BTN_SIZE)
    btn:EnableMouse(true)

    -- Anchored the same way the cave window itself is layered: the map's own
    -- strata, well above its children, so it isn't a click behind the map's
    -- own furniture.
    if not Config.mapHost then btn:SetFrameStrata(WorldMapFrame:GetFrameStrata()) end
    btn:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 800)

    -- Bottom of this icon sits on top of the side panel toggle's open
    -- button, so the two never overlap. If a client build doesn't have that
    -- button (name changed, or the side panel doesn't exist here), fall
    -- back to a fixed corner inset rather than leave the icon unanchored.
    local sidePanelToggle = WorldMapFrame.SidePanelToggle
    local openButton = sidePanelToggle and sidePanelToggle.OpenButton
    if openButton then
        btn:SetPoint("BOTTOMRIGHT", openButton, "TOPRIGHT", 0, 4)
    else
        btn:SetPoint("BOTTOMRIGHT", WorldMapFrame, "BOTTOMRIGHT", -8, 40)
    end

    -- Same chrome as the cave window itself (ApplyGameMenuChrome): the
    -- Dialog nine-slice border over the tiled dialog fill, scaled down so
    -- the window-weighted stroke reads thinner at button size. The border
    -- frame is sized up by 1/scale -- and to at least twice the corner
    -- art's own width, so opposite corners never cross -- before scaling,
    -- so the shrunken art still covers the button. The fill's 7px window
    -- inset (LayoutDialogFill) shrinks with the same factor.
    local fill = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
    fill:SetTexture(DIALOG_FILL, "REPEAT", "REPEAT")
    fill:SetHorizTile(true)
    fill:SetVertTile(true)
    local inset = 7 * REOPEN_BORDER_SCALE
    fill:SetPoint("TOPLEFT", inset, -inset)
    fill:SetPoint("BOTTOMRIGHT", -inset, inset)
    local border = CreateFrame("Frame", nil, btn, "DialogBorderNoCenterTemplate")
    local corner = border.TopLeftCorner and border.TopLeftCorner:GetWidth() or 32
    local size = math.max(REOPEN_BTN_SIZE / REOPEN_BORDER_SCALE, corner * 2)
    border:ClearAllPoints()
    border:SetPoint("CENTER")
    border:SetSize(size, size)
    border:SetScale(REOPEN_BORDER_SCALE)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    -- Inset from the button edge: shrinks the icon just enough that the
    -- Dialog border art stays visible around it.
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", REOPEN_ICON_INSET, -REOPEN_ICON_INSET)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -REOPEN_ICON_INSET, REOPEN_ICON_INSET)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Map02")
    -- Trim the icon's own baked-in border padding so it still reads full
    -- within that smaller box.
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(btn)
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")

    btn:SetScript("OnClick", function()
        ns.Cave:ForceShow()
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Open cave map")
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:Hide()
    reopenBtn = btn
end

--- Show or hide the reopen icon. Cave.lua drives this: true when the player
--- is somewhere with a cave map but has closed it (or hasn't opened it yet
--- this visit); false whenever the cave window itself is showing, or there
--- is nothing to reopen.
---@param available boolean
function CaveRenderer:SetReopenAvailable(available)
    if available then
        EnsureReopenButton()
        reopenBtn:Show()
    elseif reopenBtn then
        reopenBtn:Hide()
    end
end

-------------------------------------------------------------------------------
-- Zoom & pan
--
-- canvasScale is a plain child frame of `content`, sized to match it
-- exactly (see LayoutWindow) and holding every piece of the actual cave
-- picture: the tile/piece textures RenderTiles and RenderContinuousPieces
-- draw, and the player pin. Neither of those functions knows zoom exists;
-- they still size and place everything against plain contentW/contentH
-- pixels, exactly as before this section existed. The magnification and
-- the shift are applied in exactly one place, ApplyCanvasTransform, via
-- canvasScale:SetScale and its own anchor offset from `content`'s TOPLEFT:
-- a texture inside canvasScale at logical position (x, y) with size (w, h)
-- ends up on screen at (panX + x*zoomScale, panY + y*zoomScale) sized
-- (w*zoomScale, h*zoomScale), simply from the chain of effective scales.
-- No per-tile math anywhere else has to change for that to be true.
--
-- `content` still clips its children (see EnsureWindow), and that clip is
-- based on content's own fixed on-screen rect regardless of what canvasScale
-- is doing inside it, so a zoomed-in, panned canvasScale is cropped to the
-- window's content area for free rather than needing a second clip frame.
-------------------------------------------------------------------------------

--- Cursor position in content-local pixels: 0,0 at content's own TOPLEFT,
--- x growing right, y growing *down* as an increasingly negative number,
--- the same convention RenderTiles already anchors every tile with (see
--- `-(row * tilePxH * scaleY)` there), so a point measured here lines up
--- with the tile grid without a sign flip anywhere in this section.
--- Returns 0, 0 if content has no resolved rect yet (nothing shown, or
--- shown for the first time this frame).
local function ContentCursorXY()
    if not content then return 0, 0 end
    local scale = content:GetEffectiveScale()
    if not scale or scale == 0 then return 0, 0 end
    local x, y = GetCursorPosition()
    x, y = x / scale, y / scale
    local left, top = content:GetLeft(), content:GetTop()
    if not left or not top then return 0, 0 end
    return x - left, y - top
end

--- Is the cursor over the art area, by geometry alone? Hit-testing through
--- the frame stack (content's own OnMouse* scripts) depends on nothing
--- mouse-enabled sitting above `content`, which this window can't guarantee
--- (AceGUI chrome, the dropdown, the client's own map frames); the cursor
--- rect doesn't. The floor picker and its open list overlap the art and are
--- real controls, so they keep their clicks.
local function CursorOverArt()
    if not (content and content:IsVisible() and content:IsMouseOver()) then
        return false
    end
    if floorPicker and floorPicker:IsShown() and floorPicker:IsMouseOver() then
        return false
    end
    local list = _G.DropDownList1
    return not (list and list:IsShown() and list:IsMouseOver())
end

--- Keep canvasScale from being panned out of a sensible position: zoomed in
--- (zoomScale > 1) the canvas is larger than the viewport,
--- so it may not slide far enough to show the flat backdrop; zoomed out
--- (zoomScale < 1) it is smaller, so it may slide anywhere that keeps it
--- fully inside the viewport. Both cases are one range between 0 and the
--- offset that puts the far edge flush, which also makes the range collapse
--- to nothing at the exact fit (zoomScale 1), where there is no room to pan.
--- panY grows upward (see ContentCursorXY), hence the opposite sign to panX.
local function ClampPan()
    local a = contentW * (1 - zoomScale)
    panX = math.max(math.min(0, a), math.min(math.max(0, a), panX))

    local b = contentH * (zoomScale - 1)
    panY = math.max(math.min(0, b), math.min(math.max(0, b), panY))
end

--- Pins live on canvasScale, so zoomScale would magnify them along with the
--- art. Divide it back out so they stay a constant on-screen size.
local function ApplyPinScale()
    local inv = 1 / zoomScale
    if playerPin then playerPin:SetSize(PIN_SIZE * inv, PIN_SIZE * inv) end
    if corpsePin then corpsePin:SetSize(CORPSE_PIN_SIZE * inv, CORPSE_PIN_SIZE * inv) end
    local s = GROUP_PIN_SIZE * inv
    local b = (GROUP_PIN_SIZE + 2 * GROUP_PIN_BORDER) * inv
    for _, pin in ipairs(groupPins) do
        pin:SetSize(s, s)
        pin.border:SetSize(b, b)
    end
end

--- Push zoomScale/panX/panY onto canvasScale, the only place either value
--- is actually read into the frame tree. Every other function in this
--- section only ever changes the numbers and calls this (normally right
--- after ClampPan).
local function ApplyCanvasTransform()
    if not canvasScale then return end
    canvasScale:SetScale(zoomScale)
    ApplyPinScale()
    canvasScale:ClearAllPoints()
    -- SetPoint offsets are in the frame's *own* scale, so at zoomScale z an
    -- offset of n lands n*z away from the anchor. panX/panY are in content's
    -- (parent) units, so divide the scale back out.
    canvasScale:SetPoint("TOPLEFT", content, "TOPLEFT",
        panX / zoomScale, panY / zoomScale)
end

--- Reset to the fitted view: zoom 1, no pan. What HideCave leaves behind and
--- what the shift+right-click reset on the window snaps to, so both mean
--- exactly "the view a freshly opened cave starts with".
local function ResetViewTransform()
    zoomScale = FIT_ZOOM
    panX, panY = 0, 0
    contentDrag = nil
    zoomAnchorX, zoomAnchorY = nil, nil
    ApplyCanvasTransform()
end

--- Change zoom by `factor` (>1 in, <1 out), driving the picture toward
--- centering whichever canvas point the cursor is anchored to; see the
--- module comment above zoomAnchorX for what "anchored to" means and why.
---
--- Two approaches were tried and rejected first:
---
---   - Keep the exact pixel under the cursor pinned in place (the "browser
---     zoom" behaviour). Mathematically stable, but it never moves the
---     clicked point toward the centre: it stays exactly where the cursor
---     is, which for a click near the edge of a window this small reads as
---     the *rest* of the picture rushing past it rather than the clicked
---     thing settling into view.
---   - Recompute "what's under the cursor" fresh on every notch and centre
---     *that*. This one actually shipped for a bit, and has a real bug with
---     the cursor held still: the first notch moves the clicked content
---     most of the way to centre, so the *second* notch's fresh cursor
---     sample lands on a different part of the canvas than the first one
---     did (the picture moved, the cursor didn't) and centres *that*
---     instead. A stationary scroll visibly hunts across the map from
---     notch to notch instead of drilling into one spot, backwards from
---     "keep the mouse still and zoom in on that object."
---
--- The fix behind zoomAnchorX/zoomAnchorY: sample the canvas point under
--- the cursor once, the first notch after the cursor lands somewhere new,
--- and keep re-using that same point, not the cursor's live position, for
--- every notch until the cursor actually moves. Centering a *fixed* canvas
--- point at a *given* zoom is a direct formula with no dependency on the
--- pan that was in effect a moment ago (unlike either alternative above),
--- so back-to-back notches can't get stuck against a clamp or drift onto
--- the wrong content: each one just asks "where does zoomAnchorX land at
--- this new scale" and answers it fresh.
---@param factor number
---@param centered boolean|nil  anchor on the window's centre, not the cursor (gamepad has no cursor over the art)
local function ZoomBy(factor, centered)
    if not content or not canvasScale then return end
    if contentW <= 0 or contentH <= 0 then return end
    local newScale = math.max(MIN_ZOOM, math.min(MAX_ZOOM, zoomScale * factor))
    if newScale == zoomScale then return end

    local cx, cy
    if centered then cx, cy = contentW / 2, -contentH / 2 else cx, cy = ContentCursorXY() end
    -- Only re-sample the anchor if the cursor moved since it was last set;
    -- see the module comment above zoomAnchorX.
    if not zoomAnchorX
        or math.abs(cx - zoomAnchorCursorX) > ZOOM_ANCHOR_EPSILON
        or math.abs(cy - zoomAnchorCursorY) > ZOOM_ANCHOR_EPSILON
    then
        zoomAnchorX, zoomAnchorY = (cx - panX) / zoomScale, (cy - panY) / zoomScale
        zoomAnchorCursorX, zoomAnchorCursorY = cx, cy
    end

    -- See ContentCursorXY for the sign convention (0,0 at content's own
    -- top-left, y increasingly negative downward); centerY is negative
    -- for the same reason.
    local centerX, centerY = contentW / 2, -contentH / 2
    zoomScale = newScale
    panX = centerX - zoomScale * zoomAnchorX
    panY = centerY - zoomScale * zoomAnchorY

    ClampPan()
    ApplyCanvasTransform()
end

--- Start tracking a drag of the map picture itself. Left button, same as
--- the window's own drag-to-move. The two never compete for it, because
--- the window's drag is registered on `window` while this one is registered
--- on `content`, and content sits on top over the art, so a press there
--- reaches this handler first and never falls through to the window's.
local function BeginContentPan()
    local cx, cy = ContentCursorXY()
    contentDrag = { startX = cx, startY = cy, startPanX = panX, startPanY = panY }
end

--- Polled every frame `content` is shown, the same hand-polled pattern as
--- HeightWindowDragUpdate above, and for the same reason: release is
--- detected from a live IsMouseButtonDown check rather than an OnMouseUp,
--- so a fast drag that carries the cursor off of `content` before the
--- button lifts still stops cleanly instead of sticking the pan to the
--- cursor.
local leftWasDown = false
local function ContentPanUpdate()
    local down = IsMouseButtonDown("LeftButton")
    local pressed = down and not leftWasDown
    leftWasDown = down

    if not contentDrag then
        -- Normally OnMouseDown has already started the drag; this catches the
        -- press when something else in the stack got the event instead.
        if pressed and CursorOverArt() then BeginContentPan() end
        return
    end
    if not down then
        contentDrag = nil
        return
    end

    local cx, cy = ContentCursorXY()
    panX = contentDrag.startPanX + (cx - contentDrag.startX)
    panY = contentDrag.startPanY + (cy - contentDrag.startY)
    ClampPan()
    ApplyCanvasTransform()
end

--- Pin the cave window's own top-left corner to the world map's own
--- top-right: the x side of the pin is unchanged (still beside the map),
--- only the y alignment moves so the window's top edge sits level with
--- the map's (and with a side panel's) top edge instead of its bottom.
--- `window` is parented to WorldMapFrame (see ShowCave), so this
--- anchor tracks the map for free the instant the map itself moves or
--- resizes; it only has to be (re)applied here because SetWidth/SetHeight
--- above don't disturb an existing anchor, but a fresh AceGUI Frame starts
--- centred on UIParent (see ApplyStatus in AceGUIContainer-Frame.lua) and
--- every LayoutWindow call is cheap insurance against that ever showing.
local mapOpen = false
local pinnedTo  -- the frame PositionWindow last anchored to; a moved window isn't anchored to it

--- Rightmost shown left-side Blizzard panel (character sheet, spellbook...),
--- or nil. The map is excluded: it has its own slot.
local function RightmostPanel()
    local best, bestRight
    for name, info in pairs(UIPanelWindows or {}) do
        local f = _G[name]
        local r = f and f ~= WorldMapFrame and info.area
            and (info.area == "left" or info.area == "doublewide")
            and f:IsShown() and f:GetRight()
        if r and (not bestRight or r > bestRight) then best, bestRight = f, r end
    end
    return best
end

--- Where the cave window's TOPLEFT sits relative to a panel: beside the
--- panel's right edge, except the character sheet's own mode tabs
--- (Pet/Reputation/Currency...) extend past that edge and would be covered,
--- so anchor past the tabs themselves when they are shown. The anchor point
--- is the tabs' TOPRIGHT, but the y offset lifts it back to the sheet's own
--- top edge so the cave window's top is level with the sheet's, not the
--- tabs strip's (which starts lower).
local function PanelSideAnchor(panel)
    if panel == _G.CharacterFrame then
        local tabs = _G.CharacterFrameModeTabs
        if tabs and tabs:IsShown() then
            return tabs, "TOPRIGHT", PIN_GAP,
                (panel:GetTop() or 0) - (tabs:GetTop() or 0)
        end
    end
    return panel, "TOPRIGHT", 0, 0
end

local mapSeen = false  -- the map has been shown this session, so its scale is the real one
local function PositionWindow()
    if not window then return end
    window:ClearAllPoints()
    local pt = Config.db and Config.db.cavePlacement == "remember" and Config.db.caveWindowPoint
    if pt then
        local r = window:GetEffectiveScale() / UIParent:GetEffectiveScale()
        pinnedTo = UIParent
        window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pt.left / r, pt.top / r)
        return
    end
    local panel = Config.db and Config.db.caveKeepOpen and not mapOpen and RightmostPanel()
    if panel then
        -- Map closed: sit beside the open panel so it isn't covered,
        -- top edges level.
        local rel, point, x, y = PanelSideAnchor(panel)
        pinnedTo = rel
        window:SetPoint("TOPLEFT", rel, point, x, y)
    elseif Config.db and Config.db.caveKeepOpen and not mapOpen then
        -- Map closed, window kept open: take the map's slot (the map keeps
        -- its rect while hidden), so the window's top edge is the map's.
        pinnedTo = WorldMapFrame
        window:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", 0, 0)
    elseif Config.db and Config.db.cavePlacement ~= "inside" then
        -- Outside the pane (also "remember" before any drag): top-left of
        -- the cave window on the map's top-right, beside the map frame.
        pinnedTo = WorldMapFrame
        window:SetPoint("TOPLEFT", WorldMapFrame, "TOPRIGHT", PIN_GAP, 0)
    else
        pinnedTo = WorldMapFrame
        -- Inside the pane: bottom-right of the cave window sits on the
        -- top-right of the side panel toggle's own button, same anchor the
        -- reopen icon uses, so the window stacks straight above it. Fall
        -- back to the pane's top-left corner if this client build has no
        -- side panel toggle.
        local sidePanelToggle = WorldMapFrame.SidePanelToggle
        local openButton = sidePanelToggle and sidePanelToggle.OpenButton
        if openButton then
            pinnedTo = openButton
            window:SetPoint("BOTTOMRIGHT", openButton, "TOPRIGHT", 0, 0)
        else
            local pane = WorldMapFrame.ScrollContainer or WorldMapFrame
            window:SetPoint("TOPLEFT", pane, "TOPLEFT", PIN_GAP, -PIN_GAP)
        end
    end
end

--- Re-pin only while the window is still where PositionWindow put it; a
--- dragged window (anchor rewritten to UIParent) stays put.
function CaveRenderer:Repin()
    if window and window:IsShown() and select(2, window:GetPoint()) == pinnedTo then
        PositionWindow()
    end
end

--- The window sits one strata above the map. Frame level alone can't keep
--- it on top: clicking the map Raise()s it past any fixed level offset, and
--- a kept-open window isn't the map's child, so nothing else would lift it
--- back. A higher strata is immune to that. The map's strata can also
--- change as it opens (windowed/maximised), hence the re-sync on show.
local function SyncWindowLayer()
    window:SetFrameStrata(Config:StrataAbove(WorldMapFrame:GetFrameStrata()))
    window:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 800)
end

-------------------------------------------------------------------------------
-- Gamepad
--
-- Native gamepad UI only, and only while the map is open with the cave window
-- up (a kept-open window must not hold these buttons during play: shoulders
-- and triggers are the action-bar modifiers). Plain override bindings onto
-- addon-owned buttons, never Blizzard's gamepad binding stack: driving that
-- from addon code is what taints it. Pan is left to the map cursor's sticks;
-- zoom is about the window centre. Closing/reopening is the "Toggle cave
-- window" key binding (Bindings.xml), assignable to a pad button.
-------------------------------------------------------------------------------
local PAD_ACTIONS = {
    PADLSHOULDER = function() StepFloor(-1) end,  -- up a floor
    PADRSHOULDER = function() StepFloor(1) end,   -- down a floor
    PADLTRIGGER  = function() ZoomBy(1 / ZOOM_STEP, true) end,
    PADRTRIGGER  = function() ZoomBy(ZOOM_STEP, true) end,
    PADRSTICK    = function() ResetViewTransform() end,
}
local padOwner

local function SyncGamepadBindings()
    if InCombatLockdown() then return end  -- retried on PLAYER_REGEN_ENABLED
    if not padOwner then
        padOwner = CreateFrame("Frame")
        padOwner:SetScript("OnEvent", SyncGamepadBindings)
        padOwner:RegisterEvent("PLAYER_REGEN_ENABLED")
        for key, fn in pairs(PAD_ACTIONS) do
            local btn = CreateFrame("Button", "HFWMForeverPad" .. key, padOwner)
            btn:RegisterForClicks("AnyDown")
            btn:SetScript("OnClick", fn)
        end
    end
    ClearOverrideBindings(padOwner)
    if mapOpen and window and window:IsShown() and Config:IsGamepadUI() then
        for key in pairs(PAD_ACTIONS) do
            SetOverrideBindingClick(padOwner, false, key, "HFWMForeverPad" .. key)
        end
    end
end

function CaveRenderer:SetMapOpen(open)
    mapOpen = open
    SyncGamepadBindings()
    if open then
        mapSeen = true
        if window then
            SyncWindowLayer()
            C_Timer.After(0, function() if mapOpen then SyncWindowLayer() end end)
        end
    end
    self:Repin()
end

local function EnsureWindow()
    if window then return end

    -- The standard Ace3 dialog: the "Frame" container widget supplies the
    -- layout, title bar and status bar (repurposed below for the area name
    -- and the floor readout); ApplyGameMenuChrome swaps its retail-style
    -- art for Forever's.
    aceWindow = AceGUI:Create("Frame")
    window    = aceWindow.frame
    window:SetClampedToScreen(true)
    window:EnableMouseWheel(true)
    window:SetMovable(true)
    window:SetResizable(false)

    -- The cave window is intentionally draggable so players can tuck it out
    -- of the way, but the world map reset still works from any right-click
    -- inside the dialog itself.
    aceWindow:EnableResize(false)
    window:Hide()
    window:HookScript("OnShow", SyncGamepadBindings)
    window:HookScript("OnHide", SyncGamepadBindings)

    -- Remember placement: the title bar is the drag handle (AceGUI's own
    -- OnMouseUp has already stopped the move by the time this hook runs).
    -- Stored in UIParent units so it survives the window's scale changing
    -- between parents (see ShowCave).
    aceWindow.titletext:GetParent():HookScript("OnMouseUp", function()
        if Config.db.cavePlacement ~= "remember" then return end
        local r = window:GetEffectiveScale() / UIParent:GetEffectiveScale()
        Config.db.caveWindowPoint = { left = window:GetLeft() * r, top = window:GetTop() * r }
    end)

    ApplyGameMenuChrome()

    -- The library's own bottom-right "Close" text button duplicates the X
    -- this window has always had in its own top-right corner, and unlike
    -- that X it has no way to tell this addon a close is a statement about
    -- *this* cave rather than about the window in general (see the OnClick
    -- handler below, and CaveRenderer:HideCave's own callers). Rather than
    -- give that meaning to a second control, the library's own is hidden.
    for _, child in ipairs({ window:GetChildren() }) do
        if child.GetObjectType and child:GetObjectType() == "Button"
                and child.GetText and child:GetText() == CLOSE then
            child:Hide()
            child:EnableMouse(false)
        end
    end

    local close = CreateFrameTry("Button", nil, window, "UIPanelCloseButton")
    close:SetFrameLevel(window:GetFrameLevel() + 10)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -5, -6)
    closeBtn = close
    if not close:GetNormalTexture() then
        -- No close-button template on this client: draw an x of our own
        -- rather than leave an invisible hit area.
        local x = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        x:SetPoint("CENTER")
        x:SetText("x")
        close:SetScript("OnEnter", function() x:SetTextColor(1, 0.4, 0.4) end)
        close:SetScript("OnLeave", function() x:SetTextColor(1, 0.82, 0) end)
    end
    close:SetScript("OnClick", function()
        -- A close is a statement about *this* cave, not about the feature:
        -- suppress it until the player leaves, and leave the setting alone.
        ns.Cave:SuppressCurrent()
        CaveRenderer:HideCave()
        -- Bring the reopen icon in immediately rather than waiting up to
        -- POLL_INTERVAL for the poller to notice the suppression.
        ns.Cave:UpdateState()
    end)

    -- Content: the clipping/zoom-pan area, parented to the Ace3 frame's own
    -- content region (aceWindow.content), which already excludes the
    -- title bar, status bar and border around it. Same role `content` has
    -- always had here; only its parent chain changed.
    content = CreateFrame("Frame", nil, aceWindow.content)
    content:SetPoint("TOPLEFT", aceWindow.content, "TOPLEFT", 0, 0)
    if content.SetClipsChildren then content:SetClipsChildren(true) end

    CaveRenderer:ApplyAlpha()

    -- Zoom/pan canvas; see the "Zoom & pan" section above EnsureWindow.
    -- Sized to match `content` exactly (LayoutWindow keeps the two in sync);
    -- ApplyCanvasTransform is what actually moves and scales it.
    canvasScale = CreateFrame("Frame", nil, content)
    canvasScale:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)

    -- Mouse wheel over the art zooms toward the cursor; left-drag over it
    -- pans. Both are handled here, on `content`, rather than on `window`:
    -- content sits on top of the art, so a press inside it never reaches
    -- anything else, and a press outside it (the header, the border) is
    -- untouched by either of these.
    content:EnableMouse(true)
    content:EnableMouseWheel(true)
    content:SetScript("OnMouseWheel", function(_, dir)
        ZoomBy(dir > 0 and ZOOM_STEP or (1 / ZOOM_STEP))
    end)
    content:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then BeginContentPan() end
    end)
    content:SetScript("OnUpdate", ContentPanUpdate)
    -- Same wheel handler on the window, gated on the cursor being over the
    -- art: covers a wheel event landing on the window rather than `content`.
    window:SetScript("OnMouseWheel", function(_, dir)
        if CursorOverArt() then ZoomBy(dir > 0 and ZOOM_STEP or (1 / ZOOM_STEP)) end
    end)

    -- On canvasScale, not `content`: the pin marks the player's real
    -- position on the underlying map, so it has to zoom and pan with the
    -- art rather than stay fixed in the viewport.
    playerPin = canvasScale:CreateTexture(nil, "OVERLAY", nil, 7)
    playerPin:SetTexture(PIN_TEXTURE)
    playerPin:SetSize(PIN_SIZE, PIN_SIZE)
    playerPin:Hide()

    -- Below the player arrow and the group dots (sublevels 5-7).
    corpsePin = canvasScale:CreateTexture(nil, "OVERLAY", nil, 4)
    corpsePin:SetTexture(CORPSE_TEXTURE)
    corpsePin:SetTexCoord(unpack(CORPSE_TEXCOORDS))
    corpsePin:SetSize(CORPSE_PIN_SIZE, CORPSE_PIN_SIZE)
    corpsePin:Hide()

    PositionWindow()
    ResetView:HookFrame(window, function(_, button)
        if button ~= "RightButton" then return end
        PositionWindow()
        -- Shift+right-click is the anti-lost gesture: snap the cave
        -- window's own zoom/pan back to the fitted view. Only this view;
        -- the world map is left alone.
        if IsShiftKeyDown() then
            ResetViewTransform()
        end
    end, true)

    -- Kept for /hfwm debug and for the test harness, which asserts on what is
    -- actually on the window rather than on what it recomputes. titletext/
    -- statustext are AceGUI's own FontStrings (see aceWindow:SetTitle/
    -- SetStatusText in ShowCave below), not ones this file builds itself.
    Config.caveOverlayFrame  = window
    Config.caveContentFrame  = content
    Config.caveTitleText     = aceWindow.titletext
    Config.caveFloorText     = aceWindow.statustext
    Config.cavePlayerPin     = playerPin

    -- The status bar's own background pane, so it (and not just its text)
    -- can be hidden outright when "All" floors is selected; see ShowCave.
    statusbg = aceWindow.statustext:GetParent()
end

-------------------------------------------------------------------------------
-- Layout
-------------------------------------------------------------------------------

--- Which art layer the cave window draws, as index and descriptor.
---
--- Asked of ns.Cave rather than C_Map, because on this build C_Map has no
--- answer: its UiMap table carries no interior rows at all, and the layer
--- comes from the table CaveData.lua ships instead. Cave picks the source;
--- everything here needs is that the descriptor has the same four fields
--- either way.
---
--- Only the base layer is ever used. Where C_Map does answer it can return
--- more than one layer, and the extra ones are *zoom detail* levels: the
--- same map extent re-cut at a higher tile resolution, each carrying the
--- canvas scale range it applies to. The world map canvas swaps between
--- them as it zooms. This window's own zoom (see the "Zoom & pan" section
--- above EnsureWindow) magnifies whichever layer is already drawn rather
--- than swapping to a sharper one as the user zooms in: layer 1, the
--- full-extent base layer, is still the one it asks for at every zoom
--- level. Wiring RenderTiles to re-fetch a detail layer's own tiles each
--- time zoomScale crosses a threshold is a real option for later; today it
--- would multiply the tile count for art this addon doesn't control the
--- resolution of to begin with (see the FDID/bundled-art fallback below),
--- for sharpness only visible past MAX_ZOOM's midpoint. So the simpler
--- fixed-layer-then-magnify approach is what ships.
---
--- Renderer.lua's IsSubmerged() swap to layer 2 is a separate mechanism for
--- Vashj'ir's paired surface and underwater art, which is Cataclysm-only
--- and which Config.VASHJIR_MAPS is deliberately empty of on this client.
--- Caves have no such pairs, so keying the cave window's layer off
--- IsSubmerged() only ever picked a detail layer by accident, and did it in
--- RenderTiles while the aspect ratio was still being read from layer 1,
--- which stretched the art whenever the two layers were not cut to the
--- same proportions.
---
--- One function, so the shape of the box and the tiles that go in it can
--- never again come from different layers.
---@param floorMapID number|nil
---@return number|nil layerIdx, table|nil layer
local function ArtLayer(floorMapID)
    return ns.Cave:GetArtLayer(floorMapID)
end

--- The cave art's own proportions, so the window is the shape of the cave
--- rather than the shape of the canvas.
local function ArtAspect(floorMapID)
    local _, layer = ArtLayer(floorMapID)
    if not layer or not layer.layerWidth or not layer.layerHeight
       or layer.layerHeight == 0 then
        return 1
    end
    return layer.layerWidth / layer.layerHeight
end

--- Size the window from the art's aspect ratio, clamped so it always leaves
--- the world map visible around it. Returns content width and height.
local function LayoutWindow(floorMapID)
    local aspect = ArtAspect(floorMapID)
    local mapW, mapH = WorldMapFrame:GetSize()
    if not mapW or mapW <= 0 then mapW, mapH = 1024, 768 end

    -- Window scale preference (Options slider): a multiplier on the box the
    -- fractions below compute, so the same setting works on every map size.
    local scale = Config:CaveWindowScale()
    local maxW = math.max(MIN_CONTENT,
        math.min(MAX_CONTENT, mapW * MAP_FRACTION_W * scale))
    local maxH = math.max(MIN_CONTENT,
        math.min(MAX_CONTENT, mapH * MAP_FRACTION_H * scale))

    -- Fit inside the box, preserving aspect.
    local w, h = maxW, maxW / aspect
    if h > maxH then
        h = maxH
        w = maxH * aspect
    end

    -- A single-floor place with active pieces (Echo Ridge Mine, e.g.) still
    -- gets the gutter: SyncSlider shows it for exactly that case too (see
    -- its own comment), and this must agree or the column it shows would
    -- have no room reserved for it and overhang the window's left edge.
    local hasSlider = FloorCount() > 1 or piecesActive
    -- +2 for the gap sliderCol is anchored with below, so the gutter is wide
    -- enough to hold the whole column instead of letting it overhang the
    -- left border by that gap.
    local gutter    = hasSlider and (SLIDER_COL_W + 2) or 0

    -- Multi-floor places carry the floor picker above the art, not over it:
    -- EnsureFloorPicker anchors the picker's BOTTOM to content's TOP, and
    -- content is dropped by the picker's own height so the two meet.
    -- Single-floor: no picker, no pad, art stays flush with the top.
    local topPad = 0
    if FloorCount() > 1 then
        EnsureFloorPicker()
        if floorPicker then topPad = floorPicker:GetHeight() end
    end
    content:ClearAllPoints()
    -- Shifted right by the gutter: the slider column sits to the *left* of
    -- the art (see the sliderCol anchor below), so its room has to be
    -- carved out of content's own left edge here rather than added past
    -- the right one.
    content:SetPoint("TOPLEFT", aceWindow.content, "TOPLEFT", gutter, -topPad)
    contentW, contentH = w, h
    content:SetSize(w, h)
    -- canvasScale tracks content's own size exactly, so RenderTiles and
    -- RenderContinuousPieces can read canvasScale:GetSize() for the plain,
    -- zoom-unaware pixel math they've always done. Since w/h can change
    -- floor to floor (each art layer has its own aspect ratio) or on a
    -- world map resize, the previous pan is re-clamped against the new
    -- size rather than left pointing at a now-invalid offset.
    if canvasScale then
        canvasScale:SetSize(w, h)
        ClampPan()
        ApplyCanvasTransform()
        -- zoomAnchorX/Y (see ZoomBy) are canvas-local coordinates measured
        -- against *this* w/h; a resize invalidates them, so the next wheel
        -- notch samples a fresh anchor instead of centering a point that
        -- meant something under the old layout.
        zoomAnchorX, zoomAnchorY = nil, nil
    end

    -- The Ace3 dialog frame reserves a fixed amount of its own chrome
    -- (title bar, status bar, border; see ACE_FRAME_WIDTH_OVERHEAD/
    -- ACE_FRAME_TOP_INSET/BOTTOM_INSET) around the content region it hands
    -- back, so the frame is sized from the content this window actually
    -- needs -- the art itself plus the depth-slider gutter beside it --
    -- rather than the other way around.
    --
    -- The bottom inset shrinks when the status pane has nothing to show
    -- (see StatusBarNeeded/ShowCave): `.content`'s own BOTTOMRIGHT point is
    -- re-anchored here to match, overriding the library's fixed one, so the
    -- window's own height (and the empty gap that pane would otherwise
    -- leave behind) shrinks and grows right along with it.
    local bottomInset = StatusBarNeeded() and ACE_FRAME_BOTTOM_INSET_STATUS
        or ACE_FRAME_BOTTOM_INSET_NO_STATUS
    aceWindow.content:ClearAllPoints()
    aceWindow.content:SetPoint("TOPLEFT", window, "TOPLEFT", 17, -ACE_FRAME_TOP_INSET)
    aceWindow.content:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -17, bottomInset)

    aceWindow:SetWidth(w + gutter + ACE_FRAME_WIDTH_OVERHEAD)
    aceWindow:SetHeight(h + topPad + ACE_FRAME_TOP_INSET + bottomInset)
    PositionWindow()

    if hasSlider then
        EnsureSlider()
        sliderCol:ClearAllPoints()
        sliderCol:SetPoint("TOPRIGHT", content, "TOPLEFT", -2, 0)
        -- Height set outright as well as anchored: LayoutHeightWindow needs the
        -- number this frame, and an anchor-derived size is not guaranteed to
        -- be readable yet.
        sliderCol:SetSize(SLIDER_COL_W, h)
        sliderTrack:SetHeight(h)
    elseif sliderCol then
        sliderCol:Hide()
    end

    return w, h
end

-------------------------------------------------------------------------------
-- Player pin
-------------------------------------------------------------------------------
--- Shown at the player's real position on whichever floor
--- ns.Cave:GetCurrentFloorMapID() resolves as current, but only when that
--- matches the floor picker's own selection *and* the resolution actually
--- says so with confidence. With the picker on "All"
--- (Config.caveFloorFilterAll), every floor is layered together and there
--- is no single floor to be wrong about, so the pin always shows, same as
--- before this gate existed. With one floor picked out
--- (Config.caveCurrentFloorMapID), a pin drawn on a floor the player isn't
--- standing on would be a lie, so it hides instead, but only once
--- GetCurrentFloorMapID's second return says the mismatch is real.
---
--- That second return exists because of a case this gate got wrong before
--- it existed: Fargodeep Mine's upper and lower floors overlap almost
--- entirely in the shaft, and with no working elevation signal
--- (UnitPosition's Z is a documented, permanent placeholder that is always
--- 0; see PlayerWorldXY in CaveTable.lua) there is no way to tell them
--- apart from position alone. FindPlayerFloor's ambiguous-match fallback
--- (CaveTable.lua's FloorForPosition) defers to whichever floor is already
--- on screen, which is exactly Config.caveCurrentFloorMapID, the same
--- value this gate compares against. Comparing the two directly made the
--- check tautological: it always matched, so the pin never hid in
--- Fargodeep no matter which floor was picked or where the player actually
--- was. `confident` is false on exactly that deferral (and on the
--- smallest-rectangle fallback, another guess rather than a fix), so
--- gating on it too keeps the hide/show behaviour for places position
--- genuinely discriminates between floors (Gnomeregan's four levels, say)
--- without resurrecting Fargodeep's false negatives.
local function UpdatePlayerPin()
    if not playerPin then return end

    local playerFloorMapID, confident = ns.Cave:GetCurrentFloorMapID()
    if not playerFloorMapID then playerPin:Hide() return end

    if confident and not Config.caveFloorFilterAll
            and Config.caveCurrentFloorMapID
            and playerFloorMapID ~= Config.caveCurrentFloorMapID then
        -- A specific floor is picked, it isn't this one, and we actually
        -- know that rather than guessing.
        playerPin:Hide()
        return
    end

    local x, y = ns.Cave:GetPlayerMapXY(playerFloorMapID)
    if not x or not y or (x == 0 and y == 0) then
        -- (0,0) is the API's way of saying "no fix in this map's space".
        playerPin:Hide()
        return
    end

    -- canvasScale, not content: the pin is parented there (see EnsureWindow)
    -- so it zooms and pans with the art instead of staying fixed in the
    -- viewport, but the two share the same logical size (LayoutWindow keeps
    -- them in sync), so this fractional math is unchanged.
    local w, h = canvasScale:GetSize()
    if w <= 0 or h <= 0 then playerPin:Hide() return end

    playerPin:ClearAllPoints()
    playerPin:SetPoint("CENTER", canvasScale, "TOPLEFT", x * w, -(y * h))
    -- WoW facing and Texture:SetRotation both turn counter-clockwise for
    -- positive values, so facing is used as-is. Negating it, as this used
    -- to, was the bug an in-game check caught: north/south are their own
    -- negatives mod 2*pi, so facing 0 and pi rotate the same way under
    -- either sign and looked fine, while east/west landed mirrored: turn
    -- left and the arrow swung right, turn right and it swung left.
    --
    -- Nil while the camera is mid-transition (taxi, cinematic); point the
    -- arrow north rather than erroring in an OnUpdate.
    local facing = GetPlayerFacing()
    playerPin:SetRotation(facing or 0)
    playerPin:SetAlpha(1)
    playerPin:Show()
end

--- Dots for every other group member whose position lands on the displayed
--- floor. Z is unknowable for them (see PlayerWorldXY), so on the baked
--- source "lands on the floor" is the footprint test alone.
local function UpdateGroupPins()
    local used = 0
    local floorID = Config.caveCurrentFloorMapID or ns.Cave:GetCurrentFloorMapID()
    local w, h = canvasScale:GetSize()
    if floorID and w > 0 and h > 0 then
        local prefix, count = "party", 4
        if IsInRaid() then prefix, count = "raid", 40 end
        for i = 1, count do
            local unit = prefix .. i
            if UnitExists(unit) and not UnitIsUnit(unit, "player") then
                local x, y = ns.Cave:GetPlayerMapXY(floorID, unit)
                if x and y and not (x == 0 and y == 0) then
                    used = used + 1
                    local pin = groupPins[used]
                    if not pin then
                        local function dot(sublevel, size, r, g, b)
                            local t = canvasScale:CreateTexture(nil, "OVERLAY", nil, sublevel)
                            t:SetColorTexture(r, g, b)
                            t:SetSize(size, size)
                            local mask = canvasScale:CreateMaskTexture()
                            mask:SetTexture(GROUP_PIN_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                            mask:SetAllPoints(t)
                            t:AddMaskTexture(mask)
                            return t
                        end
                        pin = dot(6, GROUP_PIN_SIZE, 1, 1, 1)
                        pin.border = dot(5, GROUP_PIN_SIZE + 2 * GROUP_PIN_BORDER, 0, 0, 0)
                        groupPins[used] = pin
                        ApplyPinScale()
                    end
                    local _, class = UnitClass(unit)
                    local c = RAID_CLASS_COLORS[class] or GROUP_PIN_FALLBACK
                    pin:SetVertexColor(c.r, c.g, c.b)
                    pin:ClearAllPoints()
                    pin:SetPoint("CENTER", canvasScale, "TOPLEFT", x * w, -(y * h))
                    pin:Show()
                    pin.border:ClearAllPoints()
                    pin.border:SetPoint("CENTER", pin, "CENTER")
                    pin.border:Show()
                end
            end
        end
    end
    HideGroupPins(used + 1)
end

--- The player's corpse, on the displayed floor (same footprint test as the
--- group dots, for the same reason: no Z to say which floor it's on).
local function UpdateCorpsePin()
    if not UnitIsDeadOrGhost("player") then corpsePin:Hide() return end
    local floorID = Config.caveCurrentFloorMapID or ns.Cave:GetCurrentFloorMapID()
    local x, y = ns.Cave:GetCorpseMapXY(floorID)
    local w, h = canvasScale:GetSize()
    if not x or not y or (x == 0 and y == 0) or w <= 0 or h <= 0 then
        corpsePin:Hide()
        return
    end
    corpsePin:ClearAllPoints()
    corpsePin:SetPoint("CENTER", canvasScale, "TOPLEFT", x * w, -(y * h))
    corpsePin:Show()
end

local pinAccum = 0
local function OnWindowUpdate(_, elapsed)
    if not Config.caveOverlayActive then return end
    pinAccum = pinAccum + elapsed
    if pinAccum < PIN_UPDATE_INTERVAL then return end
    pinAccum = 0
    UpdatePlayerPin()
    UpdateGroupPins()
    UpdateCorpsePin()
end

-------------------------------------------------------------------------------
-- Tile rendering
--
-- Mirrors Renderer.lua's layout maths, against the content frame rather than
-- the map canvas. Cave and dungeon art is not in the bundled tile set (the
-- pipeline stitches outdoor zones), so in practice every lookup below misses
-- and the client's own FileDataIDs are drawn. The lookup is done anyway so
-- that a future art pass covering interiors needs no change here.
-------------------------------------------------------------------------------
---@param floorMapID number
---@param sublevel number|nil  ARTWORK draw sublevel (-8..7); defaults to 3.
--- Only ever varied by RenderContinuousFloors, so that a shallower floor's
--- tiles paint over a deeper floor's while both are partially visible in a
--- crossfade; a single floor's tiles never need to stack against anything.
---@param group table|nil  when given, also collects each acquired texture
--- here so the caller can drive this floor's alpha independently
--- (the continuous crossfade path); omitted for the ordinary single-floor
--- render, which drives every tile via `activeCaveTiles` as a whole.
function CaveRenderer:RenderTiles(floorMapID, sublevel, group)
    if not content or not canvasScale then return end

    -- canvasScale, not content: same logical size (LayoutWindow keeps them
    -- in sync) but this is the frame the tiles actually get parented to and
    -- anchored against below, and canvasScale is what zoom/pan transforms.
    local canvasW, canvasH = canvasScale:GetSize()
    if canvasW <= 0 or canvasH <= 0 then return end

    local layerIdx, layer = ArtLayer(floorMapID)
    if not layer then
        if Config.tracing then
            P("CaveRenderer: no art layers for mapID " .. tostring(floorMapID))
        end
        return false
    end

    local layerW   = layer.layerWidth
    local layerH   = layer.layerHeight
    local tilePxW  = layer.tileWidth  or 256
    local tilePxH  = layer.tileHeight or 256
    local cols     = math.ceil(layerW / tilePxW)
    local rows     = math.ceil(layerH / tilePxH)

    local fdids = ns.Cave:GetArtTextures(floorMapID, layerIdx)
    if not fdids or #fdids == 0 then
        if Config.tracing then
            P("CaveRenderer: no FDIDs for mapID " .. tostring(floorMapID))
        end
        return false
    end

    local FDID_MAP  = Config:GetTileMap(Config:GetBackground())
    local FDID_BASE = Config.FDID_BASE

    local scaleX = canvasW / layerW
    local scaleY = canvasH / layerH
    local tileIdx = 1

    lastRenderInfo = {
        floorMapID = floorMapID,
        layerW = layerW, layerH = layerH,
        tileW = tilePxW, tileH = tilePxH,
        cols = cols, rows = rows,
        tiles = {},
    }

    for row = 0, rows - 1 do
        for col = 0, cols - 1 do
            local fdid = fdids[tileIdx]
            if not fdid then break end

            local comp = Config:GetCaveComposite(fdid)
            if comp then
                lastRenderInfo.tiles[tileIdx] = {
                    fdid = fdid, bundled = false, src = "client composite",
                }
                DrawComposite(comp, scaleX, scaleY,
                    col * tilePxW * scaleX, row * tilePxH * scaleY,
                    sublevel, group)
            else
                local rel = FDID_MAP[fdid]
                local src = rel and (FDID_BASE .. rel) or fdid

                lastRenderInfo.tiles[tileIdx] = {
                    fdid = fdid, bundled = (rel ~= nil), rel = rel, src = src,
                }

                local artTileW = math.min(tilePxW, layerW - col * tilePxW)
                local artTileH = math.min(tilePxH, layerH - row * tilePxH)

                local tex = PoolAcquire(group)
                tex:SetDrawLayer("ARTWORK", sublevel or 3)
                tex:SetSize(artTileW * scaleX, artTileH * scaleY)
                tex:SetPoint("TOPLEFT", canvasScale, "TOPLEFT",
                    col * tilePxW * scaleX, -(row * tilePxH * scaleY))
                tex:SetTexCoord(0, artTileW / tilePxW, 0, artTileH / tilePxH)
                tex:SetTexture(src, "CLAMP", "CLAMP")
            end
            tileIdx = tileIdx + 1
        end
    end

    if group then return #group > 0 end
    return #activeCaveTiles > 0
end

--- Render every floor of a shared-canvas place at once, as opposed to
--- RenderTiles's usual one-floor-at-a-time, so UpdateContinuousAlphas has
--- something to crossfade between as the depth slider moves. Only called
--- when ns.Cave:HasContinuousDepth(floorMapID) is true (currently just
--- Fargodeep Mine); every other multi-floor cave keeps the plain
--- RenderTiles hard-swap.
---@param floors table[]  Config.caveAllFloors, topmost first
---@return boolean anyDrew
function CaveRenderer:RenderContinuousFloors(floors)
    local n = #floors
    local anyDrew = false
    for i, floor in ipairs(floors) do
        local group = {}
        -- ARTWORK sublevels run -8..7. Shallower floors (low i) get the
        -- higher sublevel so they always paint over deeper ones for as long
        -- as both are partially visible during a fade.
        local sublevel = math.max(-8, math.min(7, 3 + (n - i)))
        local drew = self:RenderTiles(floor.mapID, sublevel, group)
        if drew then anyDrew = true end
        continuousTileGroups[i] = { mapID = floor.mapID, textures = group, alpha = 1 }
    end
    return anyDrew
end

--- Push per-floor alpha out to every continuous tile group, from a
--- fractional floor index (1 = topmost, matching FloorIndex; see
--- ValueToFractionalIndex). This is the whole of what dragging the slider
--- does while continuousActive; it never tears down or re-renders the tiles
--- themselves. The player pin no longer fades with the displayed floor
--- (see UpdatePlayerPin), so it isn't touched here.
function CaveRenderer:UpdateContinuousAlphas(fractionalIndex)
    for i, grp in ipairs(continuousTileGroups) do
        local alpha = ContinuousAlpha(i, fractionalIndex)
        grp.alpha = alpha
        for _, tex in ipairs(grp.textures) do
            tex:SetAlpha(alpha)
        end
    end
end

--- Per-floor alpha from the most recent continuous render, for /hfwm debug.
--- Returns nil outside continuous mode.
function CaveRenderer:DebugContinuous()
    if not continuousActive then return nil end
    return continuousTileGroups
end

--- Float slop for PieceInFloor's containment test, comfortably smaller
--- than the gap between Fargodeep's two floors' ranges at their nearest
--- point (Lower Mines tops out at 23.50, Upper's own floor starts at
--- 14.27, sharing that whole band; see PieceInFloor) while still forgiving
--- a hand-typed CaveData.lua value that is a hair off its source.
local PIECE_FLOOR_EPSILON = 0.1

--- Does `piece`'s own real-world-Z range (its baked zMin/zMax; see
--- CaveData.lua's Fargodeep `pieces` entries) sit entirely inside `floor`'s?
---
--- This is an exact test today, not a heuristic: a floor's own zMin/zMax is
--- *defined* as the min/max spanned by exactly the WMO groups baked into
--- that floor (hfwm/caves/wmo.py's world_z_range_for_groups, run once
--- over `upper_idx`/`lower_idx` for the floors and again per-group for the
--- pieces; see split_floors_by_height), so every one of Fargodeep's 21
--- pieces lands fully inside exactly one floor's range and never straddles
--- both. Checked by hand against every piece in CaveData.lua before this
--- was trusted (see the code review that added this function): none is
--- ambiguous.
---
--- Returns true (include, don't filter out) when either side has nothing to
--- compare: a future place with pieces but no per-floor zMin/zMax baked yet
--- degrades to showing extra art rather than silently losing a room.
---@param piece table  { zMin, zMax, ... } from ns.Cave:GetPieces
---@param floor table  an entry from Config.caveAllFloors
---@return boolean
local function PieceInFloor(piece, floor)
    if not (floor and floor.zMin and floor.zMax) then return true end
    if not (piece.zMin and piece.zMax) then return true end
    return piece.zMin >= floor.zMin - PIECE_FLOOR_EPSILON
       and piece.zMax <= floor.zMax + PIECE_FLOOR_EPSILON
end

--- Restrict a place's whole per-piece art list (every room, every floor) to
--- just the one floor's worth the floor picker (see the "Floor picker"
--- section below) currently has selected, or hand the list back untouched
--- when the picker is set to "All", which is today's default and the only
--- behaviour this place had before the picker existed.
---
--- Called from ShowCave before RenderContinuousPieces, so piecesZMin/
--- piecesZMax (set from whatever list actually gets drawn) come out scoped
--- to one floor too, which is what makes the depth slider's own range
--- independent per floor rather than always spanning the whole place. See
--- ElevationForValue and HeightWindowElevationBounds, neither of which
--- needed to change, because both already just read piecesZMin/piecesZMax.
---@param pieces table[]|nil  ns.Cave:GetPieces's full list for the place
---@param floors table[]|nil  Config.caveAllFloors
---@param floorMapID number|nil  the floor currently on screen
---@return table[]|nil
local function FilterPiecesByFloor(pieces, floors, floorMapID)
    if Config.caveFloorFilterAll or not floors or not pieces then
        return pieces
    end

    local floor
    for _, f in ipairs(floors) do
        if f.mapID == floorMapID then floor = f break end
    end
    if not floor or not floor.zMin or not floor.zMax then return pieces end

    local out = {}
    for _, piece in ipairs(pieces) do
        if PieceInFloor(piece, floor) then
            out[#out + 1] = piece
        end
    end
    -- An empty result means the containment test above didn't recognise
    -- anything as belonging to this floor (a future place's data doesn't
    -- cleanly partition the way Fargodeep's does). Showing everything is
    -- a better failure than showing nothing.
    return #out > 0 and out or pieces
end

--- cave-satellite-v2 Phase 2: draw every piece of a per-piece place at once,
--- each as its own full-canvas texture, baked to the exact same shared
--- canvas as the old floor composites (see hfwm/caves's
--- generate_mine_pieces), so UpdatePieceWindowAlphas has something to
--- fade independently as the height-window rectangle moves or resizes. Only
--- called when ns.Cave:GetPieces(floorMapID) returns a non-empty list
--- (currently just Fargodeep Mine).
---@param pieces table[]  from ns.Cave:GetPieces, each {fdid, zMin, zMax, ...}
---@param pieceCanvasW number|nil  the canvas the pieces were baked to; only
--- used to sanity-check that there is one to draw, since the content frame
--- is already sized to this same canvas's aspect ratio via LayoutWindow's
--- ArtAspect (pieces share the floor art layer's dimensions by design).
---@param pieceCanvasH number|nil
---@return boolean anyDrew
function CaveRenderer:RenderContinuousPieces(pieces, pieceCanvasW, pieceCanvasH)
    if not content or not canvasScale then return false end
    if not pieceCanvasW or pieceCanvasW <= 0
       or not pieceCanvasH or pieceCanvasH <= 0 then
        return false
    end

    -- canvasScale, not content; see the same note in RenderTiles above.
    local canvasW, canvasH = canvasScale:GetSize()
    if canvasW <= 0 or canvasH <= 0 then return false end

    local FDID_MAP  = Config:GetTileMap(Config:GetBackground())
    local FDID_BASE = Config.FDID_BASE
    local n         = #pieces

    piecesZMin, piecesZMax = nil, nil
    local anyDrew = false

    for order, piece in ipairs(pieces) do
        local comp = Config:GetCaveComposite(piece.fdid)

        -- Paint order: a piece with a higher ceiling paints over one with a
        -- lower ceiling for as long as both are partially visible, spread
        -- across every ARTWORK sublevel (-8..7) rather than one per piece,
        -- since there can be (and with Fargodeep, are) more pieces than
        -- sublevels.
        local sublevel = 3
        if n > 1 then
            sublevel = math.floor(-8 + (order - 1) / (n - 1) * 15 + 0.5)
            sublevel = math.max(-8, math.min(7, sublevel))
        end

        local textures
        if comp then
            textures = DrawComposite(
                comp, canvasW / comp.w, canvasH / comp.h, 0, 0, sublevel)
        else
            local rel = FDID_MAP[piece.fdid]
            local tex = PoolAcquire()
            tex:SetDrawLayer("ARTWORK", sublevel)
            tex:SetSize(canvasW, canvasH)
            tex:SetPoint("TOPLEFT", canvasScale, "TOPLEFT", 0, 0)
            tex:SetTexture(rel and (FDID_BASE .. rel) or piece.fdid, "CLAMP", "CLAMP")
            textures = { tex }
        end

        continuousPieceGroups[order] = {
            textures = textures, zMin = piece.zMin, zMax = piece.zMax, alpha = 1,
        }
        anyDrew = true

        piecesZMin = piecesZMin and math.min(piecesZMin, piece.zMin) or piece.zMin
        piecesZMax = piecesZMax and math.max(piecesZMax, piece.zMax) or piece.zMax
    end

    return anyDrew
end

--- Per-piece alpha from the most recent piece render, for /hfwm debug.
--- Returns nil outside piece mode.
function CaveRenderer:DebugPieces()
    if not piecesActive then return nil end
    return continuousPieceGroups
end

--- Snapshot of the most recent RenderTiles call (layer dims + per-tile FDID
--- lookup results), for /hfwm debug. Returns nil if no floor has been
--- rendered yet this session. In continuous mode this is whichever floor
--- RenderContinuousFloors rendered last (the deepest); see
--- CaveRenderer:DebugContinuous for the other floors' state.
function CaveRenderer:DebugTiles()
    return lastRenderInfo
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

--- Show (or re-render) the cave window on a given floor.
---@param floorMapID number UiMapID of the floor to draw
function CaveRenderer:ShowCave(floorMapID)
    if not floorMapID then return end
    EnsureWindow()

    -- Above every part of the map, including its border frame and pins. The
    -- map's own strata is used rather than a fixed one so the window rides
    -- along when the client moves the map between strata (windowed vs.
    -- maximised), and a large level offset puts it over the map's children.
    -- Keep Open: parented to UIParent instead, so closing the world map
    -- doesn't take the window with it. Still anchored to the map (see
    -- PositionWindow), which keeps its rect while hidden. A UIParent child
    -- stops inheriting the map's scale, so that is applied by hand to keep
    -- the window the same size either way.
    local keepOpen = Config.db and Config.db.caveKeepOpen
    local parent = keepOpen and UIParent or Config:MapWidgetParent()
    if window:GetParent() ~= parent then
        window:SetParent(parent)
    end
    -- Kept-open window before the map has ever been shown this session:
    -- the hidden map's scale is still its unmanaged default, not the one
    -- the client applies on first show, so the window would come up far too
    -- large (most visible with Remember, which opens it at login). Use the
    -- scale seen last time instead; Relayout corrects it on first show.
    if mapOpen then
        mapSeen = true
        Config.db.caveMapScale = WorldMapFrame:GetScale()
    end
    local mapScale = mapSeen and WorldMapFrame:GetScale()
        or Config.db.caveMapScale or WorldMapFrame:GetScale()
    window:SetScale(keepOpen and mapScale or 1)
    SyncWindowLayer()
    PositionWindow()

    -- Normally Cave:UpdateState has already built this, but ShowCave is also
    -- reachable from Relayout and from the slash commands, so it does not
    -- assume.
    if not Config.caveAllFloors then
        Config.caveAllFloors = ns.Cave:BuildFloorList(floorMapID)
    end

    local floors = Config.caveAllFloors
    local n = floors and #floors or 0

    -- cave-satellite-v2 Phase 2: per-piece fading, when the place has piece
    -- data, supersedes the whole-floor crossfade below. It is the
    -- finer-grained replacement for it, not an addition to it, so the two
    -- are mutually exclusive (see the module-state comment above
    -- continuousPieceGroups). Fetched regardless of floor count: a
    -- single-floor place can have pieces too (Echo Ridge Mine does; this
    -- used to read `if n > 1 then`, on the since-outdated assumption that
    -- only a multi-floor place ever would). FilterPiecesByFloor is already
    -- a safe no-op without multiple floors to distinguish between: its
    -- own first check returns `pieces` unchanged whenever
    -- Config.caveFloorFilterAll is true, which it stays at by default when
    -- there's only one floor (SyncFloorPicker hides the picker itself in
    -- that case, but never touches the filter flag).
    local pieces = ns.Cave:GetPieces(floorMapID)
    -- Floor picker (see FilterPiecesByFloor): scoped to one floor's own
    -- pieces when the picker isn't set to "All", which is also what
    -- narrows piecesZMin/piecesZMax, and therefore the depth slider's
    -- whole range, to that floor alone.
    pieces = FilterPiecesByFloor(pieces, floors, floorMapID)
    local pieceCanvasW, pieceCanvasH
    if pieces then
        pieceCanvasW, pieceCanvasH = ns.Cave:GetPieceCanvasSize(floorMapID)
    end
    piecesActive = (pieces ~= nil and #pieces > 0)
    continuousActive = (not piecesActive) and n > 1
        and ns.Cave:HasContinuousDepth(floorMapID)

    PoolReleaseAll()
    LayoutWindow(floorMapID)

    local drew
    if piecesActive then
        drew = self:RenderContinuousPieces(pieces, pieceCanvasW, pieceCanvasH)
    elseif continuousActive then
        drew = self:RenderContinuousFloors(floors)
    else
        drew = self:RenderTiles(floorMapID)
    end
    aceWindow:SetTitle(ns.Cave:GetAreaTitle(floorMapID))
    ApplyGameMenuChrome()

    if n > 1 and not StatusBarNeeded() then
        -- "All" layers every floor together (see InitFloorPickerMenu): with
        -- no single current level to report, the status bar has nothing
        -- useful to say, so it's hidden outright rather than left showing
        -- stale or misleading text. LayoutWindow (above) has already
        -- shrunk the window's own bottom inset to match.
        aceWindow:SetStatusText("")
        if statusbg then statusbg:Hide() end
    elseif n > 1 then
        local idx = FloorIndex(floorMapID) or 1
        local name = floors[idx] and floors[idx].name
        aceWindow:SetStatusText(("Level %d of %d%s"):format(
            idx, n, name and ("  |cff777777" .. name .. "|r") or ""))
        if statusbg then statusbg:Show() end
    elseif drew then
        aceWindow:SetStatusText("|cff777777Single level|r")
        if statusbg then statusbg:Show() end
    else
        aceWindow:SetStatusText("|cffff7777No map art for this area|r")
        if statusbg then statusbg:Show() end
    end

    SyncSlider(floors, floorMapID, continuousActive or piecesActive)
    SyncHeightWindow(piecesActive)
    SyncFloorPicker(floors, floorMapID)
    if piecesActive then
        self:UpdatePieceWindowAlphas()
    elseif continuousActive then
        self:UpdateContinuousAlphas(IndexToValue(FloorIndex(floorMapID) or 1))
    end
    UpdatePlayerPin()

    window:SetAlpha(1)
    self:ApplyAlpha()
    window:Show()

    Config.caveOverlayActive     = true
    Config.caveCurrentFloorMapID = floorMapID
    window:SetScript("OnUpdate", OnWindowUpdate)

    if Config.tracing then
        P(("CaveRenderer:ShowCave mapID=%s tiles=%d floors=%d continuous=%s pieces=%s"):format(
            tostring(floorMapID), #activeCaveTiles, n,
            tostring(continuousActive), tostring(piecesActive)))
    end
end

--- Switch floors without tearing the window down, so the user's scroll
--- through the depth slider does not flicker.
---@param floorMapID number
function CaveRenderer:SelectFloor(floorMapID)
    if not floorMapID then return end
    if not Config.caveOverlayActive then
        self:ShowCave(floorMapID)
        return
    end
    -- Remember that the user drove: Cave:UpdateState must not yank them back
    -- to the floor they are standing on a moment later.
    Config.caveFloorPinned = (floorMapID ~= ns.Cave:GetCurrentFloorMapID())
    self:ShowCave(floorMapID)
end

--- Floor picker: scope the cave map to one floor's own pieces rather than
--- every floor layered together. Hands straight off to SelectFloor, which
--- already does everything a floor change needs (pin, rerender); the
--- picker only adds the filter flag on top of it, so it and the depth
--- slider/mouse-wheel step can never disagree about which floor is current.
---@param floorMapID number
function CaveRenderer:SelectFloorFilter(floorMapID)
    Config.caveFloorFilterAll = false
    self:SelectFloor(floorMapID)
end

--- Floor picker: go back to every floor layered together (the default, and
--- this place's only behaviour before the picker existed). Doesn't change
--- which floor is "current"; only the filter does, so there is nothing
--- here for SelectFloor's pin logic to get involved in.
function CaveRenderer:SelectAllFloors()
    if Config.caveFloorFilterAll then return end
    Config.caveFloorFilterAll = true
    if Config.caveOverlayActive and Config.caveCurrentFloorMapID then
        self:ShowCave(Config.caveCurrentFloorMapID)
    end
end

function CaveRenderer:HideCave()
    Config.caveOverlayActive     = false
    Config.caveCurrentFloorMapID = nil
    Config.caveAllFloors         = nil
    Config.caveFloorPinned       = false
    Config.caveFloorFilterAll    = true
    continuousActive             = false
    piecesActive                 = false
    piecesZMin, piecesZMax       = nil, nil
    heightWindowDrag             = nil
    -- Back to fit-to-window: see the module comment above zoomScale/panX/
    -- panY for why ShowCave itself never resets these, but a closed (and
    -- possibly later reopened, possibly on a different cave entirely)
    -- window should not remember a zoom level from a previous visit.
    ResetViewTransform()
    if windowBody then windowBody:Hide() end
    if floorPicker then floorPicker:Hide() end
    if CloseDropDownMenus then pcall(CloseDropDownMenus) end
    if not window then return end
    PoolReleaseAll()  -- also wipes continuousTileGroups and continuousPieceGroups
    if playerPin then playerPin:Hide() end
    if corpsePin then corpsePin:Hide() end
    HideGroupPins(1)
    window:SetScript("OnUpdate", nil)
    window:Hide()
end

--- Re-run the layout against the current map-frame size. Debounced, because
--- OnSizeChanged fires every frame of a maximise animation and each pass
--- re-renders the whole tile grid.
local relayoutPending = false
function CaveRenderer:Relayout()
    if relayoutPending then return end
    if not (Config.caveOverlayActive and Config.caveCurrentFloorMapID) then
        return
    end
    relayoutPending = true
    C_Timer.After(0.05, function()
        relayoutPending = false
        if Config.caveOverlayActive and Config.caveCurrentFloorMapID then
            self:ShowCave(Config.caveCurrentFloorMapID)
        end
    end)
end

--- Apply the opacity setting to an already-open window: fades every
--- background fill (dialog fill, art backing), never the borders or widgets.
function CaveRenderer:ApplyAlpha()
    LayoutDialogFill()
end

--- Current height-window rectangle state, for /hfwm debug. Returns nil
--- outside piece mode.
function CaveRenderer:DebugHeightWindow()
    if not piecesActive then return nil end
    local top, bottom = Config:CaveHeightWindow()
    local windowBottomZ, windowTopZ = HeightWindowElevationBounds()
    return { top = top, bottom = bottom, zMin = windowBottomZ, zMax = windowTopZ }
end

function CaveRenderer:IsShown()
    return window and window:IsShown() and true or false
end

--- Every tile currently drawn, discrete or continuous: RenderContinuousFloors
--- still acquires each floor's tiles through the same PoolAcquire as
--- RenderTiles, so `activeCaveTiles` already spans all of them and needs no
--- separate continuous-mode count.
function CaveRenderer:ActiveTileCount()
    return #activeCaveTiles
end

function CaveRenderer:IsContinuousActive()
    return continuousActive
end

--- cave-satellite-v2 Phase 2: true while the currently shown place is
--- fading individual pieces by real elevation rather than crossfading whole
--- floors; see the module-state comment above continuousPieceGroups for
--- why the two are mutually exclusive.
function CaveRenderer:IsPiecesActive()
    return piecesActive
end
