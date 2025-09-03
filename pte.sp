// Imports
#include <sdktools_functions>
#include <sourcemod>
#include <tf2>
#include <tf2_stocks>
#include <clientprefs>
#include <clients>
#include <sdktools>
#include <sdktools_gamerules>
#include <sdktools_trace>
#include <sdktools_entoutput>
#include <sdkhooks>

#pragma semicolon 1

// Constants
#define RED             0
#define BLU             1
#define TEAM_OFFSET     2
#define EDICT           2048
#define MAX_SPAWN_ROOMS 4
#define MAX_SLOTS       2
#define RESUPDIST       512.0 // Max dist from spawn resupply can be used

// MACROS
#define PCH return Plugin_Changed
#define PCO return Plugin_Continue
#define PH  return Plugin_Handled
#define pub public
#define Act Action
#define Han Handle
#define Ev  Event
#define i   int
#define v   void
#define f   float
#define b   bool
#define c   char
#define RCC RegConsoleCmd
#define RAC RegAdminCmd
#define HE  HookEvent
#define NEW_CMD(%1) pub Act %1( i client, i args )
#define NEW_EV_ACT(%1) pub Act %1( Ev event, const c[] name, b dontBroadcast )
#define NEW_EV(%1) pub %1( Ev event, const c[] name, b dontBroadcast )
#define STRBOOL "<0|1>"

public Plugin myinfo = {
    name        = "passtime.tf extras",
    author      = "xCape",
    description = "Plugin for use in passtime.tf servers",
    version     = "1.5",
    url         = "https://github.com/allvei/passtime-extras"
}

// Handles
Han g_hCookieFOV;
Han g_hCookieInfiniteAmmo;
Han g_hCookieImmunity;
Han g_cvFOVMin;
Han g_cvFOVMax;

// Backup system for FOV tracking when Steam connection is down
b g_bSteamConnected = true;           // Track if Steam is currently connected
b g_bBackupFOVDB    = false;          // Track if we're using the backup system
b g_bPlayerTracked[ MAXPLAYERS + 1 ]; // Track if we have a FOV value for this player
i g_iPlayerFOV[     MAXPLAYERS + 1 ]; // Store FOV values for each player

// Backup system for infinite ammo and immunity when Steam is down
b g_bBackupInfiniteAmmoTracked[MAXPLAYERS + 1]; // Track if we have infinite ammo setting for this player
b g_bBackupImmunityTracked[    MAXPLAYERS + 1]; // Track if we have immunity setting for this player
b g_bBackupInfiniteAmmo[       MAXPLAYERS + 1]; // Store infinite ammo setting for each player
b g_bBackupImmunity[           MAXPLAYERS + 1]; // Store immunity setting for each player

// Spawn room tracking
b g_bIsClientInSpawn[MAXPLAYERS + 1];                  // Track if player is in any spawn room
i g_iPlayerSpawns[   MAXPLAYERS + 1][MAX_SPAWN_ROOMS]; // Track which spawn rooms a player is in
i g_iSpawnTeam[      EDICT];                           // Track which team a spawn room belongs to (entity index -> team)
b g_bResupplyDn[     MAXPLAYERS + 1];                  // Track if resupply key is currently down
b g_bResupplyUp[     MAXPLAYERS + 1];                  // Track if resupply has been used during current key press

// No-damage & infinite ammo toggle per player
b g_bImmunity[MAXPLAYERS + 1];
i g_iPreDamageHP[MAXPLAYERS + 1];
b g_bPendingRestoreHP[MAXPLAYERS + 1];
b g_bInfiniteAmmo[MAXPLAYERS + 1];

// Original ammo values for infinite ammo restoration (only allocated for players using infinite ammo)
ArrayList g_hOriginalAmmo[MAXPLAYERS + 1]; // Dynamic arrays for players who actually use infinite ammo

// Respawn time control
ConVar g_cvRespawnTime;
b g_bTeamReadyState[2] = { false, false }; // Track ready state for RED and BLU

// Saved spawn point (admin tools)
b g_bSavedSpawnValid = false;
f g_vSavePos[3];
f g_vSaveAng[3];
f g_vSaveVel[3];

// Backup tournament controls
b g_bResupplyEnabled       = true;
b g_bInstantRespawnEnabled = true;
b g_bImmunityAmmoEnabled   = true;
b g_bSaveLoadEnabled       = true;

b g_bFailsafeTriggered = false; // Track if failsafe has been triggered

i g_iSavedClip1[    MAX_SLOTS];
i g_iSavedClip2[    MAX_SLOTS];
i g_iSavedAmmoType[ MAX_SLOTS][2];
i g_iSavedAmmoCount[MAX_SLOTS][2];

pub OnPluginStart() {
    // Admin commands
    RAC( "sm_setteam",         CSetTeam,        ADMFLAG_GENERIC, "Set a client's team" );
    RAC( "sm_st",              CSetTeam,        ADMFLAG_GENERIC, "Set a client's team" );
    RAC( "sm_setclass",        CSetClass,       ADMFLAG_GENERIC, "Set a client's class" );
    RAC( "sm_sc",              CSetClass,       ADMFLAG_GENERIC, "Set a client's class" );
    RAC( "sm_ready",           CReady,          ADMFLAG_GENERIC, "Set a team's ready status" );
    RAC( "sm_rdy",             CReady,          ADMFLAG_GENERIC, "Set a team's ready status" );
    RAC( "sm_debug_roundtime", CRoundTimeDebug, ADMFLAG_GENERIC, "Debug: print team_round_timer info" );
    RAC( "sm_drt",             CRoundTimeDebug, ADMFLAG_GENERIC, "Debug: print team_round_timer info" );
    RAC( "sm_enable_resupply", CToggleResupply, ADMFLAG_GENERIC, "Toggle resupply functionality" );
    RAC( "sm_enable_respawn",  CToggleRespawn,  ADMFLAG_GENERIC, "Toggle instant respawn" );
    RAC( "sm_enable_immunity", CToggleImmunity, ADMFLAG_GENERIC, "Toggle immunity and infinite ammo" );
    RAC( "sm_enable_saveload", CToggleSaveLoad, ADMFLAG_GENERIC, "Toggle save/load spawn functionality" );

    // Console commands
    RCC( "sm_save",         CSaveSpawn,    "Save a spawn point" );
    RCC( "sm_sv",           CSaveSpawn,    "Save a spawn point" );
    RCC( "sm_load",         CLoadSpawn,    "Teleport to saved spawn" );
    RCC( "sm_ld",           CLoadSpawn,    "Teleport to saved spawn" );
    RCC( "sm_immune",       CImmune,       "Toggle immunity" );
    RCC( "sm_i",            CImmune,       "Toggle immunity" );
    RCC( "sm_ammo",         CInfiniteAmmo, "Toggle infinite ammo" );
    RCC( "sm_a",            CInfiniteAmmo, "Toggle infinite ammo" );
    RCC( "sm_fov",          CSetFOV,       "Set your field of view." );
    RCC( "+sm_resupply",    CResupplyDn,   "Resupply inside spawn" );
    RCC( "-sm_resupply",    CResupplyUp,   "Resupply inside spawn" );
    RCC( "+sm_pt_resupply", CResupplyDn,   "Resupply inside spawn" );
    RCC( "-sm_pt_resupply", CResupplyUp,   "Resupply inside spawn" );

    g_hCookieFOV          = RegClientCookie( "sm_fov_cookie",          "Desired client field of view", CookieAccess_Private );
    g_hCookieInfiniteAmmo = RegClientCookie( "sm_infiniteammo_cookie", "Infinite ammo setting",        CookieAccess_Private );
    g_hCookieImmunity     = RegClientCookie( "sm_immunity_cookie",     "Immunity setting",             CookieAccess_Private );

    // Console variables
    g_cvFOVMin      = CreateConVar( "sm_fov_min",      "70",  "Minimum client field of view", _, 1, 1.0, 1, 175.0 );
    g_cvFOVMax      = CreateConVar( "sm_fov_max",      "120", "Maximum client field of view", _, 1, 1.0, 1, 175.0 );
    g_cvRespawnTime = CreateConVar( "sm_respawn_time", "0.0", "Player respawn delay in seconds", FCVAR_NOTIFY );

    // Hook events
    HE( "player_spawn",      EPSpawn );
    HE( "player_connect",    EPConnect );
    HE( "player_disconnect", EPDisconnect );
    HE( "player_death",      EPDeath );
    
    // Initialize team ready states
    g_bTeamReadyState[0] = false;
    g_bTeamReadyState[1] = false;
    
    // Initialize spawn room tracking arrays
    for (i n = 1; n <= MaxClients; n++) {
        g_bIsClientInSpawn[n] = false;
        g_bResupplyDn[n]      = false;
        g_bResupplyUp[n]      = false;
        
        // Initialize spawn room entity tracking
        for (i s = 0; s < MAX_SPAWN_ROOMS; s++) {
            g_iPlayerSpawns[n][s] = -1;
        }
    }
    
    // Initialize spawn room team tracking
    g_iSpawnTeam[0] = 0;
    
    // Initialize saved ammo/velocity buffers
    for (i s = 0; s < MAX_SLOTS; s++) {
        g_iSavedClip1[s] = -1;
        g_iSavedClip2[s] = -1;
        for (i t = 0; t < 2; t++) {
            g_iSavedAmmoType[s][t]  = -1;
            g_iSavedAmmoCount[s][t] = 0;
        }
    }
    
    // Initialize infinite ammo ArrayList handles and backup tracking
    for (i n = 1; n <= MaxClients; n++) {
        g_hOriginalAmmo[n]              = null;
        g_bInfiniteAmmo[n]              = false;
        g_bBackupInfiniteAmmoTracked[n] = false;
        g_bBackupImmunityTracked[n]     = false;
        g_bBackupInfiniteAmmo[n]        = false;
        g_bBackupImmunity[n]            = false;
    }
    
    // Hook damage for currently connected clients and reset nodamage flags
    for (i n = 1; n <= MaxClients; n++) {
        g_bImmunity[n]         = false;
        g_bPendingRestoreHP[n] = false;
        g_iPreDamageHP[n]      = 0;
        if ( IsClientInGame(n) ) {
            SDKHook( n, SDKHook_OnTakeDamage,     Hook_OnTakeDamage );
            SDKHook( n, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost );
        }
    }
}

pub v OnGameFrame() {
    // Loop through all clients
    for ( i client = 1; client <= MaxClients; client++ ) {
        // Check for infinite ammo players (excluding medics) and if globally enabled
        if ( IsValidClient( client ) && g_bInfiniteAmmo[ client ] && g_bImmunityAmmoEnabled && !IsMatch()) {
            // Skip medics
            if (TF2_GetPlayerClass(client) == TFClass_Medic) continue;

            // Get the active weapon
            i weapon = GetEntPropEnt( client, Prop_Send, "m_hActiveWeapon" );
            if ( weapon == -1 || !IsValidEntity( weapon ) ) continue;

            SetEntProp( weapon, Prop_Send, "m_iClip1", 19 );
            SetEntProp( weapon, Prop_Send, "m_iClip2", 84 );

            for ( i ammoType = 0; ammoType < 32; ammoType++ ) {
                SetEntProp( client, Prop_Send, "m_iAmmo", 999, _, ammoType );
            }
        }

        // Check for buffered resupply (only if globally enabled)
        if (g_bResupplyEnabled && g_bResupplyDn[client] && !g_bResupplyUp[client] && IsClientInSpawn(client)) {
            Resupply(client);
        }
    }
}

// Hook per-client when they enter the server so our damage filter is active
pub v OnClientPutInServer( i client ) {
    SDKHook( client, SDKHook_OnTakeDamage,     Hook_OnTakeDamage );
    SDKHook( client, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost );
}

b IsMatch() {
    // Match is not active if game is awaiting ready restart, timer is paused, or timer is disabled
    b awaitingReadyRestart = view_as<b>(GameRules_GetProp("m_bAwaitingReadyRestart"));
    i timerEnt      = -1;
    b timerPaused   = false;
    b timerDisabled = false;
    b IsPostRound   = GameRules_GetRoundState() == RoundState_TeamWin;
    
    // Find any active team_round_timer entity
    while ((timerEnt = FindEntityByClassname(timerEnt, "team_round_timer")) != -1) {
        timerPaused   = view_as<b>(GetEntProp(timerEnt, Prop_Send, "m_bTimerPaused"));
        timerDisabled = view_as<b>(GetEntProp(timerEnt, Prop_Send, "m_bIsDisabled"));
        
        // If we found a timer, break since we only need to check one
        if (timerEnt != -1) break;
    }
    
    // Match is active only if we're not awaiting ready restart and timer is running (not paused and not disabled)
    return !(awaitingReadyRestart || timerPaused || timerDisabled || !IsPostRound);
}

// ====================================================================================================
// COMMANDS
// ====================================================================================================

// Command to set a team's ready status
NEW_CMD(CReady) {
    if (IsMatch()) PCO;
    
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
    
    PH;
}

// Change client's team
NEW_CMD(CSetTeam) {
    // Parse team argument early so it's available in all code paths
    c target[33];
    GetCmdArg(1, target, sizeof(target));

    c input_team[5];
    GetCmdArg(2, input_team, sizeof(input_team));
    TFTeam team = ParseTeam(input_team);
    
    if ( args != 2 || team == TFTeam_Unassigned ) return EndCmd( client, "Usage: sm_setteam <#userid|name> <spec|red|blu>", args );


    i target_list[ MAXPLAYERS ];
    c target_name[ MAX_TARGET_LENGTH ];
    b tn_is_ml     = false;
    i target_count = ProcessTargetString( target, client, target_list, MAXPLAYERS, COMMAND_FILTER_CONNECTED, target_name, sizeof( target_name ), tn_is_ml );
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
        GetTeamName( view_as<i>( team ), team_name, sizeof( team_name ) );

        ReplyToCommand( client, "Switched %s to %s", target_name, team_name );
    }
    PH;
}

// Set your field of view
NEW_CMD(CSetFOV) {
    if ( args != 1 ) return EndCmd( client, "Usage: sm_fov <fov>" );

    i fov = GetCmdArgInt( 1 ),
      min = GetConVarInt( g_cvFOVMin ),
      max = GetConVarInt( g_cvFOVMax );

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
        g_bSteamConnected = true; // Steam is connected if cookies work

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

// Save a spawn point
NEW_CMD(CSaveSpawn) {
    if ( !g_bSaveLoadEnabled ) return EndCmd( client, "Save/Load spawn functionality has been disabled by an administrator.");
    if ( IsMatch() )           return EndCmd( client, "Saving spawn points is disabled in match mode.");
    if ( args != 0 )           return EndCmd( client, "Usage: sm_save" );
    if ( client <= 0 || client > MaxClients || !IsClientInGame( client ) ) PH;
    if ( !IsPlayerAlive( client ) ) PH;

    GetClientAbsOrigin( client,  g_vSavePos );
    GetClientEyeAngles( client,  g_vSaveAng );
    GetEntPropVector( client, Prop_Data, "m_vecAbsVelocity", g_vSaveVel );
    
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

    EndCmd( client, "Spawn saved!" );
    
    PH;
}

// Load (teleport) to saved spawn
NEW_CMD(CLoadSpawn) {
    if ( IsMatch() || !g_bSaveLoadEnabled ) return EndCmd(client, "Loading is disabled.");
    if ( !IsValidClient( client ) ) PH;
    if ( args != 0 ) return EndCmd( client, "Usage: sm_load" );
    if ( !g_bSavedSpawnValid ) return EndCmd( client, "No saved spawn point set yet." );

    TeleportEntity( client, g_vSavePos, g_vSaveAng, g_vSaveVel );
    
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

// Toggle immunity
NEW_CMD(CImmune) {
    if (IsMatch() || !g_bImmunityAmmoEnabled) return EndCmd(client, "Immunity is disabled.");
    if ( args == 0 ) g_bImmunity[ client ] = !g_bImmunity[ client ];
    else return EndCmd( client, "Usage: sm_immunity" );
    
    SetImmunityCookie(client, g_bImmunity[client]);
    
    if ( IsPlayerAlive( client ) ) TF2_RespawnPlayer( client );
    
    ReplyToCommand( client, "Immunity %s.", g_bImmunity[ client ] ? "enabled" : "disabled" );
    PH;
}

// Toggle infinite ammo
NEW_CMD(CInfiniteAmmo) {
    if (IsMatch() || !g_bImmunityAmmoEnabled) return EndCmd(client, "Infinite ammo is disabled.");
    if ( args == 0 ) g_bInfiniteAmmo[ client ] = !g_bInfiniteAmmo[ client ];
    else return EndCmd( client, "Usage: sm_ammo" );
    
    SetAmmoCookie(client, g_bInfiniteAmmo[client]);
    
    if ( IsPlayerAlive( client ) ) TF2_RespawnPlayer( client );
    
    ReplyToCommand( client, "Infinite ammo %s.", g_bInfiniteAmmo[ client ] ? "enabled" : "disabled" );
    PH;
}

// Set a player's class
NEW_CMD(CSetClass) {
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

TFClassType ParseClass( c[] s ) {
    if ( StrEqual( s, "soldier" )  || StrEqual( s, "2" ) ) return TFClass_Soldier;
    if ( StrEqual( s, "demo" )     || StrEqual( s, "demoman" ) || StrEqual( s, "4" ) ) return TFClass_DemoMan;
    if ( StrEqual( s, "medic" )    || StrEqual( s, "7" ) ) return TFClass_Medic;
    return TFClass_Unknown;
}

NEW_CMD(CRoundTimeDebug) {
    i ent = -1;
    i found = 0;
    
    while ((ent = FindEntityByClassname(ent, "team_round_timer")) != -1) {
        b timerPaused         = view_as<b>(GetEntProp(     ent, Prop_Send, "m_bTimerPaused"));
        f timeRemaining       =            GetEntPropFloat(ent, Prop_Send, "m_flTimeRemaining");
        f timerEndTime        =            GetEntPropFloat(ent, Prop_Send, "m_flTimerEndTime");
        b isDisabled          = view_as<b>(GetEntProp(     ent, Prop_Send, "m_bIsDisabled"));
        b showInHUD           = view_as<b>(GetEntProp(     ent, Prop_Send, "m_bShowInHUD"));
        i timerLength         =            GetEntProp(     ent, Prop_Send, "m_nTimerLength");
        i timerInitialLength  =            GetEntProp(     ent, Prop_Send, "m_nTimerInitialLength");
        i timerMaxLength      =            GetEntProp(     ent, Prop_Send, "m_nTimerMaxLength");
        b autoCountdown       = view_as<b>(GetEntProp(     ent, Prop_Send, "m_bAutoCountdown"));
        i setupTimeLength     =            GetEntProp(     ent, Prop_Send, "m_nSetupTimeLength");
        i state               =            GetEntProp(     ent, Prop_Send, "m_nState");
        b startPaused         = view_as<b>(GetEntProp(     ent, Prop_Send, "m_bStartPaused"));
        b showTimeRemaining   = view_as<b>(GetEntProp(     ent, Prop_Send, "m_bShowTimeRemaining"));
        b inCaptureWatchState = view_as<b>(GetEntProp(     ent, Prop_Send, "m_bInCaptureWatchState"));
        f totalTime           =            GetEntPropFloat(ent, Prop_Send, "m_flTotalTime");
        b stopWatchTimer      = view_as<b>(GetEntProp(     ent, Prop_Send, "m_bStopWatchTimer"));
        
        // Check if game is ongoing using m_bAwaitingReadyRestart and timer pause state
        b awaitingReadyRestart = view_as<b>(GameRules_GetProp("m_bAwaitingReadyRestart"));
        b gameOngoing = !awaitingReadyRestart && !timerPaused && !isDisabled;
        
        ReplyToCommand(client, "[timer %d] m_bTimerPaused=%d m_flTimeRemaining=%.2f m_flTimerEndTime=%.2f m_bIsDisabled=%d m_bShowInHUD=%d", ent, timerPaused, timeRemaining, timerEndTime, isDisabled, showInHUD);
        ReplyToCommand(client, "[timer %d] m_nTimerLength=%d m_nTimerInitialLength=%d m_nTimerMaxLength=%d m_bAutoCountdown=%d", ent, timerLength, timerInitialLength, timerMaxLength, autoCountdown);
        ReplyToCommand(client, "[timer %d] m_nSetupTimeLength=%d m_nState=%d m_bStartPaused=%d m_bShowTimeRemaining=%d", ent, setupTimeLength, state, startPaused, showTimeRemaining);
        ReplyToCommand(client, "[timer %d] m_bInCaptureWatchState=%d m_flTotalTime=%.2f m_bStopWatchTimer=%d", ent, inCaptureWatchState, totalTime, stopWatchTimer);
        ReplyToCommand(client, "[timer %d] Game Ongoing: %d (m_bAwaitingReadyRestart=%d)", ent, gameOngoing, awaitingReadyRestart);
        
        found++;
    }
    
    if (found == 0) return EndCmd(client, "No team_round_timer found.");
    PH;
}

// ====================================================================================================
// BACKUP COMMANDS
// ====================================================================================================

// Backup toggle for resupply
NEW_CMD(CToggleResupply) {
    if (args != 1) return EndCmd(client, "Usage: sm_enable_resupply <0|1>");
    
    c arg[4];
    GetCmdArg(1, arg, sizeof(arg));
    i value = StringToInt(arg);
    
    if (value != 0 && value != 1) return EndCmd(client, "Usage: sm_enable_resupply <0|1> (0=disable, 1=enable)");
    
    g_bResupplyEnabled = (value != 0);
    
    // Reset failsafe when manually enabling
    if (g_bResupplyEnabled) {
        g_bFailsafeTriggered = false;
    }
    
    ReplyToCommand(client, "Resupply functionality %s", g_bResupplyEnabled ? "ENABLED" : "DISABLED");
    PH;
}

// Backup toggle for instant respawn
NEW_CMD(CToggleRespawn) {
    if (args != 1) return EndCmd(client, "Usage: sm_enable_respawn <0|1>");
    
    c arg[4];
    GetCmdArg(1, arg, sizeof(arg));
    i value = StringToInt(arg);
    
    if (value != 0 && value != 1) return EndCmd(client, "Usage: sm_enable_respawn <0|1>");
    
    g_bInstantRespawnEnabled = (value != 0);
    
    ReplyToCommand(client, "Instant respawn %s", g_bInstantRespawnEnabled ? "enabled" : "disabled");
    PH;
}

// Backup toggle for immunity and infinite ammo
NEW_CMD(CToggleImmunity) {
    if (args != 1) return EndCmd(client, "Usage: sm_enable_immunity <0|1>");
    
    c arg[4];
    GetCmdArg(1, arg, sizeof(arg));
    i value = StringToInt(arg);
    
    if (value != 0 && value != 1) return EndCmd(client, "Usage: sm_enable_immunity <0|1> (0=disable, 1=enable)");
    
    g_bImmunityAmmoEnabled = (value != 0);
    
    // If disabling, turn off immunity and infinite ammo for all players
    if (!g_bImmunityAmmoEnabled) {
        for (i n = 1; n <= MaxClients; n++) {
            if (IsClientInGame(n)) {
                g_bImmunity[n] = false;
                g_bInfiniteAmmo[n] = false;
                if (g_hOriginalAmmo[n] != null) {
                    delete g_hOriginalAmmo[n];
                    g_hOriginalAmmo[n] = null;
                }
            }
        }
    }
    
    ReplyToCommand(client, "Immunity and infinite ammo %s", g_bImmunityAmmoEnabled ? "ENABLED" : "DISABLED");
    PH;
}

// Backup toggle for save/load
NEW_CMD(CToggleSaveLoad) {
    if (args != 1) return EndCmd(client, "Usage: sm_enable_saveload <0|1>");
    
    c arg[4];
    GetCmdArg(1, arg, sizeof(arg));
    i value = StringToInt(arg);
    
    if (value != 0 && value != 1) return EndCmd(client, "Usage: sm_enable_saveload <0|1> (0=disable, 1=enable)");
    
    g_bSaveLoadEnabled = (value != 0);
    
    ReplyToCommand(client, "Save/Load spawn functionality %s", g_bSaveLoadEnabled ? "ENABLED" : "DISABLED");
    PH;
}

// ====================================================================================================
// EVENTS
// ====================================================================================================

// Handle player death event
pub Act EPDeath( Ev event, const c[] name, b dontBroadcast ) {
    i userid = event.GetInt( "userid" );
    i client = GetClientOfUserId(userid);
    
    if (IsMatch()) PCO;
    
    // Validate client before proceeding
    if (client <= 0 || client > MaxClients || !IsClientInGame(client)) PCO;
    
    // Check if instant respawn is globally enabled
    if (g_bInstantRespawnEnabled && g_cvRespawnTime.FloatValue <= 0.0) {
        RequestFrame( RespawnFrame, userid );
    }
    
    PCO;
}

// Player connect event - prepare for tracking
NEW_EV(EPConnect) {
    i client = GetClientOfUserId( event.GetInt( "userid" ) );

    if ( client > 0 && client <= MaxClients && g_bBackupFOVDB ) {
        // Reset tracking for this player slot if backup system is active
        g_bPlayerTracked[ client ] = false;
        g_iPlayerFOV[ client ]     = 0;
    }
}

// Player disconnect event - clean up tracking
NEW_EV(EPDisconnect) {
    i userid = event.GetInt( "userid" );
    i client = GetClientOfUserId( userid );

    if ( client > 0 && client <= MaxClients && g_bBackupFOVDB ) {
        // Clear tracking data for this slot if backup system is active
        g_bPlayerTracked[ client ] = false;
        g_iPlayerFOV[ client ]     = 0;
    }
}

// Restores the client's FOV, infinite ammo, and immunity settings on spawn
NEW_EV(EPSpawn) {
    i client = GetClientOfUserId( event.GetInt( "userid" ) );
    if ( !IsValidClient( client ) ) return;

    // Try to restore settings from cookies first
    if ( AreClientCookiesCached( client ) ) {
        if ( GetFOVCookie( client ) ) {
            // If we were using backup but Steam is now connected, we can disable it
            if ( !g_bSteamConnected ) {
                g_bSteamConnected = true;
                if ( g_bBackupFOVDB ) SetBackupSystem( false );
            }
        }
        
        // Restore infinite ammo and immunity settings
        GetAmmoCookie( client );
        GetImmunityCookie( client );
        return;
    } else if ( !g_bBackupFOVDB ) {
        // Steam is down, initialize backup system
        SetBackupSystem( true );
        g_bSteamConnected = false;
    }

    // If cookies failed or aren't cached, try backup system
    if ( g_bBackupFOVDB && g_bPlayerTracked[ client ] && g_iPlayerFOV[ client ] > 0 ) {
        SetFOV( client, g_iPlayerFOV[ client ] );
    }
    
    // Restore from backup system for infinite ammo and immunity
    if ( g_bBackupInfiniteAmmoTracked[ client ] ) {
        g_bInfiniteAmmo[ client ] = g_bBackupInfiniteAmmo[ client ];
        if ( g_bInfiniteAmmo[ client ] ) {
            SetInitAmmo( client );
        }
    }
    
    if ( g_bBackupImmunityTracked[ client ] ) {
        g_bImmunity[ client ] = g_bBackupImmunity[ client ];
    }
}

// Retrieves the client's FOV from their local config and stores it in a cookie
pub OnFOVQueried( QueryCookie cookie, i client, ConVarQueryResult result, const c[] cvarName, const c[] fov ) {
    if ( result != ConVarQuery_Okay ) return;
    SetClientCookie( client, g_hCookieFOV, "" );
    SetFOV(          client, StringToInt( fov ) );
}

// ====================================================================================================
// HELPERS
// ====================================================================================================

// Sends a message to the client and returns PH
Act EndCmd( i client, const c[] format, any... ) {
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
b GetFOVCookie( i client ) {
    c cookie[ 4 ];
    GetClientCookie( client, g_hCookieFOV, cookie, sizeof( cookie ) );
    i fov = StringToInt( cookie ),
      min = GetConVarInt( g_cvFOVMin ),
      max = GetConVarInt( g_cvFOVMax );

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
        g_bBackupInfiniteAmmoTracked[ n ] = false;
        g_bBackupImmunityTracked[ n ] = false;
        g_bBackupInfiniteAmmo[ n ] = false;
        g_bBackupImmunity[ n ] = false;
    }

    if ( a ) PrintToServer( "Backup system enabled - Steam connection is down" );
    else PrintToServer(     "Backup system disabled - Steam connection restored" );
}

// Respawn frame callback
pub v RespawnFrame( any userid ) {
    // Get client from userid and validate
    i client = GetClientOfUserId( userid );
    
    
    // Validate client is connected and in-game
    if (client <= 0 || client > MaxClients || !IsClientInGame(client)) return;
    
    // Only respawn if on a team and not alive
    if (GetClientTeam(client) > 1 && !IsPlayerAlive(client)) TF2_RespawnPlayer(client);
}

// Command for when resupply key is pressed
NEW_CMD(CResupplyDn) {
    // Check if resupply is globally enabled
    if (!g_bResupplyEnabled) return EndCmd(client, "Resupply functionality has been disabled by an administrator.");
    
    // Check if client is valid
    if (!IsClientInGame(client)) return EndCmd(client, "You must be in-game to use this command.");
    
    // Mark the key as down and reset used flag
    g_bResupplyDn[client] = true;
    g_bResupplyUp[client] = false;
    
    // Try to resupply immediately if in spawn room
    Resupply(client);
    
    PH;
}

// Command for when resupply key is released
NEW_CMD(CResupplyUp) {
    // Check if resupply is globally enabled
    if (!g_bResupplyEnabled) return EndCmd(client, "Resupply functionality has been disabled by an administrator.");
    
    // Check if client is valid
    if (!IsClientInGame(client)) return EndCmd(client, "You must be in-game to use this command.");
    
    // Mark the key as up
    g_bResupplyDn[client] = false;
    
    PH;
}

// Try to resupply a player if conditions are met
v Resupply(i client) {
    // Check if resupply is globally enabled
    if (!g_bResupplyEnabled) return;
    
    // Check if key is down and resupply hasn't been used yet
    if (!g_bResupplyDn[client] || g_bResupplyUp[client]) return;
    if (!IsPlayerAlive(client)) return;
    
    i playerTeam = GetClientTeam(client);
    if (playerTeam <= 1) return;
    
    if (!IsClientInSpawn(client)) return;
    
    // FAILSAFE: Check distance from nearest spawn point
    if (!g_bFailsafeTriggered && !CheckResupplyFailsafe(client)) {
        return; // Failsafe triggered, resupply blocked
    }
    
    TF2_RespawnPlayer(client);
    
    // Reset player velocity to zero
    f zeroVelocity[3] = {0.0, 0.0, 0.0};
    TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, zeroVelocity);
    
    g_bResupplyUp[client] = true;
}

// Check if a player is within the bounds of a brush entity
b IsInEntityBounds(i client, i entity) {
    if (!IsValidClient(client) || !IsValidEntity(entity)) return false;
    
    // Get player hull
    f playerMins[3], playerMaxs[3];
    GetClientMins(client, playerMins);
    GetClientMaxs(client, playerMaxs);
    
    // Get player position
    f playerPos[3];
    GetClientAbsOrigin(client, playerPos);
    
    // Calculate player hull bounds in world space
    f playerHullMins[3], playerHullMaxs[3];
    playerHullMins[0] = playerPos[0] + playerMins[0];
    playerHullMins[1] = playerPos[1] + playerMins[1];
    playerHullMins[2] = playerPos[2] + playerMins[2];
    playerHullMaxs[0] = playerPos[0] + playerMaxs[0];
    playerHullMaxs[1] = playerPos[1] + playerMaxs[1];
    playerHullMaxs[2] = playerPos[2] + playerMaxs[2];
    
    // Get entity bounds
    f entityMins[3], entityMaxs[3];
    GetEntPropVector(entity, Prop_Send, "m_vecMins", entityMins);
    GetEntPropVector(entity, Prop_Send, "m_vecMaxs", entityMaxs);
    
    // Check if player hull intersects with entity bounds
    return (playerHullMaxs[0] >= entityMins[0] && playerHullMins[0] <= entityMaxs[0] &&
            playerHullMaxs[1] >= entityMins[1] && playerHullMins[1] <= entityMaxs[1] &&
            playerHullMaxs[2] >= entityMins[2] && playerHullMins[2] <= entityMaxs[2]);
}

// Check if a player is touching any func_respawnroom entities of their own team
b IsClientInSpawn(i client) {
    if (!IsValidClient(client)) return false;
    
    i playerTeam = GetClientTeam(client);
    if (playerTeam <= 1) return false; // Spectator or unassigned
    
    // Reset player spawn room tracking
    g_bIsClientInSpawn[client] = false;
    for (i s = 0; s < MAX_SPAWN_ROOMS; s++) {
        g_iPlayerSpawns[client][s] = -1;
    }
    
    // Find all func_respawnroom entities
    i entity = -1;
    i spawnCount = 0;
    while ((entity = FindEntityByClassname(entity, "func_respawnroom")) != -1) {
        if (IsValidEntity(entity)) {
            // Check if this spawn room belongs to the player's team
            i spawnTeam = GetEntProp(entity, Prop_Send, "m_iTeamNum");
            if (spawnTeam == playerTeam) {
                // Check if player is within this entity's bounds
                if (IsInEntityBounds(client, entity)) {
                    g_bIsClientInSpawn[client] = true;
                    g_iPlayerSpawns[client][spawnCount] = entity;
                    spawnCount++;
                    
                    // Break if we've reached the maximum number of spawn rooms
                    if (spawnCount >= MAX_SPAWN_ROOMS) break;
                }
            }
        }
    }
    return g_bIsClientInSpawn[client];
}

// Get distance to nearest spawn point of player's team
f GetNearestSpawnDist(i client) {
    if (!IsValidClient(client)) return 999999.0;
    
    i playerTeam = GetClientTeam(client);
    f playerPos[3];
    GetClientAbsOrigin(client, playerPos);
    
    f nearestDistance = 999999.0;
    
    // Find all info_player_teamspawn entities for the player's team
    i entity = -1;
    while ((entity = FindEntityByClassname(entity, "info_player_teamspawn")) != -1) {
        if (IsValidEntity(entity)) {
            i spawnTeam = GetEntProp(entity, Prop_Send, "m_iTeamNum");
            if (spawnTeam == playerTeam) {
                f spawnPos[3];
                GetEntPropVector(entity, Prop_Send, "m_vecOrigin", spawnPos);
                f distance = GetVectorDistance(playerPos, spawnPos);
                if (distance < nearestDistance) {
                    nearestDistance = distance;
                }
            }
        }
    }
    
    return nearestDistance;
}

// Check resupply failsafe - returns false if failsafe triggers
b CheckResupplyFailsafe(i client) {
    f distanceToSpawn = GetNearestSpawnDist(client);
    
    // If player is too far from nearest spawn point, trigger failsafe
    if (distanceToSpawn > RESUPDIST) {
        g_bFailsafeTriggered = true;
        g_bResupplyEnabled = false;
        
        // Get player name for the message
        c playerName[MAX_NAME_LENGTH];
        GetClientName(client, playerName, sizeof(playerName));
        
        // Notify all players
        PrintToChatAll("\x07FF4500[FAILSAFE] \x01Resupply exploit detected! Player %s was %.1f units from spawn (max: %.1f)", playerName, distanceToSpawn, RESUPDIST);
        PrintToChatAll("\x07FF4500[FAILSAFE] \x01Instant resupply has been automatically disabled.");
        PrintToChatAll("\x07FF4500[FAILSAFE] \x01Admins can re-enable with: \x07FFFF00sm_enable_resupply 1");
        
        // Log the event
        LogMessage("Resupply failsafe triggered by %L - distance %.1f > %.1f", client, distanceToSpawn, RESUPDIST);
        
        return false;
    }
    
    return true;
}

// Called when a client disconnects
pub OnClientDisconnect(i client) {
    // Reset spawn room tracking
    g_bIsClientInSpawn[client]  = false;
    g_bResupplyDn[client]  = false;
    g_bResupplyUp[client]     = false;
    g_bImmunity[client]         = false;
    g_bPendingRestoreHP[client] = false;
    g_iPreDamageHP[client]      = 0;
    g_bInfiniteAmmo[client]     = false;
    
    // Reset backup tracking for infinite ammo and immunity
    g_bBackupInfiniteAmmoTracked[client] = false;
    g_bBackupImmunityTracked[client] = false;
    g_bBackupInfiniteAmmo[client] = false;
    g_bBackupImmunity[client] = false;
    
    // Clean up infinite ammo ArrayList if it exists
    if (g_hOriginalAmmo[client] != null) {
        delete g_hOriginalAmmo[client];
        g_hOriginalAmmo[client] = null;
    }
    
    // Clear spawn room entity tracking
    for (i n = 0; n < MAX_SPAWN_ROOMS; n++) {
        g_iPlayerSpawns[client][n] = -1;
    }
}


// ====================================================================================================
// FORWARDS
// ====================================================================================================

// Called when a client's cookies have been loaded
pub v OnClientCookiesCached( i client ) {
    // Steam connection is now available
    g_bSteamConnected = true;

    // If we were using backup system but Steam is now connected, we can disable it
    if ( g_bBackupFOVDB ) SetBackupSystem( false );

    // Try to load from cookies
    GetFOVCookie( client );
    GetAmmoCookie( client );
    GetImmunityCookie( client );
}

v SetAmmoCookie(i client, b enabled) {
    if (AreClientCookiesCached(client)) {
        c cookie[2];
        IntToString(enabled ? 1 : 0, cookie, sizeof(cookie));
        SetClientCookie(client, g_hCookieInfiniteAmmo, cookie);
        g_bSteamConnected = true;
        
        // If we were using backup system but Steam is now connected, we can disable it
        if (g_bBackupFOVDB) SetBackupSystem(false);
    } else {
        // Steam is down, use backup system
        if (!g_bBackupFOVDB) SetBackupSystem(true);
        g_bSteamConnected = false;
        
        // Store in backup system
        g_bBackupInfiniteAmmo[client] = enabled;
        g_bBackupInfiniteAmmoTracked[client] = true;
    }
}
b GetAmmoCookie(i client) {
    c cookie[2];
    GetClientCookie(client, g_hCookieInfiniteAmmo, cookie, sizeof(cookie));
    
    if (strlen(cookie) == 0) return false; // No saved setting
    
    b enabled = (StringToInt(cookie) != 0);
    g_bInfiniteAmmo[client] = enabled;
    
    // If backup system is active, update it with cookie value
    if (g_bBackupFOVDB) {
        g_bBackupInfiniteAmmo[client] = enabled;
        g_bBackupInfiniteAmmoTracked[client] = true;
    }
    
    // Store original ammo if enabling
    if (enabled && IsValidClient(client)) {
        SetInitAmmo(client);
    }
    
    return true;
}

v SetImmunityCookie(i client, b enabled) {
    if (AreClientCookiesCached(client)) {
        c cookie[2];
        IntToString(enabled ? 1 : 0, cookie, sizeof(cookie));
        SetClientCookie(client, g_hCookieImmunity, cookie);
        g_bSteamConnected = true;
        
        // If we were using backup system but Steam is now connected, we can disable it
        if (g_bBackupFOVDB) SetBackupSystem(false);
    } else {
        // Steam is down, use backup system
        if (!g_bBackupFOVDB) SetBackupSystem(true);
        g_bSteamConnected = false;
        
        // Store in backup system
        g_bBackupImmunity[client] = enabled;
        g_bBackupImmunityTracked[client] = true;
    }
}
b GetImmunityCookie(i client) {
    c cookie[2];
    GetClientCookie(client, g_hCookieImmunity, cookie, sizeof(cookie));
    
    if (strlen(cookie) == 0) return false; // No saved setting
    
    b enabled = (StringToInt(cookie) != 0);
    g_bImmunity[client] = enabled;
    
    // If backup system is active, update it with cookie value
    if (g_bBackupFOVDB) {
        g_bBackupImmunity[client] = enabled;
        g_bBackupImmunityTracked[client] = true;
    }
    
    return true;
}

pub v SetInitAmmo( i client ) {
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
pub v GetInitAmmo( i client ) {
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

// SDKHooks damage filter: prevent/zero damage if victim is protected or attacker is restricted
pub Act Hook_OnTakeDamage( i victim, i &attacker, i &inflictor, f &damage, i &damagetype, i &weapon, f damageForce[3], f damagePosition[3], i damagecustom ) {
    if (IsMatch()) PCO;
    
    if ( victim >= 1 && victim <= MaxClients && g_bImmunity[ victim ] ) {
        g_iPreDamageHP[ victim ] = GetClientHealth( victim );
        g_bPendingRestoreHP[ victim ] = true;
        
        if ( g_iPreDamageHP[ victim ] <= damage ) {
            damage--;
        }
        PCH;
    }
    if ( attacker >= 1 && attacker <= MaxClients && g_bImmunity[ attacker ] ) {
        if ( damage > 0.0 ) damage = 0.0;
        PCH;
    }
    PCO;
}

pub v Hook_OnTakeDamagePost( i victim, i attacker, i inflictor, f damage, i damagetype, i weapon, f damageForce[3], f damagePosition[3], i damagecustom ) {
    if (IsMatch()) return;
    
    if ( victim >= 1 && victim <= MaxClients && g_bPendingRestoreHP[ victim ] ) {
        g_bPendingRestoreHP[ victim ] = false;
        if ( IsClientInGame( victim ) && IsPlayerAlive( victim ) ) {
            SetEntProp( victim, Prop_Send, "m_iHealth", g_iPreDamageHP[ victim ] );
        }
    }
}