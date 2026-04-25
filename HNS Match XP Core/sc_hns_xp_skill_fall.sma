#include <amxmodx>
#include <reapi>

#include <hns_matchsystem>   // MODE_DM, MODE_ZM, ...
#include <hns_xp_core>       // hns_xp_get_level() (ядру не нужен, но пусть будет)
#include <hns_xp_skills>     // hns_skills_register, hns_skills_is_enabled

#define PLUGIN_NAME    "HNS Skill: Fall DMG"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_AUTHOR  "you + cultura"

const FALL_MAX_HEAL       = 60;   // максимум HP за одно падение
const Float:FALL_DELAY    = 0.5;  // задержка перед отхилом
const FALL_TASK_BASE      = 6000; // чтобы не пересекалось с другими task'ами

new g_iSkillFall = -1;
new g_iPendingFallHeal[33];

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    // Регистрируем скилл в ядре:
    // название в меню, минимальный уровень, режимы (DM + ZM)
    g_iSkillFall = hns_skills_register("Fall DMG", 2, SKILL_MODE_DM | SKILL_MODE_ZM);

    // Урон (как в старом автохиле) — ловим только падение
    register_event("Damage", "Event_Damage", "b", "2>0");
}

public client_disconnected(id)
{
    if (id < 1 || id > 32)
        return;

    g_iPendingFallHeal[id] = 0;
    remove_task(FALL_TASK_BASE + id);
}

// Урон → копим только урон от падения
public Event_Damage(id)
{
    if (!is_user_alive(id))
        return;

    // если скилл не зарегистрирован
    if (g_iSkillFall < 0)
        return;

    // включён ли скилл для игрока (здесь уже проверяется уровень и режим)
    if (!hns_skills_is_enabled(id, g_iSkillFall))
        return;

    // только падение (как в твоём исходном плагине)
    if (read_data(4) != 0 || read_data(5) != 0 || read_data(6) != 0)
        return;

    new dmg = read_data(2);
    if (dmg <= 0)
        return;

    // копим "будущий" хил
    g_iPendingFallHeal[id] += dmg;
    if (g_iPendingFallHeal[id] > FALL_MAX_HEAL)
        g_iPendingFallHeal[id] = FALL_MAX_HEAL;

    // ставим отложенное лечение, если ещё нет таска
    if (!task_exists(FALL_TASK_BASE + id))
    {
        set_task(FALL_DELAY, "Task_FallHeal", FALL_TASK_BASE + id);
    }
}

public Task_FallHeal(taskid)
{
    new id = taskid - FALL_TASK_BASE;

    if (!is_user_alive(id))
    {
        g_iPendingFallHeal[id] = 0;
        return;
    }

    new heal = g_iPendingFallHeal[id];
    g_iPendingFallHeal[id] = 0;

    if (heal <= 0)
        return;

    new Float:fHp;
    get_entvar(id, var_health, fHp);

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
