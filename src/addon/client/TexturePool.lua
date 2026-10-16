-------------------------------------------------------------------------------
-- HFWM-Forever TexturePool
-- Recycle Texture objects to avoid creating new ones every refresh.
-------------------------------------------------------------------------------
local addonName, ns = ...
local Pool     = ns.Pool
local MaskPool = ns.MaskPool
local Config   = ns.Config

local texturePool    = {}   -- recycled Texture objects
local activeTextures = {}   -- currently displayed

function Pool:Acquire()
    local tex = tremove(texturePool)
    if not tex then
        tex = Config.overlayFrame:CreateTexture(nil, "ARTWORK", nil, 2)
    end
    tex:SetVertexColor(1, 1, 1, 1)
    tex:SetDesaturated(false)
    tex:SetDrawLayer("ARTWORK", 2)  -- Fog of War's tinted pieces sit at 1
    tex:Show()
    activeTextures[#activeTextures + 1] = tex
    return tex
end

function Pool:ReleaseAll()
    for i = #activeTextures, 1, -1 do
        local tex = activeTextures[i]
        -- Fog of War (Renderer's DrawExploredPiece) may have masked this
        -- texture to a slice of Blizzard's torn-edge exploration art; strip
        -- that off before it goes back in the pool, or a later Acquire
        -- could hand it out still clipped to whatever shape was last on it.
        -- The mask objects are MaskPool's to recycle, not this pool's; this
        -- only ever detaches, never keeps or destroys one.
        for i2 = tex:GetNumMaskTextures(), 1, -1 do
            tex:RemoveMaskTexture(tex:GetMaskTexture(i2))
        end
        tex:Hide()
        tex:ClearAllPoints()
        activeTextures[i] = nil
        texturePool[#texturePool + 1] = tex
    end
end

function Pool:ActiveCount()
    return #activeTextures
end

function Pool:GetActive()
    return activeTextures
end

-------------------------------------------------------------------------------
-- MaskPool: the same recycling, for the MaskTexture objects Fog of War
-- attaches to Pool's own textures (see Renderer's DrawExploredPiece) to
-- crop them to Blizzard's real exploration art instead of a hard rectangle.
-- Its own pool because MaskTexture is its own widget type
-- (Frame:CreateMaskTexture, not Frame:CreateTexture) and is never shown or
-- hidden like an ordinary texture. Pool:ReleaseAll is what detaches a mask
-- from whatever it was cropping; this just holds the unattached object so
-- Acquire doesn't have to create a fresh one every refresh.
-------------------------------------------------------------------------------
local maskPool    = {}
local activeMasks = {}

function MaskPool:Acquire()
    local mask = tremove(maskPool)
    if not mask then
        mask = Config.overlayFrame:CreateMaskTexture()
    end
    activeMasks[#activeMasks + 1] = mask
    return mask
end

function MaskPool:ReleaseAll()
    for i = #activeMasks, 1, -1 do
        local mask = activeMasks[i]
        mask:ClearAllPoints()
        activeMasks[i] = nil
        maskPool[#maskPool + 1] = mask
    end
end

function MaskPool:ActiveCount()
    return #activeMasks
end
