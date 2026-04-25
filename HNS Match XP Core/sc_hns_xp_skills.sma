#include <amxmodx>
#include <reapi>

#include <hns_matchsystem>  // MODE_DM, MODE_ZM, MODE_PUB, hns_get_mode()
#include <hns_xp_core>      // hns_xp_get_level()

#define PLUGIN_NAME    "HNS XP Skills"
#define PLUGIN_VERSION "0.7"
#define PLUGIN_AUTHOR  "cultura"

// === SKILLS ENUM ===
enum
{
    SKILL_FALL = 0,   // автохил от падения
    MAX_SKILLS
};

// Настройки скилла FALL DMG
new g_pFallMinLevel;      // минимальный уровень для открытия
new g_pFallMaxHeal;       // максимум HP, которое можно вернуть за одно падение
new g_pFallDelay;         // задержка перед лечением (сек)

// Состояние скиллов
new bool:g_bSkillEnabled[33][MAX_SKILLS];

// Буфер урона от падения
const TASK_FALL_HEAL = 5000;
new g_iPendingFallHeal[33];

// ===========================
// plugin_init
// ===========================
public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    // CVAR'ы для FALL DMG
    g_pFallMinLevel = register_cvar("hns_skill_fall_min_level", "2");   // открыть с 2 уровня
    g_pFallMaxHeal  = register_cvar("hns_skill_fall_hp_reg",    "60");  // максимум +60 хп за одно падение
    g_pFallDelay    = register_cvar("hns_skill_fall_delay",     "0.5"); // лечить через 0.5 секунды

    // Хук урона
    register_event("Damage", "Event_Damage", "b", "2>0");

    // Меню скиллов
    register_clcmd("say /skills",      "Cmd_SkillsMenu");
    register_clcmd("say_team /skills", "Cmd_SkillsMenu");

    // Обнуление
    for (new i = 1; i <= 32; i++)
    {
        for (new s = 0; s < MAX_SKILLS; s++)
            g_bSkillEnabled[i][s] = false;

        g_iPendingFallHeal[i] = 0;
    }
}

public client_disconnected(id)
{
    // Сброс состояний при выходе
    for (new s = 0; s < MAX_SKILLS; s++)
        g_bSkillEnabled[id][s] = false;

    g_iPendingFallHeal[id] = 0;
    remove_task(TASK_FALL_HEAL + id);
}

// ===========================
//  DAMAGE -> только FALL DMG
// ===========================
public Event_Damage(id)
{
    if (!is_user_alive(id))
        return;

    // Режимы: только DM и ZM
    new mode = hns_get_mode();
    if (mode != MODE_DM && mode != MODE_ZM)
        return;

    // Скилл должен быть включен
    if (!g_bSkillEnabled[id][SKILL_FALL])
        return;

    // Проверка уровня
    new level = hns_xp_get_level(id);
    new need_level = get_pcvar_num(g_pFallMinLevel);
    if (level < need_level)
        return;

    // Берём только урон от падения
    if (read_data(4) != 0 || read_data(5) != 0 || read_data(6) != 0)
        return;

    new dmg = read_data(2);
    if (dmg <= 0)
        return;

    // Копим урон от падения, который надо вернуть
    g_iPendingFallHeal[id] += dmg;

    // Ограничиваем максимумом
    new maxHeal = get_pcvar_num(g_pFallMaxHeal);
    if (maxHeal > 0 && g_iPendingFallHeal[id] > maxHeal)
        g_iPendingFallHeal[id] = maxHeal;

    // Если таска ещё нет — ставим
    if (!task_exists(TASK_FALL_HEAL + id))
    {
        new Float:delay = get_pcvar_float(g_pFallDelay);
        set_task(delay, "Task_FallHeal", TASK_FALL_HEAL + id);
    }
}

// Лечение после падения
public Task_FallHeal(taskid)
{
    new id = taskid - TASK_FALL_HEAL;

    if (!is_user_alive(id))
    {
        g_iPendingFallHeal[id] = 0;
        return;
    }

    new heal = g_iPendingFallHeal[id];
    g_iPendingFallHeal[id] = 0;

    if (heal <= 0)
        return;

    // Явно приводим результат get_entvar к Float (чтобы не было warning 213)
    new Float:fHp = Float:get_entvar(id, var_health);

    if (fHp >= 100.0)
        return;

    new Float:fMaxAdd = 100.0 - fHp;
    new maxAdd = floatround(fMaxAdd, floatround_floor);

    if (heal > maxAdd)
        heal = maxAdd;

    if (heal <= 0)
        return;

    set_entvar(id, var_health, fHp + float(heal));
}

// ===========================
//  МЕНЮ СКИЛЛОВ
// ===========================
public Cmd_SkillsMenu(id)
{
    if (!is_user_connected(id))
        return PLUGIN_HANDLED;

    new menu = menu_create("\yHNS Skills", "SkillsMenu_Handler");

    new mode = hns_get_mode();
    new szItem[64];

    new level      = hns_xp_get_level(id);
    new need_level = get_pcvar_num(g_pFallMinLevel);
    new bool:unlocked = bool:(level >= need_level);
    new bool:enabled  = bool:(g_bSkillEnabled[id][SKILL_FALL]); // <-- ЯВНЫЙ CAST

    // Если не DM/ZM — пункт серый
    if (mode != MODE_DM && mode != MODE_ZM)
    {
        if (!unlocked)
        {
            formatex(szItem, charsmax(szItem),
                "\dFALL DMG (LVL %d+, только DM/ZM)", need_level);
        }
        else
        {
            formatex(szItem, charsmax(szItem),
                "\dFALL DMG [только DM/ZM]");
        }

        menu_additem(menu, szItem, "1");
    }
    else
    {
        // DM / ZM
        if (!unlocked)
        {
            formatex(szItem, charsmax(szItem),
                "\dFALL DMG (нужен уровень: %d)", need_level);
            menu_additem(menu, szItem, "1");
        }
        else
        {
            formatex(szItem, charsmax(szItem),
                "FALL DMG \y[%s]",
                enabled ? "ON" : "OFF");
            menu_additem(menu, szItem, "1");
        }
    }

    menu_setprop(menu, MPROP_EXITNAME, "Выход");
    menu_display(id, menu);

    return PLUGIN_HANDLED;
}

public SkillsMenu_Handler(id, menu, item)
{
    if (item == MENU_EXIT || !is_user_connected(id))
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new mode = hns_get_mode();

    // Кнопка реально работает только в DM/ZM и при достаточном уровне
    if (mode != MODE_DM && mode != MODE_ZM)
    {
        Cmd_SkillsMenu(id);
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new level      = hns_xp_get_level(id);
    new need_level = get_pcvar_num(g_pFallMinLevel);

    if (level < need_level)
    {
        Cmd_SkillsMenu(id);
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    // Тоггл ON/OFF (без сообщений в чат)
    g_bSkillEnabled[id][SKILL_FALL] = !g_bSkillEnabled[id][SKILL_FALL];

    // Обновляем меню
    Cmd_SkillsMenu(id);

    menu_destroy(menu);
    return PLUGIN_HANDLED;
}
