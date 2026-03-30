#pragma semicolon 1


#include <amxmodx>
#include <hamsandwich>


#define PLUGIN_NAME	"RageQuit"
#define PLUGIN_VERSION	"2.1"
#define PLUGIN_AUTHOR	"raggy"


#define RAGEQUIT 5.0 // Max amount of elapsed time between death and disconnect. FLOAT
#define RAGESPAM 2.0 // Min amount of elapsed time between ragequit sound announcement. FLOAT


#define MAX_PLAYERS 32 + 1

new Float:g_fDiedAt[MAX_PLAYERS];
new bool:g_bHasRQ[MAX_PLAYERS];


new g_sRageQuit[] = "rayish/ragequit.wav"; // Path to ragequit sound, ie. cstrike/sound/ + g_sRageQuit
#define LEN_SOUND (sizeof g_sRageQuit + 6) // Needs +6 to fit spk "g_sRageQuit"
new Float:g_fAnnounced; // Spam


new g_iSayText;
#define COLOR 0x03 // 0x01 normal, 0x04 green, 0x03 other. CHAR


public plugin_init()
{
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
	register_cvar(PLUGIN_NAME, PLUGIN_VERSION, FCVAR_SERVER|FCVAR_SPONLY);
	
	
	// Message
	g_iSayText = get_user_msgid("SayText");
	
	
	// Forward
	RegisterHam(Ham_Killed, "player", "fwdHamKilled", 1);
	
	
	// Cmd
	new sFunction[] = "cmdRQ";
	
	register_clcmd("say /ragequit", sFunction);
	register_clcmd("say /rq", sFunction);
}

public plugin_precache()
{
    precache_sound(g_sRageQuit);
}

public client_connect(id)
{
	g_fDiedAt[id]	= 0.0;
	g_bHasRQ[id]	= true; // Sets the default state of the ragequit announcer for the player
}

public client_disconnected(id)
{
	if ( is_user_hltv(id) || is_user_bot(id) )
		return;
	
	
	// Check
	new Float:fGameTime = get_gametime();
	
	if ( (fGameTime - g_fDiedAt[id]) > RAGEQUIT )
		return;
	
	
	// Message
	new szName[32];
	get_user_name(id, szName, charsmax(szName));
	
	if ( !szName[0] ) // get_user_name() sometimes return empty in client_disconnect. Caching the name for this plugin is just unnecessary.
		return;
	
	new szMessage[192];
	formatex(szMessage, charsmax(szMessage), "%c*^x04 %s^x03 RAGEQUIT!", COLOR, szName);
	
	
	// Sound
	new szSound[LEN_SOUND];
	
	if ( (fGameTime - g_fAnnounced) >= RAGESPAM ) // Spam
	{
		formatex(szSound, charsmax(szSound), "spk ^"%s^"", g_sRageQuit);
	}
	
	
	// Play
	new i, aPlayers[MAX_PLAYERS - 1], iPlayerCount, playerId;
	get_players(aPlayers, iPlayerCount, "ch");
	
	if ( !iPlayerCount )
		return;
	
	for ( ; i < iPlayerCount; i++ )
	{
		playerId = aPlayers[i];
		
		if ( id == playerId || !g_bHasRQ[playerId] )
			continue;
		
		if ( szSound[0] )
			client_cmd(playerId, szSound);
		
		message_begin(MSG_ONE_UNRELIABLE, g_iSayText, _, playerId);
		write_byte(id);
		write_string(szMessage);
		message_end();
	}
	
	if ( szSound[0] )
		g_fAnnounced = fGameTime; // Spam
}

public fwdHamKilled(iVictim, iAttacker, bShouldGib)
{
	g_fDiedAt[iVictim] = get_gametime();
	
	return HAM_IGNORED;
}

public cmdRQ(id)
{
	g_bHasRQ[id] = !g_bHasRQ[id];
	client_print(id, print_chat, "RageQuit announcer %s. To %s, type /ragequit.", (g_bHasRQ[id] ? "enabled" : "disabled"), (g_bHasRQ[id] ? "disable" : "enable"));
}