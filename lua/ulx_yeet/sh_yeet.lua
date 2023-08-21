local IN_ATTACK2 = IN_ATTACK2

local ragdollVelocity = CreateConVar( "ulx_physgun_ragdoll_velocity", 40, { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "The velocity required for a physgunned player to turn into a ragdoll on release.", 0 ):GetInt()
local unragdollVelocity = 0.5 --Increasing this will make players unragdoll too early or create a very fast 
cvars.AddChangeCallback( "ulx_physgun_ragdoll_velocity", function( _, _, val )
    ragdollVelocity = tonumber( val )
end )

local ragdollMaxTime = CreateConVar( "ulx_physgun_ragdoll_maxtime", 30, { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "The maximum time a player can be ragdolled for.", 0 ):GetInt()
cvars.AddChangeCallback( "ulx_physgun_ragdoll_maxtime", function( _, _, val )
    ragdollMaxTime = tonumber( val )
end )

if CLIENT then
    CreateClientConVar( "cl_physgunfreezeplayers", 1, true, true, "Whether or not you can freeze players with the physgun." )
end

local function playerPickup( ply, ent )
    if not ULib.isSandbox() then return end
    if not ent:IsPlayer() then return end
    if ent.NoNoclip then return end
    if ply:GetInfoNum( "cl_pickupplayers", 1 ) ~= 1 then return end

    local access, tag = ULib.ucl.query( ply, "ulx physgunplayer" )
    if not access then return end

    local restrictions = {}

    ULib.cmds.PlayerArg.processRestrictions( restrictions, ply, {}, tag and ULib.splitArgs( tag )[1] )

    if restrictions.restrictedTargets == false or ( restrictions.restrictedTargets and not table.HasValue( restrictions.restrictedTargets, ent ) ) then
        return
    end

    if CLIENT then return true end

    ply.cfCIsHoldingPlayer = ent

    if ent:IsFrozen() then
        local freezeAccess = ULib.ucl.query( ply, "ulx freeze" )
        if not freezeAccess then return end
        if ply:IsBot() then
            ply:ConCommand( "ulx unfreeze " .. ent:GetName() )
        else
            ply:ConCommand( "ulx unfreeze $" .. ent:SteamID() )
        end
    end

    ent:SetMoveType( MOVETYPE_NONE )

    local newPos = ent:GetPos()
    local oldPos = ent:GetPos()
    local speedVec = vector_origin
    local steamId = ent:SteamID64()

    hook.Add( "Tick", "CFC_Yeet_TickHolding_" .. steamId, function()
        if not IsValid( ent ) then
            hook.Remove( "Tick", "CFC_Yeet_TickHolding_" .. steamId )
            return
        end

        newPos = ent:GetPos()

        local tempSpeed = newPos - oldPos

        if tempSpeed:LengthSqr() > 1 then
            speedVec = tempSpeed
        end

        ent.cfcYeetSpeed = speedVec -- newPos - oldPos
        oldPos = newPos
    end )

    return true
end
hook.Add( "PhysgunPickup", "ulxPlayerPickup", playerPickup, HOOK_HIGH )

if CLIENT then return end

local function playerDrop( ply, ent )
    if not ent:IsPlayer() then return end

    ply.cfCIsHoldingPlayer = nil

    hook.Remove( "Tick", "CFC_Yeet_TickHolding_" .. ent:SteamID64() )

    local newVelocity = ent.cfcYeetSpeed
    ent:SetMoveType( MOVETYPE_WALK )
    ent:SetVelocity( newVelocity * 50 )

    if not ent:Alive() then return end
    if ent.ragdoll then return end

    if newVelocity:Length() < ragdollVelocity then return end

    timer.Simple( 0, function()
        if not IsValid( ent ) then return end

        ulx.ragdollPlayer( ent )

        local ragdoll = ent.ragdoll
        if not IsValid( ragdoll ) then return end

        ragdoll.player = ent
        ragdoll.cooldown = CurTime() + 1

        local steamId = ent:SteamID64()
        local hookName = "CFC_Yeet_RagdollTick_" .. steamId

        timer.Simple( ragdollMaxTime, function()
            if not IsValid( ent ) or not IsValid( ent.ragdoll ) then return end
            hook.Remove( "Tick", hookName )
            ulx.unragdollPlayer( ent )
        end )

        hook.Add( "Tick", hookName, function()
            if not IsValid( ent ) or not IsValid( ragdoll ) then
                hook.Remove( "Tick", hookName )
                ent:Spawn()
                return
            end

            if ragdoll.cooldown > CurTime() then return end
            if ragdoll:GetVelocity():Length() > unragdollVelocity then return end
            hook.Remove( "Tick", hookName )

            ulx.unragdollPlayer( ent )
        end )
    end )
end

hook.Add( "PhysgunDrop", "ulxPlayerDrop", playerDrop )

hook.Add( "CanPlayerSuicide", "ulxYeetCanSuicideCheck", function( ply )
    if ply.yeetRagdoll then return false end
end )

hook.Add( "KeyPress", "ulxPlayerPickupFreeze", function( ply, key )
    if key ~= IN_ATTACK2 then return end
    if ply:GetWeapon( "weapon_physgun" ) ~= ply:GetActiveWeapon() then return end
    if ply:GetInfoNum( "cl_physgunfreezeplayers", 1 ) ~= 1 then return end

    local heldPlayer = ply.cfCIsHoldingPlayer
    if not heldPlayer then return end

    local access = ULib.ucl.query( ply, "ulx freeze" )
    if not access then return end

    ply:ConCommand( "ulx freeze " .. heldPlayer:GetName() )
end )
