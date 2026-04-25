#include <amxmodx>
#include <engine>
#include <fakemeta>
#include <cstrike>

#include <hns_matchsystem>   // hns_get_mode(), MODE_DM, MODE_ZM
#include <hns_xp_skills>     // hns_skills_register, hns_skills_is_enabled

#define PLUGIN_NAME    "HNS Skill: Slap"
#define PLUGIN_VERSION "1.3"
#define PLUGIN_AUTHOR  "cultura"

// ==== НАСТРОЙКИ СПОСОБНОСТИ ===================================

// радиус поиска CT
const Float:SLAP_RADIUS   = 150.0;

// базовая сила отталкивания
const Float:SLAP_FORCE    = 900.0;

// добавка вверх
const Float:SLAP_UP_ADD   = 400.0;

// кулдаун (секунд)
const Float:SLAP_COOLDOWN = 120.0;

// минимальный уровень для открытия
const SLAP_MIN_LEVEL = 5;


// ==== ВНУТРЕННИЕ ДАННЫЕ =======================================

new g_iSkillSlap = -1;
new bool:g_bUseHeld[33];
new Float:g_flLastSlapTime[33];


// ==============================================================
public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    // регистрируем скилл в ядре
    // имя в меню, мин. уровень, доступные режимы
    g_iSkillSlap = hns_skills_register("Slap", SLAP_MIN_LEVEL, SKILL_MODE_DM | SKILL_MODE_ZM);

    // ловим нажатия кнопок для +use
    register_forward(FM_CmdStart, "fw_CmdStart");
}

public client_disconnected(id)
{
    if (id < 1 || id > 32)
        return;

    g_bUseHeld[id] = false;
    g_flLastSlapTime[id] = 0.0;
}

// ловим кнопки
public fw_CmdStart(id, uc_handle, seed)
{
    if (!is_user_alive(id))
        return FMRES_IGNORED;

    new buttons = get_uc(uc_handle, UC_Buttons);

    // однократный вызов по нажатию E (+use)
    if (buttons & IN_USE)
    {
        if (!g_bUseHeld[id])
        {
            g_bUseHeld[id] = true;
            TryUseSlap(id);
        }
    }
    else
    {
        g_bUseHeld[id] = false;
    }

    return FMRES_IGNORED;
}


// ==============================================================
TryUseSlap(id)
{
    // модуль ещё не зарегистрирован
    if (g_iSkillSlap < 0)
        return;

    // скилл должен быть включён в /skills
    if (!hns_skills_is_enabled(id, g_iSkillSlap))
        return;

    // режим только DM/ZM
    new mode = hns_get_mode();
    if (mode != MODE_DM && mode != MODE_ZM)
        return;

    // только террорист
    if (cs_get_user_team(id) != CS_TEAM_T)
        return;

    // проверка кулдауна
    new Float:now = get_gametime();
    new Float:diff = now - g_flLastSlapTime[id];
    if (diff < SLAP_COOLDOWN)
    {
        client_print(id, print_chat,
            "[Slap] Перезарядка: %.0f сек.", SLAP_COOLDOWN - diff);
        return;
    }

    // пробуем найти CT поблизости
    new bool:foundCT = false;
    new Float:origin[3];
    pev(id, pev_origin, origin);

    new ent = -1;
    while ((ent = engfunc(EngFunc_FindEntityInSphere, ent, origin, SLAP_RADIUS)))
    {
        if (ent < 1 || ent > 32)
            continue;

        if (!is_user_alive(ent))
            continue;

        if (cs_get_user_team(ent) != CS_TEAM_CT)
            continue;

        foundCT = true;
        break;
    }

    if (!foundCT)
    {
        client_print(id, print_chat,
            "[Slap] Рядом нет CT (радиус %.0f).", SLAP_RADIUS);
        return;
    }

    // кулдаун стартуем только когда есть цель
    g_flLastSlapTime[id] = now;

    // откидываем всех CT в радиусе
    SlapAround(origin);
    client_print(id, print_chat, "[Slap] Способность применена.");
}


// ==============================================================
SlapAround(const Float:origin[3])
{
    new ent = -1;

    new Float:vicOrg[3];
    new Float:vel[3];

    while ((ent = engfunc(EngFunc_FindEntityInSphere, ent, origin, SLAP_RADIUS)))
    {
        if (ent < 1 || ent > 32)
            continue;

        if (!is_user_alive(ent))
            continue;

        if (cs_get_user_team(ent) != CS_TEAM_CT)
            continue;

        pev(ent, pev_origin, vicOrg);

        new Float:dx = vicOrg[0] - origin[0];
        new Float:dy = vicOrg[1] - origin[1];
        new Float:dz = vicOrg[2] - origin[2];

        new Float:dist = floatsqroot(dx*dx + dy*dy + dz*dz);
        if (dist <= 0.0 || dist > SLAP_RADIUS)
            continue;

        // нормализованный вектор, умноженный на силу
        new Float:scale = SLAP_FORCE / dist;
        vel[0] = dx * scale;
        vel[1] = dy * scale;
        vel[2] = dz * scale + SLAP_UP_ADD;

        set_pev(ent, pev_velocity, vel);
    }
}
