-------------------------------------------------------------------------------
-- HFWM-Forever Player Icons
--
-- Shows where other players are on the world map, as class-coloured dots:
--   - group members (party and raid), from the game's own unit positions;
--   - guild members and friends who share where they are.
--
-- Sharing uses OpenMap's wire format on its prefix (OpenMapLoc), so an
-- OpenMap user and an HFWM user see each other's places, and both read the
-- same feed:
--   "L1 map x y class level"  your place (uiMapID, x and y 0..1)
--   "L0"                      stopped sharing
--   "H1" / "H2"               hello to a friend, and its answer
-- Places go to guild members (GUILD channel) and to friends who answered a
-- hello (whisper). Nothing is sent inside dungeons, raids or battlegrounds.
-- Battle.net friends are not sent places yet.
--
-- Options: Config.db.playerIconsFriends, playerIconsGuild, playerIconsGroup,
-- playerIconsShare (Options > Player Icons).
-------------------------------------------------------------------------------
local addonName, ns = ...
local Config = ns.Config
local PlayerIcons = {}
ns.PlayerIcons = PlayerIcons
local Queue, QueueScan  -- defined below; used by Scan and the event handler

local WorldMapFrame = _G.WorldMapFrame

local PREFIX = "OpenMapLoc"         -- shared with OpenMap: one feed for both
local TICK = 2                      -- seconds between looks at where you are
local SEND_EVERY = 10               -- seconds between places sent while you move
local STILL_EVERY = 60              -- ... and while you stand still
local GONE_AFTER = 150              -- seconds without word before a dot goes
local MOVED = 0.002                 -- a move this small on a map isn't one
local SEND_GAP = 0.5                -- seconds between addon messages sent
local ROSTER_EVERY = 30             -- seconds between roster scans while the map is open
local REDRAW_EVERY = 1              -- seconds between redraws while the map is open
local DOT_SIZE = 12
local DOT_ATLAS = "WhiteCircle-RaidBlips"

local online = {}                   -- full name -> { name, class, level, area, guild, friend, whisper }
local live = {}                     -- full name -> { map, x, y, class, level, guild, at }
local known = {}                    -- full name -> true: friends who answered a hello (OpenMap or HFWM)
local pool = {}                     -- dot frames, reused
local sharing = false
local last = { at = -math.huge }
local outbox = {}                   -- { text, channel, target }, sent one per SEND_GAP
local classFile                    -- localised class name -> file name (friends list gives the name only)

local function Secret(v) return issecretvalue and issecretvalue(v) end

local function Realm()
    local r = GetNormalizedRealmName and GetNormalizedRealmName()
    if type(r) ~= "string" or r == "" then r = (GetRealmName and GetRealmName() or ""):gsub("[%s%-]", "") end
    return r or ""
end

local function Full(name, realm)
    if Secret(name) or type(name) ~= "string" or name == "" then return end
    if name:find("-", 1, true) then return name end
    local r = (type(realm) == "string" and realm ~= "") and realm:gsub("[%s%-]", "") or Realm()
    return name .. "-" .. r
end

local function MyFull()
    return Full(UnitName("player"))
end

local function ClassColor(class)
    local c = class and ((C_ClassColor and C_ClassColor.GetClassColor(class)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function ClassFileOf(localised)
    if type(localised) ~= "string" then return end
    if not classFile then
        classFile = {}
        for file, n in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do classFile[n] = file end
        for file, n in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do classFile[n] = file end
    end
    return classFile[localised]
end

--------------------------------------------------------------------------------
-- Who is online
--------------------------------------------------------------------------------

local function Scan()
    local before = {}
    for full in pairs(online) do before[full] = true end
    wipe(online)

    if IsInGuild() and GetNumGuildMembers then
        for i = 1, GetNumGuildMembers() do
            local name, _, _, level, _, area, _, _, isOnline, _, class = GetGuildRosterInfo(i)
            if not Secret(isOnline) and isOnline and type(name) == "string" then
                local full = Full(name)
                if full then
                    online[full] = { name = name, class = class, level = level, area = area, guild = true }
                end
            end
        end
    end

    if C_FriendList and C_FriendList.GetNumFriends then
        for i = 1, C_FriendList.GetNumFriends() do
            local f = C_FriendList.GetFriendInfoByIndex(i)
            if f and f.connected and f.name then
                local full = Full(f.name)
                if full then
                    local r = online[full] or {}
                    r.name = r.name or f.name
                    r.class = r.class or ClassFileOf(f.className)
                    r.level = r.level or f.level
                    r.area = r.area or f.area
                    r.friend = true
                    r.whisper = f.name
                    online[full] = r
                end
            end
        end
    end

    local me = MyFull()
    for full in pairs(online) do
        if full == me then online[full] = nil end
    end
    -- a friend who has just come online gets a hello: OpenMap and HFWM answer with their own
    if Config.db.playerIconsShare then
        for full, r in pairs(online) do
            if r.friend and not before[full] then
                known[full] = nil
                Queue("H1", "WHISPER", r.whisper)
            end
        end
    end
    for full in pairs(live) do
        if not online[full] then live[full] = nil end
    end
end

--------------------------------------------------------------------------------
-- Sending
--------------------------------------------------------------------------------

local sender = CreateFrame("Frame")
sender:Hide()
local gap = 0
sender:SetScript("OnUpdate", function(self, elapsed)
    gap = gap - elapsed
    if gap > 0 then return end
    local m = table.remove(outbox, 1)
    if not m then self:Hide() return end
    gap = SEND_GAP
    if m.text:sub(1, 2) == "L1" and not Config.db.playerIconsShare then return end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        pcall(C_ChatInfo.SendAddonMessage, PREFIX, m.text, m.channel, m.target)
    end
end)

function Queue(text, channel, target)
    outbox[#outbox + 1] = { text = text, channel = channel, target = target }
    sender:Show()
end

-- your place to everyone who should have it: the guild, and friends who use OpenMap or HFWM
local function Broadcast(text)
    if IsInGuild() then Queue(text, "GUILD") end
    for full, r in pairs(online) do
        if r.friend and known[full] and r.whisper then Queue(text, "WHISPER", r.whisper) end
    end
end

-- where you are, for sharing: uiMapID, x, y; nil in an instance or when the game doesn't know
local function MyPlace()
    if IsInInstance() then return end
    local best = C_Map.GetBestMapForUnit("player")
    if type(best) ~= "number" then return end
    local p = C_Map.GetPlayerMapPosition(best, "player")
    if not p then return end
    local x, y = p:GetXY()
    if Secret(x) or Secret(y) or type(x) ~= "number" or type(y) ~= "number" then return end
    if x <= 0 and y <= 0 then return end
    return best, x, y
end

local function Tick()
    if not (Config.db.enabled and Config.db.playerIconsShare) then
        if sharing then sharing = false last.at = -math.huge Broadcast("L0") end
        return
    end
    local m, x, y = MyPlace()
    if not m then
        if sharing then sharing = false last.at = -math.huge Broadcast("L0") end
        return
    end
    local now = GetTime()
    local moved = m ~= last.map or math.abs(x - (last.x or 0)) > MOVED or math.abs(y - (last.y or 0)) > MOVED
    if now - last.at < (moved and SEND_EVERY or STILL_EVERY) then return end
    last.map, last.x, last.y, last.at = m, x, y, now
    local _, class = UnitClass("player")
    local level = UnitLevel("player") or 0
    sharing = true
    last.text = ("L1\t%d\t%.4f\t%.4f\t%s\t%d"):format(m, x, y, class or "", level)
    Broadcast(last.text)
end

--------------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------------

local function Heard(full, text, guild)
    local kind, m, x, y, class, level = strsplit("\t", text, 6)
    if kind == "H1" then
        -- a hello from a friend: answer, and send our place if we share it
        if guild or not online[full] or not online[full].friend then return end
        known[full] = true
        if online[full].whisper then Queue("H2", "WHISPER", online[full].whisper) end
        if sharing and last.text and online[full].whisper then Queue(last.text, "WHISPER", online[full].whisper) end
        return
    elseif kind == "H2" then
        if not guild and online[full] and online[full].friend then known[full] = true end
        return
    end
    -- places: from guild members, and from friends (whispers)
    local r = online[full]
    if not r or not (r.guild or r.friend) then return end
    if kind == "L0" then
        live[full] = nil
    elseif kind == "L1" then
        m, x, y = tonumber(m), tonumber(x), tonumber(y)
        if not (m and x and y) or x < 0 or x > 1 or y < 0 or y > 1 then return end
        live[full] = { map = m, x = x, y = y, class = class and class:match("^%u+$"),
            level = tonumber(level), at = GetTime() }
    end
end

local function OnEvent(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        local prefix, text, channel, from = ...
        if prefix ~= PREFIX or Secret(text) or Secret(from) or Secret(channel) then return end
        if type(text) ~= "string" or (channel ~= "GUILD" and channel ~= "WHISPER") then return end
        local full = Full(from)
        if not full or full == MyFull() then return end
        Heard(full, text, channel == "GUILD")
    else
        QueueScan()
    end
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local function Canvas()
    local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
    return sc and sc.Child
end

-- a point on mapID as a point on the map on screen, 0..1, or nil
local function OnScreenPoint(mapID, x, y, shown)
    if mapID == shown then return x, y end
    local ok, instance, worldPos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if not ok or not worldPos then return end
    local ok2, pos = pcall(C_Map.GetMapPosFromWorldPos, instance, worldPos, shown)
    if not ok2 or not pos then return end
    local px, py = pos:GetXY()
    if not px or px < 0 or px > 1 or py < 0 or py > 1 then return end
    return px, py
end

local function DotFrame(i, canvas)
    local d = pool[i]
    if not d then
        d = CreateFrame("Frame", nil, canvas)
        d:SetSize(DOT_SIZE, DOT_SIZE)
        d.tex = d:CreateTexture(nil, "OVERLAY")
        d.tex:SetAllPoints()
        if not pcall(d.tex.SetAtlas, d.tex, DOT_ATLAS) then d.tex:SetTexture("Interface\\Minimap\\PartyRaidBlips") end
        d:EnableMouse(true)
        d:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.label, ClassColor(self.class))
            GameTooltip:Show()
        end)
        d:SetScript("OnLeave", GameTooltip_Hide)
        pool[i] = d
    end
    d:SetParent(canvas)
    d:SetFrameLevel(canvas:GetFrameLevel() + 40)
    return d
end

local function Redraw()
    local canvas = Canvas()
    local shown = WorldMapFrame and WorldMapFrame:GetMapID()
    local used = 0
    if not (canvas and shown and Config.db.enabled) then
        for _, d in ipairs(pool) do d:Hide() end
        return
    end
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local function Place(label, class, px, py)
        used = used + 1
        local d = DotFrame(used, canvas)
        d.label, d.class = label, class
        d.tex:SetVertexColor(ClassColor(class))
        d:ClearAllPoints()
        d:SetPoint("CENTER", canvas, "TOPLEFT", px * w, -py * h)
        d:Show()
    end

    local inGroup = {}
    if Config.db.playerIconsGroup and IsInGroup() then
        local raid = IsInRaid()
        for i = 1, raid and 40 or 4 do
            local unit = (raid and "raid" or "party") .. i
            if UnitExists(unit) and not UnitIsUnit(unit, "player") then
                local name = UnitName(unit)
                if type(name) == "string" then inGroup[name] = true end
                local pos = C_Map.GetPlayerMapPosition(shown, unit)
                local x, y = pos and pos:GetXY()
                if type(x) == "number" and type(y) == "number" and not (x == 0 and y == 0) and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                    local _, class = UnitClass(unit)
                    Place(name or unit, class, x, y)
                end
            end
        end
    end

    local now = GetTime()
    for full, p in pairs(live) do
        local r = online[full]
        local show = r and ((r.friend and Config.db.playerIconsFriends) or (r.guild and Config.db.playerIconsGuild))
        local name = full:match("^[^%-]+") or full
        if show and now - p.at <= GONE_AFTER and not inGroup[name] then
            local px, py = OnScreenPoint(p.map, p.x, p.y, shown)
            if px then Place(name, p.class or r.class, px, py) end
        end
    end

    for i = used + 1, #pool do pool[i]:Hide() end
end

--------------------------------------------------------------------------------
-- Timers and start
--------------------------------------------------------------------------------

local scanToken = 0
function QueueScan()
    scanToken = scanToken + 1
    local token = scanToken
    C_Timer.After(1, function()
        if token == scanToken then Scan() end
    end)
end

function PlayerIcons:Start()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "CHAT_MSG_ADDON", "GUILD_ROSTER_UPDATE", "FRIENDLIST_UPDATE", "GROUP_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE" }) do
        ev:RegisterEvent(e)
    end
    ev:SetScript("OnEvent", OnEvent)

    C_Timer.NewTicker(TICK, Tick)
    C_Timer.After(5, function()
        if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
        if C_FriendList and C_FriendList.ShowFriends then pcall(C_FriendList.ShowFriends) end
        QueueScan()
    end)

    -- while the world map is open: roster asked for now and then, dots redrawn each second
    if WorldMapFrame then
        local wait, rosterIn = 0, 0
        local ticker = CreateFrame("Frame", nil, WorldMapFrame)
        ticker:SetScript("OnUpdate", function(_, elapsed)
            if not WorldMapFrame:IsShown() then return end
            wait = wait - elapsed
            if wait > 0 then return end
            wait = REDRAW_EVERY
            rosterIn = rosterIn - 1
            if rosterIn <= 0 then
                rosterIn = ROSTER_EVERY
                if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
                QueueScan()
            end
            Redraw()
        end)
        WorldMapFrame:HookScript("OnHide", function() Redraw() end)
    end
end

-- Options changed: send or stop the place at once, and redraw.
function PlayerIcons:Refresh()
    last.at = -math.huge
    Tick()
    Redraw()
end
