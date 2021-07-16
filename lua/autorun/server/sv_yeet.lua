ULib.ucl.registerAccess( "ulx physgunragdollplayer", ULib.ACCESS_ADMIN, "Ability to physgun ragdoll other players.", "Other" )
CreateConVar( "ulx_physgun_ragdoll_velocity", 75, { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "The velocity required for a physgunned player to turn into a ragdoll on release.", 0 )

local function savePlayer( ply )
    local result = {}

    result.health = ply:Health()
    result.armor = ply:Armor()

    if ply:GetActiveWeapon():IsValid() then
        result.currentWeapon = ply:GetActiveWeapon():GetClass()
    end

    local weapons = ply:GetWeapons()

    for _, weapon in ipairs( weapons ) do
        result.weapondata = {}
        printname = weapon:GetClass()
        result.weapondata[ printname ] = {}
        result.weapondata[ printname ].clip1 = weapon:Clip1()
        result.weapondata[ printname ].clip2 = weapon:Clip2()
        result.weapondata[ printname ].ammo1 = ply:GetAmmoCount( weapon:GetPrimaryAmmoType() )
        result.weapondata[ printname ].ammo2 = ply:GetAmmoCount( weapon:GetSecondaryAmmoType() )
    end
    ply.cfcYeetData = result
end

local function restorePlayer( ply )
    local data = ply.cfcYeetData
    ply:SetParent()
    ply:SetHealth( data.health )
    ply:SetArmor( data.armor )

    for weaponClass, infoTable in pairs( data.weapondata ) do
        ply:Give( weaponClass )
        local weapon = ply:GetWeapon( weaponClass )
        weapon:SetClip1( infoTable.clip1 )
        weapon:SetClip2( infoTable.clip2 )
        ply:SetAmmo( infoTable.ammo1, weapon:GetPrimaryAmmoType() )
        ply:SetAmmo( infoTable.ammo2, weapon:GetSecondaryAmmoType() )
    end

    ply:SelectWeapon( data.currentWeapon )
end

local function unRagdollPlayer( ragdoll )
    local ply = ragdoll.player
    if not IsValid( ply ) then return end
    ply:SetParent()
    ply:UnSpectate()
    ply:Spawn()
    restorePlayer( ply )

    if not IsValid( ragdoll ) then return end

    ply:SetPos( ragdoll:GetPos() )
    ply:SetVelocity( ragdoll:GetVelocity() )
    local yaw = ragdoll:GetAngles().yaw
    ply:SetAngles( Angle( 0, yaw, 0 ) )
    ragdoll:Remove()
end

local function ragdollPlayer( ply )
    savePlayer( ply )

    local ragdoll = ents.Create( "prop_ragdoll" )
    if not IsValid( ragdoll ) then return end

    ragdoll:SetModel( ply:GetModel() )
    ragdoll:SetPos( ply:GetPos() )
    ragdoll:SetAngles( ply:GetAngles() )
    ragdoll:SetVelocity( ply:GetVelocity() )
    ragdoll:Spawn()

    local boneCount = ragdoll:GetPhysicsObjectCount() - 1
    local velocity = ply:GetVelocity()

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
    local access, tag = ULib.ucl.query( ply, "ulx physgunplayer" )
    if ent:IsPlayer() and ULib.isSandbox() and access and not ent.NoNoclip and not ent.frozen and ply:GetInfoNum( "cl_pickupplayers", 1 ) == 1 then
        -- Extra restrictions! UCL wasn't designed to handle this sort of thing so we're putting it in by hand...
        local restrictions = {}
        ULib.cmds.PlayerArg.processRestrictions( restrictions, ply, {}, tag and ULib.splitArgs( tag )[ 1 ] )
        if restrictions.restrictedTargets == false or (restrictions.restrictedTargets and not table.HasValue( restrictions.restrictedTargets, ent )) then
            return
        end

        ent:SetMoveType( MOVETYPE_NONE )
        local newPos = ent:GetPos()
        local oldPos = ent:GetPos()
        local steamId = ent:SteamID64()
        hook.Add( "Tick", "CFC_Yeet_Tick_Holding" .. steamId, function()
            if not IsValid( ent ) then
                hook.Remove( "Tick", "CFC_Yeet_Tick_Holding" .. steamId )
                return
            end
            newPos = ent:GetPos()
            ent.cfcYeetSpeed = newPos - oldPos
            oldPos = ent:GetPos()
        end)
        return true
    end
end
hook.Add( "PhysgunPickup", "ulxPlayerPickup", playerPickup, HOOK_HIGH )

local function playerDrop( ply, ent )
    if not ent:IsPlayer() then return end
    hook.Remove( "Tick", "CFC_Yeet_Tick_Holding" .. ent:SteamID64() )
    if ent:GetClass() == "player" then
        ent:SetMoveType( MOVETYPE_WALK )
        ent:SetVelocity( ent.cfcYeetSpeed * 50 )

        local access = ULib.ucl.query( ply, "ulx physgunragdollplayer" )
        if not access then return end

        local x = math.abs( ent.cfcYeetSpeed.x )
        local y = math.abs( ent.cfcYeetSpeed.y )
        local z = math.abs( ent.cfcYeetSpeed.z )

        local speed = x + y + z
        local speedLimit = GetConVar( "ulx_physgun_ragdoll_velocity" ):GetInt()

        if speed < speedLimit then return end

        timer.Simple( 0, function()
            local ragdoll = ragdollPlayer( ent )
            ragdoll.player = ent

            timer.Simple( 30, function()
                if IsValid( ragdoll ) then
                    unRagdollPlayer( ragdoll )
                end
            end)

            local steamId = ent:SteamID64()
            hook.Add( "Tick", "CFC_Yeet_Tick_Ragdoll" .. steamId, function()
                if not IsValid( ragdoll ) then
                    hook.Remove( "Tick", "CFC_Yeet_Tick_Ragdoll" .. steamId )
                    ent:Spawn()
                    return
                end

                if ragdoll:GetVelocity() ~= Vector( 0, 0, 0 ) then return end
                unRagdollPlayer( ragdoll )
                hook.Remove( "Tick", "CFC_Yeet_Tick_Ragdoll" .. steamId )
            end)
        end)
    end
end

hook.Add( "PhysgunDrop", "ulxPlayerDrop", playerDrop )
