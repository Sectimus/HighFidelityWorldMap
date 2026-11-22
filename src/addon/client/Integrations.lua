-------------------------------------------------------------------------------
-- HFWM-Forever Integrations
--
-- Workarounds for other addons that share the world map with us. Each one
-- looks the other addon up lazily (no OptionalDeps, no load-order
-- assumptions) and does nothing when it isn't there.
-------------------------------------------------------------------------------
local addonName, ns = ...
local Integrations = ns.Integrations

local WorldMapFrame = _G.WorldMapFrame

-- Krowi_WorldMapButtons (embedded by Questie, among others) lays its buttons
-- out in a row from the map pane's top-right corner: the first one's
-- TOPRIGHT at (-XOffset, YOffset) from the canvas container, each further one
-- KROWI_PITCH units left, all at its shown-button size of 32. That first slot
-- is exactly where the HD/SD toggle's default spot is.
local KROWI_PITCH = 32
local krowiBaseX  -- the library's own XOffset, from before we touched it

--- Shift the Krowi row (Questie's map button) to the left of the HD/SD
--- toggle while the toggle sits in the row's first slot, and put it back once
--- the toggle is hidden or has been dragged clear of that slot. Called after
--- every toggle placement (ToggleButton.lua's ApplyPosition and Refresh).
--- Overlap is tested against the row's own default slot, not where it is
--- now, so shifting it never feeds back into the test.
---
--- The row is re-laid out on every call, not just when the offset changes:
--- Krowi places a new button at XOffset + 32 per button already listed, and
--- under Forever that count still includes Blizzard's two map buttons, which
--- Questie drops from the list only afterwards (its ReleaseBlizzardMapButtons).
--- So Questie's button starts two slots too far left, and Krowi itself only
--- corrects it on the next map change.
function Integrations:FitAroundToggle(button)
    local krowi = LibStub("Krowi_WorldMapButtons-1.4", true)
    if not krowi then return end
    krowiBaseX = krowiBaseX or krowi.XOffset

    local x = krowiBaseX
    if button and button:IsShown() then
        local pane = WorldMapFrame:GetCanvasContainer()
        local left, bottom, w, h = button:GetRect()
        local right, top = pane:GetRight(), pane:GetTop()
        if left and right then
            -- Everything in Krowi-button units, relative to the pane's top-right.
            local first = krowi.Buttons and krowi.Buttons[1]
            local ks = (first or WorldMapFrame):GetEffectiveScale()
            local bs, ps = button:GetEffectiveScale() / ks, pane:GetEffectiveScale() / ks
            local bl, bt = left * bs - right * ps, (bottom + h) * bs - top * ps
            local br, bb = bl + w * bs, bt - h * bs
            local sr, st = -krowiBaseX, krowi.YOffset
            local sl, sb = sr - KROWI_PITCH, st - KROWI_PITCH
            if bl < sr and br > sl and bb < st and bt > sb then x = -bl end
        else
            x = krowi.XOffset  -- not laid out yet: keep the last fit; next placement retries
        end
    end

    krowi.XOffset = x
    if krowi.Buttons then krowi.SetPoints() end
end
