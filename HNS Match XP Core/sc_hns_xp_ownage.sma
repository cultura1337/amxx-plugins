#include <amxmodx>
#include <engine>
#include <cstrike>
#include <fakemeta>

#include <hns_xp_core>
#include <hns_xp_skills>
#include <hns_matchsystem>

#define PLUGIN  "HNS XP Skill: OWNAGE"
#define VERSION "6.0"
#define AUTHOR  "cultura"

// ================= НАСТРОЙКИ =================

#define OWN_XP_BASE        5
#define OWN_COOLDOWN      3.0
#define OWN_MIN_SPEED     80.0
#define OWN_MAX_PER_ROUND 5

#define OWNAGE_MIN_LEVEL  5   // XP уровень для открытия скилла

new const SOUND_OWN[] = "misc/own.wav";

// ================= OWNAGE LEVELS =================

new const g_iOwnageNeed[] = { 0, 5, 15, 35, 70, 120 };

// ================= ДАННЫЕ =================

new g_iSkillOwnage;

new Float:g_flLastOwn[33];
new g_iOwnRound[33];
new g_iLastVictim[33];

new g_iOwnageTotal[33];
new g_iOwnageLevel[33];

// ================= INIT =================

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    g_iSkillOwnage = hns_skills_register(
        "Ownage",
        OWNAGE_MIN_LEVEL,
        SKILL_MODE_DM | SKILL_MODE_PUB | SKILL_MODE_ZM
    );

    register_forward(FM_PlayerPreThink, "fw_PlayerPreThink");
    register_logevent("OnRoundStart", 2, "1=Round_Start");
}

public plugin_precache()
{
    precache_sound(SOUND_OWN);
}

public OnRoundStart()
{
    for (new i = 1; i <= 32; i++)
    {
        g_iOwnRound[i] = 0;
        g_iLastVictim[i] = 0;
    }
}

// ================= CORE =================

public fw_PlayerPreThink(id)
{
    if (!is_user_alive(id))
        return FMRES_IGNORED;

    if (!hns_skills_is_enabled(id, g_iSkillOwnage))
        return FMRES_IGNORED;

    if (cs_get_user_team(id) != CS_TEAM_T)
        return FMRES_IGNORED;

    if (!(pev(id, pev_flags) & FL_ONGROUND))
        return FMRES_IGNORED;

    new victim = pev(id, pev_groundentity);
    if (victim < 1 || victim > 32)
        return FMRES_IGNORED;

    if (!is_user_alive(victim))
        return FMRES_IGNORED;

    if (cs_get_user_team(victim) != CS_TEAM_CT)
        return FMRES_IGNORED;

    if (get_player_speed(victim) < OWN_MIN_SPEED)
        return FMRES_IGNORED;

    new Float:time = get_gametime();

    if (time - g_flLastOwn[id] < OWN_COOLDOWN)
        return FMRES_IGNORED;

    if (g_iOwnRound[id] >= OWN_MAX_PER_ROUND)
        return FMRES_IGNORED;

    if (g_iLastVictim[id] == victim)
        return FMRES_IGNORED;

    // ===== OWN =====

    g_flLastOwn[id] = time;
    g_iOwnRound[id]++;
    g_iLastVictim[id] = victim;

    g_iOwnageTotal[id]++;
    UpdateOwnageLevel(id);

    new online = get_playersnum();
    new xp = OWN_XP_BASE
           + g_iOwnageLevel[id]
           + clamp_int(online / 4, 1, 5);

    if (hns_get_mode() == MODE_DM)
        xp = floatround(float(xp) * 0.4);

    hns_xp_add_xp(id, xp);

    // ===== DHUD =====

    set_dhudmessage(0, 200, 100, -1.0, 0.60, 0, 0.0, 1.6, 0.1, 0.1);
    show_dhudmessage(id,
        "OWN! +%d XP^nOwnage Level: %d",
        xp, g_iOwnageLevel[id]);

    set_dhudmessage(200, 50, 50, -1.0, 0.65, 0, 0.0, 1.2, 0.1, 0.1);
    show_dhudmessage(victim,
        "YOU GOT OWNED^nEnemy Ownage: Lv.%d",
        g_iOwnageLevel[id]);

    // ===== SOUND =====

    emit_sound(id, CHAN_VOICE, SOUND_OWN, 1.0, ATTN_NORM, 0, PITCH_NORM);
    emit_sound(victim, CHAN_VOICE, SOUND_OWN, 0.8, ATTN_NORM, 0, PITCH_NORM);

    return FMRES_IGNORED;
}

// ================= OWNAGE LOGIC =================

stock UpdateOwnageLevel(id)
{
    for (new i = sizeof(g_iOwnageNeed) - 1; i >= 0; i--)
    {
        if (g_iOwnageTotal[id] >= g_iOwnageNeed[i])
        {
            g_iOwnageLevel[id] = i;
            return;
        }
    }
}

// ================= UTILS =================

stock Float:get_player_speed(id)
{
    new Float:vel[3];
    pev(id, pev_velocity, vel);
    vel[2] = 0.0;
    return vector_length(vel);
}

stock clamp_int(value, min, max)
{
    if (value < min) return min;
    if (value > max) return max;
    return value;
}
