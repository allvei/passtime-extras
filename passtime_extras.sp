#include <sdktools_functions>
#include <sourcemod>
#include <tf2>
#include <tf2_stocks>
#include <clientprefs>
#include <clients>
#include <sdktools_gamerules>
#include <sdktools_trace>
#include <sdktools_entoutput>
#include <sdkhooks>

#pragma semicolon 1

// Constants
#define RED         0
#define BLU         1
#define TEAM_OFFSET 2

// Custom condition for tracking players in spawn rooms
#define TFCond_InSpawnRoom 100

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
        version     = "1.4.0",
        url         = "https://github.com/allvei"
}

// Handles
Han g_hCookieFOV;
Han g_hCvarFOVMin;
Han g_hCvarFOVMax;
ConVar g_cvMatchActive;

// Backup system for FOV tracking when Steam connection is down
b g_bSteamConnected = true;              // Track if Steam is currently connected
b g_bBackupFOVDB    = false;             // Track if we're using the backup system
b g_bPlayerTracked[ MAXPLAYERS + 1 ];    // Track if we have a FOV value for this player
i g_iPlayerFOV[     MAXPLAYERS + 1 ];    // Store FOV values for each player

// Spawn room tracking
b g_bPlayerInSpawnRoom[MAXPLAYERS + 1];                  // Track if player is in any spawn room
#define MAX_SPAWN_ROOMS 8                                // Maximum number of spawn rooms a player can touch simultaneously
i g_iPlayerSpawnRooms[MAXPLAYERS + 1][MAX_SPAWN_ROOMS];  // Track which spawn rooms a player is in
i g_iPlayerSpawnRoomCount[MAXPLAYERS + 1];               // Track how many spawn rooms a player is in (for debugging)
i g_iSpawnRoomTeam[2048];                                // Track which team a spawn room belongs to (entity index -> team)
b g_bResupplyKeyDown[MAXPLAYERS + 1];                    // Track if resupply key is currently down
b g_bResupplyUsed[MAXPLAYERS + 1];                       // Track if resupply has been used during current key press

// No-damage toggle per player
b g_bNoDamage[MAXPLAYERS + 1];
i g_iPreDamageHP[MAXPLAYERS + 1];
b g_bPendingRestoreHP[MAXPLAYERS + 1];

// Infinite ammo toggle per player
b g_bInfiniteAmmo[MAXPLAYERS + 1];

// Original ammo values for infinite ammo restoration (only allocated for players using infinite ammo)
ArrayList g_hOriginalAmmo[MAXPLAYERS + 1]; // Dynamic arrays for players who actually use infinite ammo

// Respawn time control
ConVar g_cvRespawnTime;
ConVar g_cvTournamentMode;
ConVar g_cvRespawnModeActive; // ConVar to control if respawn mode is active
b g_bTeamReadyState[2] = { false, false }; // Track ready state for RED and BLU

// Round state tracking (for reload detection and command gating)
b g_bRoundActive = false; // True when the round is live (not in warmup/setup)

// Saved spawn point (admin tools)
b g_bSavedSpawnValid = false;
f g_vSavedSpawnOrigin[3];
f g_vSavedSpawnAngles[3];
f g_vSavedSpawnVelocity[3];

#define MAX_SLOTS 6
i g_iSavedClip1[MAX_SLOTS];
i g_iSavedClip2[MAX_SLOTS];
i g_iSavedAmmoType[MAX_SLOTS][2];
i g_iSavedAmmoCount[MAX_SLOTS][2];

pub OnPluginStart() {
    //                                  Command...
    RegAdminCmd( "sm_setteam",          CSetTeam,        ADMFLAG_GENERIC, "Set a client's team" );
    RegAdminCmd( "sm_st",               CSetTeam,        ADMFLAG_GENERIC, "Set a client's team" );
    RegAdminCmd( "sm_listspawnrooms",   CListSpawnRooms, ADMFLAG_GENERIC, "Lists spawn rooms a player is currently in" );
    RegAdminCmd( "sm_startmatch",       CStartMatch,     ADMFLAG_GENERIC, "Start match mode" );
    RegAdminCmd( "sm_stopmatch",        CStopMatch,      ADMFLAG_GENERIC, "Stop match mode" );
    RegAdminCmd( "sm_lsr",              CListSpawnRooms, ADMFLAG_GENERIC, "Lists spawn rooms a player is currently in" );
    RegAdminCmd( "sm_ready",            CReady,          ADMFLAG_GENERIC, "Set a team's ready status" );
    RegAdminCmd( "sm_r",                CReady,          ADMFLAG_GENERIC, "Set a team's ready status" );
    RegAdminCmd( "sm_setclass",         CSetClass,       ADMFLAG_GENERIC, "Set a client's class: sm_setclass <#userid|name> <class>" );
    RegAdminCmd( "sm_sc",               CSetClass,       ADMFLAG_GENERIC, "Set a client's class" );
    RegAdminCmd( "sm_debug_roundtime",  CRoundTimeDebug, ADMFLAG_GENERIC, "Debug: print team_round_timer info" );
    RegAdminCmd( "sm_drt",              CRoundTimeDebug, ADMFLAG_GENERIC, "Debug: print team_round_timer info" );

    // Save/Load are available to all players
    RegConsoleCmd( "sm_save",         CSaveSpawn,       "Save a spawn point" );
    RegConsoleCmd( "sm_sv",           CSaveSpawn,       "Save a spawn point" );
    RegConsoleCmd( "sm_load",         CLoadSpawn,       "Teleport to saved spawn" );
    RegConsoleCmd( "sm_ld",           CLoadSpawn,       "Teleport to saved spawn" );
    RegConsoleCmd( "sm_invulnerable", CNoDamage,        "Toggle invulnerability" );
    RegConsoleCmd( "sm_inv",          CNoDamage,        "Toggle invulnerability" );
    RegConsoleCmd( "sm_ammo",         CInfiniteAmmo,    "Toggle infinite ammo" );
    RegConsoleCmd( "sm_a",            CInfiniteAmmo,    "Toggle infinite ammo" );
    RegConsoleCmd( "sm_fov",          CSetFOV,          "Set your field of view." );
    RegConsoleCmd( "+sm_pt_resupply", CResupplyKeyDown, "Press and hold to resupply when in spawnroom" );
    RegConsoleCmd( "-sm_pt_resupply", CResupplyKeyUp,   "Release resupply key" );

    g_hCookieFOV = RegClientCookie( "sm_fov_cookie", "Desired client field of view", CookieAccess_Private );

    g_hCvarFOVMin         = CreateConVar( "sm_fov_min",             "70",  "Minimum client field of view", _, 1, 1.0, 1, 175.0 );
    g_hCvarFOVMax         = CreateConVar( "sm_fov_max",             "120", "Maximum client field of view", _, 1, 1.0, 1, 175.0 );
    g_cvRespawnTime       = CreateConVar( "sm_respawn_time",        "0.0", "Player respawn delay in seconds", FCVAR_NOTIFY );
    g_cvRespawnModeActive = CreateConVar( "sm_respawn_mode_active", "1",   "Enable respawn mode" );
    g_cvMatchActive       = CreateConVar( "sm_match_active",        "0",   "Enable match mode (disables invulnerability and infinite ammo)" );

    g_cvTournamentMode = FindConVar("mp_tournament");
    
    // Set default respawn time to 0.0 for immediate respawns during ready phase
    g_cvRespawnTime.SetFloat( 0.0 );

    // Hook events
    //                                   EventPlayer...
    HookEvent( "player_spawn",           EPSpawn );
    HookEvent( "player_connect",         EPConnect );
    HookEvent( "player_disconnect",      EPDisconnect );
    HookEvent( "player_death",           EPDeath );
    HookEvent( "tournament_stateupdate", ETournamentStateUpdate );
    HookEvent( "teamplay_round_start",   ERoundStart );
    HookEvent( "teamplay_round_win",     ERoundEnd );
    HookEvent( "teamplay_game_over",     EGameOver );
    HookEvent( "tf_game_over",           EGameOver );
    
    // Hook tournament restart command
    RegServerCmd( "mp_tournament_restart", CTournamentRestart, "" );
    
    // Initialize team ready states
    g_bTeamReadyState[0] = false;
    g_bTeamReadyState[1] = false;
    
    // Check ready phase on plugin start
    CheckReadyUpPhase();
    // Detect round state on plugin load (in case of plugin reload mid-game)
    DetectRoundState();
    
    // Spawn room entity outputs are now handled by direct collision detection
    // No need to hook OnStartTouch/OnEndTouch as we use IsPlayerTouchingSpawnRoom()
    
    // Initialize spawn room tracking arrays
    for (i n = 1; n <= MaxClients; n++) {
        g_bPlayerInSpawnRoom[n]    = false;
        g_iPlayerSpawnRoomCount[n] = 0;
        g_bResupplyKeyDown[n]      = false;
        g_bResupplyUsed[n]         = false;
        
        // Initialize spawn room entity tracking
        for (i s = 0; s < MAX_SPAWN_ROOMS; s++) {
            g_iPlayerSpawnRooms[n][s] = -1;  // -1 means no entity
        }
    }
    
    // Initialize spawn room team tracking
    for (i n = 0; n < 2048; n++) {
        g_iSpawnRoomTeam[n] = 0;  // 0 means unassigned team
    }
    
    // Initialize saved ammo/velocity buffers
    for (i s = 0; s < MAX_SLOTS; s++) {
        g_iSavedClip1[s] = -1;
        g_iSavedClip2[s] = -1;
        for (i t = 0; t < 2; t++) {
            g_iSavedAmmoType[s][t]  = -1;
            g_iSavedAmmoCount[s][t] = 0;
        }
    }
    
    // Initialize infinite ammo ArrayList handles
    for (i n = 1; n <= MaxClients; n++) {
        g_hOriginalAmmo[n] = null;
        g_bInfiniteAmmo[n] = false;
    }
    
    // Hook damage for currently connected clients and reset nodamage flags
    for (i n = 1; n <= MaxClients; n++) {
        g_bNoDamage[n] = false;
        g_bPendingRestoreHP[n] = false;
        g_iPreDamageHP[n] = 0;
        if ( IsClientInGame(n) ) {
            SDKHook( n, SDKHook_OnTakeDamage,     Hook_OnTakeDamage );
            SDKHook( n, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost );
        }
    }
}

// Hook per-client when they enter the server so our damage filter is active
pub v OnClientPutInServer( i client ) {
    SDKHook( client, SDKHook_OnTakeDamage,     Hook_OnTakeDamage );
    SDKHook( client, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost );
}

// Check if we're in the ready-up phase and enable/disable custom respawn times accordingly
v CheckReadyUpPhase() {
    // Get tournament mode status
    b tournamentMode = g_cvTournamentMode.BoolValue;
    
    // Check if we're in tournament mode
    if (!tournamentMode) {
        // Not in tournament mode, disable custom respawn
        
        StopMatch();
        return;
    }
    
    // Check if both teams are ready
    b redReady = view_as<b>(GameRules_GetProp("m_bTeamReady", 1, TEAM_OFFSET + RED));
    b bluReady = view_as<b>(GameRules_GetProp("m_bTeamReady", 1, TEAM_OFFSET + BLU));
    
    // Update our internal tracking
    g_bTeamReadyState[RED] = redReady;
    g_bTeamReadyState[BLU] = bluReady;
    
    
    // If both teams are ready, stop custom respawn (live phase)
    if (redReady && bluReady) {
        StopMatch();
        g_bRoundActive = true;
    } else {
        StartMatch();
        g_bRoundActive = false;
    }
}

// Disable invulnerability for a specific player
v DisablePlayerInvulnerability(i client) {
    if (g_bNoDamage[client]) {
        g_bNoDamage[client] = false;
        // Force respawn to apply changes cleanly
        if (IsPlayerAlive(client)) {
            TF2_RespawnPlayer(client);
        }
    }
}

// Disable infinite ammo for a specific player
v DisablePlayerInfiniteAmmo(i client) {
    if (g_bInfiniteAmmo[client]) {
        g_bInfiniteAmmo[client] = false;
        
        // Restore original ammo values
        if (g_hOriginalAmmo[client] != null) {
            delete g_hOriginalAmmo[client];
            g_hOriginalAmmo[client] = null;
        }
    }
}

// Disable invulnerability and infinite ammo for all players
v DisableAllPlayersSpecialModes() {
    for (i client = 1; client <= MaxClients; client++) {
        if (IsClientInGame(client)) {
            DisablePlayerInvulnerability(client);
            DisablePlayerInfiniteAmmo(client);
        }
    }
}

// Start match mode
v StartMatch() {
    PrintToServer("[PTE] StartMatch called");
    
    if (!g_cvMatchActive.BoolValue) {
        g_cvMatchActive.SetBool(true);
        PrintToServer("[PTE] Match mode activated");
        
        // Disable respawn mode during match
        if (g_cvRespawnModeActive.BoolValue) {
            g_cvRespawnModeActive.SetBool(false);
            g_cvRespawnTime.RestoreDefault();
            PrintToServer("[PTE] Respawn mode disabled during match");
        }
        
        // Disable invulnerability and infinite ammo for all players
        DisableAllPlayersSpecialModes();
        
        // Force all players to respawn to ensure they have correct state
        for (i client = 1; client <= MaxClients; client++) {
            if (IsClientInGame(client) && IsPlayerAlive(client)) {
                TF2_RespawnPlayer(client);
                PrintToServer("[PTE] Player %d respawned to apply match state", client);
            }
        }
        
        PrintToServer("[PTE] StartMatch completed - all players should be respawned with correct state");
    } else {
        PrintToServer("[PTE] StartMatch called but match is already active");
    }
}

// Re-enable respawn mode
v EnableRespawnMode() {
    if (!g_cvRespawnModeActive.BoolValue) {
        g_cvRespawnModeActive.SetBool(true);
        g_cvRespawnTime.SetFloat(0.0);
    }
}

// Stop match mode
v StopMatch() {
    PrintToServer("[PTE] StopMatch called");
    
    if (g_cvMatchActive.BoolValue) {
        g_cvMatchActive.SetBool(false);
        PrintToServer("[PTE] Match mode deactivated");
        
        // Re-enable respawn mode if it was previously active
        EnableRespawnMode();
        
        PrintToServer("[PTE] StopMatch completed");
    } else {
        PrintToServer("[PTE] StopMatch called but match is not active");
    }
}

// Detect current round state, used on plugin reloads to infer whether the game is ongoing
v DetectRoundState() {
    // Default to not active
    g_bRoundActive = false;
    
    // If in tournament mode, we can infer from team ready states
    if (g_cvTournamentMode.BoolValue) {
        b redReady = view_as<b>(GameRules_GetProp("m_bTeamReady", 1, TEAM_OFFSET + RED));
        b bluReady = view_as<b>(GameRules_GetProp("m_bTeamReady", 1, TEAM_OFFSET + BLU));
        g_bRoundActive = (redReady && bluReady);
        return;
    }
    
    // Non-tournament fallback: use team_round_timer if available
    i ent = -1;
    while ((ent = FindEntityByClassname(ent, "team_round_timer")) != -1) {
        // Use the first valid timer
        b paused = view_as<b>(GetEntProp(ent, Prop_Send, "m_bTimerPaused"));
        g_bRoundActive = !paused; // if timer isn't paused, treat as active
        break;
    }
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
        if ( team != TFTeam_Spectator ) TF2_RespawnPlayer( targetId );
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
        g_bSteamConnected = false;

        // Store in backup system
        g_iPlayerFOV[ client ]     = fov;
        g_bPlayerTracked[ client ] = true;
    }

    // Apply FOV immediately
    SetFOV( client, fov );

    ReplyToCommand( client, "Your FOV has been set to %d.%s", fov,
                    cookieSuccess ? "" : " (Steam connection down, saved for this session only)" );
    PH;
}

// Save a spawn point (global) - allowed only when round is inactive
CREATE_CMD(CSaveSpawn) {
    if ( args != 0 ) return EndCmd( client, "Usage: sm_save" );
    if ( g_bRoundActive ) return EndCmd( client, "This command is only available during warmup or when the round is inactive." );
    if ( client <= 0 || client > MaxClients || !IsClientInGame( client ) ) PH;
    if ( !IsPlayerAlive( client ) ) return EndCmd( client, "You must be alive to save your position." );

    GetClientAbsOrigin( client, g_vSavedSpawnOrigin );
    GetClientEyeAngles( client,  g_vSavedSpawnAngles );
    // Save current velocity
    GetEntPropVector( client, Prop_Data, "m_vecAbsVelocity", g_vSavedSpawnVelocity );
    
    // Save current ammo and clips for carried weapons
    for ( i s = 0; s < MAX_SLOTS; s++ ) {
        g_iSavedClip1[s] = -1;
        g_iSavedClip2[s] = -1;
        g_iSavedAmmoType[s][0] = -1;
        g_iSavedAmmoType[s][1] = -1;
        g_iSavedAmmoCount[s][0] = 0;
        g_iSavedAmmoCount[s][1] = 0;
        
        i wep = GetPlayerWeaponSlot( client, s );
        if ( wep != -1 ) {
            g_iSavedClip1[s] = GetEntProp( wep, Prop_Send, "m_iClip1" );
            g_iSavedClip2[s] = GetEntProp( wep, Prop_Send, "m_iClip2" );
            
            i at1 = GetEntProp( wep, Prop_Send, "m_iPrimaryAmmoType" );
            i at2 = GetEntProp( wep, Prop_Send, "m_iSecondaryAmmoType" );
            g_iSavedAmmoType[s][0] = at1;
            g_iSavedAmmoType[s][1] = at2;
            if ( at1 >= 0 ) g_iSavedAmmoCount[s][0] = GetEntProp( client, Prop_Send, "m_iAmmo", _, at1 );
            if ( at2 >= 0 ) g_iSavedAmmoCount[s][1] = GetEntProp( client, Prop_Send, "m_iAmmo", _, at2 );
        }
    }
    g_bSavedSpawnValid = true;

    EndCmd( client, "Saved spawn at (%.1f %.1f %.1f)", g_vSavedSpawnOrigin[0], g_vSavedSpawnOrigin[1], g_vSavedSpawnOrigin[2] );
    
    PH;
}

// Load (teleport) to saved spawn - allowed only when round is inactive
CREATE_CMD(CLoadSpawn) {
    if ( args != 0 ) return EndCmd( client, "Usage: sm_load" );
    if ( g_bRoundActive ) return EndCmd( client, "This command is only available during warmup or when the round is inactive." );
    if ( !g_bSavedSpawnValid ) return EndCmd( client, "No saved spawn point set yet." );
    if ( client <= 0 || client > MaxClients || !IsClientInGame( client ) ) PH;
    if ( !IsPlayerAlive( client ) ) return EndCmd( client, "You must be alive to use this." );

    TeleportEntity( client, g_vSavedSpawnOrigin, g_vSavedSpawnAngles, g_vSavedSpawnVelocity );
    
    // Restore ammo and clips for current carried weapons
    for ( i s = 0; s < MAX_SLOTS; s++ ) {
        i wep = GetPlayerWeaponSlot( client, s );
        if ( wep != -1 ) {
            if ( g_iSavedClip1[s] >= 0 ) SetEntProp( wep, Prop_Send, "m_iClip1", g_iSavedClip1[s] );
            if ( g_iSavedClip2[s] >= 0 ) SetEntProp( wep, Prop_Send, "m_iClip2", g_iSavedClip2[s] );
        }
        
        // Set reserve ammo by ammo types
        i at1 = g_iSavedAmmoType[s][0];
        i at2 = g_iSavedAmmoType[s][1];
        if ( at1 >= 0 ) SetEntProp( client, Prop_Send, "m_iAmmo", g_iSavedAmmoCount[s][0], _, at1 );
        if ( at2 >= 0 ) SetEntProp( client, Prop_Send, "m_iAmmo", g_iSavedAmmoCount[s][1], _, at2 );
    }
    PH;
}

// Toggle no-damage mode: you take no damage and deal no damage (knockback still applies)
CREATE_CMD(CNoDamage) {
    if ( args > 1 ) return EndCmd( client, "Usage: sm_nodamage [0|1]" );
    
    b newValue;
    
    if ( args == 0 ) {
        newValue = !g_bNoDamage[ client ];
        g_bNoDamage[ client ] = newValue;
    } else {
        c arg[ 12 ];
        GetCmdArg( 1, arg, sizeof( arg ) );
        if ( StrEqual( arg, "1" ) || StrEqual( arg, "on", false ) || StrEqual( arg, "true", false ) || StrEqual( arg, "enable", false ) ) {
            newValue = true;
            g_bNoDamage[ client ] = true;
        } else if ( StrEqual( arg, "0" ) || StrEqual( arg, "off", false ) || StrEqual( arg, "false", false ) || StrEqual( arg, "disable", false ) ) {
            newValue = false;
            g_bNoDamage[ client ] = false;
        } else {
            return EndCmd( client, "Usage: sm_nodamage [0|1]" );
        }
    }
    
    // If player is alive, force respawn to apply changes cleanly
    if ( IsPlayerAlive( client ) ) {
        TF2_RespawnPlayer( client );
    }
    
    ReplyToCommand( client, "No-damage %s.", g_bNoDamage[ client ] ? "ENABLED" : "DISABLED" );
    PH;
}

// Toggle infinite ammo mode
CREATE_CMD(CInfiniteAmmo) {
    if ( args > 1 ) return EndCmd( client, "Usage: sm_infammo [0|1]" );
    
    b oldValue = g_bInfiniteAmmo[ client ];
    
    if ( args == 0 ) {
        g_bInfiniteAmmo[ client ] = !g_bInfiniteAmmo[ client ];
    } else {
        c arg[ 12 ];
        GetCmdArg( 1, arg, sizeof( arg ) );
        if ( StrEqual( arg, "1" ) || StrEqual( arg, "on", false ) || StrEqual( arg, "true", false ) || StrEqual( arg, "enable", false ) ) {
            g_bInfiniteAmmo[ client ] = true;
            
            // If enabling and wasn't previously enabled, store original ammo values
            if ( !oldValue ) {
                StoreOriginalAmmo( client );
            }
        } else if ( StrEqual( arg, "0" ) || StrEqual( arg, "off", false ) || StrEqual( arg, "false", false ) || StrEqual( arg, "disable", false ) ) {
            g_bInfiniteAmmo[ client ] = false;
        } else {
            return EndCmd( client, "Usage: sm_infammo [0|1]" );
        }
    }
    
    // If player is alive, force respawn to apply changes cleanly
    if ( IsPlayerAlive( client ) ) {
        TF2_RespawnPlayer( client );
    }
    
    ReplyToCommand( client, "Infinite ammo %s.", g_bInfiniteAmmo[ client ] ? "ENABLED" : "DISABLED" );
    PH;
}

// Set a player's class
CREATE_CMD(CSetClass) {
    if ( args != 2 ) return EndCmd( client, "Usage: sm_setclass <#userid|name> <class>" );

    c classArg[ 16 ];
    GetCmdArg( 2, classArg, sizeof( classArg ) );
    TFClassType tfclass = ParseClass( classArg );
    if ( tfclass == TFClass_Unknown ) return EndCmd( client, "Invalid class. Use class name or number" );

    c targetArg[ 33 ];
    GetCmdArg( 1, targetArg, sizeof( targetArg ) );

    i targets[ MAXPLAYERS ];
    c target_name[ MAX_TARGET_LENGTH ];
    b tn_is_ml = false;
    i count = ProcessTargetString( targetArg, client, targets, MAXPLAYERS, COMMAND_FILTER_CONNECTED, target_name, sizeof( target_name ), tn_is_ml );
    b changed = false;
    if ( count == COMMAND_TARGET_NONE ) PH;

    for ( i n = 0; n < count; n++ ) {
        i tid = targets[ n ];
        if ( tid <= 0 || tid > MaxClients || !IsClientInGame( tid ) ) continue;
        if ( TF2_GetClientTeam( tid ) == TFTeam_Spectator ) continue;
        TF2_SetPlayerClass( tid, tfclass );
        TF2_RespawnPlayer( tid );
        changed = true;
    }

    if ( changed ) {
        c className[16];
        switch (tfclass) {
            case TFClass_Scout:    strcopy(className, sizeof(className), "Scout");
            case TFClass_Soldier:  strcopy(className, sizeof(className), "Soldier");
            case TFClass_Pyro:     strcopy(className, sizeof(className), "Pyro");
            case TFClass_DemoMan:  strcopy(className, sizeof(className), "Demoman");
            case TFClass_Heavy:    strcopy(className, sizeof(className), "Heavy");
            case TFClass_Engineer: strcopy(className, sizeof(className), "Engineer");
            case TFClass_Medic:    strcopy(className, sizeof(className), "Medic");
            case TFClass_Sniper:   strcopy(className, sizeof(className), "Sniper");
            case TFClass_Spy:      strcopy(className, sizeof(className), "Spy");
            default:               strcopy(className, sizeof(className), "Unknown");
        }
        ReplyToCommand( client, "Set %s class to %s", target_name, className );
    }
    PH;
}

// Debug: print team_round_timer state
CREATE_CMD(CRoundTimeDebug) {
    // PrintRoundTimerDebugInfo(client);
    // Function not implemented
    ReplyToCommand(client, "Round timer debug function not implemented.");
    PH;
}

// Start match command
CREATE_CMD(CStartMatch) {
    StartMatch();
    ReplyToCommand(client, "Match mode started. Invulnerability and infinite ammo disabled for all players.");
    PH;
}

// Stop match command
CREATE_CMD(CStopMatch) {
    StopMatch();
    ReplyToCommand(client, "Match mode stopped. Respawn mode re-enabled.");
    PH;
}

// Parse class from string
TFClassType ParseClass( c[] s ) {
    if ( StrEqual( s, "scout" )    || StrEqual( s, "1" ) ) return TFClass_Scout;
    if ( StrEqual( s, "soldier" )  || StrEqual( s, "2" ) ) return TFClass_Soldier;
    if ( StrEqual( s, "pyro" )     || StrEqual( s, "3" ) ) return TFClass_Pyro;
    if ( StrEqual( s, "demo" )     || StrEqual( s, "demoman" ) || StrEqual( s, "4" ) ) return TFClass_DemoMan;
    if ( StrEqual( s, "heavy" )    || StrEqual( s, "heavyweapons" ) || StrEqual( s, "5" ) ) return TFClass_Heavy;
    if ( StrEqual( s, "engineer" ) || StrEqual( s, "engie" ) || StrEqual( s, "6" ) ) return TFClass_Engineer;
    if ( StrEqual( s, "medic" )    || StrEqual( s, "7" ) ) return TFClass_Medic;
    if ( StrEqual( s, "sniper" )   || StrEqual( s, "8" ) ) return TFClass_Sniper;
    if ( StrEqual( s, "spy" )      || StrEqual( s, "9" ) ) return TFClass_Spy;
    return TFClass_Unknown;
}

// Events

// Handle player death event
pub Action EPDeath( Event event, const c[] name, b dontBroadcast ) {
    i userid = event.GetInt( "userid" );
    i client = GetClientOfUserId(userid);
    
    // Validate client before proceeding
    if (client <= 0 || client > MaxClients || !IsClientInGame(client)) PC;
    
    // Reset player's spawn room tracking on death
    ResetPlayerSpawnRooms(client);
    
    if (!g_cvRespawnModeActive.BoolValue) PC;
    
    if (g_cvRespawnTime.FloatValue <= 0.0) {
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
    return client > 0 && client <= MaxClients && IsClientInGame( client ) && !IsFakeClient( client ) && IsPlayerAlive( client ) && IsClientConnected( client );
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
    else PrintToServer(     "Backup FOV system disabled - Steam connection restored" );
}

// Handle tournament restart command
pub Action CTournamentRestart( i args ) {
    CheckReadyUpPhase();
    PC;
}

// Handle tournament state update event
pub Action ETournamentStateUpdate( Event event, const c[] name, b dontBroadcast ) {
    CheckReadyUpPhase();
    PC;
}

// Round start event handler
CREATE_EV_ACT(ERoundStart) {
    StopMatch();
    g_bRoundActive = true;
    PC;
}

// Round end event handler
CREATE_EV_ACT(ERoundEnd) {
    g_bRoundActive = false;
    PC;
}

// Game over event handler
CREATE_EV(EGameOver) {
    g_bTeamReadyState[0] = false;
    g_bTeamReadyState[1] = false;
    GameRules_SetProp("m_bTeamReady", 0, 1, 2, false);
    GameRules_SetProp("m_bTeamReady", 0, 1, 3, false);
    StartMatch();
    g_bRoundActive = false;
}
// Respawn frame callback
pub v Respawn_Frame( any userid ) {
    // Get client from userid and validate
    i client = GetClientOfUserId( userid );
    
    
    // Validate client is connected and in-game
    if (client <= 0 || client > MaxClients || !IsClientInGame(client)) return;
    
    // Only respawn if on a team and not alive
    if (GetClientTeam(client) > 1 && !IsPlayerAlive(client)) TF2_RespawnPlayer(client);
}

// Command for when resupply key is pressed
CREATE_CMD(CResupplyKeyDown) {
    // Check if client is valid
    if (!IsClientInGame(client)) return EndCmd(client, "You must be in-game to use this command.");
    
    // Mark the key as down and reset used flag
    g_bResupplyKeyDown[client] = true;
    g_bResupplyUsed[client] = false;
    
    // Try to resupply immediately if in spawn room
    TryResupplyPlayer(client);
    
    PH;
}

// Command for when resupply key is released
CREATE_CMD(CResupplyKeyUp) {
    // Check if client is valid
    if (!IsClientInGame(client)) return EndCmd(client, "You must be in-game to use this command.");
    
    // Mark the key as up
    g_bResupplyKeyDown[client] = false;
    
    PH;
}

// Try to resupply a player if conditions are met
v TryResupplyPlayer(i client) {
    // Check if key is down and resupply hasn't been used yet
    if (!g_bResupplyKeyDown[client] || g_bResupplyUsed[client]) return;
    
    // Check if player is alive and in a valid team
    if (!IsPlayerAlive(client)) return;
    
    i playerTeam = GetClientTeam(client);
    if (playerTeam <= 1) return;
    
    if (!IsPlayerTouchingSpawnRoom(client)) return;
    
    // Check if player is in their own team's spawnroom
    // Check each spawn room the player is in
    for (i n = 0; n < MAX_SPAWN_ROOMS; n++) {
        i spawnRoom = g_iPlayerSpawnRooms[client][n];
        if (spawnRoom != -1) {
            // If spawn room team matches player team, they're in their own spawn
            if (GetSpawnRoomTeam(spawnRoom) == playerTeam) {
                // Before respawn, reset spawn room tracking
                ResetPlayerSpawnRooms(client);
                // Resupply the player
                TF2_RespawnPlayer(client);
                
                // Mark as used for this key press
                g_bResupplyUsed[client] = true;
                return;
            }
        }
    }
}

// Check if an entity is a valid func_respawnroom and update its team info
b IsValidSpawnRoom(i entity) {
    // Quick check for invalid entities
    if (entity <= 0) return false;
    
    c classname[64];
    if (!GetEntityClassname(entity, classname, sizeof(classname))) {
        return false;
    }
    
    if (StrEqual(classname, "func_respawnroom")) {
        // Update the spawn room team data if needed
        if (g_iSpawnRoomTeam[entity] == 0) {
            g_iSpawnRoomTeam[entity] = GetEntProp(entity, Prop_Data, "m_iTeamNum", 4);
        }
        return true;
    }
    
    return false;
}

// Check if a player is touching a func_respawnroom entity directly
b IsPlayerTouchingSpawnRoom(i client) {
    // Validate client
    if (!IsClientInGame(client) || !IsPlayerAlive(client)) {
        PrintToServer("[PTE] IsPlayerTouchingSpawnRoom: Invalid client %d", client);
        return false;
    }
    
    // Get client position
    f clientOrigin[3];
    GetClientAbsOrigin(client, clientOrigin);
    PrintToServer("[PTE] IsPlayerTouchingSpawnRoom: Checking client %d at position (%.2f, %.2f, %.2f)", client, clientOrigin[0], clientOrigin[1], clientOrigin[2]);
    
    // Loop through all entities to find func_respawnroom
    i entity = -1;
    i foundCount = 0;
    i inCount = 0;
    
    while ((entity = FindEntityByClassname(entity, "func_respawnroom")) != -1) {
        foundCount++;
        // Check if player is inside this spawn room using point containment
        if (IsPlayerInEntityBounds(client, entity)) {
            inCount++;
            PrintToServer("[PTE] IsPlayerTouchingSpawnRoom: Client %d is inside spawn room %d", client, entity);
            return true;
        }
    }
    
    PrintToServer("[PTE] IsPlayerTouchingSpawnRoom: Client %d checked %d spawn rooms, found in %d", client, foundCount, inCount);
    return false;
}

// Check if a player is within the bounds of an entity
b IsPlayerInEntityBounds(i client, i entity) {
    // Get entity bounds
    f entityMins[3], entityMaxs[3], entityOrigin[3];
    GetEntPropVector(entity, Prop_Send, "m_vecMins", entityMins);
    GetEntPropVector(entity, Prop_Send, "m_vecMaxs", entityMaxs);
    GetEntPropVector(entity, Prop_Send, "m_vecOrigin", entityOrigin);
    
    // Calculate absolute bounds
    f absMins[3], absMaxs[3];
    absMins[0] = entityOrigin[0] + entityMins[0];
    absMins[1] = entityOrigin[1] + entityMins[1];
    absMins[2] = entityOrigin[2] + entityMins[2];
    absMaxs[0] = entityOrigin[0] + entityMaxs[0];
    absMaxs[1] = entityOrigin[1] + entityMaxs[1];
    absMaxs[2] = entityOrigin[2] + entityMaxs[2];
    
    // Get player position
    f playerOrigin[3];
    GetClientAbsOrigin(client, playerOrigin);
    
    PrintToServer("[PTE] IsPlayerInEntityBounds: Client %d at (%.2f, %.2f, %.2f) checking entity %d bounds min(%.2f, %.2f, %.2f) max(%.2f, %.2f, %.2f)", 
        client, playerOrigin[0], playerOrigin[1], playerOrigin[2],
        entity, absMins[0], absMins[1], absMins[2], absMaxs[0], absMaxs[1], absMaxs[2]);
    
    // Check if player is within bounds
    if (playerOrigin[0] >= absMins[0] && playerOrigin[0] <= absMaxs[0] &&
        playerOrigin[1] >= absMins[1] && playerOrigin[1] <= absMaxs[1] &&
        playerOrigin[2] >= absMins[2] && playerOrigin[2] <= absMaxs[2]) {
        PrintToServer("[PTE] IsPlayerInEntityBounds: Client %d is inside entity %d bounds", client, entity);
        return true;
    }
    
    PrintToServer("[PTE] IsPlayerInEntityBounds: Client %d is NOT inside entity %d bounds", client, entity);
    return false;
}

// Get the team of a spawn room entity
i GetSpawnRoomTeam(i entity) {
    // First check if the entity is valid
    if (!IsValidSpawnRoom(entity)) {
        return 0; // Invalid team
    }
    
    // If we already know the team, return it
    if (g_iSpawnRoomTeam[entity] != 0) {
        return g_iSpawnRoomTeam[entity];
    }
    
    // Otherwise, try to determine the team from the entity
    i team = GetEntProp(entity, Prop_Data, "m_iTeamNum", 4);
    
    // Store the team for future reference
    g_iSpawnRoomTeam[entity] = team;
    
    return team;
}

// Check if a player is in their own spawnroom
b IsPlayerInSpawnRoom(i client) {
    // Get player's team
    i playerTeam = GetClientTeam(client);
    
    // Check if player is in any spawn room
    if (!g_bPlayerInSpawnRoom[client]) {
        return false;
    }
    
        // Check if player is in a spawn room of their own team
    b foundValidSpawnRoom = false;
    
    for (i n = 0; n < MAX_SPAWN_ROOMS; n++) {
        i spawnRoom = g_iPlayerSpawnRooms[client][n];
        
        // Skip empty slots
        if (spawnRoom == -1) {
            continue;
        }
        
        // Validate the spawn room entity
        if (!IsValidSpawnRoom(spawnRoom)) {
            // Entity is no longer valid, remove it from tracking
            g_iPlayerSpawnRooms[client][n] = -1;
            continue;
        }
        
        // Entity is valid, mark that we found at least one valid spawn room
        foundValidSpawnRoom = true;
        
        // Check if it's the player's team's spawn room
        i spawnTeam = GetSpawnRoomTeam(spawnRoom);
        if (spawnTeam == playerTeam) {
            return true; // Player is in their own team's spawn room
        }
    }
    
    // Update the player's spawn room status if we didn't find any valid spawn rooms
    if (!foundValidSpawnRoom) {
        g_bPlayerInSpawnRoom[client] = false;
        g_iPlayerSpawnRoomCount[client] = 0;
    }
    
    // Player is not in a spawn room of their own team
    return false;
}

// Helper function to add a spawn room entity to player's tracking
b AddSpawnRoomToPlayer(i client, i spawnRoomEntity) {
    // First check if this entity is already tracked
    for (i n = 0; n < MAX_SPAWN_ROOMS; n++) {
        if (g_iPlayerSpawnRooms[client][n] == spawnRoomEntity) {
            // Already tracking this entity
            return false;
        }
    }
    
    // Find an empty slot
    for (i n = 0; n < MAX_SPAWN_ROOMS; n++) {
        if (g_iPlayerSpawnRooms[client][n] == -1) {
            // Found an empty slot, add the entity
            g_iPlayerSpawnRooms[client][n] = spawnRoomEntity;
            return true;
        }
    }
    
    // No empty slots found
    return false;
}

// Helper function to count how many spawn rooms a player is in
i CountPlayerSpawnRooms(i client) {
    i count = 0;
    for (i n = 0; n < MAX_SPAWN_ROOMS; n++) {
        if (g_iPlayerSpawnRooms[client][n] != -1) {
            count++;
        }
    }
    return count;
}

// Helper function to remove a spawn room entity from player's tracking
b RemoveSpawnRoomFromPlayer(i client, i spawnRoomEntity) {
    for (i n = 0; n < MAX_SPAWN_ROOMS; n++) {
        if (g_iPlayerSpawnRooms[client][n] == spawnRoomEntity) {
            // Found the entity, remove it
            g_iPlayerSpawnRooms[client][n] = -1;
            return true;
        }
    }
    
    // Entity not found
    return false;
}

// Helper to clear all spawn room tracking for a player
v ResetPlayerSpawnRooms(i client) {
    g_bPlayerInSpawnRoom[client] = false;
    g_iPlayerSpawnRoomCount[client] = 0;
    for (i n = 0; n < MAX_SPAWN_ROOMS; n++) {
        g_iPlayerSpawnRooms[client][n] = -1;
    }
}

// Admin command to list spawn rooms a player is currently in
CREATE_CMD(CListSpawnRooms) {
    if (args < 1) {
        PrintToConsole(client, "Usage: sm_listspawnrooms <player>");
        PH;
    }
    
    // Get target player
    c targetArg[MAX_NAME_LENGTH];
    GetCmdArg(1, targetArg, sizeof(targetArg));
    
    // Try to find the target player
    c targetName[MAX_NAME_LENGTH];
    i targets[MAXPLAYERS];
    b tn_is_ml;
    i targetCount = ProcessTargetString(
        targetArg,
        client,
        targets,
        MAXPLAYERS,
        COMMAND_FILTER_ALIVE,
        targetName,
        sizeof(targetName),
        tn_is_ml);
    
    // Check if we found a valid target
    if (targetCount <= 0) {
        ReplyToTargetError(client, targetCount);
        PH;
    }
    
    // We only care about the first match
    i targetClient = targets[0];
    i playerTeam = GetClientTeam(targetClient);
    
    // Get player name
    c playerName[MAX_NAME_LENGTH];
    GetClientName(targetClient, playerName, sizeof(playerName));
    
    // Print header
    PrintToConsole(client, "\n===== Spawn Room Status for %s (Team %d) =====", playerName, playerTeam);
    PrintToConsole(client, "In any spawn room: %s", g_bPlayerInSpawnRoom[targetClient] ? "Yes" : "No");
    PrintToConsole(client, "Spawn room count: %d", g_iPlayerSpawnRoomCount[targetClient]);
    PrintToConsole(client, "In own team's spawn: %s", IsPlayerInSpawnRoom(targetClient) ? "Yes" : "No");
    
    // List all spawn rooms the player is in
    PrintToConsole(client, "\nActive spawn rooms:");
    b hasSpawnRooms = false;
    
    for (i n = 0; n < MAX_SPAWN_ROOMS; n++) {
        i spawnRoom = g_iPlayerSpawnRooms[targetClient][n];
        if (spawnRoom != -1) {
            hasSpawnRooms = true;
            i spawnTeam = GetSpawnRoomTeam(spawnRoom);
            PrintToConsole(client, "  [%d] Entity: %d, Team: %d, Matches player team: %s", 
                n, spawnRoom, spawnTeam, (spawnTeam == playerTeam) ? "Yes" : "No");
        }
    }
    
    if (!hasSpawnRooms) PrintToConsole(client, "  None");
    
    PrintToConsole(client, "======================================\n");
    PH;
}

// Spawn room entry detection
pub v OnSpawnRoomStartTouch(const c[] output, i caller, i activator, f delay) {
    // Check if the activator is a valid client
    if (activator > 0 && activator <= MaxClients && IsClientInGame(activator)) {
        // Get player name and team for debugging
        c playerName[MAX_NAME_LENGTH];
        GetClientName(activator, playerName, sizeof(playerName));
        
        // Add this spawn room to the player's tracking
        AddSpawnRoomToPlayer(activator, caller);
        
        // Set the player as in spawn room
        g_bPlayerInSpawnRoom[activator] = true;
        
        // Update count for debugging
        g_iPlayerSpawnRoomCount[activator] = CountPlayerSpawnRooms(activator);
        
        // Try to resupply if key is down
        TryResupplyPlayer(activator);
    }
}

// Spawn room exit detection
pub v OnSpawnRoomEndTouch(const c[] output, i caller, i activator, f delay) {
    // Check if the activator is a valid client
    if (activator > 0 && activator <= MaxClients && IsClientInGame(activator)) {
        // Get player name and team for debugging
        c playerName[MAX_NAME_LENGTH];
        GetClientName(activator, playerName, sizeof(playerName));
        
        // Remove this spawn room from the player's tracking
        RemoveSpawnRoomFromPlayer(activator, caller);
        
        // Update count for debugging
        g_iPlayerSpawnRoomCount[activator] = CountPlayerSpawnRooms(activator);
        
        // If player is not in any spawn rooms, update the flag
        if (g_iPlayerSpawnRoomCount[activator] == 0) {
            g_bPlayerInSpawnRoom[activator] = false;
        }
    }
}



// Called when a client disconnects
pub OnClientDisconnect(i client) {
    // Reset spawn room tracking
    g_bPlayerInSpawnRoom[client] = false;
    g_iPlayerSpawnRoomCount[client] = 0;
    g_bResupplyKeyDown[client] = false;
    g_bResupplyUsed[client] = false;
    g_bNoDamage[client] = false;
    g_bPendingRestoreHP[client] = false;
    g_iPreDamageHP[client] = 0;
    g_bInfiniteAmmo[client] = false;
    
    // Clean up infinite ammo ArrayList if it exists
    if (g_hOriginalAmmo[client] != null) {
        delete g_hOriginalAmmo[client];
        g_hOriginalAmmo[client] = null;
    }
    
    // Clear spawn room entity tracking
    for (i n = 0; n < MAX_SPAWN_ROOMS; n++) {
        g_iPlayerSpawnRooms[client][n] = -1;
    }
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

// Store original ammo values for a client
pub v StoreOriginalAmmo( i client ) {
    // Clean up existing ArrayList if it exists
    if (g_hOriginalAmmo[client] != null) {
        delete g_hOriginalAmmo[client];
    }
    
    // Create new ArrayList for this player
    g_hOriginalAmmo[client] = new ArrayList(34); // 2 clip values + 32 ammo types
    
    // Get the active weapon
    i weapon = GetEntPropEnt( client, Prop_Send, "m_hActiveWeapon" );
    if ( weapon == -1 || !IsValidEntity( weapon ) ) return;
    
    // Store clip values
    g_hOriginalAmmo[client].Set(0, GetEntProp( weapon, Prop_Send, "m_iClip1" ));
    g_hOriginalAmmo[client].Set(1, GetEntProp( weapon, Prop_Send, "m_iClip2" ));
    
    // Store reserve ammo values for all ammo types
    for ( i ammoType = 0; ammoType < 32; ammoType++ ) {
        g_hOriginalAmmo[client].Set(ammoType + 2, GetEntProp( client, Prop_Send, "m_iAmmo", _, ammoType ));
    }
}

// Restore original ammo values for a client
pub v RestoreOriginalAmmo( i client ) {
    // Check if player has stored ammo data
    if (g_hOriginalAmmo[client] == null) return;
    
    // Get the active weapon
    i weapon = GetEntPropEnt( client, Prop_Send, "m_hActiveWeapon" );
    if ( weapon == -1 || !IsValidEntity( weapon ) ) return;
    
    // Restore clip values
    SetEntProp( weapon, Prop_Send, "m_iClip1", g_hOriginalAmmo[client].Get(0) );
    SetEntProp( weapon, Prop_Send, "m_iClip2", g_hOriginalAmmo[client].Get(1) );
    
    // Restore reserve ammo values
    for ( i ammoType = 0; ammoType < 32; ammoType++ ) {
        SetEntProp( client, Prop_Send, "m_iAmmo", g_hOriginalAmmo[client].Get(ammoType + 2), _, ammoType );
    }
}

// OnGameFrame - replenish ammo every frame for infinite ammo players
pub v OnGameFrame() {
    // Loop through all clients
    for ( i client = 1; client <= MaxClients; client++ ) {
        // Check if client is valid, in-game, alive, and has infinite ammo enabled
        if ( IsClientInGame( client ) && IsPlayerAlive( client ) && g_bInfiniteAmmo[ client ] ) {
            // Get the active weapon
            i weapon = GetEntPropEnt( client, Prop_Send, "m_hActiveWeapon" );
            if ( weapon == -1 || !IsValidEntity( weapon ) ) continue;
            
            // Replenish clip ammo to a high value (99)
            SetEntProp( weapon, Prop_Send, "m_iClip1", 99 );
            SetEntProp( weapon, Prop_Send, "m_iClip2", 99 );
            
            // Replenish reserve ammo for all ammo types
            // TF2 has a maximum of 32 ammo types
            for ( i ammoType = 0; ammoType < 32; ammoType++ ) {
                SetEntProp( client, Prop_Send, "m_iAmmo", 999, _, ammoType );
            }
        }
    }
}

// SDKHooks damage filter: prevent/zero damage if victim is protected or attacker is restricted
pub Act Hook_OnTakeDamage( i victim, i &attacker, i &inflictor, f &damage, i &damagetype, i &weapon, f damageForce[3], f damagePosition[3], i damagecustom ) {
    // If the victim is invulnerable: allow knockback by letting damage go through, but prevent death and restore HP afterward
    if ( victim >= 1 && victim <= MaxClients && g_bNoDamage[ victim ] ) {
        // Store current health for restoration
        g_iPreDamageHP[ victim ] = GetClientHealth( victim );
        g_bPendingRestoreHP[ victim ] = true;
        
        // Allow damage to go through for knockback calculation
        // We'll restore health in the post-damage hook
        
        // If player has very low health, ensure they don't die
        if ( g_iPreDamageHP[ victim ] <= 1 ) {
            // For extremely low health, we still need minimal damage for knockback
            damage = 1.0;
        }
        return Plugin_Changed;
    }
    // If the attacker is invulnerable: their hits do no damage
    if ( attacker >= 1 && attacker <= MaxClients && g_bNoDamage[ attacker ] ) {
        if ( damage > 0.0 ) damage = 0.0;
        return Plugin_Changed;
    }
    PC;
}

// Post-damage hook (reserved for future use, e.g., preserving knockback if needed)
pub v Hook_OnTakeDamagePost( i victim, i attacker, i inflictor, f damage, i damagetype, i weapon, f damageForce[3], f damagePosition[3], i damagecustom ) {
    if ( victim >= 1 && victim <= MaxClients && g_bPendingRestoreHP[ victim ] ) {
        g_bPendingRestoreHP[ victim ] = false;
        if ( IsClientInGame( victim ) && IsPlayerAlive( victim ) ) {
            // Restore health to pre-damage value
            SetEntProp( victim, Prop_Send, "m_iHealth", g_iPreDamageHP[ victim ] );
            
            // Debug message if needed
            // PrintToChat( victim, "Restored health after knockback" );
        }
    }
}
