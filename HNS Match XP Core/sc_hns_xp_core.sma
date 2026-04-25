#include <amxmodx> 
#include <nvault>
#include <hns_matchsystem>
#include <fakemeta>

#define PLUGIN_NAME        "HNS Match XP Core"
#define PLUGIN_VERSION     "0.4"
#define PLUGIN_AUTHOR      "cultura"

#define MAX_LEVEL          100
#define LEVEL_XP_BASE      100

#define HUD_UPDATE_TIME        2.0
#define TIME_TRACK_INTERVAL    60.0

// ------------- ОСНОВНЫЕ ДАННЫЕ ИГРОКА -------------

new g_iXP[33];
new g_iLevel[33];
new g_iPlayTimeSec[33];

// *** КЭШИ ДЛЯ ОПТИМИЗАЦИИ ***
new g_iXPForLevel[MAX_LEVEL + 1];    // Предсчитанные XP для каждого уровня
new g_iCachedMode = -1;             // Кэш текущего режима
new Float:g_flModeCacheTime = 0.0;  // Время последней проверки режима

new g_hVault;
new g_pCvarHudEnable;
new g_fwdLevelUp;

// ------------- MOVE SKILL -------------

#define MOVE_TYPE_BHOP   1
#define MOVE_TYPE_SGS    2
#define MOVE_TYPE_DDRUN  3

new Float:g_flMoveSkill[33];
new g_iMoveSessions[33];

forward ms_session_bhop(id, iCount, Float:flPercent, Float:flAVGSpeed);
forward ms_session_sgs(id, iCount, Float:flPercent, Float:flAVGSpeed);
forward ms_session_ddrun(id, iCount, Float:flPercent, Float:flAVGSpeed);

// ==================================================
// plugin_init / natives
// ==================================================

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    // *** ПРЕДСЧИТАЕМ ВСЕ УРОВНИ ОДИН РАЗ ***
    for (new l = 1; l <= MAX_LEVEL; l++)
    {
        g_iXPForLevel[l] = (l - 1) * l * LEVEL_XP_BASE / 2;
    }

    g_hVault = nvault_open("hns_xp_system");
    if (g_hVault == INVALID_HANDLE)
    {
        log_amx("[HNS XP] ERROR: Can't open nVault hns_xp_system");
    }

    g_pCvarHudEnable = register_cvar("hns_xp_hud_enable", "1");

    set_task(HUD_UPDATE_TIME, "Task_ShowHUD", _, _, _, "b");
    set_task(TIME_TRACK_INTERVAL, "Task_TrackPlayTime", _, _, _, "b");

    register_clcmd("say /xp",       "Cmd_ShowXPMenu");
    register_clcmd("say_team /xp",  "Cmd_ShowXPMenu");
    register_clcmd("say /rank",     "Cmd_ShowXPMenu");
    register_clcmd("say_team /rank","Cmd_ShowXPMenu");

    g_fwdLevelUp = CreateMultiForward("hns_xp_levelup",
                                      ET_CONTINUE,
                                      FP_CELL, FP_CELL, FP_CELL);
}

public plugin_natives()
{
    register_native("hns_xp_get_xp",       "Native_GetXP");
    register_native("hns_xp_get_level",    "Native_GetLevel");
    register_native("hns_xp_get_playtime", "Native_GetPlayTime");
    register_native("hns_xp_add_xp",       "Native_AddXP");
}

// ==================================================
//  Нативы
// ==================================================

public Native_GetXP(plugin, params)
{
    new id = get_param(1);
    if (id < 1 || id > 32) return 0;
    return g_iXP[id];
}

public Native_GetLevel(plugin, params)
{
    new id = get_param(1);
    if (id < 1 || id > 32) return 0;
    return g_iLevel[id];
}

public Native_GetPlayTime(plugin, params)
{
    new id = get_param(1);
    if (id < 1 || id > 32) return 0;
    return g_iPlayTimeSec[id];
}

public Native_AddXP(plugin, params)
{
    if (params < 2)
        return 0;

    new id = get_param(1);
    new amount = get_param(2);

    if (id < 1 || id > 32)
        return 0;

    GiveXP(id, amount);
    return 1;
}

// ==================================================
//  Жизненный цикл игрока
// ==================================================

public client_authorized(id)
{
    LoadPlayerData(id);
    g_flMoveSkill[id]   = 0.0;
    g_iMoveSessions[id] = 0;
}

public client_disconnected(id)
{
    SavePlayerData(id);

    g_iXP[id]          = 0;
    g_iLevel[id]       = 0;
    g_iPlayTimeSec[id] = 0;

    g_flMoveSkill[id]   = 0.0;
    g_iMoveSessions[id] = 0;
}

public plugin_end()
{
    for (new id = 1; id <= 32; id++)
    {
        if (is_user_connected(id))
        {
            SavePlayerData(id);
        }
    }

    if (g_hVault != INVALID_HANDLE)
    {
        nvault_close(g_hVault);
    }
}

// ==================================================
//  *** ОПТИМИЗИРОВАННЫЙ КЭШ РЕЖИМА ***
// ==================================================

stock GetCachedMode()
{
    new Float:now = get_gametime();
    
    // Обновляем кэш режима раз в 0.5 сек
    if (now - g_flModeCacheTime > 0.5)
    {
        g_iCachedMode = hns_get_mode();
        g_flModeCacheTime = now;
    }
    
    return g_iCachedMode;
}

stock bool:IsValidGameMode()
{
    new mode = GetCachedMode();
    return (mode == MODE_DM || mode == MODE_ZM || mode == MODE_PUB);
}

// ==================================================
//  Учёт времени (без XP)
// ==================================================

public Task_TrackPlayTime()
{
    if (!IsValidGameMode())
        return;

    new players[32], num, id;
    get_players(players, num, "ch");

    for (new i = 0; i < num; i++)
    {
        id = players[i];

        new team = get_user_team(id);
        if (team == 1 || team == 2)
        {
            g_iPlayTimeSec[id] += floatround(TIME_TRACK_INTERVAL);
        }
    }
}

// ==================================================
//  HUD (оптимизировано)
// ==================================================

stock get_hud_target(id)
{
    if (!is_user_connected(id))
        return 0;

    if (is_user_alive(id))
        return id;

    new specmode = pev(id, pev_iuser1);
    if (specmode != 3)
    {
        new target = pev(id, pev_iuser2);
        if (1 <= target <= 32 && is_user_connected(target))
            return target;
    }

    return 0;
}

public Task_ShowHUD()
{
    if (!get_pcvar_num(g_pCvarHudEnable))
        return;

    if (!IsValidGameMode())
        return;

    new players[32], num, id;
    get_players(players, num, "ch");

    for (new i = 0; i < num; i++)
    {
        id = players[i];
        if (!is_user_connected(id))
            continue;

        new target = get_hud_target(id);
        if (!target)
            continue;

        ShowPlayerHUD(id, target);
    }
}

ShowPlayerHUD(viewer, target)
{
    if (!is_user_connected(target))
        return;

    new name[32];
    get_user_name(target, name, charsmax(name));

    new level = g_iLevel[target];
    if (level <= 0) level = 1;

    new rankName[32];
    GetRankName(level, rankName, charsmax(rankName));

    new xp    = g_iXP[target];
    new hours = g_iPlayTimeSec[target] / 3600;

    new Float:skillVal = g_flMoveSkill[target];
    new skillLabel[16];
    get_move_skill_label(skillVal, skillLabel, charsmax(skillLabel));

    set_hudmessage(0, 255, 0, 0.01, 0.15, 0, 0.0,
                   HUD_UPDATE_TIME + 0.1, 0.0, 0.0, -1);

    if (level >= MAX_LEVEL)
    {
        show_hudmessage(viewer,
            "Name: %s^nRank: %s [L%d MAX]^nXP: %d^nTime: %d h^nSkill: %s (%.0f)",
            name, rankName, level, xp, hours, skillLabel, skillVal);
        return;
    }

    // *** КЭШИРУЕМ ВЫЧИСЛЕНИЯ XP ***
    new nextLevel = level + 1;
    new xpNeedNext = g_iXPForLevel[nextLevel];
    new xpForCurrentLevel = g_iXPForLevel[level];
    new xpInCurrent = xp - xpForCurrentLevel;
    if (xpInCurrent < 0) xpInCurrent = 0;

    new xpToNext = xpNeedNext - xpForCurrentLevel;
    if (xpToNext <= 0) xpToNext = 1;

    show_hudmessage(viewer,
        "Name: %s^nRank: %s [L%d]^nXP: %d / %d^nTime: %d h^nSkill: %s (%.0f)",
        name, rankName, level,
        xpInCurrent, xpToNext,
        hours,
        skillLabel, skillVal);
}

// ==================================================
//  МЕНЮ / КОМАНДЫ
// ==================================================

public Cmd_ShowXPMenu(id)
{
    if (!is_user_connected(id))
        return PLUGIN_HANDLED;

    new menu = menu_create("\yHNS XP System", "XPMenu_Handler");

    new szItem[128];
    new level = (g_iLevel[id] > 0) ? g_iLevel[id] : 1;

    new rankName[32];
    GetRankName(level, rankName, charsmax(rankName));

    new xp    = g_iXP[id];
    new hours = g_iPlayTimeSec[id] / 3600;

    formatex(szItem, charsmax(szItem), "\wВаш статус: \y%s \w(L%d)", rankName, level);
    menu_additem(menu, szItem);

    if (level >= MAX_LEVEL)
    {
        formatex(szItem, charsmax(szItem), "\wОпыт: \y%d \r(MAX)", xp);
    }
    else
    {
        new nextLevel = level + 1;
        new xpNeedNext = g_iXPForLevel[nextLevel];
        new xpForCurrentLevel = g_iXPForLevel[level];
        new xpInCurrent = xp - xpForCurrentLevel;
        if (xpInCurrent < 0) xpInCurrent = 0;
        new xpToNext = xpNeedNext - xpForCurrentLevel;
        if (xpToNext <= 0) xpToNext = 1;

        formatex(szItem, charsmax(szItem), "\wОпыт: \y%d\w/\y%d", xpInCurrent, xpToNext);
    }
    menu_additem(menu, szItem);

    formatex(szItem, charsmax(szItem), "\wВремя на сервере: \y%d h", hours);
    menu_additem(menu, szItem);

    menu_addtext(menu, "^n\yСкиллы и ножи будут отдельными модулями.");
    menu_display(id, menu);

    return PLUGIN_HANDLED;
}

public XPMenu_Handler(id, menu, item)
{
    if (item == MENU_EXIT)
    {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

// ==================================================
//  *** ОПТИМИЗИРОВАННАЯ ЛОГИКА XP/LEVEL (БИНАРНЫЙ ПОИСК) ***
// ==================================================

GiveXP(id, amount)
{
    if (!is_user_connected(id))
        return;

    if (amount == 0)
        return;

    new oldLevel = g_iLevel[id];

    g_iXP[id] += amount;
    if (g_iXP[id] < 0) g_iXP[id] = 0;

    UpdatePlayerLevel(id);

    new newLevel = g_iLevel[id];

    if (newLevel > oldLevel)
    {
        //client_print(id, print_chat, "[XP] Вы получили новый уровень! (%d -> %d)", oldLevel, newLevel);

        if (g_fwdLevelUp)
        {
            ExecuteForward(g_fwdLevelUp, _, id, oldLevel, newLevel);
        }
    }
}

// *** БИНАРНЫЙ ПОИСК (вместо линейного) O(log n) ***
UpdatePlayerLevel(id)
{
    new xp = g_iXP[id];
    new lo = 1, hi = MAX_LEVEL, level = 1;
    
    while (lo <= hi)
    {
        new mid = (lo + hi) / 2;
        if (xp >= g_iXPForLevel[mid])
        {
            level = mid;
            lo = mid + 1;
        }
        else
        {
            hi = mid - 1;
        }
    }
    
    g_iLevel[id] = level;
}

GetRankName(level, szOut[], len)
{
    if      (level < 5)   copy(szOut, len, "Newbie");
    else if (level < 10)  copy(szOut, len, "Rookie");
    else if (level < 20)  copy(szOut, len, "Skilled");
    else if (level < 30)  copy(szOut, len, "Pro");
    else if (level < 40)  copy(szOut, len, "Elite");
    else if (level < 60)  copy(szOut, len, "Master");
    else if (level < 80)  copy(szOut, len, "Legend");
    else                  copy(szOut, len, "Myth");
}

// ==================================================
//  nVault
// ==================================================

GetPlayerKey(id, szKey[], len)
{
    new authid[32];
    get_user_authid(id, authid, charsmax(authid));

    if (equali(authid, "STEAM_ID_LAN") ||
        equali(authid, "VALVE_ID_LAN") ||
        equali(authid, "STEAM_ID_PENDING"))
    {
        new ip[32];
        get_user_ip(id, ip, charsmax(ip), 1);
        formatex(szKey, len, "IP_%s", ip);
    }
    else
    {
        copy(szKey, len, authid);
    }
}

LoadPlayerData(id)
{
    if (is_user_bot(id) || is_user_hltv(id))
        return;

    if (g_hVault == INVALID_HANDLE)
        return;

    new auth[64];
    GetPlayerKey(id, auth, charsmax(auth));

    new data[64], xpStr[16], timeStr[16];
    if (!nvault_get(g_hVault, auth, data, charsmax(data)))
    {
        g_iXP[id]          = 0;
        g_iLevel[id]       = 1;
        g_iPlayTimeSec[id] = 0;
        return;
    }

    parse(data, xpStr, charsmax(xpStr), timeStr, charsmax(timeStr));

    g_iXP[id]          = str_to_num(xpStr);
    g_iPlayTimeSec[id] = str_to_num(timeStr);

    if (g_iXP[id] < 0) g_iXP[id] = 0;
    if (g_iPlayTimeSec[id] < 0) g_iPlayTimeSec[id] = 0;

    UpdatePlayerLevel(id);
}

SavePlayerData(id)
{
    if (is_user_bot(id) || is_user_hltv(id))
        return;

    if (g_hVault == INVALID_HANDLE)
        return;

    new auth[64];
    GetPlayerKey(id, auth, charsmax(auth));

    new data[64];
    formatex(data, charsmax(data), "%d %d", g_iXP[id], g_iPlayTimeSec[id]);

    nvault_set(g_hVault, auth, data);
}

// ==================================================
//  MOVE SKILL
// ==================================================

stock Float:clamp_float(Float:x, Float:min, Float:max)
{
    if (x < min) return min;
    if (x > max) return max;
    return x;
}

stock get_move_skill_label(Float:skill, szLabel[], len)
{
    if (skill < 1.0)
        copy(szLabel, len, "none");
    else if (skill < 200.0)
        copy(szLabel, len, "rookie");
    else if (skill < 400.0)
        copy(szLabel, len, "casual");
    else if (skill < 600.0)
        copy(szLabel, len, "skilled");
    else if (skill < 800.0)
        copy(szLabel, len, "pro");
    else
        copy(szLabel, len, "godlike");
}

stock update_move_skill(id, moveType, iCount, Float:flPercent, Float:flAVGSpeed)
{
    if (!is_user_connected(id) || iCount <= 0)
        return;

    new Float:qPerfect = clamp_float(flPercent / 100.0, 0.0, 1.0);
    new Float:lengthFactor = clamp_float(float(iCount) / 20.0, 0.0, 1.0);

    new Float:minSpeed, Float:maxSpeed;
    switch (moveType)
    {
        case MOVE_TYPE_BHOP:
        {
            minSpeed = 240.0;
            maxSpeed = 280.0;
        }
        case MOVE_TYPE_SGS:
        {
            minSpeed = 260.0;
            maxSpeed = 340.0;
        }
        case MOVE_TYPE_DDRUN:
        {
            minSpeed = 260.0;
            maxSpeed = 320.0;
        }
        default:
        {
            minSpeed = 240.0;
            maxSpeed = 280.0;
        }
    }

    new Float:speedNorm =
        clamp_float((flAVGSpeed - minSpeed) / (maxSpeed - minSpeed), 0.0, 1.0);

    new Float:score01 =
        0.60 * qPerfect +
        0.25 * speedNorm +
        0.15 * lengthFactor;

    score01 = clamp_float(score01, 0.0, 1.0);

    new Float:sessionSkill = score01 * 1000.0;

    if (g_iMoveSessions[id] == 0)
    {
        g_flMoveSkill[id] = sessionSkill;
    }
    else
    {
        g_flMoveSkill[id] =
            g_flMoveSkill[id] * 0.8 + sessionSkill * 0.2;
    }

    g_iMoveSessions[id]++;
}

public ms_session_bhop(id, iCount, Float:flPercent, Float:flAVGSpeed)
{
    update_move_skill(id, MOVE_TYPE_BHOP, iCount, flPercent, flAVGSpeed);
}

public ms_session_sgs(id, iCount, Float:flPercent, Float:flAVGSpeed)
{
    update_move_skill(id, MOVE_TYPE_SGS, iCount, flPercent, flAVGSpeed);
}

public ms_session_ddrun(id, iCount, Float:flPercent, Float:flAVGSpeed)
{
    update_move_skill(id, MOVE_TYPE_DDRUN, iCount, flPercent, flAVGSpeed);
}