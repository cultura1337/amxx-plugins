#include <amxmodx>
#include <reapi>
#include <hamsandwich>
#include <fakemeta>
#include <hns_matchsystem>
#include <hns_xp_core>

#define PLUGIN  "HNS XP Grenade Drop (PUB + DHUD)"
#define VERSION "2.1"
#define AUTHOR  "cultura"

#define XP_PER_GRENADE  5
#define BOX_LIFETIME    15.0

enum {
    G_HE,
    G_FLASH,
    G_SMOKE,
    G_MAX
}

new const WeaponIdType:gWeaponIds[G_MAX] = {
    WEAPON_HEGRENADE,
    WEAPON_FLASHBANG,
    WEAPON_SMOKEGRENADE
};

new const gWeaponNames[G_MAX][] = {
    "weapon_hegrenade",
    "weapon_flashbang",
    "weapon_smokegrenade"
};

new const gWorldModels[G_MAX][] = {
    "models/w_hegrenade.mdl",
    "models/w_flashbang.mdl",
    "models/w_smokegrenade.mdl"
};

// ---------------- UTILS ----------------

stock bool:IsPubMode()
{
    return (hns_get_mode() == MODE_PUB);
}

// ---------------- INIT ----------------

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    RegisterHookChain(RG_CBasePlayer_Killed, "OnPlayerKilled", true);
    RegisterHookChain(RG_RoundEnd, "OnRoundEnd", true);

    RegisterHam(Ham_Touch, "weaponbox", "OnWeaponBoxTouch", false);
}

public plugin_precache()
{
    for (new i = 0; i < G_MAX; i++)
        precache_model(gWorldModels[i]);
}

// ---------------- DROP ----------------

public OnPlayerKilled(victim, attacker, shouldgib)
{
    if (!IsPubMode())
        return HC_CONTINUE;

    if (!is_user_connected(victim))
        return HC_CONTINUE;

    new Float:origin[3];
    get_entvar(victim, var_origin, origin);
    origin[2] += 10.0;

    for (new i = 0; i < G_MAX; i++)
    {
        new ammoType = rg_get_weapon_info(gWeaponIds[i], WI_AMMO_TYPE);
        new count = get_member(victim, m_rgAmmo, ammoType);

        if (count <= 0)
            continue;

        new box = rg_create_entity("weaponbox", true);
        if (!box)
            continue;

        engfunc(EngFunc_SetModel, box, gWorldModels[i]);
        set_entvar(box, var_origin, origin);
        set_entvar(box, var_movetype, MOVETYPE_TOSS);
        set_entvar(box, var_solid, SOLID_TRIGGER);

        set_entvar(box, var_iuser1, i);        // тип гранаты
        set_entvar(box, var_iuser2, count);    // количество

        set_entvar(box, var_nextthink, get_gametime() + BOX_LIFETIME);
        SetThink(box, "KillWeaponBox");
    }

    return HC_CONTINUE;
}

public KillWeaponBox(ent)
{
    if (!is_nullent(ent))
        set_entvar(ent, var_flags, FL_KILLME);
}

// ---------------- PICKUP ----------------

public OnWeaponBoxTouch(box, player)
{
    if (!IsPubMode())
        return HAM_SUPERCEDE;

    if (!is_user_alive(player))
        return HAM_IGNORED;

    if (get_member(player, m_iTeam) != TEAM_TERRORIST)
        return HAM_SUPERCEDE;

    new type   = get_entvar(box, var_iuser1);
    new amount = get_entvar(box, var_iuser2);

    if (type < 0 || type >= G_MAX || amount <= 0)
        return HAM_IGNORED;

    new ammoType = rg_get_weapon_info(gWeaponIds[type], WI_AMMO_TYPE);
    new maxAmmo  = rg_get_weapon_info(gWeaponIds[type], WI_MAX_ROUNDS);
    new current  = get_member(player, m_rgAmmo, ammoType);

    new give = min(amount, maxAmmo - current);
    if (give <= 0)
        return HAM_SUPERCEDE;

    rg_give_item(player, gWeaponNames[type]);
    set_member(player, m_rgAmmo, current + give, ammoType);

    // ===== XP =====
    new xp = give * XP_PER_GRENADE;
    hns_xp_add_xp(player, xp);

    // ===== DHUD =====
    set_dhudmessage(
        0, 200, 100,
        -1.0, 0.80,
        0,
        0.0,
        1.2,
        0.1, 0.1
    );
    show_dhudmessage(player, "+%d XP", xp);

    set_entvar(box, var_flags, FL_KILLME);
    return HAM_SUPERCEDE;
}

// ---------------- CLEANUP ----------------

public OnRoundEnd(WinStatus:status, ScenarioEventEndRound:event, Float:tm)
{
    if (!IsPubMode())
        return HC_CONTINUE;

    new ent = -1;
    while ((ent = rg_find_ent_by_class(ent, "weaponbox")) > 0)
        set_entvar(ent, var_flags, FL_KILLME);

    return HC_CONTINUE;
}
