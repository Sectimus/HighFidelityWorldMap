-------------------------------------------------------------------------------
-- HFWM-Forever Namespace
-- Shared addon namespace table. Every other Lua module receives this via
-- the "..." idiom:
--     local addonName, ns = ...
-------------------------------------------------------------------------------
local addonName, ns = ...

-- The AceAddon-3.0 object. AceConsole-3.0 gives it slash commands,
-- AceEvent-3.0 gives it :RegisterEvent. See Core.lua for OnInitialize/OnEnable.
ns.addon = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")

-- Public sub-tables filled by individual modules
ns.Config      = {}
ns.Pool        = {}
ns.MaskPool    = {}
ns.BaseArt     = {}
ns.MapFrameBg  = {}
ns.Exploration = {}
ns.Watchdog    = {}
ns.Renderer    = {}
ns.Commands    = {}
ns.Options     = {}
ns.Cave        = {}
ns.CaveTable   = {}
ns.CaveRenderer = {}
ns.Taint       = {}
ns.MapMemory   = {}
ns.ZoomLevels  = {}
ns.ResetView   = {}
ns.KeepCentered = {}
ns.ToggleButton = {}
ns.Integrations = {}
ns.Coords      = {}
ns.ZoneFog = {}
ns.AreaLabels  = {}

-- Convenience printer (accessible everywhere via ns.P)
ns.P = function(msg) print("|cff33ccffHFWM-F:|r " .. msg) end
