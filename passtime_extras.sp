#include <sdktools_functions>
#include <sourcemod>
#include <tf2>
#include <tf2_stocks>
#include <clientprefs>

#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo =
{
    name        = "passtime.tf extras",
    author      = "xCape",
    description = "Add a setteam command for setting the player team",
    version     = "1.0.0",
    url         = "https://github.com/allvei" 
}

Handle g_hCookieFOV;
Handle g_hCvarFOVMin;
Handle g_hCvarFOVMax;

public void OnPluginStart() {
    RegAdminCmd( "sm_setteam", Command_SetTeam, ADMFLAG_GENERIC, "Set a client's team" );
    RegConsoleCmd( "sm_fov",   Command_SetFOV,  "Set your field of view." );

    g_hCookieFOV  = RegClientCookie( "sm_fov_cookie", "Desired client field of view", CookieAccess_Private );
    g_hCvarFOVMin = CreateConVar( "sm_fov_min", "20", "Minimum client field of view", _, 1, 1.0, 1, 175.0 );
    g_hCvarFOVMax = CreateConVar( "sm_fov_max", "130", "Maximum client field of view", _, 1, 1.0, 1, 175.0 );

    HookEvent( "player_spawn", Event_PlayerSpawn );
}

// Change client's team
public Action Command_SetTeam( int client, int args ) {
    char input_team[ 5 ];
    GetCmdArg( 2, input_team, sizeof( input_team ) );
    TFTeam team = ParseTeam( input_team );

    if ( args != 2 ) {
        return UsageError( client, "Usage: sm_setteam <#userid|name> <spec|red|blue>", args );
    }

    char arg_playerTarget[ 33 ];
    GetCmdArg( 1, arg_playerTarget, sizeof( arg_playerTarget ) );

    if ( team == TFTeam_Unassigned ) {
        return UsageError( client, "Setting the unassigned team is not allowed.", args );
    }

    int  target_list[ MAXPLAYERS ];
    char target_name[ MAX_TARGET_LENGTH ];

    // Get client(s)
    bool tn_is_ml     = false;
    int  target_count = ProcessTargetString( arg_playerTarget, client, target_list, MAXPLAYERS, COMMAND_FILTER_CONNECTED, target_name, sizeof( target_name ), tn_is_ml );

    // Change team of client(s)
    for ( int i; i < target_count; i++ ) {
        int targetId = target_list[ i ];
        ForcePlayerSuicide( targetId );
        TF2_ChangeClientTeam( targetId, team );
        TF2_RespawnPlayer( targetId );
    }

    char team_name[ 5 ];
    GetTeamName( view_as<int>( team ), team_name, sizeof( team_name ) );

    ReplyToCommand( client, "Switched %s to %s", target_name, team_name );
    return Plugin_Handled;
}

// Parse TFTeam from string
TFTeam ParseTeam( char[] team ) {
    return StrEqual( team, "spec" ) ? TFTeam_Spectator
         : StrEqual( team, "red" )  ? TFTeam_Red
         : StrEqual( team, "blu" )  ? TFTeam_Blue
         : TFTeam_Unassigned;
}

// Retrieves the client's FOV from the cookie and applies it, returns false if invalid
bool RestoreFOV( int client ) {
    char cookie[ 4 ];
    GetClientCookie( client, g_hCookieFOV, cookie, sizeof( cookie ) );
    int fov = StringToInt( cookie ),
        min = GetConVarInt( g_hCvarFOVMin ),
        max = GetConVarInt( g_hCvarFOVMax );
    if ( fov < min || fov > max ) return 0;
    SetFOV( client, fov );
    return 1;
}

// Sets the client's FOV
void SetFOV( int client, int fov ) {
    SetEntProp( client, Prop_Send, "m_iFOV", fov );
    SetEntProp( client, Prop_Send, "m_iDefaultFOV", fov );
}

// Restores the client's FOV on spawn
public void Event_PlayerSpawn( Event event, const char[] name, bool dontBroadcast ) {
    int client = GetClientOfUserId( event.GetInt( "userid" ) );
    if ( !AreClientCookiesCached( client ) || !RestoreFOV( client ) ) return;
}

// Restores the client's FOV when they are teleported
public void TF2_OnConditionAdded( int client, TFCond cond ) {
    if ( cond != TFCond_TeleportedGlow || !RestoreFOV( client ) ) return;
}

// Restores the client's FOV when they unzoom
public void TF2_OnConditionRemoved( int client, TFCond cond ) {
    if ( cond != TFCond_Zoomed || !RestoreFOV( client ) ) return;
}

// Retrieves the client's FOV from their local config and stores it in a cookie
public void OnFOVQueried( QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] fov ) {
    if ( result != ConVarQuery_Okay ) return;
    SetClientCookie( client, g_hCookieFOV, "" );
    SetFOV( client, StringToInt( fov ) );
}

public Action Command_SetFOV( int client, int args ) {
    if ( !AreClientCookiesCached( client ) ) {
        return UsageError( client, "\x04[SM] \x01Unable to load FOV data." );
    }
    if ( args != 1 ) {
        return UsageError( client, "Usage: sm_fov <fov>" );
    }
    int fov = GetCmdArgInt( 1 ),
        min = GetConVarInt( g_hCvarFOVMin ),
        max = GetConVarInt( g_hCvarFOVMax );
    if ( fov == 0 ) {
        QueryClientConVar( client, "fov_desired", OnFOVQueried );
        return UsageError( client, "\x04[SM] \x01Your FOV has been reset." );
    }
    if ( fov < min ) {
        return UsageError( client, "\x04[SM] \x01The minimum FOV you can set is %d.", min );
    }
    if ( fov > max ) {
        return UsageError( client, "\x04[SM] \x01The maximum FOV you can set is %d.", max );
    }
    char cookie[ 4 ];
    IntToString( fov, cookie, sizeof( cookie ) );
    SetClientCookie( client, g_hCookieFOV, cookie );
    SetFOV( client, fov );
    ReplyToCommand( client, "\x04[SM] \x01Your FOV has been set to %d.", fov );
    return Plugin_Handled;
}

public Action UsageError( int client, const char[] format, any ... ) {
    char buffer[ 254 ];
    VFormat( buffer, sizeof( buffer ), format, 3 );
    ReplyToCommand( client, "%s", buffer );
    return Plugin_Handled;
}