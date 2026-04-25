#include <amxmodx>
#include <reapi>
#include <hns_matchsystem>

#define PLUGIN_NAME        "HNS Match XP Rewards"
#define PLUGIN_VERSION     "0.8 Fixed"
#define PLUGIN_AUTHOR      "cultura"

native hns_xp_add_xp(id, amount);
native hns_xp_get_level(id);

#define MAXP 32
#define XP_EVENTS_MAX 10

// =====================
// CVARS
// =====================
new g_pHudEnable;
new g_pSoundsEnable;

new g_pRunThreshold;
new g_pRunInterval;

// DM
new g_pDmKillXP;
new g_pDmDeathXP;

// PUB
new g_pPubKillCT;
new g_pPubDeathKill;
new g_pPubDeathT;
new g_pPubSuicide;
new g_pPubRoundWinXP;
new g_pPubClutch1vX;
new g_pPubMulti2;
new g_pPubMulti3;
new g_pPubMulti4plus;
new g_pPubRunTT;

// ZM
new g_pZmKillCT;
new g_pZmDeathKill;
new g_pZmDeathT;
new g_pZmSuicide;
new g_pZmRoundWinXP;
new g_pZmClutch1vX;
new g_pZmMulti2;
new g_pZmMulti3;
new g_pZmMulti4plus;
new g_pZmRunTT;

// =====================
// STATE
// =====================
new bool:g_bLive;                  // LIVE фаза для PUB/ZM (после freezeend)
new g_iRoundKills[MAXP + 1];

// run distance
new bool:g_bHasLastOrigin[MAXP + 1];
new Float:g_fLastOrigin[MAXP + 1][3];
new Float:g_fRunDist[MAXP + 1];

// HUD events ring buffer
new g_iEvtHead[MAXP + 1];
new g_iEvtTail[MAXP + 1];
new g_iEvtCount[MAXP + 1];
new g_iEvtAmount[MAXP + 1][XP_EVENTS_MAX];
new Float:g_fEvtTime[MAXP + 1][XP_EVENTS_MAX];
new g_szEvtReason[MAXP + 1][XP_EVENTS_MAX][48];

new g_iLastLevel[MAXP + 1];
new g_iHudSync;

// spawn random sound once per round
new bool:g_bSpawnSoundPlayed[MAXP + 1];

// =====================
// SOUNDS
// =====================
new const SND_XP_GAIN[] = "subcultura/launch_upmenu1.wav";

new const SND_LEVELUP[][] = {
    "subcultura/unlocked.wav",
    "subcultura/howinteresting.wav",
    "subcultura/completelywrong.wav",
    "subcultura/c1a0_sci_crit2a.wav",
    "subcultura/somethingmoves.wav"
};

new const SND_SPAWN[][] = {
    "subcultura/youhearthat.wav",
    "subcultura/gman_wise.wav",
    "subcultura/c1a0_sci_crit3a.wav",
    "subcultura/okgetout.wav"
};

new const SND_ROUND_WIN[][] = {
    "subcultura/gman_nowork.wav",
    "subcultura/areyouthink.wav",
    "subcultura/c1a0_sci_crit2a.wav",
    "subcultura/okgetout.wav",
    "subcultura/sorryimleaving.wav",
    "subcultura/tr_sci_goodwork.wav"
};

new const SND_ROUND_LOSE[][] = {
    "subcultura/startle9.wav",
    "subcultura/stench.wav",
    "subcultura/whatnext.wav",
    "subcultura/whatyoudoing.wav"
};

const Float:XP_EVENT_DISPLAY_TIME = 4.0;

// =====================
// HELPERS
// =====================
stock bool:IsValidRealPlayer(id)
{
    return (1 <= id <= MaxClients && is_user_connected(id) && !is_user_bot(id) && !is_user_hltv(id));
}

stock bool:IsModePubOrZm(mode)
{
    return (mode == MODE_PUB || mode == MODE_ZM);
}

// LIVE gating: в DM можно давать всегда, в PUB/ZM — только когда g_bLive=true
stock bool:CanGiveXpNow(mode)
{
    if (mode == MODE_DM) return true;
    if (IsModePubOrZm(mode)) return g_bLive;
    return false;
}

// =====================
// PRECACHE
// =====================
public plugin_precache()
{
    precache_sound(SND_XP_GAIN);

    for (new i; i < sizeof(SND_LEVELUP); i++)  precache_sound(SND_LEVELUP[i]);
    for (new i; i < sizeof(SND_SPAWN); i++)    precache_sound(SND_SPAWN[i]);
    for (new i; i < sizeof(SND_ROUND_WIN); i++)precache_sound(SND_ROUND_WIN[i]);
    for (new i; i < sizeof(SND_ROUND_LOSE); i++)precache_sound(SND_ROUND_LOSE[i]);
}

// =====================
// INIT
// =====================
public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    g_pHudEnable    = register_cvar("hns_xp_hud", "1");
    g_pSoundsEnable = register_cvar("hns_xp_sounds", "1");

    g_pRunThreshold = register_cvar("hns_xp_run_threshold", "500000"); // units
    g_pRunInterval  = register_cvar("hns_xp_run_interval", "0.10");    // seconds

    // DM
    g_pDmKillXP   = register_cvar("hns_xp_dm_kill", "5");
    g_pDmDeathXP  = register_cvar("hns_xp_dm_death", "3");

    // PUB
    g_pPubKillCT      = register_cvar("hns_xp_pub_kill_ct", "6");
    g_pPubDeathKill   = register_cvar("hns_xp_pub_death_kill", "2");
    g_pPubDeathT      = register_cvar("hns_xp_pub_death_t", "2");
    g_pPubSuicide     = register_cvar("hns_xp_pub_suicide", "5");
    g_pPubRoundWinXP  = register_cvar("hns_xp_pub_roundwin", "4");
    g_pPubClutch1vX   = register_cvar("hns_xp_pub_clutch1vx", "6");
    g_pPubMulti2      = register_cvar("hns_xp_pub_multikill2", "2");
    g_pPubMulti3      = register_cvar("hns_xp_pub_multikill3", "3");
    g_pPubMulti4plus  = register_cvar("hns_xp_pub_multikill4plus", "1");
    g_pPubRunTT       = register_cvar("hns_xp_pub_run_t", "3");

    // ZM
    g_pZmKillCT       = register_cvar("hns_xp_zm_kill_ct", "10");
    g_pZmDeathKill    = register_cvar("hns_xp_zm_death_kill", "3");
    g_pZmDeathT       = register_cvar("hns_xp_zm_death_t", "2");
    g_pZmSuicide      = register_cvar("hns_xp_zm_suicide", "5");
    g_pZmRoundWinXP   = register_cvar("hns_xp_zm_roundwin", "5");
    g_pZmClutch1vX    = register_cvar("hns_xp_zm_clutch1vx", "7");
    g_pZmMulti2       = register_cvar("hns_xp_zm_multikill2", "2");
    g_pZmMulti3       = register_cvar("hns_xp_zm_multikill3", "3");
    g_pZmMulti4plus   = register_cvar("hns_xp_zm_multikill4plus", "1");
    g_pZmRunTT        = register_cvar("hns_xp_zm_run_t", "4");

    g_iHudSync = CreateHudSyncObj();

    RegisterHookChain(RG_CBasePlayer_Killed,       "OnPlayerKilled_Post", true);
    RegisterHookChain(RG_RoundEnd,                 "OnRoundEnd_Post", true);
    RegisterHookChain(RG_CSGameRules_RestartRound, "OnRestartRound_Post", true);
    RegisterHookChain(RG_CBasePlayer_Spawn,        "OnPlayerSpawn_Post", true);

    g_bLive = false;

    // tasks
    set_task(get_pcvar_float(g_pRunInterval), "Task_CheckRunDistance", _, _, _, "b");
    set_task(0.50, "Task_UpdateXpHUD", _, _, _, "b");

    for (new i = 1; i <= MaxClients; i++)
        ResetPlayerState(i);
}

// =====================
// HNS FORWARDS (LIVE gating)
// =====================
public hns_round_start()
{
    g_bLive = false;
    for (new id = 1; id <= MaxClients; id++)
    {
        g_iRoundKills[id] = 0;
        g_bHasLastOrigin[id] = false;
        g_fRunDist[id] = 0.0;
        g_bSpawnSoundPlayed[id] = false;
    }
}

public hns_round_freezeend()
{
    g_bLive = true;
}

public hns_round_end()
{
    g_bLive = false;
}

// =====================
// PLAYER STATE
// =====================
stock ResetPlayerState(id)
{
    g_iRoundKills[id] = 0;

    g_bHasLastOrigin[id] = false;
    g_fRunDist[id] = 0.0;

    g_iEvtHead[id] = 0;
    g_iEvtTail[id] = 0;
    g_iEvtCount[id] = 0;

    g_iLastLevel[id] = 0;
    g_bSpawnSoundPlayed[id] = false;
}

public client_putinserver(id)
{
    ResetPlayerState(id);
    if (is_user_connected(id))
        g_iLastLevel[id] = hns_xp_get_level(id);
}

public client_disconnected(id)
{
    ResetPlayerState(id);
}

public OnRestartRound_Post()
{
    // на рестарте раунда возвращаемся к freeze-фазе
    g_bLive = false;

    for (new id = 1; id <= MaxClients; id++)
    {
        if (!is_user_connected(id)) continue;
        g_iRoundKills[id] = 0;
        g_bHasLastOrigin[id] = false;
        g_fRunDist[id] = 0.0;
        g_bSpawnSoundPlayed[id] = false;
    }
}

// =====================
// SPAWN (random sound)
// =====================
public OnPlayerSpawn_Post(id)
{
    if (!IsValidRealPlayer(id) || !is_user_alive(id))
        return HC_CONTINUE;

    // только если включены звуки
    if (get_pcvar_num(g_pSoundsEnable) && !g_bSpawnSoundPlayed[id] && random(100) < 20)
    {
        new idx = random(sizeof(SND_SPAWN));
        emit_sound(id, CHAN_VOICE, SND_SPAWN[idx], 1.0, ATTN_NORM, 0, PITCH_NORM);
        g_bSpawnSoundPlayed[id] = true;
    }

    return HC_CONTINUE;
}

// =====================
// XP EVENTS (ring buffer)
// =====================
stock PushXpEvent(id, amount, const reason[])
{
    if (!is_user_connected(id)) return;

    // записываем в head
    new h = g_iEvtHead[id];
    g_iEvtAmount[id][h] = amount;
    g_fEvtTime[id][h]   = get_gametime();
    copy(g_szEvtReason[id][h], charsmax(g_szEvtReason[][]), reason);

    // двигаем head
    g_iEvtHead[id] = (h + 1) % XP_EVENTS_MAX;

    // если переполнили — сдвигаем tail
    if (g_iEvtCount[id] < XP_EVENTS_MAX)
        g_iEvtCount[id]++;
    else
        g_iEvtTail[id] = (g_iEvtTail[id] + 1) % XP_EVENTS_MAX;

    // звук
    if (get_pcvar_num(g_pSoundsEnable))
        emit_sound(id, CHAN_VOICE, SND_XP_GAIN, 1.0, ATTN_NORM, 0, PITCH_NORM);
}

stock PlayLevelUp(id)
{
    if (!get_pcvar_num(g_pSoundsEnable)) return;
    new idx = random(sizeof(SND_LEVELUP));
    emit_sound(id, CHAN_VOICE, SND_LEVELUP[idx], 1.0, ATTN_NORM, 0, PITCH_NORM);
}

// =====================
// KILL XP
// =====================
public OnPlayerKilled_Post(const victim, const attacker, const shouldgib)
{
    if (!is_user_connected(victim))
        return HC_CONTINUE;

    new mode = hns_get_mode();
    if (!CanGiveXpNow(mode))
        return HC_CONTINUE;

    if (mode == MODE_DM)
    {
        HandleKillDM(victim, attacker);
    }
    else if (mode == MODE_PUB || mode == MODE_ZM)
    {
        HandleKillPubZm(victim, attacker, mode);
    }

    return HC_CONTINUE;
}

stock HandleKillDM(const victim, const attacker)
{
    if (IsValidRealPlayer(attacker) && attacker != victim)
    {
        new xp = get_pcvar_num(g_pDmKillXP);
        hns_xp_add_xp(attacker, xp);
        PushXpEvent(attacker, xp, "Kill");
    }

    if (IsValidRealPlayer(victim))
    {
        new xp = get_pcvar_num(g_pDmDeathXP);
        hns_xp_add_xp(victim, -xp);
        PushXpEvent(victim, -xp, "Death");
    }
}

stock HandleKillPubZm(const victim, const attacker, const mode)
{
    new TeamName:tVictim   = TeamName:rg_get_user_team(victim);
    new TeamName:tAttacker = TeamName:rg_get_user_team(attacker);

    new bool:bValidAttacker = (IsValidRealPlayer(attacker) && attacker != victim);

    if (bValidAttacker)
    {
        // CT убил T
        if (tAttacker == TEAM_CT && tVictim == TEAM_TERRORIST)
        {
            new xp = (mode == MODE_PUB) ? get_pcvar_num(g_pPubKillCT) : get_pcvar_num(g_pZmKillCT);
            hns_xp_add_xp(attacker, xp);
            PushXpEvent(attacker, xp, "Kill");
        }

        // мультики только для CT (как у тебя)
        if (tAttacker == TEAM_CT)
        {
            g_iRoundKills[attacker]++;

            new xp;
            if (g_iRoundKills[attacker] == 2)
            {
                xp = (mode == MODE_PUB) ? get_pcvar_num(g_pPubMulti2) : get_pcvar_num(g_pZmMulti2);
                hns_xp_add_xp(attacker, xp);
                PushXpEvent(attacker, xp, "Double Kill");
            }
            else if (g_iRoundKills[attacker] == 3)
            {
                xp = (mode == MODE_PUB) ? get_pcvar_num(g_pPubMulti3) : get_pcvar_num(g_pZmMulti3);
                hns_xp_add_xp(attacker, xp);
                PushXpEvent(attacker, xp, "Triple Kill");
            }
            else if (g_iRoundKills[attacker] >= 4)
            {
                xp = (mode == MODE_PUB) ? get_pcvar_num(g_pPubMulti4plus) : get_pcvar_num(g_pZmMulti4plus);
                hns_xp_add_xp(attacker, xp);
                PushXpEvent(attacker, xp, "Quadra+ Kill");
            }
        }

        // смерть жертвы (минус XP) — только real players
        if (IsValidRealPlayer(victim))
        {
            new xp = (mode == MODE_PUB) ? get_pcvar_num(g_pPubDeathKill) : get_pcvar_num(g_pZmDeathKill);
            hns_xp_add_xp(victim, -xp);
            PushXpEvent(victim, -xp, "Death");
        }
    }
    else
    {
        // suicide / странная смерть
        if (IsValidRealPlayer(victim))
        {
            new bool:bSuicide = (attacker == victim || attacker == 0);
            new xp = bSuicide
                ? ((mode == MODE_PUB) ? get_pcvar_num(g_pPubSuicide) : get_pcvar_num(g_pZmSuicide))
                : ((mode == MODE_PUB) ? get_pcvar_num(g_pPubDeathT) : get_pcvar_num(g_pZmDeathT));

            hns_xp_add_xp(victim, -xp);
            PushXpEvent(victim, -xp, bSuicide ? "Suicide" : "Death");
        }
    }
}

// =====================
// ROUND END XP + SOUNDS
// =====================
public OnRoundEnd_Post(WinStatus:iWinStatus, ScenarioEventEndRound:iEvent, Float:fDelay)
{
    new mode = hns_get_mode();
    if (!IsModePubOrZm(mode))
        return HC_CONTINUE;

    // если раунд не был live — не начисляем
    // (часто при рестартах/свичах это спасает от мусора)
    if (!g_bLive)
        return HC_CONTINUE;

    new players[32], num;
    get_players(players, num, "ch");

    for (new i; i < num; i++)
    {
        new id = players[i];
        if (!IsValidRealPlayer(id)) continue;

        new TeamName:team = TeamName:rg_get_user_team(id);
        if (team != TEAM_CT && team != TEAM_TERRORIST) continue;

        new bool:bWon = false;
        // WinStatus: 1 CTs, 2 Ts (как у тебя по смыслу)
        if ((iWinStatus == WINSTATUS_CTS && team == TEAM_CT) ||
            (iWinStatus == WINSTATUS_TERRORISTS && team == TEAM_TERRORIST))
        {
            bWon = true;
        }

        if (bWon)
        {
            // бонус за победу раунда — только если жив
            if (is_user_alive(id))
            {
                new xp = (mode == MODE_PUB) ? get_pcvar_num(g_pPubRoundWinXP) : get_pcvar_num(g_pZmRoundWinXP);
                hns_xp_add_xp(id, xp);
                PushXpEvent(id, xp, "Round Win");
            }

            // clutch 1vX — только CT (как было)
            if (team == TEAM_CT && is_user_alive(id) && g_iRoundKills[id] >= 1)
            {
                new aliveCT = 0;
                for (new j; j < num; j++)
                {
                    new p = players[j];
                    if (is_user_connected(p) && rg_get_user_team(p) == TEAM_CT && is_user_alive(p))
                        aliveCT++;
                }

                if (aliveCT == 1)
                {
                    new xp = (mode == MODE_PUB) ? get_pcvar_num(g_pPubClutch1vX) : get_pcvar_num(g_pZmClutch1vX);
                    hns_xp_add_xp(id, xp);
                    PushXpEvent(id, xp, "Clutch 1vX");
                }
            }

            // win sound
            if (get_pcvar_num(g_pSoundsEnable))
            {
                new idx = random(sizeof(SND_ROUND_WIN));
                emit_sound(id, CHAN_VOICE, SND_ROUND_WIN[idx], 1.0, ATTN_NORM, 0, PITCH_NORM);
            }
        }
        else
        {
            if (get_pcvar_num(g_pSoundsEnable))
            {
                new idx = random(sizeof(SND_ROUND_LOSE));
                emit_sound(id, CHAN_VOICE, SND_ROUND_LOSE[idx], 1.0, ATTN_NORM, 0, PITCH_NORM);
            }
        }
    }

    return HC_CONTINUE;
}

// =====================
// RUN DISTANCE (T only, alive)
// =====================
public Task_CheckRunDistance()
{
    new mode = hns_get_mode();
    if (!IsModePubOrZm(mode)) return;
    if (!g_bLive) return;

    new Float:threshold = float(get_pcvar_num(g_pRunThreshold));
    if (threshold < 1000.0) threshold = 1000.0;

    new players[32], num;
    get_players(players, num, "ah"); // alive + human

    for (new i; i < num; i++)
    {
        new id = players[i];
        if (rg_get_user_team(id) != TEAM_TERRORIST)
            continue;

        new Float:origin[3];
        get_entvar(id, var_origin, origin);

        if (!g_bHasLastOrigin[id])
        {
            g_fLastOrigin[id][0] = origin[0];
            g_fLastOrigin[id][1] = origin[1];
            g_fLastOrigin[id][2] = origin[2];
            g_bHasLastOrigin[id] = true;
            continue;
        }

        new Float:dx = origin[0] - g_fLastOrigin[id][0];
        new Float:dy = origin[1] - g_fLastOrigin[id][1];
        new Float:dz = origin[2] - g_fLastOrigin[id][2];

        new Float:dist = floatsqroot(dx*dx + dy*dy + dz*dz);
        g_fRunDist[id] += dist;

        g_fLastOrigin[id][0] = origin[0];
        g_fLastOrigin[id][1] = origin[1];
        g_fLastOrigin[id][2] = origin[2];

        if (g_fRunDist[id] >= threshold)
        {
            new xp = (mode == MODE_PUB) ? get_pcvar_num(g_pPubRunTT) : get_pcvar_num(g_pZmRunTT);
            hns_xp_add_xp(id, xp);
            PushXpEvent(id, xp, "Runner Bonus");
            g_fRunDist[id] = 0.0;
        }
    }
}

// =====================
// HUD (events + level up)
// =====================
public Task_UpdateXpHUD()
{
    if (!get_pcvar_num(g_pHudEnable))
        return;

    new players[32], num;
    get_players(players, num, "ch");

    new Float:now = get_gametime();

    for (new i; i < num; i++)
    {
        new id = players[i];
        if (!is_user_connected(id)) continue;

        // level up detect
        new lvl = hns_xp_get_level(id);
        if (lvl > g_iLastLevel[id])
        {
            PushXpEvent(id, 0, "LEVEL UP!");
            PlayLevelUp(id);
            g_iLastLevel[id] = lvl;
        }

        // чистим старые события с tail
        while (g_iEvtCount[id] > 0)
        {
            new t = g_iEvtTail[id];
            if (now - g_fEvtTime[id][t] <= XP_EVENT_DISPLAY_TIME)
                break;

            g_iEvtTail[id] = (t + 1) % XP_EVENTS_MAX;
            g_iEvtCount[id]--;
        }

        if (g_iEvtCount[id] <= 0)
            continue;

        // собираем текст от tail -> count
        new szText[512], len = 0;

        new idx = g_iEvtTail[id];
        for (new k = 0; k < g_iEvtCount[id]; k++)
        {
            new amount = g_iEvtAmount[id][idx];

            if (amount > 0)
                len += formatex(szText[len], charsmax(szText) - len, "+%d XP - %s^n", amount, g_szEvtReason[id][idx]);
            else if (amount < 0)
                len += formatex(szText[len], charsmax(szText) - len, "%d XP - %s^n", amount, g_szEvtReason[id][idx]);
            else
                len += formatex(szText[len], charsmax(szText) - len, "%s^n", g_szEvtReason[id][idx]);

            idx = (idx + 1) % XP_EVENTS_MAX;
            if (len >= charsmax(szText) - 64) break;
        }

        set_hudmessage(0, 200, 100, -1.0, 0.75, 2, 0.10, 0.60, 0.0, 0.0, -1);
        ShowSyncHudMsg(id, g_iHudSync, "%s", szText);
    }
}
