#include <amxmodx>
#include <reapi>
#include <fakemeta>
#include <hamsandwich>

#include <hns_xp_skills>

#define PLUGIN_NAME    "HNS Skill: Toxic Gas (Optimized)"
#define PLUGIN_VERSION "1.1"
#define PLUGIN_AUTHOR  "cultura"

#define GAS_CLASSNAME  "hns_toxic_gas"
#define GAS_MIN_LEVEL  5
#define GAS_MAX_ACTIVE 2   // 🔒 максимум газов на игрока

// CVARs
new g_pGasDmg;
new g_pGasRadius;
new g_pGasLife;
new g_pGasTick;

new g_iSkillGas;
new g_pFriendlyFire;
new g_iMaxPlayers;

new g_iActiveGas[33]; // 🔒 активные газы игрока

// ================= INIT =================

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    g_iMaxPlayers = get_maxplayers();

    g_pGasDmg    = register_cvar("hns_gas_dmg",    "5");
    g_pGasRadius = register_cvar("hns_gas_radius", "180");
    g_pGasLife   = register_cvar("hns_gas_life",   "8.0");
    g_pGasTick   = register_cvar("hns_gas_tick",   "1.0");

    g_pFriendlyFire = get_cvar_pointer("mp_friendlyfire");

    g_iSkillGas = hns_skills_register(
        "Toxic Gas",
        GAS_MIN_LEVEL,
        SKILL_MODE_DM | SKILL_MODE_PUB | SKILL_MODE_ZM
    );

    register_forward(FM_EmitSound, "fwEmitSound");
    register_forward(FM_Think, "fwGasThink");
}

public client_disconnected(id)
{
    g_iActiveGas[id] = 0;
}

// ================= CREATE GAS =================

public fwEmitSound(ent, channel, const sample[], Float:vol, Float:att, flags, pitch)
{
    if (!equal(sample, "weapons/sg_explode.wav"))
        return FMRES_IGNORED;

    if (!pev_valid(ent))
        return FMRES_IGNORED;

    new owner = pev(ent, pev_owner);
    if (owner < 1 || owner > g_iMaxPlayers || !is_user_alive(owner))
        return FMRES_IGNORED;

    if (!hns_skills_is_enabled(owner, g_iSkillGas))
        return FMRES_IGNORED;

    if (g_iActiveGas[owner] >= GAS_MAX_ACTIVE)
        return FMRES_IGNORED;

    new gas = rg_create_entity("info_target");
    if (!pev_valid(gas))
        return FMRES_IGNORED;

    new Float:origin[3];
    pev(ent, pev_origin, origin);

    set_pev(gas, pev_classname, GAS_CLASSNAME);
    set_pev(gas, pev_origin, origin);
    set_pev(gas, pev_owner, owner);
    set_pev(gas, pev_solid, SOLID_NOT);

    set_pev(gas, pev_fuser1, get_pcvar_float(g_pGasRadius));
    set_pev(gas, pev_fuser2, get_pcvar_float(g_pGasDmg));
    set_pev(gas, pev_fuser3, get_gametime() + get_pcvar_float(g_pGasLife));

    new Float:tick = get_pcvar_float(g_pGasTick);
    if (tick <= 0.0) tick = 1.0;

    set_pev(gas, pev_nextthink, get_gametime() + tick);

    g_iActiveGas[owner]++;

    return FMRES_IGNORED;
}

// ================= THINK =================

public fwGasThink(ent)
{
    if (!pev_valid(ent))
        return FMRES_IGNORED;

    static classname[32];
    pev(ent, pev_classname, classname, charsmax(classname));
    if (!equal(classname, GAS_CLASSNAME))
        return FMRES_IGNORED;

    new Float:now = get_gametime();
    new Float:die;
    pev(ent, pev_fuser3, die);

    new owner = pev(ent, pev_owner);

    if (now >= die)
    {
        if (owner >= 1 && owner <= g_iMaxPlayers && g_iActiveGas[owner] > 0)
            g_iActiveGas[owner]--;

        engfunc(EngFunc_RemoveEntity, ent);
        return FMRES_HANDLED;
    }

    new Float:radius, Float:dmg;
    pev(ent, pev_fuser1, radius);
    pev(ent, pev_fuser2, dmg);

    if (radius <= 0.0 || dmg <= 0.0)
    {
        engfunc(EngFunc_RemoveEntity, ent);
        return FMRES_HANDLED;
    }

    new Float:gasOrigin[3];
    pev(ent, pev_origin, gasOrigin);

    new bool:ff = (g_pFriendlyFire && get_pcvar_num(g_pFriendlyFire));

    new players[32], num;
    get_players(players, num, "a");

    for (new i; i < num; i++)
    {
        new id = players[i];

        if (id == owner)
            continue;

        if (!ff && get_user_team(id) == get_user_team(owner))
            continue;

        new Float:plOrigin[3];
        pev(id, pev_origin, plOrigin);

        if (get_distance_f(gasOrigin, plOrigin) > radius)
            continue;

        ExecuteHamB(Ham_TakeDamage, id, ent, owner, dmg, DMG_POISON);
    }

    new Float:tick = get_pcvar_float(g_pGasTick);
    if (tick <= 0.0) tick = 1.0;

    set_pev(ent, pev_nextthink, now + tick);
    return FMRES_HANDLED;
}
