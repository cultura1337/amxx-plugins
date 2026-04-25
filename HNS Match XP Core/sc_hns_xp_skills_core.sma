#include <amxmodx>
#include <hns_xp_core>       // hns_xp_get_level()
#include <hns_matchsystem>   // MODE_DM, MODE_ZM, MODE_PUB, hns_get_mode()
#include <hns_xp_skills>     // SKILL_MODE_*, нативы

#define PLUGIN_NAME    "HNS XP Skills Core"
#define PLUGIN_VERSION "1.1"
#define PLUGIN_AUTHOR  "cultura + GPT"

#define MAX_SKILLS      16
#define MAX_SKILL_NAME  32

#define SOUND_ON   "subcultura/activated.wav"
#define SOUND_OFF  "subcultura/deactivated.wav"

enum SkillInfo
{
    bool:SkillUsed,
    SkillName[MAX_SKILL_NAME],
    SkillMinLevel,
    SkillModes
}

new g_eSkills[MAX_SKILLS][SkillInfo];
new bool:g_bSkillEnabled[33][MAX_SKILLS];

// =====================================================
// precache
// =====================================================
public plugin_precache()
{
    precache_sound(SOUND_ON);
    precache_sound(SOUND_OFF);
}

// =====================================================
// natives
// =====================================================
public plugin_natives()
{
    register_native("hns_skills_register",   "Native_SkillsRegister");
    register_native("hns_skills_is_enabled", "Native_SkillsIsEnabled");
}

// =====================================================
// init
// =====================================================
public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    register_clcmd("say /skills",      "Cmd_SkillsMenu");
    register_clcmd("say_team /skills", "Cmd_SkillsMenu");
}

// =====================================================
// cleanup
// =====================================================
public client_disconnected(id)
{
    if (id < 1 || id > 32)
        return;

    for (new s = 0; s < MAX_SKILLS; s++)
        g_bSkillEnabled[id][s] = false;
}

// =====================================================
// mode mask
// =====================================================
stock GetCurrentModeMask()
{
    new mode = hns_get_mode();

    switch (mode)
    {
        case MODE_DM:  return SKILL_MODE_DM;
        case MODE_ZM:  return SKILL_MODE_ZM;
        case MODE_PUB: return SKILL_MODE_PUB;
    }

    return 0;
}

// =====================================================
// register skill
// =====================================================
public Native_SkillsRegister(plugin, params)
{
    if (params < 3)
        return -1;

    new name[MAX_SKILL_NAME];
    get_string(1, name, charsmax(name));

    new minLevel = get_param(2);
    new modes    = get_param(3);

    if (minLevel < 1)
        minLevel = 1;

    for (new i = 0; i < MAX_SKILLS; i++)
    {
        if (!g_eSkills[i][SkillUsed])
        {
            g_eSkills[i][SkillUsed]     = true;
            g_eSkills[i][SkillMinLevel]= minLevel;
            g_eSkills[i][SkillModes]   = modes;
            copy(g_eSkills[i][SkillName], charsmax(g_eSkills[][SkillName]), name);

            log_amx("[HNS Skills] Registered skill #%d: %s", i, name);
            return i;
        }
    }

    log_amx("[HNS Skills] ERROR: No free skill slots");
    return -1;
}

// =====================================================
// is enabled
// =====================================================
public bool:Native_SkillsIsEnabled(plugin, params)
{
    if (params < 2)
        return false;

    new id = get_param(1);
    new skill = get_param(2);

    if (id < 1 || id > 32)
        return false;

    if (skill < 0 || skill >= MAX_SKILLS)
        return false;

    if (!g_eSkills[skill][SkillUsed])
        return false;

    if (hns_xp_get_level(id) < g_eSkills[skill][SkillMinLevel])
        return false;

    if (!(GetCurrentModeMask() & g_eSkills[skill][SkillModes]))
        return false;

    return g_bSkillEnabled[id][skill];
}

// =====================================================
// /skills menu
// =====================================================
public Cmd_SkillsMenu(id)
{
    if (!is_user_connected(id))
        return PLUGIN_HANDLED;

    new menu = menu_create("\yHNS Skills", "SkillsMenu_Handler");

    new level = hns_xp_get_level(id);
    new modeMask = GetCurrentModeMask();

    new item[64], info[4];

    for (new i = 0; i < MAX_SKILLS; i++)
    {
        if (!g_eSkills[i][SkillUsed])
            continue;

        new need = g_eSkills[i][SkillMinLevel];
        new modes = g_eSkills[i][SkillModes];

        if (level < need)
        {
            formatex(item, charsmax(item), "\d%s (lvl %d+)", g_eSkills[i][SkillName], need);
        }
        else if (!(modes & modeMask))
        {
            formatex(item, charsmax(item), "\d%s (not in this mode)", g_eSkills[i][SkillName]);
        }
        else
        {
            formatex(item, charsmax(item), "%s \y[%s]",
                g_eSkills[i][SkillName],
                g_bSkillEnabled[id][i] ? "ON" : "OFF");
        }

        num_to_str(i, info, charsmax(info));
        menu_additem(menu, item, info);
    }

    menu_setprop(menu, MPROP_EXITNAME, "Exit");
    menu_display(id, menu);

    return PLUGIN_HANDLED;
}

// =====================================================
// menu handler + SOUND
// =====================================================
public SkillsMenu_Handler(id, menu, item)
{
    if (item == MENU_EXIT || !is_user_connected(id))
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new info[4], access, callback;
    menu_item_getinfo(menu, item, access, info, charsmax(info), _, _, callback);

    new skill = str_to_num(info);

    if (skill < 0 || skill >= MAX_SKILLS || !g_eSkills[skill][SkillUsed])
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    if (hns_xp_get_level(id) < g_eSkills[skill][SkillMinLevel] ||
        !(GetCurrentModeMask() & g_eSkills[skill][SkillModes]))
    {
        Cmd_SkillsMenu(id);
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new bool:wasEnabled = g_bSkillEnabled[id][skill];
    g_bSkillEnabled[id][skill] = !wasEnabled;

    // 🔊 SOUND (100% WORKING)
    if (wasEnabled)
        client_cmd(id, "spk ^"%s^"", SOUND_OFF);
    else
        client_cmd(id, "spk ^"%s^"", SOUND_ON);

    Cmd_SkillsMenu(id);
    menu_destroy(menu);

    return PLUGIN_HANDLED;
}
