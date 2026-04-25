#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <reapi>
#include <time>
#include <nvault>

#include <hns_xp_core>   // hns_xp_get_level()

new const PLUGIN[]  = "Hats"
new const AUTHOR[]  = "cultura"
new const VERSION[] = "lvl`s"

new const HATS_PATH[] = "models/SC_hats"
#define MAX_HATS       64
#define VIP_FLAG       ADMIN_LEVEL_H
#define VAULT_DAYS     30

new const CHAT_SET_HAT_FORMAT[] = "^4[%s] ^3%L ^4%s"
#define NAME_LEN       64

#define MAXSTUDIOBODYPARTS 32

enum _:PLAYER_DATA
{
    PLR_HAT_ENT,
    PLR_HAT_ID,
    PLR_MENU_HATID
}

enum _:HAT_DATA
{
    HAT_MODEL[NAME_LEN],
    HAT_NAME[NAME_LEN],
    HAT_SKINS_NUM,
    HAT_BODIES_NUM,
    HAT_PARTS_NAMES[MAXSTUDIOBODYPARTS * NAME_LEN],
    HAT_TAG,
    HAT_VIP_FLAG,
    HAT_MIN_LEVEL
}

new g_ePlayerData[MAX_PLAYERS + 1][PLAYER_DATA]
new g_eHatData[MAX_HATS][HAT_DATA]
new g_iTotalHats
new g_fwChangeHat
new g_iVaultHats

// =====================================================
// plugin_precache / cfg
// =====================================================
public plugin_precache()
{
    new szCfgDir[32], szHatFile[64]
    get_configsdir(szCfgDir, charsmax(szCfgDir))

    formatex(szHatFile, charsmax(szHatFile), "%s/HatList.ini", szCfgDir)

    load_hats(szHatFile)
    
    for (new i = 1, szCurrentFile[256]; i < g_iTotalHats; i++)
    {
        formatex(szCurrentFile, charsmax(szCurrentFile), "%s/%s", HATS_PATH, g_eHatData[i][HAT_MODEL])
        if (file_exists(szCurrentFile))
        {
            precache_model(szCurrentFile)
            server_print("[%s] Precached %s", PLUGIN, szCurrentFile)
        }
        else
        {
            server_print("[%s] Failed to precache %s", PLUGIN, szCurrentFile)
        }
    }
}

public plugin_cfg()
{
    g_iVaultHats = nvault_open("next21_hat")
            
    if (g_iVaultHats == INVALID_HANDLE)
        set_fail_state("Error opening nVault!")
        
    nvault_prune(g_iVaultHats, 0, get_systime() - (SECONDS_IN_DAY * VAULT_DAYS))
}

// =====================================================
// plugin_init / end
// =====================================================
public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR)
        
    register_concmd("amx_givehat",      "concmd_give_hat",       ADMIN_RCON, "<nick> <hat #> <part #>")
    register_concmd("amx_removehats",   "concmd_remove_all_hats",ADMIN_RCON, " - Removes hats from everyone")
        
    register_clcmd("say /hats",        "clcmd_show_menu", .info="Shows hats menu")
    register_clcmd("say_team /hats",   "clcmd_show_menu", .info="Shows hats menu")
    register_clcmd("hats",             "clcmd_show_menu", .info="Shows hats menu")

    register_dictionary("next21_hats.txt")
    
    g_fwChangeHat = CreateMultiForward("n21_change_hat", ET_STOP, FP_CELL, FP_CELL)
}

public plugin_end()
{
    nvault_close(g_iVaultHats)
    DestroyForward(g_fwChangeHat)
}

// =====================================================
// Подключение / отключение игроков
// =====================================================
public client_putinserver(iPlayer)
{
    remove_hat(iPlayer)

    static szKey[24], szValue[128]
    get_user_authid(iPlayer, szKey, charsmax(szKey))
    nvault_get(g_iVaultHats, szKey, szValue, charsmax(szValue))

    new iHatId, iPartId
    if (!szValue[0])
        goto set_hat_and_return

    static szHatModel[120], szHatPart[5]
    split(szValue, szHatModel, charsmax(szHatModel), szHatPart, charsmax(szHatPart), "|")

    if (equal(szHatModel, "!NULL"))
        goto set_hat_and_return
    
    for (new i = 1; i < g_iTotalHats; i++)
    {
        if (!equal(szHatModel, g_eHatData[i][HAT_MODEL]))
            continue

        // при заходе тоже проверяем доступ по уровню
        if (check_hat_access(iPlayer, i) && check_hat_level(iPlayer, i))
        {
            iHatId = i
            iPartId = str_to_num(szHatPart)
        }
        goto set_hat_and_return
    }

    set_hat_and_return:
    set_hat(iPlayer, iHatId, iPlayer, iPartId)
}

public client_disconnected(iPlayer)
{
    remove_hat(iPlayer)
}

public CBasePlayer_Spawn_Post(const iPlayer)
{
    if (!g_ePlayerData[iPlayer][PLR_HAT_ID] || !is_user_alive(iPlayer))
        return HC_CONTINUE

    new iHatId = g_ePlayerData[iPlayer][PLR_HAT_ID]
    if (g_eHatData[iHatId][HAT_TAG] != 't')
        return HC_CONTINUE

    new iHatEnt = g_ePlayerData[iPlayer][PLR_HAT_ENT],
        iPartId = get_member(iPlayer, m_iTeam) == 2

    if (g_eHatData[iHatId][HAT_BODIES_NUM] > 1)
        set_entvar(iHatEnt, var_body, iPartId)
    
    if (g_eHatData[iHatId][HAT_SKINS_NUM] > 1)
        set_entvar(iHatEnt, var_skin, iPartId)
        
    return HC_CONTINUE
}

// =====================================================
// Команды
// =====================================================
public clcmd_show_menu(iPlayer)
{
    display_hats_menu(iPlayer)
    return PLUGIN_HANDLED
}

public concmd_give_hat(iPlayer, iLevel, cid)
{
    if (!cmd_access(iPlayer, iLevel, cid, 1))
        return PLUGIN_CONTINUE

    new szPlayerName[32], szHatId[4], szPartId[5]
    read_argv(1, szPlayerName, charsmax(szPlayerName))
    read_argv(2, szHatId, charsmax(szHatId))
    read_argv(3, szPartId, charsmax(szPartId))
    
    new iTarget = find_player_ex(FindPlayer_MatchName, szPlayerName)
    if (!iTarget)
    {
        client_print(iPlayer, print_console, "[%s] %L", PLUGIN, iPlayer, "HAT_NICK_NOT_FOUND")
        return PLUGIN_HANDLED
    }
    
    new iHatId = str_to_num(szHatId)
    if (iHatId >= g_iTotalHats)
        return PLUGIN_HANDLED
            
    // админская команда не проверяет уровень, только VIP-флаг
    set_hat(iTarget, iHatId, iPlayer, str_to_num(szPartId))
    return PLUGIN_HANDLED
}

public concmd_remove_all_hats(iPlayer, iLevel, cid)
{
    if (!cmd_access(iPlayer, iLevel, cid, 1))
        return PLUGIN_CONTINUE

    new iMaxPlayers = get_maxplayers()
    for (new i = 1; i <= iMaxPlayers; i++)
        if (is_user_connected(i))
            remove_hat(i)
    
    client_print(iPlayer, print_console, "[%s] %L", PLUGIN, iPlayer, "HAT_ALL_REMOVED")
    return PLUGIN_HANDLED
}

// =====================================================
// Меню шапок (с уровнями)
// =====================================================
display_hats_menu(iPlayer, iPage=0)
{
    static szItemName[128]
    new iMenu = menu_create("Hat Menu", "handler_hats_menu")

    // пункт "снять шапку"
    menu_additem(iMenu, fmt("\r%L", iPlayer, "HAT_ITEM_REMOVE"))

    new playerLevel = hns_xp_get_level(iPlayer)

    for (new iHatId = 1; iHatId < g_iTotalHats; iHatId++)
    {
        new reqLevel = g_eHatData[iHatId][HAT_MIN_LEVEL]
        new bool:hasVip   = check_hat_access(iPlayer, iHatId)
        new bool:hasLevel = (playerLevel >= reqLevel)

        szItemName[0] = 0

        // если нет доступа по уровню / VIP — показываем серым
        if (!hasVip || !hasLevel)
        {
            add(szItemName, charsmax(szItemName), "\d")
        }
        else
        {
            // доступна — белым
            add(szItemName, charsmax(szItemName), "\w")
        }

        // имя шапки
        add(szItemName, charsmax(szItemName), g_eHatData[iHatId][HAT_NAME])

        // если есть требуемый lvl — показываем его
        if (reqLevel > 0)
        {
            new szLvl[32]
            formatex(szLvl, charsmax(szLvl), " (Lvl %d)", reqLevel)
            add(szItemName, charsmax(szItemName), szLvl)
        }

        // VIP помечаем как [VIP]
        if (g_eHatData[iHatId][HAT_VIP_FLAG])
        {
            add(szItemName, charsmax(szItemName), " [VIP]")
        }

        menu_additem(iMenu, szItemName)
    }

    set_menu_common_prop(iMenu, iPlayer)
    menu_display(iPlayer, iMenu, iPage)
}

display_skins_menu(iPlayer)
{
    new iHatId = g_ePlayerData[iPlayer][PLR_MENU_HATID]
    new iMenu = menu_create(fmt("Hat Skin (\r%s\y)", g_eHatData[iHatId][HAT_NAME]), "handler_hatparts_menu")
    new iSkinsNum = g_eHatData[iHatId][HAT_SKINS_NUM]

    for (new i; i < iSkinsNum; i++)
        menu_additem(iMenu, g_eHatData[iHatId][HAT_PARTS_NAMES][i * NAME_LEN])
    set_menu_common_prop(iMenu, iPlayer)
    
    menu_display(iPlayer, iMenu)
}

display_bodies_menu(iPlayer)
{
    new iHatId = g_ePlayerData[iPlayer][PLR_MENU_HATID]
    new iMenu = menu_create(fmt("Hat Model (\r%s\y)", g_eHatData[iHatId][HAT_NAME]), "handler_hatparts_menu")
    new iBodiesNum = g_eHatData[iHatId][HAT_BODIES_NUM]

    for (new i; i < iBodiesNum; i++)
        menu_additem(iMenu, g_eHatData[iHatId][HAT_PARTS_NAMES][i * NAME_LEN])
    set_menu_common_prop(iMenu, iPlayer)
    
    menu_display(iPlayer, iMenu)
}

public handler_hats_menu(iPlayer, iMenu, iItem)
{
    if (iItem == MENU_EXIT)
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    new iHatId = iItem // 0 = remove, дальше шапки по порядку

    // пункт «снять шапку»
    if (iHatId == 0)
    {
        set_hat(iPlayer, 0, iPlayer, 0)
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    // защита от некорректного id
    if (iHatId >= g_iTotalHats)
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    // проверка VIP
    if (!check_hat_access(iPlayer, iHatId))
    {
        client_print_color(iPlayer, print_team_red, "^4[%s] ^3%L", PLUGIN, iPlayer, "HAT_ONLY_VIP")
        menu_display(iPlayer, iMenu, iItem / 7)
        return PLUGIN_HANDLED
    }

    // проверка уровня
    if (!check_hat_level(iPlayer, iHatId))
    {
        new reqLevel = g_eHatData[iHatId][HAT_MIN_LEVEL]
        client_print_color(iPlayer, print_team_red,
            "^4[%s] ^3Шапка доступна с уровня %d.", PLUGIN, reqLevel)
        menu_display(iPlayer, iMenu, iItem / 7)
        return PLUGIN_HANDLED
    }

    new cTag = g_eHatData[iHatId][HAT_TAG]
    switch (cTag)
    {
        case 's':
        {
            g_ePlayerData[iPlayer][PLR_MENU_HATID] = iHatId
            menu_destroy(iMenu)
            display_skins_menu(iPlayer)
        }
        case 'b', 'c':
        {
            g_ePlayerData[iPlayer][PLR_MENU_HATID] = iHatId
            menu_destroy(iMenu)
            display_bodies_menu(iPlayer)
        }
        default:
        {
            new iPartId
            if (cTag == 't')
                iPartId = get_member(iPlayer, m_iTeam) == 2
            set_hat(iPlayer, iHatId, iPlayer, iPartId)
            menu_display(iPlayer, iMenu, iItem / 7)
        }
    }

    return PLUGIN_HANDLED
}

public handler_hatparts_menu(iPlayer, iMenu, iItem)
{
    if (iItem == MENU_EXIT)
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    new iHatId = g_ePlayerData[iPlayer][PLR_MENU_HATID]

    // на всякий случай — проверяем уровень и VIP
    if (!check_hat_access(iPlayer, iHatId) || !check_hat_level(iPlayer, iHatId))
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    set_hat(iPlayer, iHatId, iPlayer, iItem)
    menu_display(iPlayer, iMenu, iItem / 7)
    return PLUGIN_HANDLED
}

set_menu_common_prop(iMenu, iLangId)
{
    menu_setprop(iMenu, MPROP_BACKNAME, fmt("%L", iLangId, "HAT_ITEM_PREV"))
    menu_setprop(iMenu, MPROP_NEXTNAME, fmt("%L", iLangId, "HAT_ITEM_NEXT"))
    menu_setprop(iMenu, MPROP_EXITNAME, fmt("%L", iLangId, "HAT_ITEM_EXIT"))
}

// =====================================================
// Логика шапок
// =====================================================
remove_hat(iPlayer)
{
    new iHatEnt = g_ePlayerData[iPlayer][PLR_HAT_ENT]
    if (iHatEnt)
        set_entvar(iHatEnt, var_flags, FL_KILLME)
    g_ePlayerData[iPlayer][PLR_HAT_ENT] = 0
    g_ePlayerData[iPlayer][PLR_HAT_ID] = 0
}

set_hat(iPlayer, iHatId, iSender, iPartId=0)
{
    static szKey[24]
    new iFwdReturn = PLUGIN_CONTINUE
    
    if (!check_hat_access(iPlayer, iHatId))
    {
        client_print_color(iSender, print_team_red, "^4[%s] ^3%L", PLUGIN, iSender, "HAT_ONLY_VIP")
        return NULLENT
    }
    
    // проверку уровня тут можно пропустить, чтобы амин через amx_givehat мог выдать любую
    // если нужно, можно добавить check_hat_level()

    if (iHatId == 0)
    {
        remove_hat(iPlayer)
        client_print_color(iSender, print_team_red, "^4[%s] ^3%L", PLUGIN, iSender, "HAT_REMOVE")

        ExecuteForward(g_fwChangeHat, iFwdReturn, iPlayer, 0)

        get_user_authid(iPlayer, szKey, charsmax(szKey))
        nvault_set(g_iVaultHats, szKey, "!NULL|0")
        return NULLENT
    }

    new iHatEnt = g_ePlayerData[iPlayer][PLR_HAT_ENT]
    
    if (is_nullent(iHatEnt))
    {
        iHatEnt = rg_create_entity("info_target", true)
        if (is_nullent(iHatEnt))
            return NULLENT
                                            
        set_entvar(iHatEnt, var_movetype, MOVETYPE_FOLLOW)
        set_entvar(iHatEnt, var_aiment, iPlayer)
        set_entvar(iHatEnt, var_rendermode, kRenderNormal)
        set_entvar(iHatEnt, var_renderamt, 0.0)
    }

    ExecuteForward(g_fwChangeHat, iFwdReturn, iPlayer, iHatEnt)	
    g_ePlayerData[iPlayer][PLR_HAT_ID] = iHatId
        
    engfunc(EngFunc_SetModel, iHatEnt, fmt("%s/%s", HATS_PATH, g_eHatData[iHatId][HAT_MODEL]))
    
    new iSkin, iBody
    new cTag = g_eHatData[iHatId][HAT_TAG]

    switch (cTag)
    {
        case 's': iSkin = iPartId < g_eHatData[iHatId][HAT_SKINS_NUM] ? iPartId : 0
        case 'b': iBody = iPartId < g_eHatData[iHatId][HAT_BODIES_NUM] ? iPartId : 0
        case 'c', 't':
        {
            iSkin = iPartId < g_eHatData[iHatId][HAT_SKINS_NUM] ? iPartId : 0
            iBody = iPartId < g_eHatData[iHatId][HAT_BODIES_NUM] ? iPartId : 0
        }
    }
    
    switch (cTag)
    {
        case 's': client_print_color(iSender, print_team_red, CHAT_SET_HAT_FORMAT,
            PLUGIN, iSender, "HAT_SET", g_eHatData[iHatId][HAT_PARTS_NAMES][iSkin * NAME_LEN])

        case 'b', 'c': client_print_color(iSender, print_team_red, CHAT_SET_HAT_FORMAT,
            PLUGIN, iSender, "HAT_SET", g_eHatData[iHatId][HAT_PARTS_NAMES][iBody * NAME_LEN])

        default: client_print_color(iSender, print_team_red, CHAT_SET_HAT_FORMAT,
            PLUGIN, iSender, "HAT_SET", g_eHatData[iHatId][HAT_NAME])
    }

    set_entvar(iHatEnt, var_skin, iSkin)
    set_entvar(iHatEnt, var_body, iBody)
    
    set_entvar(iHatEnt, var_sequence, iBody)
    set_entvar(iHatEnt, var_framerate, 1.0)
    set_entvar(iHatEnt, var_animtime, get_gametime())
                                
    get_user_authid(iPlayer, szKey, charsmax(szKey))
    nvault_set(g_iVaultHats, szKey, fmt("%s|%i", g_eHatData[iHatId][HAT_MODEL], iPartId))

    g_ePlayerData[iPlayer][PLR_HAT_ENT] = iHatEnt

    return iHatEnt
}

// =====================================================
// Загрузка шапок из INI (MODEL, NAME, LEVEL)
// =====================================================
load_hats(const szHatFile[])
{
    g_iTotalHats = 1

    new bool: bRes = load_hats_from_ini(szHatFile)

    if (bRes)
        server_print("[%s] Loaded %i hats from %s", PLUGIN, g_iTotalHats - 1, szHatFile)
    else
        server_print("[%s] Failed load %s", PLUGIN, szHatFile)
}

bool: load_hats_from_ini(const szHatFile[])
{
    if (!file_exists(szHatFile))
        return false

    new szLineData[192], iFile = fopen(szHatFile, "rt")
    new szCurrentFile[256], szHatModel[NAME_LEN], szHatName[NAME_LEN], szLevel[16]

    while (iFile && !feof(iFile))
    {
        fgets(iFile, szLineData, charsmax(szLineData))
        if (szLineData[0] == ';' || strlen(szLineData) < 7)
            continue

        // "model.mdl" "Name" LEVEL
        parse(szLineData,
            szHatModel, charsmax(szHatModel),
            szHatName,  charsmax(szHatName),
            szLevel,    charsmax(szLevel))

        formatex(szCurrentFile, charsmax(szCurrentFile), "%s/%s", HATS_PATH, szHatModel)

        if (!file_exists(szCurrentFile))
        {
            server_print("[%s] Failed to precache %s", PLUGIN, szCurrentFile)
            continue
        }

        new iReqLevel = str_to_num(szLevel)
        if (iReqLevel < 0) iReqLevel = 0

        copy(g_eHatData[g_iTotalHats][HAT_MODEL], NAME_LEN - 1, szHatModel)
        copy(g_eHatData[g_iTotalHats][HAT_NAME],  NAME_LEN - 1, szHatName)
        g_eHatData[g_iTotalHats][HAT_TAG]       = 0
        g_eHatData[g_iTotalHats][HAT_VIP_FLAG]  = 0
        g_eHatData[g_iTotalHats][HAT_SKINS_NUM] = 1
        g_eHatData[g_iTotalHats][HAT_BODIES_NUM]= 1
        g_eHatData[g_iTotalHats][HAT_MIN_LEVEL] = iReqLevel

        if (++g_iTotalHats == MAX_HATS)
        {
            server_print("[%s] Reached hat limit", PLUGIN)
            break
        }
    }

    if (iFile)
        fclose(iFile)
    return true
}

// =====================================================
// Помощники
// =====================================================
bool: check_hat_access(iPlayer, iHatId)
{
    return !g_eHatData[iHatId][HAT_VIP_FLAG] || (get_user_flags(iPlayer) & VIP_FLAG)
}

bool: check_hat_level(iPlayer, iHatId)
{
    new req = g_eHatData[iHatId][HAT_MIN_LEVEL]
    if (req <= 0) return true

    new lvl = hns_xp_get_level(iPlayer)
    return lvl >= req
}
