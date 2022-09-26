AddCSLuaFile( "ulx_yeet/sh_yeet.lua" )

hook.Add( "InitPostEntity", "CFC_ULX_Yeet_InitPostEntity", function()
    include( "ulx_yeet/sh_yeet.lua" )
end )
