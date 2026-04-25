#include <amxmodx>
#include <nvault>
#include <reapi>

#include <hns_matchsystem>
#include <hns_xp_core>

#define PLUGIN  "HNS XP Zombie Skins"
#define VERSION "1.6"
#define AUTHOR  "cultura"

#define CONFIG_FILE "hns_zombie_models.ini"
#define MAX_SKINS 32

#define MENU_REMOVE_SKIN "-1"

enum _:SkinData
{
    SKIN_LEVEL,
    SKIN_MODEL[32],
    SKIN_NAME[32]
}

new g_Skins[MAX_SKINS][SkinData]
new g_SkinCount

// -1 = стандартный (ничего не выбрано)
new g_PlayerSkin[33]

// vault
new g_hVault

// =========================
// INIT
// =========================
public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR)

    register_clcmd("say /zskins", "CmdSkinMenu")
    register_clcmd("say_team /zskins", "CmdSkinMenu")

    RegisterHookChain(RG_CBasePlayer_Spawn, "OnPlayerSpawn", true)

    g_hVault = nvault_open("hns_zskins")
    if (g_hVault == INVALID_HANDLE)
        set_fail_state("[ZSKINS] Can't open nvault")

    for (new i = 1; i <= MaxClients; i++)
        g_PlayerSkin[i] = -1
}

public plugin_end()
{
    if (g_hVault != INVALID_HANDLE)
        nvault_close(g_hVault)
}

// =========================
// PRECACHE
// =========================
public plugin_precache()
{
    LoadSkins()
    PrecacheSkins()
}

// =========================
// CLIENT
// =========================
public client_putinserver(id)
{
    g_PlayerSkin[id] = -1
    LoadPlayerChoice(id)
}

public client_disconnected(id)
{
    SavePlayerChoice(id)
    g_PlayerSkin[id] = -1
}

// =========================
// LOAD CONFIG
// =========================
LoadSkins()
{
    g_SkinCount = 0

    new path[128]
    get_localinfo("amxx_configsdir", path, charsmax(path))
    formatex(path, charsmax(path), "%s/%s", path, CONFIG_FILE)

    new fp = fopen(path, "rt")
    if (!fp)
    {
        log_amx("[ZSKINS] Config not found: %s", path)
        return
    }

    new line[256], lvl[16], model[64], name[64]

    while (!feof(fp) && g_SkinCount < MAX_SKINS)
    {
        fgets(fp, line, charsmax(line))
        trim(line)

        if (!line[0] || line[0] == ';')
            continue

        // формат строки:
        // <level> <model> <name with spaces allowed if quoted>
        // пример: 10 zombi_kruger "Kruger Zombie"
        lvl[0] = model[0] = name[0] = 0

        parse(line, lvl, charsmax(lvl), model, charsmax(model), name, charsmax(name))

        if (!lvl[0] || !model[0] || !name[0])
            continue

        g_Skins[g_SkinCount][SKIN_LEVEL] = max(0, str_to_num(lvl))

        copy(g_Skins[g_SkinCount][SKIN_MODEL], charsmax(g_Skins[][SKIN_MODEL]), model)
        copy(g_Skins[g_SkinCount][SKIN_NAME],  charsmax(g_Skins[][SKIN_NAME]),  name)

        g_SkinCount++
    }

    fclose(fp)

    log_amx("[ZSKINS] Loaded %d skins", g_SkinCount)
}

// =========================
// PRECACHE MODELS
// =========================
PrecacheSkins()
{
    new path[128]

    for (new i = 0; i < g_SkinCount; i++)
    {
        formatex(path, charsmax(path), "models/player/%s/%s.mdl",
            g_Skins[i][SKIN_MODEL], g_Skins[i][SKIN_MODEL])

        if (file_exists(path))
            precache_model(path)
        else
            log_amx("[ZSKINS] Missing model: %s", path)
    }
}

// =========================
// SPAWN
// =========================
public OnPlayerSpawn(id)
{
    if (!is_user_alive(id))
        return HC_CONTINUE

    // только ZM
    if (hns_get_mode() != MODE_ZM)
    {
        rg_reset_user_model(id)
        return HC_CONTINUE
    }

    // только CT (если у тебя CT = зомби — ок, иначе поменяешь на TEAM_TERRORIST)
    if (get_member(id, m_iTeam) != TEAM_CT)
    {
        rg_reset_user_model(id)
        return HC_CONTINUE
    }

    // стандартный
    if (g_PlayerSkin[id] == -1)
    {
        rg_reset_user_model(id)
        return HC_CONTINUE
    }

    ApplySkin(id)
    return HC_CONTINUE
}

// =========================
// APPLY SKIN
// =========================
ApplySkin(id)
{
    new skin = g_PlayerSkin[id]

    if (skin < 0 || skin >= g_SkinCount)
        return

    if (hns_xp_get_level(id) < g_Skins[skin][SKIN_LEVEL])
        return

    rg_set_user_model(id, g_Skins[skin][SKIN_MODEL])
}

// =========================
// MENU
// =========================
public CmdSkinMenu(id)
{
    if (!is_user_connected(id))
        return PLUGIN_HANDLED

    if (hns_get_mode() != MODE_ZM)
    {
        client_print(id, print_chat, "[HNS] Доступно только в ZM режиме")
        return PLUGIN_HANDLED
    }

    if (get_member(id, m_iTeam) != TEAM_CT)
    {
        client_print(id, print_chat, "[HNS] Только для КТ")
        return PLUGIN_HANDLED
    }

    new title[128]
    formatex(title, charsmax(title), "Zombie Skins \y(Your level: %d)", hns_xp_get_level(id))

    new menu = menu_create(title, "MenuHandler")

    // пункт снять скин
    menu_additem(menu, "\r[Снять скин] \wСтандартный", MENU_REMOVE_SKIN)

    new level = hns_xp_get_level(id)
    new info[8], itemText[128]

    for (new i = 0; i < g_SkinCount; i++)
    {
        num_to_str(i, info, charsmax(info))

        if (g_Skins[i][SKIN_LEVEL] <= level)
        {
            // доступно
            formatex(itemText, charsmax(itemText), "\w%s \y(LVL %d)", g_Skins[i][SKIN_NAME], g_Skins[i][SKIN_LEVEL])
            menu_additem(menu, itemText, info)
        }
        else
        {
            // закрыто
            formatex(itemText, charsmax(itemText), "\d%s \r[need LVL %d]", g_Skins[i][SKIN_NAME], g_Skins[i][SKIN_LEVEL])
            menu_additem(menu, itemText, info, 0) // доступ=0, но обработчик сам отфильтрует
        }
    }

    menu_display(id, menu)
    return PLUGIN_HANDLED
}

public MenuHandler(id, menu, item)
{
    if (item == MENU_EXIT)
    {
        menu_destroy(menu)
        return
    }

    new info[8], access, callback
    menu_item_getinfo(menu, item, access, info, charsmax(info), _, _, callback)

    // снять скин
    if (equal(info, MENU_REMOVE_SKIN))
    {
        g_PlayerSkin[id] = -1
        SavePlayerChoice(id)
        rg_reset_user_model(id)

        client_print(id, print_chat, "[HNS] Скин снят (стандартный).")
        menu_destroy(menu)
        return
    }

    new skin = str_to_num(info)

    if (skin < 0 || skin >= g_SkinCount)
    {
        menu_destroy(menu)
        return
    }

    // уровень
    new level = hns_xp_get_level(id)
    if (level < g_Skins[skin][SKIN_LEVEL])
    {
        client_print(id, print_chat, "[HNS] Недоступно. Нужно LVL %d.", g_Skins[skin][SKIN_LEVEL])
        menu_destroy(menu)
        return
    }

    g_PlayerSkin[id] = skin
    SavePlayerChoice(id)

    client_print(id, print_chat, "[HNS] Выбран скин: %s", g_Skins[skin][SKIN_NAME])

    // по желанию можно применить сразу:
    if (is_user_alive(id))
        ApplySkin(id)

    menu_destroy(menu)
}

// =========================
// SAVE/LOAD
// =========================
SavePlayerChoice(id)
{
    if (g_hVault == INVALID_HANDLE)
        return

    new authid[32]
    get_user_authid(id, authid, charsmax(authid))
    if (!authid[0] || equal(authid, "STEAM_ID_PENDING"))
        return

    new key[64], val[16]
    formatex(key, charsmax(key), "zskin_%s", authid)
    formatex(val, charsmax(val), "%d", g_PlayerSkin[id])

    nvault_set(g_hVault, key, val)
}

LoadPlayerChoice(id)
{
    if (g_hVault == INVALID_HANDLE)
        return

    new authid[32]
    get_user_authid(id, authid, charsmax(authid))
    if (!authid[0] || equal(authid, "STEAM_ID_PENDING"))
        return

    new key[64], val[16]
    formatex(key, charsmax(key), "zskin_%s", authid)

    if (nvault_get(g_hVault, key, val, charsmax(val)))
        g_PlayerSkin[id] = str_to_num(val)
}
