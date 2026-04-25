#include <amxmodx>
#include <reapi>
#include <fakemeta>
#include <hamsandwich>

#include <hns_matchsystem>  // MODE_ZM, MODE_PUB, hns_get_mode()
#include <hns_xp_skills>    // hns_skills_register, hns_skills_is_enabled

#define PLUGIN_NAME    "HNS Skill: HE Knockback"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_AUTHOR  "cultura"

// с какого уровня открывается скилл
#define HE_KNOCK_MIN_LEVEL   5

// имя скилла в /skills
#define HE_KNOCK_NAME        "HE Knockback"

// cvar: множитель силы отталкивания
new g_pHePushPower;

// id скилла в ядре
new g_iSkillHe = -1;

new g_iMaxPlayers;

// =======================
//    plugin_init
// =======================
public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    g_iMaxPlayers = get_maxplayers();

    // сила отталкивания: итоговая скорость = power * damage
    g_pHePushPower = register_cvar("hns_skill_he_push_power", "20.0");

    // Регистрируем скилл:
    // доступен только в ZM и PUB
    g_iSkillHe = hns_skills_register(
        HE_KNOCK_NAME,
        HE_KNOCK_MIN_LEVEL,
        SKILL_MODE_ZM | SKILL_MODE_PUB
    );

    // перехватываем спавн игрока, чтобы выдавать HE
    RegisterHookChain(RG_CBasePlayer_Spawn, "CBasePlayer_Spawn_Post", true);

    // перехватываем получение урона, чтобы заменить взрыв HE на отталкивание
    RegisterHam(Ham_TakeDamage, "player", "Ham_TakeDamage_Pre", false);
}

// =======================
//   Выдача HE на спавне
// =======================
public CBasePlayer_Spawn_Post(id)
{
    if (!is_user_alive(id))
        return HC_CONTINUE;

    if (g_iSkillHe < 0)
        return HC_CONTINUE;

    // режим: только ZM / PUB
    new mode = hns_get_mode();
    if (mode != MODE_ZM && mode != MODE_PUB)
        return HC_CONTINUE;

    // только террористы (1 = T)
    if (get_user_team(id) != 1)
        return HC_CONTINUE;

    // скилл должен быть включен в /skills
    if (!hns_skills_is_enabled(id, g_iSkillHe))
        return HC_CONTINUE;

    // даём HE, если нужно
    // reapi сам корректно обработает, если у игрока уже есть граната
    rg_give_item(id, "weapon_hegrenade");

    return HC_CONTINUE;
}

// =======================
//   HE -> только отталкивание
// =======================
//
// Ham_TakeDamage_Pre вызывается при уроне по игроку.
// Мы ловим случай, когда урон от HE, и заменяем его на push без урона.
//
public Ham_TakeDamage_Pre(victim, inflictor, attacker, Float:damage, damagebits)
{
    if (damage <= 0.0)
        return HAM_IGNORED;

    if (victim < 1 || victim > g_iMaxPlayers)
        return HAM_IGNORED;

    if (attacker < 1 || attacker > g_iMaxPlayers)
        return HAM_IGNORED;

    if (!is_user_connected(attacker) || !is_user_alive(attacker))
        return HAM_IGNORED;

    if (victim == attacker)
        return HAM_IGNORED;

    if (!pev_valid(inflictor))
        return HAM_IGNORED;

    // режим: только ZM / PUB
    new mode = hns_get_mode();
    if (mode != MODE_ZM && mode != MODE_PUB)
        return HAM_IGNORED;

    // только террористы отталкивают
    if (get_user_team(attacker) != 1) // 1 = T
        return HAM_IGNORED;

    // жертва должна быть противником (обычно CT)
    if (get_user_team(victim) == get_user_team(attacker))
        return HAM_IGNORED;

    // скилл должен быть включен у атакующего
    if (g_iSkillHe < 0 || !hns_skills_is_enabled(attacker, g_iSkillHe))
        return HAM_IGNORED;

    // проверяем, что источник урона — граната
    static classname[16];
    pev(inflictor, pev_classname, classname, charsmax(classname));

    if (!equal(classname, "grenade"))
        return HAM_IGNORED;

    // === здесь мы точно знаем:
    // victim — игрок
    // attacker — игрок T
    // inflictor — граната HE
    // режим ZM/PUB, скилл включен
    // => заменяем урон на отталкивание

    new Float:originExpl[3];
    pev(inflictor, pev_origin, originExpl);

    new Float:pushPower = get_pcvar_float(g_pHePushPower);
    if (pushPower <= 0.0)
        pushPower = 20.0;

    new Float:vel[3];
    get_velocity_from_origin(victim, originExpl, pushPower * damage, vel);

    // вертикальная составляющая, чтобы "подкидывало"
    if (vel[2] < 300.0)
        vel[2] = 300.0;

    set_pev(victim, pev_velocity, vel);

    // урона не наносим
    SetHamParamFloat(4, 0.0);

    return HAM_HANDLED;
}

// =======================
//   Вспомогательные функции
// =======================

// Считает вектор скорости от точки origin к игроку ent с заданной скоростью speed
stock get_velocity_from_origin(ent, const Float:origin[3], Float:speed, Float:outVel[3])
{
    new Float:entOrigin[3];
    pev(ent, pev_origin, entOrigin);

    new Float:dir[3];
    dir[0] = entOrigin[0] - origin[0];
    dir[1] = entOrigin[1] - origin[1];
    dir[2] = entOrigin[2] - origin[2];

    new Float:len = floatsqroot(dir[0]*dir[0] + dir[1]*dir[1] + dir[2]*dir[2]);
    if (len <= 0.0)
    {
        outVel[0] = outVel[1] = outVel[2] = 0.0;
        return;
    }

    new Float:scale = speed / len;

    outVel[0] = dir[0] * scale;
    outVel[1] = dir[1] * scale;
    outVel[2] = dir[2] * scale;
}
