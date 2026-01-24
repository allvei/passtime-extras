// Imports
#include <morecolors>
#include <clientprefs>
#include <clients>
#include <sdkhooks>
#include <sdktools_entoutput>
#include <sdktools_functions>
#include <sdktools_gamerules>
#include <sdktools_trace>
#include <sdktools>
#include <sourcemod>
#include <tf2_stocks>
#include <tf2>
#include <tf2attributes>

#pragma semicolon 1

// Constants
#define RED         0
#define BLU         1
#define TEAM_OFFSET 2
#define EDICT       2048
#define MAXSPAWNS   4
#define MAXSLOTS    2
#define RESUPDIST   512.0 // Max dist from spawn resupply can be used

// Simple
#define PCH   return Plugin_Changed
#define PCO   return Plugin_Continue
#define PH    return Plugin_Handled
#define pub   public
#define as    view_as
#define Act   Action
#define Han   Handle
#define Ev    Event
#define Pac   public Action
#define i     int
#define v     void
#define f     float
#define b     bool
#define c     char
#define Reply ReplyToCommand
#define elif  else if

#define CC    RegConsoleCmd
#define CCS   RegConsoleCmdWithShort
#define AC    RegAdminCmd
#define ACS   RegAdminCmdWithShort

#define HE             HookEvent
#define NOTIFY         FCVAR_NOTIFY
#define GENERIC        ADMFLAG_GENERIC
#define FindEntByClass FindEntityByClassname


// Complex macros
#define GET_ARG(%1,%2,%3)      c %2[%3]; GetCmdArg(%1,%2,%3)
#define NEW_CMD(%1)            Pac %1( i client, i args )
#define NEW_EV_ACT(%1)         Pac %1( Ev event, const c[] name, b dontBroadcast )
#define NEW_EV(%1)             pub %1( Ev event, const c[] name, b dontBroadcast )
#define STRCP(%1,%2)           strcopy(%1, sizeof(%1), %2)
#define FOR_EACH_CLIENT(%1)    for ( i %1 = 1; %1 <= MaxClients; %1++ )
#define FOR_EACH_ENT(%1)       for ( i %1 = 1; %1 <= EDICT; %1++ )
#define END_CMD(%1)            return EndCommand(client,%1)
#define END_CMD2(%1,%2)        return EndCommand(%1,%2)
#define END_CMD3(%1,%2,%3)     return EndCommand(%1,%2,%3)
#define END_CMD4(%1,%2,%3,%4)  return EndCommand(%1,%2,%3,%4)

public Plugin myinfo = {
    name        = "passtime.tf extras",
    author      = "xCape",
    description = "Plugin for use in passtime.tf servers",
    version     = "1.9.0",
    url         = "https://github.com/allvei/passtime-extras/"
}

// Handles
Han g_hCookieFOV;
Han g_hCookieInfiniteAmmo;
Han g_hCookieImmunity;

// ConVars
ConVar g_cvFOVMin;
ConVar g_cvFOVMax;

// Backup system for FOV tracking when Steam connection is down
b g_bSteamOnline = true;          // Track if Steam is currently connected
b g_bBackupFOVDB = false;         // Track if we're using the backup system
b g_bPlayerTracked[ MAXPLAYERS ]; // Track if we have a FOV value for this player
i g_iPlayerFOV[     MAXPLAYERS ]; // Store FOV values for each player

// Backup system for infinite ammo and immunity when Steam is down
b g_bBackupInfiniteAmmoTracked[MAXPLAYERS]; // Track if we have infinite ammo setting for this player
b g_bBackupImmunityTracked[    MAXPLAYERS]; // Track if we have immunity setting for this player
b g_bBackupInfiniteAmmo[       MAXPLAYERS]; // Store infinite ammo setting for each player
b g_bBackupImmunity[           MAXPLAYERS]; // Store immunity setting for each player

// Resupply tracking
b g_bResupplyDn[ MAXPLAYERS ]; // Is resupply key down
b g_bResupplyUp[ MAXPLAYERS ]; // Has resupply been used during current key press

// Immunity & infinite ammo toggle per player
b g_bImmunity[    MAXPLAYERS];
i g_iPreDamageHP[ MAXPLAYERS];
b g_bPendingHP[   MAXPLAYERS];
b g_bInfiniteAmmo[MAXPLAYERS];

// Original ammo values for infinite ammo restoration (only allocated for players using infinite ammo)
ArrayList g_hOriginalAmmo[MAXPLAYERS]; // Dynamic arrays for players who actually use infinite ammo

// Respawn time control
ConVar g_cvRespawnTime;
b      g_bIsTeamReady[2] = { false, false }; // Track ready state for RED and BLU

// Saved spawn point (admin tools)
b g_bSavedSpawnValid = false;
f g_vSavePos[3];
f g_vSaveAng[3];
f g_vSaveVel[3];

// Backup tournament controls
b g_bResupplyEnabled       = true;
b g_bInstantRespawnEnabled = true;
b g_bImmunityAmmoEnabled   = true;
b g_bSaveEnabled           = true;
b g_bDemoResistEnabled     = false;

// Performance optimization: cached entity indices
i g_iCachedTimerEntity = -1;
ArrayList g_hCachedSpawnRooms = null;
ArrayList g_hCachedSpawnPoints[2] = {null, null}; // RED and BLU spawn points

// Performance optimization: demo resistance state tracking
f g_fCurrentDemoResistValue[MAXPLAYERS]; // Track current applied resistance value
b g_bDemoResistApplied[     MAXPLAYERS]; // Track if resistance is currently applied

// Performance optimization: static ammo arrays (replace ArrayList allocations)
i g_iStaticOriginalAmmo[MAXPLAYERS][34]; // 2 clip values + 32 ammo types
b g_bStaticAmmoValid[   MAXPLAYERS];     // Track if ammo data is valid

i g_iSavedClip1[    MAXSLOTS];
i g_iSavedClip2[    MAXSLOTS];
i g_iSavedAmmoType[ MAXSLOTS][2];
i g_iSavedAmmoCount[MAXSLOTS][2];

pub OnPluginStart() {
    // Admin commands
    ACS( "sm_force_ready",       "sm_fr",   CForceReady,       GENERIC, "Set a team's ready status" );
    ACS( "sm_debug_roundtime",   "sm_drt",  CDebugRoundTime,   GENERIC, "Debug: print team_round_timer info" );
    ACS( "sm_enable_resupply",   "sm_res",  CToggleResupply,   GENERIC, "Toggle resupply functionality" );
    ACS( "sm_enable_respawn",    "sm_resp", CToggleRespawn,    GENERIC, "Toggle instant respawn" );
    ACS( "sm_enable_immunity",   "sm_imm",  CToggleImmunity,   GENERIC, "Toggle immunity and infinite ammo" );
    ACS( "sm_enable_saveload",   "sm_sl",   CToggleSave,       GENERIC, "Toggle save/load spawn functionality" );
    ACS( "sm_enable_demoresist", "sm_dr",   CToggleDemoResist, GENERIC, "Toggle demo blast vulnerability" );
    ACS( "sm_list_blast_attrib", "sm_lba",  CListBlastAttrib,  GENERIC, "Debug: list entities with blast attributes" );
    ACS( "sm_add_tag",           "sm_atag", CAddTag,           GENERIC, "Add prefix tag to all players on a team" );
    ACS( "sm_remove_tag",        "sm_rtag", CRemoveTag,        GENERIC, "Remove prefix tag from all players on a team" );

    // Runner commands
    ACS( "sm_setteam",           "sm_st",   CSetTeam,          GENERIC, "Set a client's team" );
    ACS( "sm_setclass",          "sm_sc",   CSetClass,         GENERIC, "Set a client's class" );

    // Console commands
    CCS( "sm_save",              "sm_sv",   CSaveSpawn,        "Save a spawn point" );
    CCS( "sm_load",              "sm_ld",   CLoadSpawn,        "Teleport to saved spawn" );
    CCS( "sm_immune",            "sm_i",    CImmune,           "Toggle immunity" );
    CCS( "sm_ammo",              "sm_a",    CInfAmmo,         "Toggle infinite ammo" );
    CCS( "sm_diceroll",          "sm_dice", CDice,             "Select a random player from targets" );
    CCS( "sm_ready",             "sm_r",    CReady,            "Toggle your team's ready state" );
    CCS( "sm_team_name",         "sm_tn",   CTeamName,         "Rename your team" );
    CC(  "sm_fov",                          CSetFOV,           "Set your field of view." );
    CC(  "+sm_resupply",                    CResupDn,          "Resupply inside spawn" );
    CC(  "-sm_resupply",                    CResupUp,          "Resupply inside spawn" );
    CC(  "+sm_pt_resupply",                 CResupDn,          "Resupply inside spawn" );
    CC(  "-sm_pt_resupply",                 CResupUp,          "Resupply inside spawn" );

    g_hCookieFOV          = RegClientCookie( "sm_fov_cookie",          "Desired client field of view", CookieAccess_Private );
    g_hCookieInfiniteAmmo = RegClientCookie( "sm_infiniteammo_cookie", "Infinite ammo setting",        CookieAccess_Private );
    g_hCookieImmunity     = RegClientCookie( "sm_immunity_cookie",     "Immunity setting",             CookieAccess_Private );

    // Console variables
    g_cvFOVMin      = CreateConVar( "sm_fov_min",      "70",  "Minimum client field of view", _, 1, 1.0, 1, 175.0 );
    g_cvFOVMax      = CreateConVar( "sm_fov_max",      "120", "Maximum client field of view", _, 1, 1.0, 1, 175.0 );
    g_cvRespawnTime = CreateConVar( "sm_respawn_time", "0.0", "Player respawn delay in seconds", NOTIFY );

    // Hook events
    HE( "player_spawn",      EPSpawn );
    HE( "player_disconnect", EPDisconnect );
    HE( "player_death",      EPDeath );

    // Initialize team ready states
    g_bIsTeamReady[0] = false;
    g_bIsTeamReady[1] = false;

    // Initialize spawn room tracking arrays
    FOR_EACH_CLIENT( n ) {
        g_bResupplyDn[n]      = false;
        g_bResupplyUp[n]      = false;
    }

    // Initialize saved ammo/velocity buffers
    for (i s = 0; s < MAXSLOTS; s++) {
        g_iSavedClip1[s] = -1;
        g_iSavedClip2[s] = -1;
        for (i t = 0; t < 2; t++) {
            g_iSavedAmmoType[s][t]  = -1;
            g_iSavedAmmoCount[s][t] = 0;
        }
    }

    // Initialize infinite ammo ArrayList handles and backup tracking
    FOR_EACH_CLIENT( n ) {
        g_hOriginalAmmo[n]              = null;
        g_bInfiniteAmmo[n]              = false;
        g_bBackupInfiniteAmmoTracked[n] = false;
        g_bBackupImmunityTracked[n]     = false;
        g_bBackupInfiniteAmmo[n]        = false;
        g_bBackupImmunity[n]            = false;
        
        // Initialize performance optimization arrays
        g_fCurrentDemoResistValue[n] = 0.0;
        g_bDemoResistApplied[n]      = false;
        g_bStaticAmmoValid[n]        = false;
        
        // Initialize static ammo array
        for (i j = 0; j < 34; j++) {
            g_iStaticOriginalAmmo[n][j] = 0;
        }
    }

    // Hook damage for currently connected clients and reset nodamage flags
    FOR_EACH_CLIENT( n ) {
        g_bImmunity[n]    = false;
        g_bPendingHP[n]   = false;
        g_iPreDamageHP[n] = 0;
        if ( IsClientInGame(n) ) {
            SDKHook( n, SDKHook_OnTakeDamage,     Hook_OnTakeDamage );
            SDKHook( n, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost );
            
            // Load cookies for currently connected clients on plugin load/reload
            LoadClientCookies(n);
        }
    }
    
    // Initialize entity cache arrays
    g_hCachedSpawnRooms       = new ArrayList();
    g_hCachedSpawnPoints[RED] = new ArrayList();
    g_hCachedSpawnPoints[BLU] = new ArrayList();
    
    // Build initial entity cache
    BuildEntityCache();
}

// Load infinite ammo and immunity cookies for a client on plugin load/reload
v LoadClientCookies(i client) {
    if (!IsValidClient(client)) return;
    
    // Only load cookies if they are cached (Steam is online)
    if (AreClientCookiesCached(client)) {
        // Only load ammo cookie if player is alive and has a weapon
        // This prevents ArrayList errors during plugin startup
        if (IsPlayerAlive(client)) {
            i weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
            if (weapon != -1 && IsValidEntity(weapon)) {
                GetAmmoCookie(client);
            }
        }
        
        // Immunity and FOV cookies don't require weapons, so they're safe to load
        GetImmunityCookie(client);
        GetFOVCookie(client);
    }
}

// OnGameFrame() with immediate response for resupply and ammo
pub v OnGameFrame() {
    // Only validate entity cache periodically (every 30 frames = ~0.5 seconds)
    static i frameCounter = 0;
    if (++frameCounter >= 30) {
        frameCounter = 0;
        ValidateEntityCache();
    }
    
    FOR_EACH_CLIENT( client ) {
        if ( !IsValidClientAlive( client ) ) continue;
        
        // Handle infinite ammo excluding medics
        if ( !IsMatch() && g_bImmunityAmmoEnabled && g_bInfiniteAmmo[ client ] && TF2_GetPlayerClass(client) != TFClass_Medic ) {
            // Get the active weapon
            i weapon = GetEntPropEnt( client, Prop_Send, "m_hActiveWeapon" );
            if ( weapon != -1 && IsValidEntity( weapon ) ) {
                SetEntProp( weapon, Prop_Send, "m_iClip1", 19 );
                SetAmmo( client, weapon, 84 );
            }
        }
        
        // Check for buffered resupply (only if globally enabled)
        if (g_bResupplyEnabled && g_bResupplyDn[client] && !g_bResupplyUp[client] && IsClientInSpawnroom(client)) {
            Resupply(client);
        }
    }
    
    // Only demo resistance moved to event-driven hooks (applied on spawn/class change)
}

// Hook per-client when they enter the server so our damage filter is active
pub v OnClientPutInServer( i client ) {
    SDKHook( client, SDKHook_OnTakeDamage,     Hook_OnTakeDamage );
    SDKHook( client, SDKHook_OnTakeDamagePost, Hook_OnTakeDamagePost );
    
    // Initialize performance tracking for this client
    g_fCurrentDemoResistValue[client] = 0.0;
    g_bDemoResistApplied[client]      = false;
    g_bStaticAmmoValid[client]        = false;
    
    if ( g_bBackupFOVDB ) {
        // Reset tracking for this player slot if backup system is active
        g_bPlayerTracked[ client ] = false;
        g_iPlayerFOV[     client ] = 0;
    }
}

// Use cached timer entity
b IsMatch() {
    // Match is not active if game is awaiting ready restart, timer is paused, or timer is disabled
    b awaitingReadyRestart = as<b>(GameRules_GetProp("m_bAwaitingReadyRestart"));
    b timerPaused   = false;
    b timerDisabled = false;
    b IsPostRound   = GameRules_GetRoundState() == RoundState_TeamWin;

    // Use cached timer entity instead of searching
    if (g_iCachedTimerEntity != -1 && IsValidEntity(g_iCachedTimerEntity)) {
        timerPaused   = as<b>(GetEntProp(g_iCachedTimerEntity, Prop_Send, "m_bTimerPaused"));
        timerDisabled = as<b>(GetEntProp(g_iCachedTimerEntity, Prop_Send, "m_bIsDisabled"));
    }

    // Match is active only if we're not awaiting ready restart and timer is running (not paused and not disabled)
    return !(awaitingReadyRestart || timerPaused || timerDisabled || IsPostRound);
}

// ====================================================================================================
// COMMANDS
// ====================================================================================================

// Command to set a team's ready status
NEW_CMD(CForceReady) {
    if (IsMatch()) PCO;

    if ( args != 2 ) END_CMD( "Usage: sm_force_ready <red|blu> <0|1>" );

    GET_ARG(1, teamArg, 10);
    GET_ARG(2, statusArg, 2);

    i teamIndex = ParseTeamIndex( teamArg );
    i status    = StringToInt( statusArg );

    // Validate input
    if ( teamIndex == -1 ) END_CMD( "Invalid team. Use 'red' or 'blu'." );
    if ( status < 0 || status > 1 ) END_CMD( "Invalid status. Use 0 (not ready) or 1 (ready)." );

    // Set the team's ready status
    i gameRulesTeamOffset = teamIndex + TEAM_OFFSET;
    GameRules_SetProp( "m_bTeamReady", status, 1, gameRulesTeamOffset );

    // Update our internal tracking
    g_bIsTeamReady[teamIndex] = (status != 0);

    PH;
}


// Change client's team
NEW_CMD(CSetTeam) {
    GET_ARG(1, target,     33);
    GET_ARG(2, input_team, 5);
    TFTeam team = ParseTeam(input_team);

    if ( args != 2 || team == TFTeam_Unassigned ) END_CMD2( client, "Usage: sm_setteam <#userid|name> <spec|red|blu>" );


    i target_list[ MAXPLAYERS ];
    c target_name[ MAX_TARGET_LENGTH ];
    b tn_is_ml     = false;
    i target_count = ProcessTargetString( target, client, target_list, MAXPLAYERS, COMMAND_FILTER_CONNECTED, target_name, sizeof( target_name ), tn_is_ml );
    b check        = false;

    if ( target_count == COMMAND_TARGET_NONE ) PH;

    // Change team of client(s)
    for ( i n = 0; n < target_count; n++ ) {
        i targetId = target_list[ n ];
        if ( !IsValidClient( targetId ) || TF2_GetClientTeam( targetId ) == team ) continue;
        check = true;
        ForcePlayerSuicide( targetId );
        TF2_ChangeClientTeam( targetId, team );
        if ( team != TFTeam_Spectator ) TF2_RespawnPlayer( targetId );
    }

    if ( check ) {
        FOR_EACH_CLIENT( n ) {
            GameRules_SetProp( "m_bTeamReady", 0, .element = n );
        }

        c team_name[ 5 ];
        GetTeamName( as<i>( team ), team_name, sizeof( team_name ) );

        Reply( client, "Switched %s to %s", target_name, team_name );
    }
    PH; 
}

// Set your field of view
NEW_CMD(CSetFOV) {
    if ( args != 1 ) END_CMD( "Usage: sm_fov <fov>" );

    i fov = GetCmdArgInt( 1 ),
      min = GetConVarInt( g_cvFOVMin ),
      max = GetConVarInt( g_cvFOVMax );

    if ( fov == 0 ) {
        QueryClientConVar( client, "fov_desired", OnFOVQueried );
        END_CMD( "Your FOV has been reset." );
    }

    if ( fov < min ) END_CMD3( client, "The minimum FOV you can set is %d.", min );
    if ( fov > max ) END_CMD3( client, "The maximum FOV you can set is %d.", max );

    // Try to store in cookies if available
    b cookieSuccess = false;
    if ( AreClientCookiesCached( client ) ) {
        c cookie[ 4 ];
        IntToString( fov, cookie, sizeof( cookie ) );
        SetClientCookie( client, g_hCookieFOV, cookie );
        cookieSuccess     = true;
        g_bSteamOnline = true; // Steam is connected if cookies work

        // If we were using backup system but Steam is now connected, we can disable it
        if ( g_bBackupFOVDB ) SetBackupSystem( false );
    } else {
        // Steam is down, initialize backup system if not already done
        if ( !g_bBackupFOVDB ) SetBackupSystem( true );
        g_bSteamOnline = false;

        // Store in backup system
        g_iPlayerFOV[ client ]     = fov;
        g_bPlayerTracked[ client ] = true;
    }

    // Apply FOV immediately
    SetFOV( client, fov );

    Reply( client, "Your FOV has been set to %d. %s", fov, cookieSuccess ? "" : "(Steam is down, the change will not be permanent.)" );
    PH;
}

// Save a point
NEW_CMD(CSaveSpawn) {
    if ( IsMatch() || !g_bSaveEnabled )                                    END_CMD( "Saving is disabled.");
    if ( client <= 0 || client > MaxClients || !IsClientInGame( client ) ) PH;
    if ( !IsPlayerAlive( client ) )                                        PH;

    GetClientAbsOrigin( client,  g_vSavePos );
    GetClientEyeAngles( client,  g_vSaveAng );
    GetEntPropVector( client, Prop_Data, "m_vecAbsVelocity", g_vSaveVel );

    // Save current ammo and clips for carried weapons
    for ( i s = 0; s < MAXSLOTS; s++ ) {
        g_iSavedClip1[s]        = -1;
        g_iSavedClip2[s]        = -1;
        g_iSavedAmmoType[s][0]  = -1;
        g_iSavedAmmoType[s][1]  = -1;
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

    END_CMD( "Spawn saved!" );
}

// Load saved point
NEW_CMD(CLoadSpawn) {
    if ( IsMatch() || !g_bSaveEnabled )  END_CMD( "Loading is disabled." );
    if ( !IsValidClientAlive( client ) ) PH;
    if ( args != 0 )                     END_CMD( "Usage: sm_load" );
    if ( !g_bSavedSpawnValid )           END_CMD( "No saved spawn point set yet." );

    TeleportEntity( client, g_vSavePos, g_vSaveAng, g_vSaveVel );

    // Restore ammo and clips for current carried weapons
    for ( i s = 0; s < MAXSLOTS; s++ ) {
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
    if ( IsMatch() || !g_bImmunityAmmoEnabled ) END_CMD( "Immunity is disabled." );
    if ( args == 0 ) g_bImmunity[ client ] = !g_bImmunity[ client ];
    else END_CMD( "Usage: sm_immune" );

    SetImmunityCookie( client, g_bImmunity[ client ] );

    if ( IsPlayerAlive( client ) ) TF2_RespawnPlayer( client );

    END_CMD3( client, "Immunity %s.", g_bImmunity[ client ] ? "enabled" : "disabled" );
}

// Toggle infinite ammo
NEW_CMD(CInfAmmo) {
    if ( IsMatch() || !g_bImmunityAmmoEnabled ) END_CMD( "Infinite ammo is disabled." );
    if ( args == 0 ) g_bInfiniteAmmo[ client ] = !g_bInfiniteAmmo[ client ];
    else END_CMD( "Usage: sm_ammo" );

    SetAmmoCookie( client, g_bInfiniteAmmo[ client ] );

    if ( IsPlayerAlive( client ) ) TF2_RespawnPlayer( client );

    END_CMD3( client, "Infinite ammo %s.", g_bInfiniteAmmo[ client ] ? "enabled" : "disabled" );
}

// Set a player's class
NEW_CMD(CSetClass) {
    if ( args != 2 ) END_CMD( "Usage: sm_setclass <#userid|name> <class>" );

    GET_ARG(2, classArg, 16);
    TFClassType tfclass = ParseClass( classArg );
    if ( tfclass == TFClass_Unknown ) END_CMD( "Invalid class. Use class name or number" );

    GET_ARG(1, targetArg, 33);

    i targets[ MAXPLAYERS ];
    c target_name[ MAX_TARGET_LENGTH ];
    b tn_is_ml = false;
    i count    = ProcessTargetString( targetArg, client, targets, MAXPLAYERS, COMMAND_FILTER_CONNECTED, target_name, sizeof( target_name ), tn_is_ml );
    b changed  = false;
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
            case TFClass_Scout:    STRCP(className, "Scout");
            case TFClass_Soldier:  STRCP(className, "Soldier");
            case TFClass_Pyro:     STRCP(className, "Pyro");
            case TFClass_DemoMan:  STRCP(className, "Demoman");
            case TFClass_Heavy:    STRCP(className, "Heavy");
            case TFClass_Engineer: STRCP(className, "Engineer");
            case TFClass_Medic:    STRCP(className, "Medic");
            case TFClass_Sniper:   STRCP(className, "Sniper");
            case TFClass_Spy:      STRCP(className, "Spy");
            default: STRCP(className, "Unknown");
        }
        Reply( client, "Set %s class to %s", target_name, className );
    }
    PH;
}

// Select a random player from targets or custom strings
NEW_CMD(CDice) {
    if (args < 1) END_CMD2(client, "Usage: sm_dice <\"customstring\" | #userid | playername | @team>");

    c customStrings[10][64]; // Support up to 10 custom strings
    i customCount = 0;
    i allTargets[MAXPLAYERS];
    i totalTargetCount = 0;
    
    // Get the full command string to handle quoted arguments properly
    c fullCmd[256];
    GetCmdArgString(fullCmd, sizeof(fullCmd));
    
    // Parse arguments manually to handle quotes correctly
    c arguments[10][64];
    i argCount = 0;
    i pos = 0;
    i len = strlen(fullCmd);
    
    while (pos < len && argCount < 10) {
        // Skip leading spaces
        while (pos < len && (fullCmd[pos] == ' ' || fullCmd[pos] == '\t')) {
            pos++;
        }
        
        if (pos >= len) break;
        
        i argStart = pos;
        i argLen = 0;
        
        if (fullCmd[pos] == '"') {
            // Quoted argument - find closing quote
            pos++; // Skip opening quote
            argStart = pos;
            
            while (pos < len && fullCmd[pos] != '"') {
                pos++;
            }
            
            if (pos < len) {
                argLen = pos - argStart;
                pos++; // Skip closing quote
            } else {
                argLen = len - argStart;
            }
        } else {
            // Unquoted argument - read until space
            while (pos < len && fullCmd[pos] != ' ' && fullCmd[pos] != '\t') {
                pos++;
            }
            argLen = pos - argStart;
        }
        
        // Copy argument
        if (argLen > 0 && argLen < sizeof(arguments[])) {
            for (i copyIdx = 0; copyIdx < argLen && copyIdx < sizeof(arguments[]) - 1; copyIdx++) {
                arguments[argCount][copyIdx] = fullCmd[argStart + copyIdx];
            }
            arguments[argCount][argLen] = '\0';
            argCount++;
        }
    }
    
    // Process parsed arguments
    for (i argIndex = 0; argIndex < argCount; argIndex++) {
        c arg[64];
        strcopy(arg, sizeof(arg), arguments[argIndex]);
        
        // Check if it looks like a number (custom string)
        b isNumeric = true;
        for (i j = 0; j < strlen(arg); j++) {
            if (arg[j] < '0' || arg[j] > '9') {
                isNumeric = false;
                break;
            }
        }
        
        if (isNumeric || strlen(arg) <= 3) {
            // Treat as custom string
            strcopy(customStrings[customCount], sizeof(customStrings[]), arg);
            customCount++;
        } else {
            // Try to process as player target
            i targets[MAXPLAYERS];
            c target_name[MAX_TARGET_LENGTH];
            b tn_is_ml = false;
            i target_count = ProcessTargetString(arg, client, targets, MAXPLAYERS, COMMAND_FILTER_CONNECTED, target_name, sizeof(target_name), tn_is_ml);
            
            // Add found targets to our combined list (avoid duplicates)
            for (i n = 0; n < target_count && totalTargetCount < MAXPLAYERS; n++) {
                b alreadyAdded = false;
                for (i existing = 0; existing < totalTargetCount; existing++) {
                    if (allTargets[existing] == targets[n]) {
                        alreadyAdded = true;
                        break;
                    }
                }
                
                if (!alreadyAdded) {
                    allTargets[totalTargetCount] = targets[n];
                    totalTargetCount++;
                }
            }
        }
    }
    
    // Determine what to select from
    if (customCount > 0 && totalTargetCount == 0) {
        // Only custom strings - select random custom string
        i random_index = GetRandomInt(0, customCount - 1);
        PrintToChatAll("Rolled %s", customStrings[random_index]);
    } elif (totalTargetCount > 0) {
        // Players found - select random player
        i random_index = GetRandomInt(0, totalTargetCount - 1);
        i selected_player = allTargets[random_index];
        
        c selected_name[MAX_NAME_LENGTH];
        GetClientName(selected_player, selected_name, sizeof(selected_name));
        PrintToChatAll("%s was rolled!", selected_name);
    } elif (customCount > 0) {
        // Mixed case - select from custom strings
        i random_index = GetRandomInt(0, customCount - 1);
        PrintToChatAll("Rolled %s", customStrings[random_index]);
    } else {
        Reply(client, "No valid targets or options provided.");
        PH;
    }
    
    PH;
}

// Toggle ready state for the user's team
NEW_CMD(CReady) {
    if (IsMatch()) END_CMD2(client, "Ready command can not be used during a game.");
    if (args != 0) END_CMD2(client, "Usage: sm_ready");
    
    // Get client's team
    TFTeam clientTeam = TF2_GetClientTeam(client);
    if (clientTeam != TFTeam_Red && clientTeam != TFTeam_Blue) {
        END_CMD2(client, "You must be on RED or BLU team to use this command.");
    }
    
    // Convert TF team to array index
    i teamIndex = (clientTeam == TFTeam_Red) ? RED : BLU;
    
    // Toggle ready state
    g_bIsTeamReady[teamIndex] = !g_bIsTeamReady[teamIndex];
    
    // Update game rules
    i gameRulesTeamOffset = teamIndex + TEAM_OFFSET;
    GameRules_SetProp("m_bTeamReady", g_bIsTeamReady[teamIndex] ? 1 : 0, 1, gameRulesTeamOffset);
    
    // Get team name for display
    c teamName[10];
    if (clientTeam == TFTeam_Red) {
        STRCP(teamName, "RED");
    } else {
        STRCP(teamName, "BLU");
    }
    
    // Announce to all players
    c playerName[MAX_NAME_LENGTH];
    GetClientName(client, playerName, sizeof(playerName));
    PrintToChatAll("%s set team %s to %s", playerName, teamName, g_bIsTeamReady[teamIndex] ? "READY" : "NOT READY");
    
    PH;
}

// Rename team command
NEW_CMD(CTeamName) {
    if (IsMatch()) END_CMD2(client, "Team rename command can only be used during preround.");
    if (args != 1) END_CMD2(client, "Usage: sm_team_name <new_name>");
    
    // Get client's team
    TFTeam clientTeam = TF2_GetClientTeam(client);
    if (clientTeam != TFTeam_Red && clientTeam != TFTeam_Blue) {
        END_CMD2(client, "You must be on RED or BLU team to use this command.");
    }
    
    // Get new team name
    GET_ARG(1, newName, 64);
    
    // Validate name length
    if (strlen(newName) < 1)  END_CMD2(client, "Team name cannot be empty.");
    if (strlen(newName) > 32) END_CMD2(client, "Team name cannot be longer than 32 characters.");
    
    // Get team entity
    i teamEntity = -1;
    if (clientTeam == TFTeam_Red) {
        teamEntity = FindEntityByClassname(-1, "tf_team");
        while (teamEntity != -1 && GetEntProp(teamEntity, Prop_Send, "m_iTeamNum") != 2) {
            teamEntity = FindEntityByClassname(teamEntity, "tf_team");
        }
    } else {
        teamEntity = FindEntityByClassname(-1, "tf_team");
        while (teamEntity != -1 && GetEntProp(teamEntity, Prop_Send, "m_iTeamNum") != 3) {
            teamEntity = FindEntityByClassname(teamEntity, "tf_team");
        }
    }
    
    if (teamEntity == -1) END_CMD2(client, "Could not find team entity.");
    
    // Set the team name
    SetEntPropString(teamEntity, Prop_Data, "m_szTeamname", newName);
    
    // Get old team name for display
    c oldTeamName[10];
    if (clientTeam == TFTeam_Red) STRCP(oldTeamName, "RED");
    else STRCP(oldTeamName, "BLU");
    
    // Announce to all players
    c playerName[MAX_NAME_LENGTH];
    GetClientName(client, playerName, sizeof(playerName));
    PrintToChatAll("%s renamed team %s to \"%s\"", playerName, oldTeamName, newName);
    
    PH;
}

TFClassType ParseClass( c[] s ) {
    if ( StrEqual( s, "soldier" ) || StrEqual( s, "2" ) ) return TFClass_Soldier;
    if ( StrEqual( s, "demo" )    || StrEqual( s, "demoman" ) || StrEqual( s, "4" ) ) return TFClass_DemoMan;
    if ( StrEqual( s, "med" )     || StrEqual( s, "medic" )   || StrEqual( s, "7" ) ) return TFClass_Medic;
    return TFClass_Unknown;
}

NEW_CMD(CDebugRoundTime) {
    i ent   = -1;
    i found = 0;

    while ((ent = FindEntityByClassname(ent, "team_round_timer")) != -1) {
        b timerPaused         = as<b>(GetEntProp(     ent, Prop_Send, "m_bTimerPaused"));
        f timeRemaining       =       GetEntPropFloat(ent, Prop_Send, "m_flTimeRemaining");
        f timerEndTime        =       GetEntPropFloat(ent, Prop_Send, "m_flTimerEndTime");
        b isDisabled          = as<b>(GetEntProp(     ent, Prop_Send, "m_bIsDisabled"));
        b showInHUD           = as<b>(GetEntProp(     ent, Prop_Send, "m_bShowInHUD"));
        i timerLength         =       GetEntProp(     ent, Prop_Send, "m_nTimerLength");
        i timerInitialLength  =       GetEntProp(     ent, Prop_Send, "m_nTimerInitialLength");
        i timerMaxLength      =       GetEntProp(     ent, Prop_Send, "m_nTimerMaxLength");
        b autoCountdown       = as<b>(GetEntProp(     ent, Prop_Send, "m_bAutoCountdown"));
        i setupTimeLength     =       GetEntProp(     ent, Prop_Send, "m_nSetupTimeLength");
        i state               =       GetEntProp(     ent, Prop_Send, "m_nState");
        b startPaused         = as<b>(GetEntProp(     ent, Prop_Send, "m_bStartPaused"));
        b showTimeRemaining   = as<b>(GetEntProp(     ent, Prop_Send, "m_bShowTimeRemaining"));
        b inCaptureWatchState = as<b>(GetEntProp(     ent, Prop_Send, "m_bInCaptureWatchState"));
        f totalTime           =       GetEntPropFloat(ent, Prop_Send, "m_flTotalTime");
        b stopWatchTimer      = as<b>(GetEntProp(     ent, Prop_Send, "m_bStopWatchTimer"));
        
        // Check if game is ongoing using m_bAwaitingReadyRestart and timer pause state
        b awaitingReadyRestart = as<b>(GameRules_GetProp("m_bAwaitingReadyRestart"));
        b gameOngoing = !awaitingReadyRestart && !timerPaused && !isDisabled;
        
        Reply(client, "[timer %d] m_bTimerPaused=%d m_flTimeRemaining=%.2f m_flTimerEndTime=%.2f m_bIsDisabled=%d m_bShowInHUD=%d", ent, timerPaused, timeRemaining, timerEndTime, isDisabled, showInHUD);
        Reply(client, "[timer %d] m_nTimerLength=%d m_nTimerInitialLength=%d m_nTimerMaxLength=%d m_bAutoCountdown=%d",             ent, timerLength, timerInitialLength, timerMaxLength, autoCountdown);
        Reply(client, "[timer %d] m_nSetupTimeLength=%d m_nState=%d m_bStartPaused=%d m_bShowTimeRemaining=%d",                     ent, setupTimeLength, state, startPaused, showTimeRemaining);
        Reply(client, "[timer %d] m_bInCaptureWatchState=%d m_flTotalTime=%.2f m_bStopWatchTimer=%d",                               ent, inCaptureWatchState, totalTime, stopWatchTimer);
        Reply(client, "[timer %d] Game Ongoing: %d (m_bAwaitingReadyRestart=%d)",                                                   ent, gameOngoing, awaitingReadyRestart);
        
        found++;
    }

    if (found == 0) END_CMD2(client, "No team_round_timer found.");
    PH;
}

// ====================================================================================================
// BACKUP COMMANDS
// ====================================================================================================

// Backup toggle for resupply
NEW_CMD(CToggleResupply) {
    if (args != 1) END_CMD2(client, "Usage: sm_enable_resupply <0|1>");

    GET_ARG(1, arg, 4);
    i value = StringToInt(arg);

    if (value != 0 && value != 1) END_CMD2(client, "Usage: sm_enable_resupply <0|1> (0=disable, 1=enable)");

    g_bResupplyEnabled = (value != 0);

    END_CMD3(client, "Resupply functionality %s", g_bResupplyEnabled ? "ENABLED" : "DISABLED");
}

// Backup toggle for instant respawn
NEW_CMD(CToggleRespawn) {
    if (args != 1) END_CMD2(client, "Usage: sm_enable_respawn <0|1>");

    GET_ARG(1, arg, 4);
    i value = StringToInt(arg);

    if (value != 0 && value != 1) END_CMD2(client, "Usage: sm_enable_respawn <0|1>");

    g_bInstantRespawnEnabled = (value != 0);

    END_CMD3(client, "Instant respawn %s", g_bInstantRespawnEnabled ? "enabled" : "disabled");
}

// Backup toggle for immunity and infinite ammo
NEW_CMD(CToggleImmunity) {
    if (args != 1) END_CMD2(client, "Usage: sm_enable_immunity <0|1>");

    GET_ARG(1, arg, 4);
    i value = StringToInt(arg);

    if (value != 0 && value != 1) END_CMD2(client, "Usage: sm_enable_immunity <0|1> (0=disable, 1=enable)");

    g_bImmunityAmmoEnabled = (value != 0);

    // If disabling, turn off immunity and infinite ammo for all players
    if (!g_bImmunityAmmoEnabled) {
        FOR_EACH_CLIENT( n ) {
            if (IsClientInGame(n)) {
                g_bImmunity[n]     = false;
                g_bInfiniteAmmo[n] = false;
                if (g_hOriginalAmmo[n] != null) {
                    delete g_hOriginalAmmo[n];
                    g_hOriginalAmmo[n] = null;
                }
            }
        }
    }

    END_CMD3(client, "Immunity and infinite ammo %s", g_bImmunityAmmoEnabled ? "ENABLED" : "DISABLED");
}

// Backup toggle for save/load
NEW_CMD(CToggleSave) {
    if (args != 1) END_CMD2(client, "Usage: sm_enable_saveload <0|1>");

    GET_ARG(1, arg, 4);
    i value = StringToInt(arg);

    if (value != 0 && value != 1) END_CMD2(client, "Usage: sm_enable_saveload <0|1> (0=disable, 1=enable)");

    g_bSaveEnabled = (value != 0);

    END_CMD3(client, "Save/Load spawn functionality %s", g_bSaveEnabled ? "ENABLED" : "DISABLED");
}

// Backup toggle for demo blast vulnerability
NEW_CMD(CToggleDemoResist) {
    if (args != 1) END_CMD2(client, "Usage: sm_enable_demoresist <0|1>");

    GET_ARG(1, arg, 4);
    i value = StringToInt(arg);

    if (value != 0 && value != 1) END_CMD2(client, "Usage: sm_enable_demoresist <0|1>");

    g_bDemoResistEnabled = (value != 0);

    // Apply resistance changes to all connected players
    FOR_EACH_CLIENT( n ) {
        if (IsClientInGame(n)) {
            ApplyDemoResistance(n);
        }
    }

    END_CMD3(client, "Demo blast vulnerability %s", g_bDemoResistEnabled ? "ENABLED" : "DISABLED");
}

// Debug command to list entities with blast attributes
NEW_CMD(CListBlastAttrib) {
    i count = 0;
    FOR_EACH_CLIENT( n ) {
        if (IsClientInGame(n) && g_bDemoResistApplied[n]) {
            c name[MAX_NAME_LENGTH];
            GetClientName(n, name, sizeof(name));
            Reply(client, "Player %s (ID: %d) has blast resistance value: %.2f", name, n, g_fCurrentDemoResistValue[n]);
            count++;
        }
    }
    
    if (count == 0) {
        Reply(client, "No players currently have blast resistance attributes applied.");
    } else {
        Reply(client, "Total players with blast resistance: %d", count);
    }
    
    PH;
}

// Add prefix tag to all players on a team
NEW_CMD(CAddTag) {
    if (args != 2) END_CMD2(client, "Usage: sm_add_tag <red|blu> <tag>");
    
    GET_ARG(1, teamArg, 10);
    GET_ARG(2, tagArg, 8);
    
    // Validate team
    i teamIndex = ParseTeamIndex(teamArg);
    if (teamIndex == -1) END_CMD2(client, "Invalid team. Use 'red|r' or 'blu|blue|b'.");
    
    // Validate tag length (max 7 characters)
    if (strlen(tagArg) < 1) END_CMD2(client, "Tag cannot be empty.");
    if (strlen(tagArg) > 7) END_CMD2(client, "Tag cannot be longer than 7 characters.");
    
    // Apply tag to all players on the team
    i playersTagged = 0;
    TFTeam targetTeam = (teamIndex == RED) ? TFTeam_Red : TFTeam_Blue;
    
    FOR_EACH_CLIENT(n) {
        if (!IsClientInGame(n) || IsFakeClient(n)) continue;
        if (TF2_GetClientTeam(n) != targetTeam) continue;
        
        // Get current name
        c currentName[MAX_NAME_LENGTH];
        GetClientName(n, currentName, sizeof(currentName));
        
        // Check if name already has this tag
        if (StrContains(currentName, tagArg, false) == 0) continue; // Skip if already has tag at start
        
        // Create new name with tag prefix
        c newName[MAX_NAME_LENGTH];
        Format(newName, sizeof(newName), "%s %s", tagArg, currentName);
        
        // Ensure new name doesn't exceed max length
        if (strlen(newName) > MAX_NAME_LENGTH - 1) {
            // Truncate original name to fit
            i maxOriginalLength = MAX_NAME_LENGTH - strlen(tagArg) - 2; // -2 for space and null terminator
            if (maxOriginalLength > 0) {
                c truncatedName[MAX_NAME_LENGTH];
                strcopy(truncatedName, maxOriginalLength + 1, currentName);
                Format(newName, sizeof(newName), "%s %s", tagArg, truncatedName);
            } else {
                continue; // Skip if tag is too long
            }
        }
        
        // Set the new name
        SetClientName(n, newName);
        playersTagged++;
    }
    
    // Report results
    c teamName[10];
    if (teamIndex == RED) STRCP(teamName, "RED");
    else STRCP(teamName, "BLU");
    
    if (playersTagged > 0) {
        c adminName[MAX_NAME_LENGTH];
        GetClientName(client, adminName, sizeof(adminName));
        PrintToChatAll("Admin %s added tag \"%s\" to %d players on team %s", adminName, tagArg, playersTagged, teamName);
        Reply(client, "Successfully added tag \"%s\" to %d players on team %s", tagArg, playersTagged, teamName);
    } else {
        Reply(client, "No players were tagged on team %s (team empty or all players already have this tag)", teamName);
    }
    
    PH;
}

// Remove prefix tag from all players on a team
NEW_CMD(CRemoveTag) {
    if (args != 2) END_CMD2(client, "Usage: sm_remove_tag <red|blu> <tag>");
    
    GET_ARG(1, teamArg, 10);
    GET_ARG(2, tagArg, 8);
    
    // Validate team
    i teamIndex = ParseTeamIndex(teamArg);
    if (teamIndex == -1) END_CMD2(client, "Invalid team. Use 'red|r' or 'blu|blue|b'.");
    
    // Validate tag length
    if (strlen(tagArg) < 1) END_CMD2(client, "Tag cannot be empty.");
    if (strlen(tagArg) > 7) END_CMD2(client, "Tag cannot be longer than 7 characters.");
    
    // Remove tag from all players on the team
    i playersUntagged = 0;
    TFTeam targetTeam = (teamIndex == RED) ? TFTeam_Red : TFTeam_Blue;
    
    FOR_EACH_CLIENT(n) {
        if (!IsClientInGame(n) || IsFakeClient(n)) continue;
        if (TF2_GetClientTeam(n) != targetTeam) continue;
        
        // Get current name
        c currentName[MAX_NAME_LENGTH];
        GetClientName(n, currentName, sizeof(currentName));
        
        // Check if name starts with the tag followed by a space
        c tagWithSpace[10];
        Format(tagWithSpace, sizeof(tagWithSpace), "%s ", tagArg);
        
        if (StrContains(currentName, tagWithSpace, false) == 0) {
            // Remove the tag prefix (tag + space)
            c newName[MAX_NAME_LENGTH];
            strcopy(newName, sizeof(newName), currentName[strlen(tagWithSpace)]);
            
            // Ensure we don't end up with an empty name
            if (strlen(newName) < 1) {
                strcopy(newName, sizeof(newName), "Player");
            }
            
            // Set the new name
            SetClientName(n, newName);
            playersUntagged++;
        }
    }
    
    // Report results
    c teamName[10];
    if (teamIndex == RED) STRCP(teamName, "RED");
    else STRCP(teamName, "BLU");
    
    if (playersUntagged > 0) {
        c adminName[MAX_NAME_LENGTH];
        GetClientName(client, adminName, sizeof(adminName));
        PrintToChatAll("Admin %s removed tag \"%s\" from %d players on team %s", adminName, tagArg, playersUntagged, teamName);
        Reply(client, "Successfully removed tag \"%s\" from %d players on team %s", tagArg, playersUntagged, teamName);
    } else {
        Reply(client, "No players had tag \"%s\" removed on team %s", tagArg, teamName);
    }
    
    PH;
}

// ====================================================================================================
// EVENTS
// ====================================================================================================

// Handle player death event
Pac EPDeath( Ev event, const c[] name, b dontBroadcast ) {
    if (IsMatch()) PCO;

    i client = GetClientOfUserId(event.GetInt( "userid" ));

    // Validate client before proceeding
    if (!IsValidClient(client)) PCO;

    // Check if instant respawn is globally enabled
    if (g_bInstantRespawnEnabled && g_cvRespawnTime.FloatValue <= 0.0) {
        RequestFrame( RespawnFrame, client );
    }

    PCO;
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

    ApplyDemoResistance(client);

    // Try to restore settings from cookies first
    if ( AreClientCookiesCached( client ) ) {
        if ( GetFOVCookie( client ) ) {
            // If we were using backup but Steam is now connected, we can disable it
            if ( !g_bSteamOnline ) {
                g_bSteamOnline = true;
                if ( g_bBackupFOVDB ) SetBackupSystem( false );
            }
        }
        
        // Restore infinite ammo and immunity settings
        GetAmmoCookie( client );
        GetImmunityCookie( client );
        return;
    } elif ( !g_bBackupFOVDB ) {
        // Steam is down, initialize backup system
        SetBackupSystem( true );
        g_bSteamOnline = false;
    }

    // If cookies failed or aren't cached, try backup system
    if ( g_bBackupFOVDB && g_bPlayerTracked[ client ] && g_iPlayerFOV[ client ] > 0 ) {
        SetFOV( client, g_iPlayerFOV[ client ] );
    }

    // Restore from backup system for infinite ammo and immunity
    if ( g_bBackupInfiniteAmmoTracked[ client ] ) {
        g_bInfiniteAmmo[ client ] = g_bBackupInfiniteAmmo[ client ];
        if ( g_bInfiniteAmmo[ client ] ) {
            SetInitAmmoStatic( client );
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
Act EndCommand( i client, const c[] format, any... ) {
    c buffer[ 254 ];
    VFormat( buffer, sizeof( buffer ), format, 3 );
    Reply( client, "%s", buffer );
    PH;
}

// Checks if a client in-game, connected, not fake, and in a valid team
b IsValidClient( i client ) {
    return IsClientInGame( client ) && !IsFakeClient( client ) && IsClientConnected( client );
}

// Checks if a client in-game, connected, not fake, and in a valid team
b IsValidClientAlive( i client ) {
    return IsValidClient( client ) && IsPlayerAlive( client );
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
TFTeam ParseTeam( c[] team ) {
    return StrEqual( team, "spectator" ) || StrEqual( team, "spec" ) || StrEqual( team, "s" ) ? TFTeam_Spectator
         : StrEqual( team, "red" )       || StrEqual( team, "r" )                             ? TFTeam_Red
         : StrEqual( team, "blue" )      || StrEqual( team, "blu" )  || StrEqual( team, "b" ) ? TFTeam_Blue
                                                                                              : TFTeam_Unassigned;
}

// Converts team name string to RED/BLU constants
i ParseTeamIndex( c[] team ) {
    return StrEqual( team, "red" ) || StrEqual( team, "r" )                             ? RED
         : StrEqual( team, "blu" ) || StrEqual( team, "blue" ) || StrEqual( team, "b" ) ? BLU
                                                                                        : -1;
}

// Enable or disable the backup system based on Steam connection status
SetBackupSystem( b a ) {
    if ( g_bBackupFOVDB == a ) return; // Already in desired state
    g_bBackupFOVDB = a;
    // Initialize/clear player tracking arrays
    FOR_EACH_CLIENT( client ) {
        g_iPlayerFOV[                 client ] = 0;
        g_bPlayerTracked[             client ] = false;
        g_bBackupInfiniteAmmoTracked[ client ] = false;
        g_bBackupImmunityTracked[     client ] = false;
        g_bBackupInfiniteAmmo[        client ] = false;
        g_bBackupImmunity[            client ] = false;
    }

    if ( a ) PrintToServer( "Backup system enabled - Steam connection is down" );
    else PrintToServer(     "Backup system disabled - Steam connection restored" );
}

// Respawn frame callback
pub v RespawnFrame( any client ) {
    if (!IsPlayerAlive(client)) TF2_RespawnPlayer(client);
}

// Command for when resupply key is pressed
NEW_CMD(CResupDn) {
    // Check if resupply is globally enabled
    if (!g_bResupplyEnabled) END_CMD2(client, "Resupply is disabled.");

    // Check if client is valid
    if (!IsClientInGame(client)) END_CMD2(client, "You must be in-game to use this command.");

    // Mark the key as down and reset used flag
    g_bResupplyDn[client] = true;
    g_bResupplyUp[client] = false;

    // Try to resupply immediately if in spawn room
    Resupply(client);

    PH;
}

// Command for when resupply key is released
NEW_CMD(CResupUp) {
    // Check if client is valid
    if (!IsClientInGame(client)) PH;

    // Check if resupply is globally enabled
    if (!g_bResupplyEnabled) PH;

    // Mark the key as up
    g_bResupplyDn[client] = false;
    PH;
}

// Try to resupply a player if conditions are met
v Resupply(i client) {
    if (!IsValidClientAlive(client)) return;
    // Check if resupply is globally enabled
    if (!g_bResupplyEnabled) return;

    // Check if key is down and resupply hasn't been used yet
    if (!g_bResupplyDn[client] || g_bResupplyUp[client]) return;

    if (!IsClientInSpawnroom(client)) return;

    TF2_RespawnPlayer(client);

    // Reset player velocity to zero
    TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, {0.0, 0.0, 0.0});

    g_bResupplyUp[client] = true;
}

// Check if a player is within the bounds of a brush entity
b IsColliding(i client, i entity) {
    // Get player hull
    f playerMins[3], playerMaxs[3];
    GetClientMins(client, playerMins);
    GetClientMaxs(client, playerMaxs);

    // Get player position
    f playerPos[3];
    GetClientAbsOrigin(client, playerPos);

    // Calculate player hull bounds in world space
    f playerHullMins[3], playerHullMaxs[3];
    for (i n = 0; n < 3; n++) {
        playerHullMins[n] = playerPos[n] + playerMins[n];
        playerHullMaxs[n] = playerPos[n] + playerMaxs[n];
    }

    // Get entity bounds - use Prop_Data for accurate values and add origin for absolute coordinates
    f entityOrigin[3], entityMins[3], entityMaxs[3];
    GetEntPropVector(entity, Prop_Data, "m_vecOrigin", entityOrigin);
    GetEntPropVector(entity, Prop_Data, "m_vecMins", entityMins);
    GetEntPropVector(entity, Prop_Data, "m_vecMaxs", entityMaxs);
    
    // Convert relative bounds to absolute world coordinates
    f entityAbsMins[3], entityAbsMaxs[3];
    AddVectors(entityOrigin, entityMins, entityAbsMins);
    AddVectors(entityOrigin, entityMaxs, entityAbsMaxs);

    // Check if player hull intersects with entity bounds (now in absolute coordinates)
    return (playerHullMaxs[0] >= entityAbsMins[0] && playerHullMins[0] <= entityAbsMaxs[0] &&
            playerHullMaxs[1] >= entityAbsMins[1] && playerHullMins[1] <= entityAbsMaxs[1] &&
            playerHullMaxs[2] >= entityAbsMins[2] && playerHullMins[2] <= entityAbsMaxs[2]);
}

// Check if a player is touching any func_respawnroom entities of their own team
b IsClientInSpawnroom(i client) {
    // Use cached spawn room entities instead of searching
    i clientTeam = GetClientTeam(client);
    
    for (i idx = 0; idx < g_hCachedSpawnRooms.Length; idx++) {
        i spawnroom = g_hCachedSpawnRooms.Get(idx);
        if (IsValidEntity(spawnroom) && GetEntProp(spawnroom, Prop_Send, "m_iTeamNum") == clientTeam && IsColliding(client, spawnroom)) {
            if (IsTooFarFromSpawnpoint(client)) return false;
            return true;
        }
    }
    return false;
}

// Get distance to nearest spawn point of player's team
b IsTooFarFromSpawnpoint(i client) {
    f playerPos[3];
    GetClientAbsOrigin(client, playerPos);

    f nearestDistance = 100000.0;
    i clientTeam = GetClientTeam(client);
    i teamIndex = (clientTeam == 2) ? RED : BLU; // Convert TF team to array index
    
    // Use cached spawn points instead of searching
    if (g_hCachedSpawnPoints[teamIndex] != null) {
        for (i idx = 0; idx < g_hCachedSpawnPoints[teamIndex].Length; idx++) {
            i spawn = g_hCachedSpawnPoints[teamIndex].Get(idx);
            if (!IsValidEntity(spawn)) continue;

            f spawnPos[3];
            GetEntPropVector(spawn, Prop_Send, "m_vecOrigin", spawnPos);

            f distance = GetVectorDistance(playerPos, spawnPos);
            if (distance < nearestDistance) nearestDistance = distance;
        }
    }
    
    if (nearestDistance < RESUPDIST) return false;
    else {
        c name[MAX_NAME_LENGTH];
        GetClientName(client, name, sizeof(name));
        return true;
    }
}

// Called when a client disconnects
pub OnClientDisconnect(i client) {
    g_bResupplyDn[   client] = false;
    g_bResupplyUp[   client] = false;
    g_bImmunity[     client] = false;
    g_bPendingHP[    client] = false;
    g_iPreDamageHP[  client] = 0;
    g_bInfiniteAmmo[ client] = false;

    // Reset backup tracking for infinite ammo and immunity
    g_bBackupInfiniteAmmoTracked[client] = false;
    g_bBackupImmunityTracked[    client] = false;
    g_bBackupInfiniteAmmo[       client] = false;
    g_bBackupImmunity[           client] = false;

    // Clean up infinite ammo ArrayList if it exists
    if (g_hOriginalAmmo[client] != null) {
        delete g_hOriginalAmmo[client];
        g_hOriginalAmmo[client] = null;
    }
    
    // Clean up performance optimization tracking
    g_fCurrentDemoResistValue[client] = 0.0;
    g_bDemoResistApplied[client]      = false;
    g_bStaticAmmoValid[client]        = false;
    
    // Clear static ammo array
    for (i j = 0; j < 34; j++) {
        g_iStaticOriginalAmmo[client][j] = 0;
    }
}

v SetAmmo(i client, i weapon, i ammo)
{
    if (IsValidEntity(weapon))
    {
        i offset   = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType", 1)*4;
        i ammotype = FindSendPropInfo("CTFPlayer", "m_iAmmo") + offset;
        SetEntData(client, ammotype, ammo, 4, true);
    }
}

i TF2_GetPlayerMaxHealth(int client) {
	return GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, client);
}

v RegAdminCmdWithShort(const char[] cmd,
                       const char[] shortcmd,
                       ConCmd callback,
                       int adminflags,
                       const char[] description="",
                       const char[] group="",
                       int flags=0) {
    RegAdminCmd(cmd,      callback, adminflags, description, group, flags);
    RegAdminCmd(shortcmd, callback, adminflags, description, group, flags);
}

v RegConsoleCmdWithShort(const char[] cmd,
                         const char[] shortcmd,
                         ConCmd callback,
                         const char[] description="",
                         int flags=0) {
    RegConsoleCmd(cmd,      callback, description, flags);
    RegConsoleCmd(shortcmd, callback, description, flags);
}

// ====================================================================================================
// FORWARDS
// ====================================================================================================

// Called when a client's cookies have been loaded
pub v OnClientCookiesCached( i client ) {
    // Steam connection is now available
    g_bSteamOnline = true;

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
        g_bSteamOnline = true;
        
        // If we were using backup system but Steam is now connected, we can disable it
        if (g_bBackupFOVDB) SetBackupSystem(false);
    } else {
        // Steam is down, use backup system
        if (!g_bBackupFOVDB) SetBackupSystem(true);
        g_bSteamOnline = false;
        
        // Store in backup system
        g_bBackupInfiniteAmmo[client] = enabled;
        g_bBackupInfiniteAmmoTracked[client] = true;
    }
}
b GetAmmoCookie(i client) {
    c cookie[2];
    GetClientCookie(client, g_hCookieInfiniteAmmo, cookie, sizeof(cookie));

    if (strlen(cookie) == 0) return false;

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
        g_bSteamOnline = true;
        
        // If we were using backup system but Steam is now connected, we can disable it
        if (g_bBackupFOVDB) SetBackupSystem(false);
    } else {
        // Steam is down, use backup system
        if (!g_bBackupFOVDB) SetBackupSystem(true);
        g_bSteamOnline = false;
        
        // Store in backup system
        g_bBackupImmunity[client] = enabled;
        g_bBackupImmunityTracked[client] = true;
    }
}
b GetImmunityCookie(i client) {
    c cookie[2];
    GetClientCookie(client, g_hCookieImmunity, cookie, sizeof(cookie));

    if (strlen(cookie) == 0) { return false; }

    b enabled = (StringToInt(cookie) != 0);
    g_bImmunity[client] = enabled;

    // If backup system is active, update it with cookie value
    if (g_bBackupFOVDB) {
        g_bBackupImmunity[client] = enabled;
        g_bBackupImmunityTracked[client] = true;
    }

    return true;
}

// Static array version of SetInitAmmo (no ArrayList allocation)
pub v SetInitAmmoStatic( i client ) {
    // Get the active weapon
    i weapon = GetEntPropEnt( client, Prop_Send, "m_hActiveWeapon" );
    if ( weapon == -1 || !IsValidEntity( weapon ) ) return;

    // Store clip values in static array
    g_iStaticOriginalAmmo[client][0] = GetEntProp( weapon, Prop_Send, "m_iClip1" );
    g_iStaticOriginalAmmo[client][1] = GetEntProp( weapon, Prop_Send, "m_iClip2" );

    // Store reserve ammo values for all ammo types
    for ( i ammoType = 0; ammoType < 32; ammoType++ ) {
        g_iStaticOriginalAmmo[client][ammoType + 2] = GetEntProp( client, Prop_Send, "m_iAmmo", _, ammoType );
    }
    
    g_bStaticAmmoValid[client] = true;
}

// Static array version of GetInitAmmo
pub v GetInitAmmoStatic( i client ) {
    // Check if player has valid stored ammo data
    if (!g_bStaticAmmoValid[client]) return;

    // Get the active weapon
    i weapon = GetEntPropEnt( client, Prop_Send, "m_hActiveWeapon" );
    if ( weapon == -1 || !IsValidEntity( weapon ) ) return;

    // Restore clip values
    SetEntProp( weapon, Prop_Send, "m_iClip1", g_iStaticOriginalAmmo[client][0] );
    SetEntProp( weapon, Prop_Send, "m_iClip2", g_iStaticOriginalAmmo[client][1] );

    // Restore reserve ammo values
    for ( i ammoType = 0; ammoType < 32; ammoType++ ) {
        SetEntProp( client, Prop_Send, "m_iAmmo", g_iStaticOriginalAmmo[client][ammoType + 2], _, ammoType );
    }
}

// Legacy ArrayList version (kept for compatibility)
pub v SetInitAmmo( i client ) {
    // Clean up existing ArrayList if it exists
    if (g_hOriginalAmmo[client] != null) {
        delete g_hOriginalAmmo[client];
    }

    // Create new ArrayList for this player
    g_hOriginalAmmo[client] = new ArrayList();
    
    // Resize ArrayList to hold 34 elements (2 clip values + 32 ammo types)
    g_hOriginalAmmo[client].Resize(34);

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
    if ( g_bImmunity[ victim ] ) {
        i health = GetClientHealth( victim );
        g_bPendingHP[ victim ] = true;
        
        if ( health <= damage ) damage = health - 1.0;
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

    if ( g_bPendingHP[ victim ] ) {
        g_bPendingHP[ victim ] = false;
        if ( IsValidClientAlive(victim) ) SetEntityHealth( victim, TF2_GetPlayerMaxHealth(victim) );
    }
}

// ====================================================================================================
// PERFORMANCE OPTIMIZATION HELPER FUNCTIONS
// ====================================================================================================

// Build entity cache
v BuildEntityCache() {
    // Clear existing cache
    g_hCachedSpawnRooms.Clear();
    g_hCachedSpawnPoints[RED].Clear();
    g_hCachedSpawnPoints[BLU].Clear();
    g_iCachedTimerEntity = -1;
    
    // Cache team_round_timer entities
    i entity = -1;
    while ((entity = FindEntityByClassname(entity, "team_round_timer")) != -1) {
        if (IsValidEntity(entity)) {
            g_iCachedTimerEntity = entity;
            break; // Only need one timer
        }
    }
    
    // Cache func_respawnroom entities
    entity = -1;
    while ((entity = FindEntityByClassname(entity, "func_respawnroom")) != -1) {
        if (IsValidEntity(entity)) {
            g_hCachedSpawnRooms.Push(entity);
        }
    }
    
    // Cache info_player_teamspawn entities
    entity = -1;
    while ((entity = FindEntityByClassname(entity, "info_player_teamspawn")) != -1) {
        if (IsValidEntity(entity)) {
            i team = GetEntProp(entity, Prop_Send, "m_iTeamNum");
            if (team == 2) { // RED
                g_hCachedSpawnPoints[RED].Push(entity);
            } elif (team == 3) { // BLU
                g_hCachedSpawnPoints[BLU].Push(entity);
            }
        }
    }
    
    PrintToServer("[PTE] Entity cache built: %d spawn rooms, %d RED spawns, %d BLU spawns, timer: %d", 
                  g_hCachedSpawnRooms.Length, g_hCachedSpawnPoints[RED].Length, g_hCachedSpawnPoints[BLU].Length, g_iCachedTimerEntity);
}

// Validate entity cache
v ValidateEntityCache() {
    b needsRebuild = false;
    
    // Check if timer entity is still valid
    if (g_iCachedTimerEntity != -1 && !IsValidEntity(g_iCachedTimerEntity)) {
        needsRebuild = true;
    }
    
    // Check spawn rooms
    for (i idx = 0; idx < g_hCachedSpawnRooms.Length; idx++) {
        if (!IsValidEntity(g_hCachedSpawnRooms.Get(idx))) {
            needsRebuild = true;
            break;
        }
    }
    
    // Check spawn points
    if (!needsRebuild) {
        for (i team = 0; team < 2; team++) {
            for (i idx = 0; idx < g_hCachedSpawnPoints[team].Length; idx++) {
                if (!IsValidEntity(g_hCachedSpawnPoints[team].Get(idx))) {
                    needsRebuild = true;
                    break;
                }
            }
            if (needsRebuild) break;
        }
    }
    
    if (needsRebuild) {
        PrintToServer("[PTE] Entity cache invalidated, rebuilding...");
        BuildEntityCache();
    }
}

v ApplyDemoResistance(i client) {
    if (!IsValidClient(client)) return;
    
    TFClassType playerClass = TF2_GetPlayerClass(client);
    f desiredValue = 0.0;
    b shouldApply = false;
    
    // Determine desired resistance value based on settings and class
    if (playerClass == TFClass_DemoMan) {
        if (!g_bDemoResistEnabled) {
            // Demo resistance disabled = apply vulnerability (1.25 = 25% more damage)
            desiredValue = 1.25;
            shouldApply = true;
        } else {
            // Demo resistance enabled = remove attribute (let shield work normally)
            shouldApply = false;
        }
    }
    
    // Only update if the value has changed (performance optimization)
    if (shouldApply) {
        if (!g_bDemoResistApplied[client] || g_fCurrentDemoResistValue[client] != desiredValue) {
            TF2Attrib_SetByName(client, "dmg taken from blast reduced", desiredValue);
            g_fCurrentDemoResistValue[client] = desiredValue;
            g_bDemoResistApplied[client] = true;
        }
    } else {
        if (g_bDemoResistApplied[client]) {
            TF2Attrib_RemoveByName(client, "dmg taken from blast reduced");
            g_fCurrentDemoResistValue[client] = 0.0;
            g_bDemoResistApplied[client] = false;
        }
    }
}

pub v OnMapStart() {
    // Rebuild entity cache when map changes
    CreateTimer(1.0, Timer_DelayedCacheBuild, 0, TIMER_FLAG_NO_MAPCHANGE);
}

// Delayed cache build timer
pub Act Timer_DelayedCacheBuild(Handle timer) {
    BuildEntityCache();
    return Plugin_Stop;
}