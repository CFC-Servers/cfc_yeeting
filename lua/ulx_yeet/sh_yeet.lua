if SERVER then
    ULib.ucl.registerAccess( "physgunragdollplayer", ULib.ACCESS_ADMIN, "Ability to physgun ragdoll other players.", "Other" )
end

local ragdollVelocity = CreateConVar( "ulx_physgun_ragdoll_velocity", 50, { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "The velocity required for a physgunned player to turn into a ragdoll on release.", 0 ):GetInt()

cvars.AddChangeCallback( "ulx_physgun_ragdoll_velocity", function( _, _, val )
    ragdollVelocity = tonumber( val )
end)

local function savePlayer( ply )
    local result = {
        health = ply:Health(),
        armor = ply:Armor(),
        weaponData = {}
    }

    if ply:GetActiveWeapon():IsValid() then
        result.currentWeapon = ply:GetActiveWeapon():GetClass()
    end

    local weapons = ply:GetWeapons()

    for _, weapon in ipairs( weapons ) do
        local className = weapon:GetClass()
        result.weaponData[className] = {
            clip1 = weapon:Clip1(),
            clip2 = weapon:Clip2(),
            ammo1 = ply:GetAmmoCount( weapon:GetPrimaryAmmoType() ),
            ammo2 = ply:GetAmmoCount( weapon:GetSecondaryAmmoType() )
        }
    end

    ply.cfcYeetData = result
end

local function restorePlayer( ply )
    local data = ply.cfcYeetData
    ply:SetParent()
    ply:SetHealth( data.health )
    ply:SetArmor( data.armor )

    for weaponClass, weaponInfo in pairs( data.weaponData ) do
        ply:Give( weaponClass )
        local weapon = ply:GetWeapon( weaponClass )
        weapon:SetClip1( weaponInfo.clip1 )
        weapon:SetClip2( weaponInfo.clip2 )
        ply:SetAmmo( weaponInfo.ammo1, weapon:GetPrimaryAmmoType() )
        ply:SetAmmo( weaponInfo.ammo2, weapon:GetSecondaryAmmoType() )
    end

    ply:SelectWeapon( data.currentWeapon )
end

local function unRagdollPlayer( ragdoll )
    if not IsValid( ragdoll ) then return end
    local ply = ragdoll.player
    if not IsValid( ply ) then return end
    ply:SetParent()
    ply:UnSpectate()
    ply:Spawn()
    restorePlayer( ply )

    ply:SetPos( ragdoll:GetPos() )
    ply:SetVelocity( ragdoll:GetVelocity() )
    local yaw = ragdoll:GetAngles().yaw
    ply:SetAngles( Angle( 0, yaw, 0 ) )
    ragdoll:Remove()
end

local function ragdollPlayer( ply, velocity )
    savePlayer( ply )

    local ragdoll = ents.Create( "prop_ragdoll" )

    ragdoll:SetModel( ply:GetModel() )
    ragdoll:SetPos( ply:GetPos() )
    ragdoll:SetAngles( ply:GetAngles() )
    ragdoll:SetVelocity( velocity )
    ragdoll:Spawn()

    local boneCount = ragdoll:GetPhysicsObjectCount() - 1

    for i = 0, boneCount do
        local bonePhys = ragdoll:GetPhysicsObjectNum( i )

        if IsValid( bonePhys ) then
            local boneVec, boneAng = ply:GetBonePosition( ragdoll:TranslatePhysBoneToBone( i ) )

            if boneVec and boneAng then
                bonePhys:SetPos( boneVec )
                bonePhys:SetAngles( boneAng )
            end
            bonePhys:SetVelocity( velocity )
        end
    end

    ply:Spectate( OBS_MODE_CHASE )
    ply:SpectateEntity( ragdoll )
    ply:StripWeapons()

    return ragdoll
end


local function playerPickup( ply, ent )
    if not ULib.isSandbox() then return end
    if not ent:IsPlayer() then return end
    if ent.NoNoclip then return end
    if ent.frozen then return end
    if ply:GetInfoNum( "cl_pickupplayers", 1 ) ~= 1 then return end

    local access, tag = ULib.ucl.query( ply, "ulx physgunplayer" )
    if not access then return end

    local restrictions = {}

    ULib.cmds.PlayerArg.processRestrictions( restrictions, ply, {}, tag and ULib.splitArgs( tag )[ 1 ] )

    if restrictions.restrictedTargets == false or (restrictions.restrictedTargets and not table.HasValue( restrictions.restrictedTargets, ent )) then
        return
    end

    if CLIENT then return true end

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
    end)

    return true
end
hook.Add( "PhysgunPickup", "ulxPlayerPickup", playerPickup, HOOK_HIGH )

if CLIENT then return end

local function playerDrop( ply, ent )
    if not ent:IsPlayer() then return end

    hook.Remove( "Tick", "CFC_Yeet_TickHolding_" .. ent:SteamID64() )

    local newVelocity = ent.cfcYeetSpeed
    ent:SetMoveType( MOVETYPE_WALK )
    ent:SetVelocity( newVelocity * 50 )

    local access = ULib.ucl.query( ply, "physgunragdollplayer" )
    if not access then return end

    if newVelocity:Length() < ragdollVelocity then return end

    timer.Simple( 0, function()
        if not IsValid( ent ) then return end

        local ragdoll = ragdollPlayer( ent, newVelocity * 50 )
        ragdoll.player = ent
        ragdoll.cooldown = CurTime() + 1

        timer.Simple( 30, function()
            unRagdollPlayer( ragdoll )
        end)

        local steamId = ent:SteamID64()
        local hookName = "CFC_Yeet_RagdollTick_" .. steamId

        hook.Add( "Tick", hookName, function()
            if not IsValid( ragdoll ) then
                hook.Remove( "Tick", hookName )
                ent:Spawn()
                return
            end
            if ragdoll:GetVelocity():Length() > 10 or ragdoll.cooldown > CurTime() then return end
            unRagdollPlayer( ragdoll )
            hook.Remove( "Tick", hookName )
        end)
    end)
end

hook.Add( "PhysgunDrop", "ulxPlayerDrop", playerDrop )
