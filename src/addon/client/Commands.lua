-------------------------------------------------------------------------------
-- HFWM-Forever Commands
-- Slash command handler (/hfwm, /hfwmforever), registered through
-- AceConsole-3.0.
-------------------------------------------------------------------------------
local addonName, ns = ...
local Commands = ns.Commands
local Config   = ns.Config
local Pool     = ns.Pool
local P        = ns.P

function Commands:Handle(msg)
    local args = { strsplit(" ", strtrim(msg):lower()) }
    local cmd  = args[1] or ""
    local db   = Config.db

    if cmd == "on" or cmd == "enable" then
        db.enabled = true
    elseif cmd == "off" or cmd == "disable" then
        db.enabled = false
    elseif cmd == "cave" then
        local sub = args[2] or ""

        -- "show" is the way back from the close button: the window suppresses
        -- itself per cave when dismissed, and without this the only way to
        -- get it back would be to walk out and back in.
        if sub == "show" or sub == "open" then
            if not ns.Cave:IsEnabledHere() then
                P("The map window is off here. Turn it on under Cave map "
                    .. "or Instance map (beta) in Options.")
            elseif not ns.Cave:ForceShow() then
                P("Nothing to show: you are not in a cave, or the world map "
                    .. "is already showing the one you are in.")
            end
            return
        elseif sub == "hide" or sub == "close" then
            ns.Cave:SuppressCurrent()
            ns.CaveRenderer:HideCave()
            P("Cave map hidden for this area "
                .. "(|cff999999/hfwm cave show|r brings it back).")
            return
        elseif sub == "reset" then
            ns.CaveRenderer:HideCave()
            db.caveWindowPoint = nil
            ns.Cave:Unsuppress()
            ns.Cave:UpdateState()
            P("Cave map reset.")
            return
        elseif sub == "alpha" then
            local val = tonumber(args[3])
            if not val then
                P("Usage: /hfwm cave alpha 0-1.0")
                return
            end
            db.caveAlpha = math.max(0, math.min(1, val))
            ns.CaveRenderer:ApplyAlpha()
            P(("Cave map opacity: %.0f%%"):format(db.caveAlpha * 100))
            ns.Options:Refresh()
            return
        elseif sub == "autoopen" then
            local want = args[3]
            if want == "on" then db.caveAutoOpen = true
            elseif want == "off" then db.caveAutoOpen = false
            else db.caveAutoOpen = not db.caveAutoOpen end
            P(("Cave map auto-open: %s"):format(
                db.caveAutoOpen and "|cff00ff00on|r" or "|cffff4444off|r"))
            ns.Options:Refresh()
            return
        elseif sub == "remember" then
            local want = args[3]
            if want == "on" then db.caveRememberState = true
            elseif want == "off" then db.caveRememberState = false
            else db.caveRememberState = not db.caveRememberState end
            P(("Cave map remember state: %s"):format(
                db.caveRememberState and "|cff00ff00on|r" or "|cffff4444off|r"))
            ns.Options:Refresh()
            return
        elseif sub == "indoors" then
            local want = args[3]
            if want == "on" then db.caveOtherIndoors = true
            elseif want == "off" then db.caveOtherIndoors = false
            else db.caveOtherIndoors = not db.caveOtherIndoors end
            P(("Cave map other indoors: %s"):format(
                db.caveOtherIndoors and "|cff00ff00on|r" or "|cffff4444off|r"))
            ns.Cave:UpdateState()
            ns.Options:Refresh()
            return
        elseif sub == "on" or sub == "enable" then
            db.caveEnabled = true
        elseif sub == "off" or sub == "disable" then
            db.caveEnabled = false
        else
            db.caveEnabled = not db.caveEnabled
        end

        if db.caveEnabled then
            P("|cff00ff00Cave map enabled|r. Opens over the world map when "
                .. "you are somewhere it cannot show.")
            -- On a client with no interior maps the line above is a promise
            -- that will never be kept, so qualify it immediately rather than
            -- leaving the user waiting for a window.
            ns.Cave:WarnIfUnsupported()
            ns.Cave:Unsuppress()
            ns.Cave:UpdateState()
        else
            P("|cffff4444Cave map disabled|r")
            ns.Cave:UpdateState()
        end
        ns.Options:Refresh()
        return
    elseif cmd == "remember" then
        local want = args[2]
        if want == "on" then
            db.rememberMapZoomPan = true
        elseif want == "off" then
            db.rememberMapZoomPan = false
        else
            db.rememberMapZoomPan = not db.rememberMapZoomPan
        end
        if not db.rememberMapZoomPan then
            ns.MapMemory:Clear()
        end
        P(("Remember map zoom+pan: %s"):format(
            db.rememberMapZoomPan and "|cff00ff00on|r" or "|cffff4444off|r"))
        ns.Options:Refresh()
        return
    elseif cmd == "zoom" then
        local want = args[2]
        if want == "on" then
            db.additionalZoomLevels = true
        elseif want == "off" then
            db.additionalZoomLevels = false
        else
            db.additionalZoomLevels = not db.additionalZoomLevels
        end
        ns.ZoomLevels:Refresh()
        P(("Additional zoom levels: %s"):format(
            db.additionalZoomLevels and "|cff00ff00on|r" or "|cffff4444off|r"))
        ns.Options:Refresh()
        return
    elseif cmd == "clarity" then
        local want = args[2]
        if want == "on" then
            db.worldMapClarity = true
        elseif want == "off" then
            db.worldMapClarity = false
        else
            db.worldMapClarity = not db.worldMapClarity
        end
        db.continentMapClarity = db.worldMapClarity
        ns.ZoomLevels:Refresh()
        ns.Renderer:ForceRefresh()
        if db.worldMapClarity and not Config:IsArtInstalled() then
            P("World map clarity: |cffff4444off|r |cffff8800(needs the High "
                .. "Fidelity World Map: Art addon, which is not installed or "
                .. "not enabled)|r")
        else
            P(("World map clarity: %s"):format(
                db.worldMapClarity and "|cff00ff00on|r" or "|cffff4444off|r")
                .. (db.worldMapClarity
                    and " |cff999999(Kalimdor/Eastern Kingdoms/Azeroth at higher "
                        .. "detail, may render a bit slower)|r"
                    or ""))
        end
        ns.Options:Refresh()
        return
    elseif cmd == "cavetitle" then
        local d = ns.CaveRenderer:DebugTitle()
        if not d then
            P("No cave window yet: open a cave first.")
            return
        end
        local function s(v) return v == nil and "nil" or tostring(v) end
        local function list(t) if not t then return "nil" end local o = {} for i = 1, 5 do o[i] = s(t[i]) end return table.concat(o, ", ") end
        P(("title text=%q shown=%s visible=%s alpha=%s eff=%s"):format(
            s(d.text), s(d.shown), s(d.visible), s(d.alpha), s(d.effAlpha)))
        P("  font=" .. s(d.font) .. " size=" .. s(d.size) .. " flags=" .. s(d.flags)
            .. " color=" .. list(d.color))
        P("  point=" .. list(d.point) .. "  rect=" .. list(d.rect))
        P("  window=" .. list(d.windowRect) .. "  levels title/window=" .. list(d.levels))
        P("  header=" .. (d.header and (s(d.header.shown) .. " " .. s(d.header.w) .. "x" .. s(d.header.h)) or "none"))
        return
    elseif cmd == "cavefocus" then
        -- Hover the cave map art after running this: three seconds later it
        -- reports what is under the cursor and the pan/zoom state.
        P("Hover the cave map art; reporting in 3 seconds...")
        C_Timer.After(3, function()
            local d = ns.CaveRenderer:DebugPan()
            if not d then P("No cave window yet: open a cave first.") return end
            local function s(v) return v == nil and "nil" or tostring(v) end
            P(("pan: zoom=%s pan=%s,%s content=%sx%s dragging=%s"):format(
                s(d.zoom), s(d.panX), s(d.panY), s(d.contentW), s(d.contentH), s(d.dragging)))
            P(("content: mouse=%s wheel=%s onMouseDown=%s onUpdate=%s shown=%s visible=%s level=%s window=%s strata=%s"):format(
                s(d.mouse), s(d.wheel), s(d.hasDown), s(d.hasUpdate), s(d.shown),
                s(d.visible), s(d.level), s(d.windowLevel), s(d.strata)))
            local f = (GetMouseFoci and GetMouseFoci()[1]) or (GetMouseFocus and GetMouseFocus())
            if not f then P("under cursor: nothing") return end
            local depth = 0
            while f and depth < 8 do
                local name = f.GetName and f:GetName() or "?"
                local lvl = f.GetFrameLevel and f:GetFrameLevel() or "-"
                P(("  [%d] %s <%s> level=%s%s"):format(depth, s(name),
                    f.GetObjectType and f:GetObjectType() or "?", s(lvl),
                    f == Config.caveContentFrame and "  <-- cave content" or ""))
                f = f.GetParent and f:GetParent() or nil
                depth = depth + 1
            end
        end)
        return
    elseif cmd == "fog" or cmd == "fogofwar" then
        local want = args[2]
        if want == "on" then
            db.fogOfWarEnabled = true
        elseif want == "off" then
            db.fogOfWarEnabled = false
        else
            db.fogOfWarEnabled = not db.fogOfWarEnabled
        end
        ns.Renderer:ForceRefresh()
        P(("Fog of War: %s"):format(
            db.fogOfWarEnabled and "|cff00ff00on|r" or "|cffff4444off|r")
            .. (db.fogOfWarEnabled
                and " |cff999999(shows through unexplored ground; explored "
                    .. "ground still shows this addon's own art)|r"
                or ""))
        ns.Options:Refresh()
        return
    elseif cmd == "bg" or cmd == "background" then
        local want = args[2] or ""
        -- Only what this install can actually draw: "raw" needs the
        -- second, raw tile dump, which a build without --original never wrote.
        local list = Config:AvailableBackgrounds()
        if want == "" then
            -- No argument: cycle, which is what a keybind would want.
            local cur = Config:GetBackground()
            local nxt = list[1]
            for i, bg in ipairs(list) do
                if bg.key == cur.key then
                    nxt = list[i % #list + 1]
                    break
                end
            end
            want = nxt and nxt.key or ""
        end
        local applied = Config:SetBackground(want)
        if applied then
            P(("Map background: |cff33ccff%s|r. %s"):format(
                applied.label, applied.desc))
            ns.Options:Refresh()
        else
            local keys = {}
            for _, bg in ipairs(list) do
                keys[#keys + 1] = bg.key
            end
            P(("Unknown background '%s'. Options: %s"):format(
                want, table.concat(keys, ", ")))
            if not Config:BackgroundAvailable({ tiles = "original" }) then
                P("  (|cff999999raw|r needs the raw tile dump, rebuild "
                    .. "the art with --original)")
            end
        end
        return
    elseif cmd == "baseart" then
        -- Blizzard's own detail layer: the parchment, the sea labels and the
        -- compass rose. Every background but Hybrid hides it, and only
        -- Transparent puts nothing opaque in front, so if the search below
        -- comes back empty, Transparent is the one entry that shows it.
        local BaseArt = ns.BaseArt
        local found = BaseArt:Describe()
        P(("detail layers: %d found, currently %s"):format(
            #found, BaseArt.visible and "shown" or "hidden"))
        for i, line in ipairs(found) do
            print(("  %d. %s"):format(i, line))
        end
        if #found == 0 then
            print("  (none found. open the map first; if the map is open "
                .. "and this is still empty, the client keeps its detail "
                .. "layers somewhere the search does not look)")
        end
        return
    elseif cmd == "framebg" then
        -- What the Transparent background hides, and, when the answer turns
        -- out to be "not enough", what else is down there. The search is by
        -- draw layer and size rather than by name, so a miss is invisible
        -- unless something walks the whole tree and says so.
        local MapFrameBg = ns.MapFrameBg
        local sub = args[2] or ""

        if sub == "all" or sub == "survey" then
            local rows = MapFrameBg:Survey()
            P(("map-frame survey: %d widget(s) under WorldMapFrame"):format(
                #rows))
            print("  reached | alpha shown  layer/sub  owner -> region  = texture")
            for _, r in ipairs(rows) do
                print(("  %s | %.2f %-5s %s/%d  %s -> %s  = %s"):format(
                    r.reached and "YES" or " no", r.alpha,
                    tostring(r.shown), r.layer, r.sublevel,
                    r.owner, r.region, r.tex))
            end
            if #rows == 0 then
                print("  (nothing found, open the map first)")
            end
            return
        elseif sub == "big" then
            -- `all` dumps everything under WorldMapFrame, hundreds of rows
            -- once quest log panels etc. are open, which scrolls straight
            -- out of chat history. This is the same survey, filtered down to
            -- what could plausibly BE the map-frame backing: currently shown
            -- and covering a real fraction of the map frame.
            local wmf = WorldMapFrame
            local fw, fh = wmf and wmf:GetWidth() or 0, wmf and wmf:GetHeight() or 0
            local frac = tonumber(args[3]) or 0.3
            local rows = MapFrameBg:Survey()
            local shown = {}
            for _, r in ipairs(rows) do
                if r.shown and fw > 0 and fh > 0
                    and r.width >= fw * frac and r.height >= fh * frac
                then
                    shown[#shown + 1] = r
                end
            end
            P(("map-frame survey, shown + >= %d%% of frame (%dx%d): %d/%d widget(s)"):format(
                frac * 100, fw, fh, #shown, #rows))
            print("  reached | alpha  size          layer/sub  owner -> region  = texture")
            for _, r in ipairs(shown) do
                print(("  %s | %.2f  %4dx%-4d  %s/%d  %s -> %s  = %s"):format(
                    r.reached and "YES" or " no", r.alpha, r.width, r.height,
                    r.layer, r.sublevel, r.owner, r.region, r.tex))
            end
            if #shown == 0 then
                print("  (nothing shown at that size, try a smaller fraction, "
                    .. "e.g. |cff999999framebg big 0.15|r)")
            end
            return
        elseif sub == "strip" then
            P("navbar strip:")
            for _, line in ipairs(MapFrameBg:DescribeStrip()) do
                print("  " .. line)
            end
            return
        elseif sub == "nuke" then
            -- Not a setting: a bisection tool. If this makes the map
            -- see-through then the backing is in the survey and the ordinary
            -- search can be taught to reach it; if not, nothing in the UI is
            -- what we are looking at.
            local n = MapFrameBg:Nuke()
            P(("hid %d widget(s) under WorldMapFrame. "):format(n)
                .. "|cffff4444/hfwm framebg restore|r puts them back.")
            return
        elseif sub == "restore" then
            P(("restored %d widget(s)."):format(MapFrameBg:Unnuke()))
            return
        end

        local found = MapFrameBg:Describe()
        P(("map-frame backing: %d region(s), currently %s"):format(
            #found, MapFrameBg.visible and "shown" or "hidden"))
        for i, row in ipairs(found) do
            print(("  %d. %s  shown=%s  alpha=%.2f  weHid=%s"):format(
                i, row.name, tostring(row.shown), row.alpha,
                tostring(row.weHid)))
        end
        if #found == 0 then
            print("  (nothing found, open the map first)")
        end
        print("  |cff999999framebg all|r surveys the whole frame tree; "
            .. "|cff999999framebg big|r narrows that to what's shown and "
            .. "large enough to be backing; |cff999999framebg nuke|r hides "
            .. "all of it")
        return
    elseif cmd == "testmask" then
        -- Throwaway diagnostic, not part of the real render path: shows each
        -- live exploration reveal texture's own raw file, full size, with no
        -- masking or slicing, exactly what that file's own alpha channel
        -- looks like on its own. One screenshot settles whether it carries a
        -- real organic/torn shape or is just an ordinary opaque terrain tile.
        local sub = args[2] or ""
        if sub == "off" or sub == "clear" then
            if ns._testMaskTextures then
                for _, tex in ipairs(ns._testMaskTextures) do
                    tex:Hide()
                end
                ns._testMaskTextures = nil
            end
            P("testmask: cleared")
            return
        end

        if not Config.overlayFrame then
            P("testmask: overlay frame not built yet. enable the addon first")
            return
        end

        local textures = ns.Exploration:EnumerateOverlayTextures()
        if not textures or #textures == 0 then
            P("testmask: no live exploration texture(s) found on this map "
                .. "right now")
            return
        end

        if ns._testMaskTextures then
            for _, tex in ipairs(ns._testMaskTextures) do tex:Hide() end
        end
        ns._testMaskTextures = {}

        local shown = 0
        for _, blizTex in ipairs(textures) do
            if blizTex:IsShown() then
                local left, top = blizTex:GetLeft(), blizTex:GetTop()
                local right, bottom = blizTex:GetRight(), blizTex:GetBottom()
                local file = blizTex:GetTexture()
                if left and top and right and bottom and file then
                    local tex = Config.overlayFrame:CreateTexture(
                        nil, "OVERLAY", nil, 7)
                    tex:SetTexture(file)
                    tex:SetSize(right - left, top - bottom)
                    tex:SetPoint(
                        "BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
                    tex:Show()
                    table.insert(ns._testMaskTextures, tex)
                    shown = shown + 1
                end
            end
        end
        P(("testmask: showing %d raw reveal file(s), unmasked and "
            .. "un-sliced. Look for parchment showing through in an "
            .. "organic/torn shape (real reveal mask) vs. a plain solid "
            .. "rectangle (ordinary terrain tile). "
            .. "|cff999999/hfwm testmask off|r removes them."):format(shown))
        return
    elseif cmd == "icon" then
        -- Diagnostic for ToggleButton.lua: prints exactly which texture
        -- file (and, for an atlas, which sub-region of which shared sheet)
        -- backs WorldMapFrame.SidePanelToggle.OpenButton's own artwork, so
        -- it can be pulled out and edited rather than guessed at from a
        -- file listing -- atlases pack dozens of icons into one shared
        -- sheet, so a file name alone isn't enough to find just this one.
        local wmf = WorldMapFrame
        local sidePanelToggle = wmf and wmf.SidePanelToggle
        local reference = sidePanelToggle and sidePanelToggle.OpenButton
        if not reference then
            P("icon: WorldMapFrame.SidePanelToggle.OpenButton not found "
                .. "on this client (open the map first)")
            return
        end

        local function describe(label, tex)
            if not tex then
                print(("  %s: (no texture)"):format(label))
                return
            end
            local ok, atlas = pcall(tex.GetAtlas, tex)
            if ok and atlas then
                print(("  %s: atlas=%s"):format(label, atlas))
                if C_Texture and C_Texture.GetAtlasInfo then
                    local info = C_Texture.GetAtlasInfo(atlas)
                    if info then
                        print(("      file=%s  %dx%d  "
                            .. "L%.4f R%.4f T%.4f B%.4f"):format(
                            tostring(info.file or info.filename),
                            info.width or 0, info.height or 0,
                            info.leftTexCoord or 0, info.rightTexCoord or 0,
                            info.topTexCoord or 0, info.bottomTexCoord or 0))
                    end
                end
            else
                local ok2, file = pcall(tex.GetTexture, tex)
                print(("  %s: file=%s"):format(
                    label, ok2 and tostring(file) or "?"))
            end
        end

        P("icon: WorldMapFrame.SidePanelToggle.OpenButton textures")
        describe("normal", reference.GetNormalTexture and reference:GetNormalTexture())
        describe("pushed", reference.GetPushedTexture and reference:GetPushedTexture())
        describe("highlight", reference.GetHighlightTexture and reference:GetHighlightTexture())
        describe("disabled", reference.GetDisabledTexture and reference:GetDisabledTexture())
        return
    elseif cmd == "padzoom" then
        self:PadZoomDebug()
        return
    elseif cmd == "taint" then
        self:TaintDebug()
        return
    elseif cmd == "legend" then
        self:LegendDebug()
        return
    elseif cmd == "debug" then
        self:Debug()
        return
    elseif cmd == "" then
        db.enabled = not db.enabled
    else
        print("|cff33ccffHigh Fidelity World Map|r commands:")
        print("  /hfwm               - toggle overlay")
        print("  /hfwm on|off        - enable / disable")
        local keys = {}
        for _, bg in ipairs(Config:AvailableBackgrounds()) do
            keys[#keys + 1] = bg.key
        end
        print("  /hfwm bg [NAME]     - map background: "
            .. table.concat(keys, " | ") .. " (no name cycles)")
        print("  /hfwm remember [on|off] - remember world map zoom+pan "
            .. "across close/reopen")
        print("  /hfwm zoom [on|off] - additional (closer) world map zoom "
            .. "levels")
        print("  /hfwm clarity [on|off] - higher-detail Kalimdor/Eastern "
            .. "Kingdoms/Azeroth maps (off by default, may render slower)")
        print("  /hfwm fog [on|off]  - fog of war over unexplored ground "
            .. "(off by default)")
        print("  /hfwm cave [on|off] - toggle the cave map (opt-in)")
        print("                        show/hide, reset, alpha N,")
        print("                        autoopen [on|off], remember [on|off]")
        print("  /hfwm baseart       - Blizzard's detail layer, and whether "
            .. "the search finds it")
        print("  /hfwm framebg       - map-frame backing Transparent hides")
        print("                        (all = survey everything, big = shown"
            .. " + large only, nuke/restore)")
        print("  /hfwm debug         - diagnostic info + force refresh")
        print("  /hfwm testmask [off] - show live reveal texture file(s) "
            .. "raw, unmasked (diagnostic; off removes them)")
        print("  /hfwm icon          - texture/atlas info for the quest-list "
            .. "side-panel toggle button's own artwork")
        return
    end

    if db.enabled then
        P("|cff00ff00Enabled|r")
    else
        P("|cffff4444Disabled|r")
    end
    ns.Renderer:ForceRefresh()
    ns.ToggleButton:Refresh()
    ns.MapLabels:Refresh()
end

function Commands:Debug()
    local bg = Config:GetBackground()
    -- The tile table the active background actually draws from, so every
    -- lookup reported below matches what is on screen.
    local FDID_MAP     = Config:GetTileMap(bg)
    local FDID_MAP_SUB = Config.FDID_MAP_SUB

    -- FDID_MAP health check
    local mapCount = 0
    for _ in pairs(FDID_MAP) do mapCount = mapCount + 1 end
    local subCount = 0
    for _ in pairs(FDID_MAP_SUB) do subCount = subCount + 1 end
    P("debug: FDID_MAP=" .. mapCount .. " entries, FDID_MAP_SUB=" .. subCount
        .. "  enabled=" .. tostring(Config.db and Config.db.enabled))
    print(("  FDID_BASE (low res): %s"):format(Config.FDID_BASE or "nil"))
    print(("  HD_BASE (high res): %s"):format(Config.HD_BASE or "nil"))
    print(("  art addon: %s"):format(Config:IsArtInstalled() and "loaded"
        or "NOT loaded (world/continent maps limited to low resolution)"))
    print(("  tile tables: bundled=%d  original=%d"):format(
        Config._fdidMapSize or -1, Config._fdidMapOriginalSize or -1))
    print(("  native zones: bundled=%d  original=%d"):format(
        Config._nativeZonesSize or -1, Config._nativeZonesOriginalSize or -1))
    local bgHow
    if bg.rgb then
        bgHow = ("#%02X%02X%02X"):format(
            bg.rgb[1] * 255, bg.rgb[2] * 255, bg.rgb[3] * 255)
    elseif bg.blizzardArt then
        bgHow = "Blizzard art"
    elseif bg.seeThrough then
        bgHow = "nothing behind the tiles, map frame backing hidden"
    else
        bgHow = "nothing behind the tiles"
    end
    print(("  background: %s (%s)  tiles=%s  backdrop=%s  baseArtVisible=%s")
        :format(
            bg.key, bgHow, bg.tiles or "bundled",
            Config.backdropTexture
                and tostring(Config.backdropTexture:IsShown()) or "nil",
            tostring(ns.BaseArt.visible)))
    print(("  frame backing: %d region(s) touched, currently %s"):format(
        #ns.MapFrameBg.order,
        ns.MapFrameBg.visible and "shown" or "hidden"))
    print(("  options: registered=%s"):format(
        tostring(ns.Options.clientRegistered)))

    local mapID = WorldMapFrame:GetMapID()
    P("debug: mapID=" .. tostring(mapID)
        .. "  lastMapID=" .. tostring(Config.lastMapID))

    local minimapMapID = C_Minimap and C_Minimap.GetUiMapID and C_Minimap.GetUiMapID()
    local bestMapID = C_Map.GetBestMapForUnit("player")
    local minimapInfo = minimapMapID and C_Map.GetMapInfo(minimapMapID)
    local bestInfo = bestMapID and C_Map.GetMapInfo(bestMapID)
    print(("  minimap mapID: %s (%s)"):format(
        tostring(minimapMapID),
        minimapInfo and minimapInfo.name or "?"))
    print(("  bestMap(player): %s (%s)"):format(
        tostring(bestMapID),
        bestInfo and bestInfo.name or "?"))
    -- Where the cave feature is getting its interiors from. On this build the
    -- client's UiMap has none, so this should read "baked". If it says
    -- "client" while the window refuses to open, look at CaveData.lua, not
    -- C_Map.
    local tableDesc = "not loaded"
    if ns.CaveTable:IsLoaded() then
        local tableBuild = ns.CaveTable:GetBuild()
        -- GetBuildInfo returns version, build, ... ("1.60.1" and "69913"),
        -- and the generator stamps the table with the two joined. A mismatch
        -- is not fatal (the art rarely moves between patches) but it is the
        -- first thing to suspect if tiles come out wrong.
        local version, build = GetBuildInfo()
        local clientBuild = version and build
            and (version .. "." .. build) or nil
        local stale = (tableBuild and clientBuild and tableBuild ~= clientBuild)
        tableDesc = ("%d places, build %s%s"):format(
            ns.CaveTable:CountPlaces(), tostring(tableBuild),
            stale and (" <-- client is " .. clientBuild) or "")
    end
    print(("  cave source: %s  (shipped table: %s)"):format(
        ns.Cave:SourceName(), tableDesc))
    -- Which map the cave feature actually believed, and what it is called:
    -- mapType is the trigger, so this is the first line to read when the
    -- window will not open. Resolved through the same source, since a baked
    -- floor ID means nothing to C_Map.
    local resolved     = ns.Cave:GetCurrentFloorMapID()
    local bakedFloor   = resolved and ns.CaveTable:GetFloor(resolved)
    local resolvedInfo = resolved and (bakedFloor
        and ns.CaveTable:GetMapInfo(resolved)
        or C_Map.GetMapInfo(resolved))
    print(("  resolved floor: %s (%s)  mapType=%s  from=%s"):format(
        tostring(resolved),
        resolvedInfo and resolvedInfo.name or "?",
        resolvedInfo and tostring(resolvedInfo.mapType) or "?",
        bakedFloor and ("shipped table: " .. bakedFloor.place.name)
            or (resolved == bestMapID and "position" or "minimap")))
    local interiors = ns.Cave:CountInteriorMaps()
    print(("  interior maps in this client's map tree: %s%s"):format(
        interiors == nil and "unknown (no API)" or tostring(interiors),
        (interiors == 0 and not ns.CaveTable:IsLoaded())
            and "  <-- and no shipped table, so the window cannot open"
            or ""))
    print(("  minimapZone: %s  subZone: %s"):format(
        tostring(GetMinimapZoneText()), tostring(GetSubZoneText())))
    local hybridMinimap = C_Minimap and C_Minimap.ShouldUseHybridMinimap
        and C_Minimap.ShouldUseHybridMinimap()
    print(("  submerged: %s  outdoors: %s  hybridMinimap: %s"):format(
        tostring(IsSubmerged()), tostring(IsOutdoors()), tostring(hybridMinimap)))
    -- Step-by-step replay of the baked lookup itself. "resolved floor" above
    -- only says it fell back to C_Map; this says which check let go:
    -- instance routing, the outdoors gate, the name index, or the rectangle.
    if ns.CaveTable:IsLoaded() then
        for _, line in ipairs(ns.CaveTable:DebugTrace()) do
            print(line)
        end
    end

    if minimapMapID then
        local groupID = C_Map.GetMapGroupID(minimapMapID)
        if groupID then
            local members = C_Map.GetMapGroupMembersInfo(groupID)
            print(("  mapGroup: %d  floors: %d"):format(
                groupID, members and #members or 0))
            if members then
                for i, m in ipairs(members) do
                    local current = (m.mapID == minimapMapID) and " <-- CURRENT" or ""
                    print(("    floor %d: mapID=%d  heightIdx=%d  name=%s%s"):format(
                        i, m.mapID, m.relativeHeightIndex, m.name or "?", current))
                end
            end
        else
            print("  mapGroup: none (no floors)")
        end
    end

    -- Cave window: built on AceGUI-3.0's own "Frame" dialog widget now (see
    -- CaveRenderer's EnsureWindow), so there is no hand-cloned header
    -- geometry left to diagnose here; just report whether it exists and
    -- where it sits.
    if Config.caveOverlayFrame then
        local w = Config.caveOverlayFrame
        local point, _, relPoint, px, py = w:GetPoint()
        print(("  cave window: %.0f x %.0f  shown=%s  anchor=%s/%s (%.0f, %.0f)")
            :format(w:GetWidth(), w:GetHeight(), tostring(w:IsShown()),
                tostring(point), tostring(relPoint), px or 0, py or 0))
    else
        print("  cave window: not built yet (open a cave first)")
    end

    if bestMapID and bestMapID ~= minimapMapID then
        local groupID = C_Map.GetMapGroupID(bestMapID)
        if groupID then
            local members = C_Map.GetMapGroupMembersInfo(groupID)
            print(("  bestMap group: %d  floors: %d"):format(
                groupID, members and #members or 0))
            if members then
                for i, m in ipairs(members) do
                    local current = (m.mapID == bestMapID) and " <-- CURRENT" or ""
                    print(("    floor %d: mapID=%d  heightIdx=%d  name=%s%s"):format(
                        i, m.mapID, m.relativeHeightIndex, m.name or "?", current))
                end
            end
        end
    end

    if mapID then
        local allLayers = C_Map.GetMapArtLayers(mapID)
        local numLayers = allLayers and #allLayers or 0
        local sub = IsSubmerged() and true or false
        local lIdx = (numLayers >= 2 and sub) and 2 or 1
        print(("  worldmap layers: %d  activeLayer: %d"):format(numLayers, lIdx))
        local fdids = C_Map.GetMapArtLayerTextures(mapID, lIdx)
        local hasBundled = fdids and #fdids > 0 and FDID_MAP[fdids[1]]
        local hasSub = fdids and #fdids > 0 and FDID_MAP_SUB[fdids[1]]
        if hasSub and sub then
            print("  source: BUNDLED BLP SUB (" .. FDID_MAP_SUB[fdids[1]] .. ")")
        elseif hasBundled then
            print("  source: BUNDLED BLP (" .. FDID_MAP[fdids[1]] .. ")")
        else
            print("  source: C_Map API (no bundled BLPs)")
        end
        if numLayers > 0 then
            local l = allLayers[lIdx]
            print(("  art layer %d: %dx%d  tile: %dx%d"):format(
                lIdx, l.layerWidth, l.layerHeight,
                l.tileWidth or 256, l.tileHeight or 256))
        end
        print("  FileDataIDs: " .. (fdids and #fdids or 0))
        if fdids and #fdids > 0 then
            print(("  first FDID: %d  last FDID: %d"):format(fdids[1], fdids[#fdids]))
            -- Show lookup result for first 3 FDIDs
            for i = 1, math.min(3, #fdids) do
                local rel = FDID_MAP[fdids[i]]
                if rel then
                    local full = Config.FDID_BASE .. rel
                    print(("  FDID[%d]=%d => %s"):format(i, fdids[i], full))
                else
                    print(("  FDID[%d]=%d => NOT IN MAP"):format(i, fdids[i]))
                end
            end
        end
        local canvas = WorldMapFrame.ScrollContainer.Child
        if canvas then
            local w, h = canvas:GetSize()
            print(("  canvas: %.0f x %.0f"):format(w, h))
        end

        -- Check detail layer pool. The pool is only one of the places BaseArt
        -- looks, so this reports what it actually found alongside it, rather
        -- than treating a NIL pool as BaseArt having given up entirely.
        local dlp = WorldMapFrame.detailLayerPool
        local dlpCount = 0
        if dlp and dlp.EnumerateActive then
            for _ in dlp:EnumerateActive() do dlpCount = dlpCount + 1 end
        end
        print(("  detailLayerPool: %s  active=%d"):format(
            dlp and "exists" or "NIL", dlpCount))
        print(("  BaseArt: %d layer(s) found, visible=%s  "
            .. "(|cff999999/hfwm baseart|r for detail)"):format(
            #ns.BaseArt:Describe(), tostring(ns.BaseArt.visible)))
        local coordLines = ns.Coords:Describe()
        print(("  map coords readouts: %d found"):format(#coordLines))
        for _, line in ipairs(coordLines) do print("    " .. line) end
    end

    print("  overlayActive: " .. tostring(Config.overlayActive))
    print("  active overlay textures: " .. Pool:ActiveCount())
    if Config.overlayFrame then
        local w, h = Config.overlayFrame:GetSize()
        print(("  overlayFrame: %.0f x %.0f  alpha=%.2f  level=%d  shown=%s"):format(
            w, h, Config.overlayFrame:GetAlpha(), Config.overlayFrame:GetFrameLevel(),
            tostring(Config.overlayFrame:IsShown())))
    else
        print("  overlayFrame: NIL")
    end

    -- Cave map diagnostics
    local inCave, caveMapID = ns.Cave:IsPlayerInCave()
    print(("  cave: enabled=%s  inCave=%s  caveMapID=%s  active=%s"):format(
        tostring(Config.db and Config.db.caveEnabled),
        tostring(inCave), tostring(caveMapID),
        tostring(Config.caveOverlayActive)))
    print(("        currentFloor=%s  floors=%d  pinned=%s  filterAll=%s  suppressed=%s"):format(
        tostring(Config.caveCurrentFloorMapID),
        Config.caveAllFloors and #Config.caveAllFloors or 0,
        tostring(Config.caveFloorPinned),
        tostring(Config.caveFloorFilterAll),
        tostring(Config.caveSuppressedKey)))
    print(("        continuousDepth=%s  pieces=%s"):format(
        tostring(ns.CaveRenderer:IsContinuousActive()),
        tostring(ns.CaveRenderer:IsPiecesActive())))
    local heightWindow = ns.CaveRenderer:DebugHeightWindow()
    if heightWindow then
        print(("        heightWindow: top=%.2f  bottom=%.2f  zMax=%.1f  zMin=%.1f"):format(
            heightWindow.top, heightWindow.bottom,
            heightWindow.zMax or 0, heightWindow.zMin or 0))
    end
    if Config.caveCurrentFloorMapID then
        print(("        title=%s"):format(
            ns.Cave:GetAreaTitle(Config.caveCurrentFloorMapID)))
    end
    if Config.caveOverlayFrame then
        local cw, ch = Config.caveOverlayFrame:GetSize()
        local point, _, relPoint, px, py = Config.caveOverlayFrame:GetPoint()
        print(("        window: %.0f x %.0f  alpha=%.2f  level=%d  shown=%s  tiles=%d"):format(
            cw, ch, Config.caveOverlayFrame:GetAlpha(),
            Config.caveOverlayFrame:GetFrameLevel(),
            tostring(Config.caveOverlayFrame:IsShown()),
            ns.CaveRenderer:ActiveTileCount()))
        print(("        anchor: %s -> %s  (%.0f, %.0f)"):format(
            tostring(point), tostring(relPoint), px or 0, py or 0))
    else
        print("        window: not built yet (no cave entered this session)")
    end
    -- Per-tile FDID lookup replay for the current cave floor: which FDID was
    -- asked for, whether it hit FDID_MAP (real baked art, e.g. Fargodeep's
    -- md_goldmine_varianta.wmo composite), and the exact source string that
    -- got handed to SetTexture. "raw FDID (client art)" means it fell
    -- through to whatever Blizzard's own client streams for that FDID.
    local tileInfo = ns.CaveRenderer:DebugTiles()
    if tileInfo then
        print(("        last render: mapID=%s  layer=%dx%d  tile=%dx%d  grid=%dx%d"):format(
            tostring(tileInfo.floorMapID), tileInfo.layerW, tileInfo.layerH,
            tileInfo.tileW, tileInfo.tileH, tileInfo.cols, tileInfo.rows))
        for i, t in ipairs(tileInfo.tiles) do
            if t.bundled then
                print(("          tile %d: fdid=%s => BUNDLED (%s)"):format(
                    i, tostring(t.fdid), t.src))
            else
                print(("          tile %d: fdid=%s => raw FDID (client art)"):format(
                    i, tostring(t.fdid)))
            end
        end
    else
        print("        last render: none yet (no floor rendered this session)")
    end
    -- Per-floor alpha from the continuous crossfade, when active: replaces
    -- the plain "<-- ACTIVE" marker (which is still printed alongside it,
    -- since ACTIVE means "the slider's anchor floor", not "the only one
    -- visible") with what's actually on screen right now.
    local continuousInfo = ns.CaveRenderer:DebugContinuous()
    if Config.caveAllFloors then
        for i, f in ipairs(Config.caveAllFloors) do
            local marker = (f.mapID == Config.caveCurrentFloorMapID)
                and " <-- ACTIVE" or ""
            local alphaText = ""
            if continuousInfo and continuousInfo[i] then
                alphaText = (" alpha=%.2f"):format(continuousInfo[i].alpha or 0)
            end
            print(("        level %d: mapID=%d  heightIdx=%d  name=%s%s%s"):format(
                i, f.mapID, f.relativeHeightIndex, f.name or "?", alphaText, marker))
        end
    end
    -- cave-satellite-v2 Phase 2: per-piece alpha, when piece mode is active.
    -- Floors above still print (they still drive player-location/title/
    -- suppression per the Phase 2 design), but the art actually on screen is
    -- these pieces, each fading independently by its own real world-Z range
    -- rather than by floor index.
    local piecesInfo = ns.CaveRenderer:DebugPieces()
    if piecesInfo then
        local playerZ = ns.Cave:GetPlayerWorldZ()
        print(("        pieces: %d rendered  playerWorldZ=%s"):format(
            #piecesInfo, playerZ and ("%.1f"):format(playerZ) or "?"))
        for i, grp in ipairs(piecesInfo) do
            print(("          piece %d: zMin=%.1f  zMax=%.1f  alpha=%.2f"):format(
                i, grp.zMin, grp.zMax, grp.alpha or 0))
        end
    end
    Config.tracing = true
    ns.Renderer:ForceRefresh()
    Config.tracing = false
    print("  After refresh: " .. Pool:ActiveCount() .. " textures")

    -- Show first active texture info
    local active = Pool:GetActive()
    if active and #active > 0 then
        local tex = active[1]
        local texFile = tex:GetTexture()
        print(("  tex[1]: texture=%s  shown=%s  alpha=%.2f  w=%.0f h=%.0f"):format(
            tostring(texFile), tostring(tex:IsShown()), tex:GetAlpha(),
            tex:GetWidth(), tex:GetHeight()))
    end
end

--- /hfwm padzoom: why the gamepad map zoom might not move. Prints a state
--- snapshot (including which fields are tainted, and by whom), then samples
--- the scroll container for 10 s -- hold the right stick during it.
function Commands:PadZoomDebug()
    local sc, wmf = WorldMapFrame.ScrollContainer, WorldMapFrame
    local function out(fmt, ...) print("|cff33ccffpadzoom|r " .. fmt:format(...)) end
    local function sec(tbl, key)
        local ok, by = issecurevariable(tbl, key)
        return ok and "secure" or ("TAINTED by " .. tostring(by))
    end
    local levels = sc.zoomLevels
    local n = levels and #levels or 0
    local style = C_InputInterfaceStyle and C_InputInterfaceStyle.GetCurrentStyle()
    out("build: HFWM %s  IsGamepadUI=%s  rawStyle=%s  mapShown=%s",
        tostring(C_AddOns.GetAddOnMetadata("HighFidelityWorldMap", "Version")),
        tostring(Config.IsGamepadUI and Config:IsGamepadUI()), tostring(style),
        tostring(wmf:IsShown()))
    out("focus: currentFocus=%s isMapFocused=%s softCursorShown=%s zoomSpeedCVar=%s",
        tostring(wmf.currentFocus), tostring(wmf.IsMapFocused and wmf:IsMapFocused()),
        tostring(SoftCursor and SoftCursor:IsShown()), tostring(GetCVar("GamepadMapZoomSpeed")))
    out("zoom: gamepadZoom=%s speed=%s cur=%s target=%s zoomTarget=%s base=%s levels=%d first=%s last=%s",
        tostring(sc.gamepadZoom), tostring(sc.gamepadZoomSpeed), tostring(sc.currentScale),
        tostring(sc.targetScale), tostring(sc.zoomTarget), tostring(sc.baseScale), n,
        tostring(n > 0 and levels[1].scale), tostring(n > 0 and levels[n].scale))
    for _, k in ipairs({ "currentScale", "targetScale", "zoomTarget", "baseScale", "zoomLevels",
        "gamepadZoom", "gamepadZoomSpeed", "OnUpdate", "SetZoomTarget", "InstantPanAndZoom",
        "GamepadZoom", "SetGamepadZoom", "CreateZoomLevels" }) do
        out("  sc.%s: %s", k, sec(sc, k))
    end
    if n > 0 then
        out("  zoomLevels[1]: %s   zoomLevels[%d]: %s", sec(levels, 1), n, sec(levels, n))
        out("  zoomLevels[%d].scale: %s", n, sec(levels[n], "scale"))
    end
    for _, k in ipairs({ "GamepadZoom", "currentFocus", "OnMapChanged", "ScrollContainer" }) do
        out("  WorldMapFrame.%s: %s", k, sec(wmf, k))
    end
    out("sampling 10 s: hold the right stick now (lines print only on change)")

    local t, acc, last = 0, 0, ""
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(self, dt)
        t, acc = t + dt, acc + dt
        if t > 10 then self:SetScript("OnUpdate", nil) out("sampling done") return end
        if acc < 0.1 then return end
        acc = 0
        local ok, line = pcall(function()
            return ("gz=%s zooming=%s cur=%.4f tgt=%.4f max=%.4f"):format(
                tostring(sc.gamepadZoom), tostring(sc:IsGamepadZooming()),
                sc.currentScale or -1, sc.targetScale or -1,
                sc.zoomLevels[#sc.zoomLevels].scale)
        end)
        line = ok and line or ("ERR " .. tostring(line))
        if line ~= last then last = line out("t=%.1f %s", t, line) end
    end)
end

--- /hfwm legend: dump WorldMapFooterInputLegend (its fields, methods,
--- children) so the HD/SD pad hint can be written against the real API.
function Commands:LegendDebug()
    local function out(fmt, ...) print("|cff33ccfflegend|r " .. fmt:format(...)) end
    local function keys(t, filter)
        local ks = {}
        for k, v in pairs(t) do
            k = tostring(k)
            if not filter or filter(k:lower()) then ks[#ks + 1] = k .. "=" .. type(v) end
        end
        table.sort(ks)
        return table.concat(ks, " ")
    end
    local L = WorldMapFrame.WorldMapFooterinputLegend
    local pad = _G.HFWMForeverPadToggle
    out("IsGamepadUI=%s padBtn=%s mapShown=%s PADRSTICK->%s", tostring(Config:IsGamepadUI()),
        tostring(pad ~= nil), tostring(WorldMapFrame:IsShown()), tostring(GetBindingAction("PADRSTICK", true)))
    local function vis(f) return f and ("shown=%s visible=%s alpha=%.2f"):format(tostring(f:IsShown()), tostring(f:IsVisible()), f:GetEffectiveAlpha()) or "nil" end
    out("focus: currentFocus=%s IsMapFocused=%s softCursorShown=%s",
        tostring(WorldMapFrame.currentFocus),
        tostring(WorldMapFrame.IsMapFocused and WorldMapFrame:IsMapFocused()),
        tostring(_G.SoftCursor and _G.SoftCursor:IsShown()))
    out("worldMap legend: %s", vis(L))
    out("questLog legend: %s", vis(WorldMapFrame.QuestLogFooterinputLegend))
    out("questDetails legend: %s", vis(WorldMapFrame.QuestDetailsFooterinputLegend))
    -- Focus moves once chat closes, so also sample 15 s and print on change.
    local t, last = 0, nil
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(self, dt)
        t = t + dt
        if t > 15 then self:SetScript("OnUpdate", nil) out("sampling done") return end
        local wm = WorldMapFrame.WorldMapFooterinputLegend
        local line = ("focus=%s IsMapFocused=%s soft=%s wmLegend=%s/%s qlLegend=%s qdLegend=%s PADRSTICK->%s"):format(
            tostring(WorldMapFrame.currentFocus),
            tostring(WorldMapFrame.IsMapFocused and WorldMapFrame:IsMapFocused()),
            tostring(_G.SoftCursor and _G.SoftCursor:IsShown()),
            tostring(wm and wm:IsShown()), tostring(wm and wm:IsVisible()),
            tostring(WorldMapFrame.QuestLogFooterinputLegend and WorldMapFrame.QuestLogFooterinputLegend:IsVisible()),
            tostring(WorldMapFrame.QuestDetailsFooterinputLegend and WorldMapFrame.QuestDetailsFooterinputLegend:IsVisible()),
            tostring(GetBindingAction("PADRSTICK", true)))
        if line ~= last then last = line out("t=%.1f %s", t, line) end
    end)
    -- Prove whether the bound key actually reaches our button.
    if pad and not pad.hfwmProbe then
        pad.hfwmProbe = true
        pad:HookScript("OnClick", function() out("pad button OnClick fired") end)
        out("probe installed: press R3 on the map now")
    end
    out("WorldMapFrame pad/footer fields: %s", keys(WorldMapFrame, function(k)
        return k:find("pad") or k:find("footer") or k:find("focus") or k:find("button")
    end))
    if _G.GamepadPersistentInputLegendMixin then
        out("GamepadPersistentInputLegendMixin: %s", keys(_G.GamepadPersistentInputLegendMixin))
    end
    if _G.GamepadPersistentInputLegendEntryMixin then
        out("GamepadPersistentInputLegendEntryMixin: %s", keys(_G.GamepadPersistentInputLegendEntryMixin))
    end
    if not L then out("WorldMapFooterinputLegend missing") return end
    out("legend %s shown=%s parent=%s", L:GetObjectType(), tostring(L:IsShown()),
        tostring(L:GetParent() and L:GetParent():GetName()))
    out("legend fields: %s", keys(L))
    for i, child in ipairs({ L:GetChildren() }) do
        out("child %d: %s shown=%s text=%s", i, child:GetObjectType(), tostring(child:IsShown()),
            tostring(child.GetText and child:GetText()))
        out("  fields: %s", keys(child))
    end
end

--- /hfwm taint: list the keys on the map's frames that addon code has
--- written (issecurevariable false). Run it after the ADDON_ACTION_FORBIDDEN
--- error is seen: whatever Blizzard reads from here taints its later calls.
function Commands:TaintDebug()
    local function out(fmt, ...) print("|cff33ccfftaint|r " .. fmt:format(...)) end
    local sc = WorldMapFrame.ScrollContainer
    local targets = {
        WorldMapFrame = WorldMapFrame, ScrollContainer = sc, Child = sc and sc.Child,
        WorldMapFooterinputLegend = WorldMapFrame.WorldMapFooterinputLegend,
        SidePanelToggle = WorldMapFrame.SidePanelToggle,
    }
    for name, t in pairs(targets) do
        local bad = {}
        for k in pairs(t) do
            local ok, by = issecurevariable(t, k)
            if not ok then bad[#bad + 1] = tostring(k) .. "<-" .. tostring(by) end
        end
        table.sort(bad)
        out("%s: %s", name, #bad > 0 and table.concat(bad, " ") or "clean")
    end
end

--- Register /hfwm and /hfwmforever through AceConsole-3.0.
function Commands:Register()
    ns.addon.OnChatCommand = function(_, input) Commands:Handle(input) end
    ns.addon:RegisterChatCommand("hfwm", "OnChatCommand")
    ns.addon:RegisterChatCommand("hfwmforever", "OnChatCommand")
end
