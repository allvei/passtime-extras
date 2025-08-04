#include <sdktools_functions>
#include <sourcemod>
#include <tf2>
#include <tf2_stocks>
#include <clientprefs>
#include <clients>
#include <sdktools_gamerules>
#include <sdktools_trace>

#pragma semicolon 1

// Constants
#define RED         0
#define BLU         1
#define TEAM_OFFSET 2

#define PC  return Plugin_Continue
#define PH  return Plugin_Handled
#define pub public
#define Act Action
#define Han Handle
#define i   int
#define v   void
#define f   float
#define b   bool
#define c   char

#define CREATE_CMD(%1) pub Act %1( i client, i args )
#define CREATE_EV_ACT(%1) pub Act %1( Event event, const c[] name, b dontBroadcast )
#define CREATE_EV(%1) pub %1( Event event, const c[] name, b dontBroadcast )

public Plugin myinfo = {
        name        = "passtime.tf extras",
        author      = "xCape",
        description = "Plugin for use in passtime.tf servers",
        version     = "1.3.0",
        url         = "https://github.com/allvei"
}

// Handles
Han g_hCookieFOV;
Han g_hCvarFOVMin;
Han g_hCvarFOVMax;

// Backup system for FOV tracking when Steam connection is down
b g_bSteamConnected = true;              // Track if Steam is currently connected
b g_bBackupFOVDB    = false;             // Track if we're using the backup system
b g_bPlayerTracked[ MAXPLAYERS + 1 ];    // Track if we have a FOV value for this player
i g_iPlayerFOV[     MAXPLAYERS + 1 ];    // Store FOV values for each player

// Respawn time control
ConVar g_cvRespawnTime;
ConVar g_cvTournamentMode;
b g_bRespawnModeActive = true;    // Track if respawn mode is active (similar to soap_tournament.sp's dming)
b g_bRespawnOverride = false;     // Override flag for respawn time
b g_bTeamReadyState[2] = { false, false };  // Track ready state for RED and BLU

pub OnPluginStart() {
    // We'll initialize the backup system only when needed
    //                         Command...
    RegAdminCmd( "sm_setteam", CSetTeam,      ADMFLAG_GENERIC, "Set a client's team" );
    RegAdminCmd( "sm_st",      CSetTeam,      ADMFLAG_GENERIC, "Set a client's team" );
    RegAdminCmd( "sm_ready",   CReady,        ADMFLAG_GENERIC, "Set a team's ready status" );

    RegConsoleCmd( "sm_fov",   CSetFOV,                        "Set your field of view." );
    RegConsoleCmd( "sm_pt_resupply", CRespawnSelf,                "Respawn yourself if you're in your spawnroom" );

    g_hCookieFOV   = RegClientCookie( "sm_fov_cookie", "Desired client field of view", CookieAccess_Private );

    g_hCvarFOVMin  = CreateConVar( "sm_fov_min",      "70",  "Minimum client field of view", _, 1, 1.0, 1, 175.0 );
    g_hCvarFOVMax  = CreateConVar( "sm_fov_max",      "120", "Maximum client field of view", _, 1, 1.0, 1, 175.0 );
    g_cvRespawnTime = CreateConVar( "sm_respawn_time", "0.0", "Time in seconds before player respawns after death (0.0 = instant respawn)", FCVAR_NOTIFY );
    g_cvTournamentMode = FindConVar("mp_tournament");
    
    // Set default respawn time to 0.0 for immediate respawns during ready phase
    g_cvRespawnTime.SetFloat( 0.0 );
    
    // Register respawn override command
    RegAdminCmd( "sm_respawn_override", CRespawnOverride, ADMFLAG_GENERIC, "Override respawn time via player_death event (0=off, 1=on)" );

    // Hook events
    //                              EventPlayer...
    HookEvent( "player_spawn",      EPSpawn );
    HookEvent( "player_connect",    EPConnect );
    HookEvent( "player_disconnect", EPDisconnect );
    HookEvent( "player_death",      EPDeath );
    HookEvent( "tournament_stateupdate", ETournamentStateUpdate );
    HookEvent( "teamplay_round_start", ERoundStart );
    HookEvent( "teamplay_round_win", ERoundEnd );
    HookEvent( "teamplay_game_over", EGameOver );
    HookEvent( "tf_game_over", EGameOver );
    
    // Hook tournament restart command
    RegServerCmd( "mp_tournament_restart", CTournamentRestart, "" );
    
    // Initialize team ready states
    g_bTeamReadyState[0] = false;
    g_bTeamReadyState[1] = false;
    
    // Check ready phase on plugin start
    CheckReadyUpPhase();
}
// Check if we're in the ready-up phase and enable/disable custom respawn times accordingly
v CheckReadyUpPhase() {
    // Check if tournament mode is enabled
    if (g_cvTournamentMode != null && g_cvTournamentMode.BoolValue) {
        // Check if both teams are ready
        b redReady = GameRules_GetProp("m_bTeamReady", 1, 2) != 0;
        b bluReady = GameRules_GetProp("m_bTeamReady", 1, 3) != 0;
        
        g_bTeamReadyState[RED] = redReady;
        g_bTeamReadyState[BLU] = bluReady;
        
        // If both teams are ready, disable custom respawn
        if (redReady && bluReady) {
            StopCustomRespawn();
        } else {
            StartCustomRespawn();
        }
    }
}

// Enable custom respawn times
v StartCustomRespawn() {
    if (g_bRespawnModeActive) {
        return;
    }
    
    g_bRespawnModeActive = true;
    PrintToChatAll("Instant respawn enabled!");
}

// Disable custom respawn times
v StopCustomRespawn() {
    if (!g_bRespawnModeActive) {
        return;
    }
    
    g_bRespawnModeActive = false;
    PrintToChatAll("Instant respawn disabled!");
}

// Commands

// Command to manually set a team's ready status
CREATE_CMD(CReady) {
    if ( args != 2 ) return EndCmd( client, "Usage: sm_ready <red|blu> <0|1>" );

    c teamArg[ 10 ];
    c statusArg[ 2 ];

    GetCmdArg( 1, teamArg,   sizeof( teamArg ) );
    GetCmdArg( 2, statusArg, sizeof( statusArg ) );

    i teamIndex = ParseTeamIndex( teamArg );
    i status    = StringToInt( statusArg );

    // Validate input
    if ( teamIndex == -1 ) return EndCmd( client, "Invalid team. Use 'red|r', 'blue|blu|b'." );
    if ( status < 0 || status > 1 ) return EndCmd( client, "Invalid status. Use 0 (not ready) or 1 (ready)." );

    // Set the team's ready status
    i gameRulesTeamOffset = teamIndex + TEAM_OFFSET;
    GameRules_SetProp( "m_bTeamReady", status, 1, gameRulesTeamOffset );
    
    // Update our internal tracking
    g_bTeamReadyState[teamIndex] = (status != 0);
    
    // Check if we need to update respawn mode
    CheckReadyUpPhase();

    PH;
}
// Change client's team
CREATE_CMD(CSetTeam) {
    c input_team[ 5 ];
    GetCmdArg( 2, input_team, sizeof( input_team ) );
    TFTeam team = ParseTeam( input_team );

    if ( args != 2 || team == TFTeam_Unassigned ) return EndCmd( client, "Usage: sm_setteam <#userid|name> <spec|red|blu>", args );

    c arg_playerTarget[ 33 ];
    GetCmdArg( 1, arg_playerTarget, sizeof( arg_playerTarget ) );

    i target_list[ MAXPLAYERS ];
    c target_name[ MAX_TARGET_LENGTH ];
    b tn_is_ml     = false;
    i target_count = ProcessTargetString( arg_playerTarget, client, target_list, MAXPLAYERS, COMMAND_FILTER_CONNECTED, target_name, sizeof( target_name ), tn_is_ml );
    b check        = false;

    if ( target_count == COMMAND_TARGET_NONE ) PH;

    // Change team of client(s)
    for ( i n = 0; n < target_count; n++ ) {
        i targetId = target_list[ n ];
        if ( !IsValidClient( targetId ) || TF2_GetClientTeam( targetId ) == team ) {
            continue;
        }
        check = true;
        ForcePlayerSuicide( targetId );
        TF2_ChangeClientTeam( targetId, team );
        if ( team != TFTeam_Spectator ) {
            TF2_RespawnPlayer( targetId );
        }
    }

    if ( check ) {
        for ( i n = 1; n <= MaxClients; n++ ) {
            GameRules_SetProp( "m_bTeamReady", 0, .element = n );
        }

        c team_name[ 5 ];
        GetTeamName( view_as<int>( team ), team_name, sizeof( team_name ) );

        ReplyToCommand( client, "Switched %s to %s", target_name, team_name );
    }
    PH;
}
// Set your field of view
CREATE_CMD(CSetFOV) {
    if ( args != 1 ) return EndCmd( client, "Usage: sm_fov <fov>" );

    i fov = GetCmdArgInt( 1 ),
      min = GetConVarInt( g_hCvarFOVMin ),
      max = GetConVarInt( g_hCvarFOVMax );

    if ( fov == 0 ) {
        QueryClientConVar( client, "fov_desired", OnFOVQueried );
        return EndCmd( client, "Your FOV has been reset." );
    }

    if ( fov < min ) return EndCmd( client, "The minimum FOV you can set is %d.", min );
    if ( fov > max ) return EndCmd( client, "The maximum FOV you can set is %d.", max );

    // Try to store in cookies if available
    b cookieSuccess = false;
    if ( AreClientCookiesCached( client ) ) {
        c cookie[ 4 ];
        IntToString( fov, cookie, sizeof( cookie ) );
        SetClientCookie( client, g_hCookieFOV, cookie );
        cookieSuccess     = true;
        g_bSteamConnected = true;    // Steam is connected if cookies work

        // If we were using backup system but Steam is now connected, we can disable it
        if ( g_bBackupFOVDB ) SetBackupSystem( false );
    } else {
        // Steam is down, initialize backup system if not already done
        if ( !g_bBackupFOVDB ) SetBackupSystem( true );
        g_bSteamConnected          = false;

        // Store in backup system
        g_iPlayerFOV[ client ]     = fov;
        g_bPlayerTracked[ client ] = true;
        PrintToChat( client, "Steam connection down. Your FOV is saved locally for this session." );
    }

    // Apply FOV immediately
    SetFOV( client, fov );

    ReplyToCommand( client, "Your FOV has been set to %d.%s", fov,
                    cookieSuccess ? "" : " (Steam connection down, saved for this session only)" );
    PH;
}

// Events

// Player death event handler for respawn control
CREATE_EV_ACT(EPDeath) {
    if (!g_bRespawnModeActive) PC;
    
    i userid = GetClientOfUserId( GetClientOfUserId( event.GetInt( "userid" ) ) );
    
    if (g_bRespawnOverride || g_cvRespawnTime.FloatValue <= 0.0) {
        RequestFrame( Respawn_Frame, userid );
    }
    PC;
}
// Player connect event - prepare for tracking
CREATE_EV(EPConnect) {
    i client = GetClientOfUserId( event.GetInt( "userid" ) );

    if ( client > 0 && client <= MaxClients && g_bBackupFOVDB ) {
        // Reset tracking for this player slot if backup system is active
        g_bPlayerTracked[ client ] = false;
        g_iPlayerFOV[ client ]     = 0;
    }
}
// Player disconnect event - clean up tracking
CREATE_EV(EPDisconnect) {
    i userid = event.GetInt( "userid" );
    i client = GetClientOfUserId( userid );

    if ( client > 0 && client <= MaxClients && g_bBackupFOVDB ) {
        // Clear tracking data for this slot if backup system is active
        g_bPlayerTracked[ client ] = false;
        g_iPlayerFOV[ client ]     = 0;
    }
}
// Restores the client's FOV on spawn
CREATE_EV(EPSpawn) {
    i client = GetClientOfUserId( event.GetInt( "userid" ) );
    if ( !IsValidClient( client ) ) return;

    // Try to restore FOV from cookies first
    if ( AreClientCookiesCached( client ) ) {
        if ( RestoreFOV( client ) ) {
            // If we were using backup but Steam is now connected, we can disable it
            if ( !g_bSteamConnected ) {
                g_bSteamConnected = true;
                if ( g_bBackupFOVDB ) SetBackupSystem( false );
            }
            return;
        }
    } else if ( !g_bBackupFOVDB ) {
        // Steam is down, initialize backup system
        SetBackupSystem( true );
        g_bSteamConnected = false;
    }

    // If cookies failed or aren't cached, try backup system
    if ( g_bBackupFOVDB && g_bPlayerTracked[ client ] && g_iPlayerFOV[ client ] > 0 ) {
        SetFOV( client, g_iPlayerFOV[ client ] );
    } else if ( !g_bSteamConnected ) {
        PrintToChat( client, "Use !fov command to set your preferred FOV." );
    }
}
// Retrieves the client's FOV from their local config and stores it in a cookie
pub OnFOVQueried( QueryCookie cookie, i client, ConVarQueryResult result, const c[] cvarName, const c[] fov ) {
    if ( result != ConVarQuery_Okay ) return;
    SetClientCookie( client, g_hCookieFOV, "" );
    SetFOV(          client, StringToInt( fov ) );
}

// Helpers

// Sends a message to the client and returns PH
Action EndCmd( i client, const c[] format, any... ) {
    c buffer[ 254 ];
    VFormat( buffer, sizeof( buffer ), format, 3 );
    ReplyToCommand( client, "%s", buffer );
    PH;
}
// Checks if a client in-game, connected, not fake, alive and in a valid team
b IsValidClient( i client ) {
    return IsClientInGame( client ) && !IsFakeClient( client ) && IsPlayerAlive( client ) && IsClientConnected( client );
}
b IsPlayerInTeam( i client ) {
    return ( GetClientTeam( client ) == RED || GetClientTeam( client ) == BLU );
}
// Sets the client's FOV
SetFOV( i client, i fov ) {
    SetEntProp( client, Prop_Send, "m_iFOV",        fov );
    SetEntProp( client, Prop_Send, "m_iDefaultFOV", fov );
}
// Retrieves the client's FOV from the cookie and applies it, returns false if invalid
b RestoreFOV( i client ) {
    c cookie[ 4 ];
    GetClientCookie( client, g_hCookieFOV, cookie, sizeof( cookie ) );
    i fov = StringToInt( cookie ),
      min = GetConVarInt( g_hCvarFOVMin ),
      max = GetConVarInt( g_hCvarFOVMax );

    if ( fov < min || fov > max ) return false;

    // If backup system is active, update it with cookie value
    if ( g_bBackupFOVDB ) {
         g_iPlayerFOV[ client ]     = fov;
         g_bPlayerTracked[ client ] = true;
    }

    SetFOV( client, fov );
    return true;
}
// Parse TFTeam from string
TFTeam ParseTeam( c[] t ) {
    return StrEqual( t, "spectator" ) || StrEqual( t, "spec" ) || StrEqual( t, "s" ) ? TFTeam_Spectator
         : StrEqual( t, "red" )       || StrEqual( t, "r" )                          ? TFTeam_Red
         : StrEqual( t, "blue" )      || StrEqual( t, "blu" )  || StrEqual( t, "b" ) ? TFTeam_Blue
                                                                                     : TFTeam_Unassigned;
}
// Converts team name string to RED/BLU constants
i ParseTeamIndex( c[] t ) {
    return StrEqual( t, "red" ) || StrEqual( t, "r" )                          ? RED
         : StrEqual( t, "blu" ) || StrEqual( t, "blue" ) || StrEqual( t, "b" ) ? BLU
                                                                               : -1;
}
// Enable or disable the backup system based on Steam connection status
SetBackupSystem( b a ) {
    if ( g_bBackupFOVDB == a ) return;    // Already in desired state
    g_bBackupFOVDB = a;
    // Initialize/clear player tracking arrays
    for ( i n = 0; n <= MaxClients; n++ ) {
        g_iPlayerFOV[ n ]     = 0;
        g_bPlayerTracked[ n ] = false;
    }

    if ( a ) PrintToServer( "Backup FOV system enabled - Steam connection is down" );
    else PrintToServer( "Backup FOV system disabled - Steam connection restored" );
}
// Command to override respawn time
CREATE_CMD(CRespawnOverride) {
    if (args != 1) {
        ReplyToCommand(client, "Usage: sm_respawn_override <0|1>");
        return 3;
    }
    
    c arg[2];
    GetCmdArg(1, arg, sizeof(arg));
    i value = StringToInt(arg);
    
    g_bRespawnOverride = (value != 0);
    ReplyToCommand(client, "[Respawn Control] Respawn override %s", g_bRespawnOverride ? "enabled" : "disabled");
    
    PH;
}

// Tournament restart command handler
pub Act CTournamentRestart(i args) {
    PrintToServer("[Respawn Control] Tournament restart detected, resetting ready state and enabling respawn mode");
    g_bTeamReadyState[0] = false;
    g_bTeamReadyState[1] = false;
    StartCustomRespawn();
    PH;
}

// Tournament state update event handler
CREATE_EV(ETournamentStateUpdate) {
    CheckReadyUpPhase();
}

// Round start event handler
CREATE_EV_ACT(ERoundStart) {
    StopCustomRespawn();
    PC;
}

// Round end event handler
CREATE_EV_ACT(ERoundEnd) {
    PC;
}

// Game over event handler
CREATE_EV(EGameOver) {
    g_bTeamReadyState[0] = false;
    g_bTeamReadyState[1] = false;
    GameRules_SetProp("m_bTeamReady", 0, 1, 2, false);
    GameRules_SetProp("m_bTeamReady", 0, 1, 3, false);
    StartCustomRespawn();
}
// Respawn player frame callback
pub v Respawn_Frame( any userid ) {
    i client = GetClientOfUserId( userid );
    
    if ( client != 0 && GetClientTeam( client ) > 1 && !IsPlayerAlive( client ) ) {
        TF2_RespawnPlayer( client );
    }
}

// Command to respawn yourself if in spawnroom
CREATE_CMD(CRespawnSelf) {
    // Check if client is valid
    if (!IsValidClient(client)) {
        return EndCmd(client, "You must be in-game to use this command.");
    }

    if (!IsPlayerInTeam(client)) {
        return EndCmd(client, "You must be on a team to use this command.");
    }
    
    // Check if player is in their own spawnroom
    if (!IsPlayerInSpawnRoom(client)) {
        return EndCmd(client, "You must be in your team's spawnroom to use this command.");
    }
    
    // Respawn the player
    ForcePlayerSuicide(client);
    RequestFrame(RespawnAfterSuicide, GetClientUserId(client));
    
    return EndCmd(client, "Respawning...");
}

// Check if a player is in their own spawnroom
b IsPlayerInSpawnRoom(i client) {
    // Check if player is in a spawn area using TF2-specific detection
    
    // Get player's current position
    f pos[3];
    GetClientAbsOrigin(client, pos);
    
    // Create a trace ray from the player's position downward
    f endPos[3];
    endPos[0] = pos[0];
    endPos[1] = pos[1];
    endPos[2] = pos[2] - 20.0; // Trace downward a bit
    
    // Perform the trace
    TR_TraceRayFilter(pos, endPos, MASK_PLAYERSOLID, RayType_EndPoint, TraceFilter_DontHitPlayers, client);
    
    if (TR_DidHit()) {
        // Get the entity that was hit
        i entity = TR_GetEntityIndex();
        
        if (entity > 0) {
            c classname[64];
            GetEdictClassname(entity, classname, sizeof(classname));
            
            // Check if the entity is a spawn room floor/trigger
            if (StrContains(classname, "func_respawnroom") != -1 || 
                StrContains(classname, "trigger_spawn") != -1) {
                return true;
            }
        }
    }
    
    // Check if player has respawn room protection
    if (TF2_IsPlayerInCondition(client, TFCond_Ubercharged) && 
        !TF2_IsPlayerInCondition(client, TFCond_UberchargedHidden) && 
        !TF2_IsPlayerInCondition(client, TFCond_UberchargedCanteen)) {
        // Player has spawn protection, likely in spawn room
        return true;
    }
    
    return false;
}

// Respawn player after suicide
pub v RespawnAfterSuicide(any userid) {
    i client = GetClientOfUserId(userid);
    if (client != 0 && GetClientTeam(client) > 1) {
        TF2_RespawnPlayer(client);
    }
}

// Trace filter that ignores players
pub b TraceFilter_DontHitPlayers(i entity, i contentsMask, any data) {
    // Don't hit players or their projectiles
    if (entity > 0 && entity <= MaxClients) {
        return false;
    }
    return true;
}

// Forwards

// Called when a client's cookies have been loaded
pub OnClientCookiesCached( i client ) {
    // Steam connection is now available
    g_bSteamConnected = true;

    // If we were using backup system but Steam is now connected, we can disable it
    if ( g_bBackupFOVDB ) SetBackupSystem( false );

    // Try to load from cookies
    RestoreFOV( client );
}
// Restores the client's FOV when they are teleportedConfigFormat
pub TF2_OnConditionRemoved( i client, TFCond cond ) {
    if ( cond != TFCond_Zoomed || !RestoreFOV( client ) ) return;
}
