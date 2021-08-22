if SERVER then
    ULib.ucl.registerAccess( "physgunragdollplayer", ULib.ACCESS_ADMIN, "Ability to physgun ragdoll other players.", "Other" )
end

local ragdollVelocity = CreateConVar( "ulx_physgun_ragdoll_velocity", 150, { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "The velocity required for a physgunned player to turn into a ragdoll on release.", 0 )

local function savePlayer( ply )
    local result = {
        health = ply:Health(),
        armor = ply:Armor()
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

    for weaponClass, weaponInfo in pairs( data.weapondata ) do
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

    local access, tag = ULib.ucl.query( ply, "physgunplayer" )
    if not access then return end

    local restrictions = {}
    ULib.cmds.PlayerArg.processRestrictions( restrictions, ply, {}, tag and ULib.splitArgs( tag )[1] )

    if restrictions.restrictedTargets == false then return end
    if not table.HasValue( restrictions.restrictedTargets, ent ) ) then return end

    if CLIENT then return true end

    ent:SetMoveType( MOVETYPE_NONE )

    local curPos
    local newPos = ent:GetPos()
    local oldPos = ent:GetPos()
    local steamId = ent:SteamID64()

    hook.Add( "Tick", "CFC_Yeet_TickHolding_" .. steamId, function()
        if not IsValid( ent ) then
            hook.Remove( "Tick", "CFC_Yeet_TickHolding_" .. steamId )
            return
        end

        curPos = ent:GetPos()
        newPos = curPos
        ent.cfcYeetSpeed = newPos - oldPos
        oldPos = curPos
    end)

    return true
end
hook.Add( "PhysgunPickup", "ulxPlayerPickup", playerPickup, HOOK_HIGH )

if CLIENT then return end

local function playerDrop( ply, ent )
    if not ent:IsPlayer() then return end

    hook.Remove( "Tick", "CFC_Yeet_Tick_Holding" .. ent:SteamID64() )

    ent:SetMoveType( MOVETYPE_WALK )
    ent:SetVelocity( ent.cfcYeetSpeed * 50 )

    local access = ULib.ucl.query( ply, "physgunragdollplayer" )
    if not access then return end

    if ent.cfcYeetSpeed:Length() < ragdollVelocity then return end

    timer.Simple( 0, function()
        local ragdoll = ragdollPlayer( ent, ent.cfcYeetSpeed * 50 )
        ragdoll.player = ent
        ragdoll.cooldown = CurTime() + 1

        timer.Simple( 30, function()
            unRagdollPlayer( ragdoll )
        end)

        local steamId = ent:SteamID64()
        hook.Add( "Tick", "CFC_Yeet_Tick_Ragdoll" .. steamId, function()
            if not IsValid( ragdoll ) then
                hook.Remove( "Tick", "CFC_Yeet_Tick_Ragdoll" .. steamId )
                ent:Spawn()
                return
            end

            if ragdoll:GetVelocity():Length() > 10 or ragdoll.cooldown > CurTime() then return end
            unRagdollPlayer( ragdoll )
            hook.Remove( "Tick", "CFC_Yeet_Tick_Ragdoll" .. steamId )
        end)
    end)
end

hook.Add( "PhysgunDrop", "ulxPlayerDrop", playerDrop )
