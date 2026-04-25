#include <amxmodx>
#include <reapi>
#include <hamsandwich>
#include <fakemeta>
#include <engine>

#include <hns_matchsystem>
#include <hns_xp_skills>

#define PLUGIN_NAME   "HNS Skill: Redie (PUB only)"
#define PLUGIN_VER    "1.0"
#define PLUGIN_AUTH   "cultura"

// ===== настройка скилла =====
#define SKILL_MIN_LEVEL   5
#define SKILL_NAME        "Redie"

// ===== ghost flags =====
new bool:g_bGhost[33];
new g_iSkillRedie = -1;

// CVAR'ы
new g_pEnable;
new g_pTabRefresh;
new g_pBlockPickup;

// TAB
new g_msgScoreAttrib;
const SCOREATTRIB_DEAD = 1;

#define TASK_TABREFRESH 91177
#define TASK_CHECKEND   92277

// =====================================================
// INIT
// =====================================================
public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VER, PLUGIN_AUTH);

    g_pEnable      = register_cvar("sc_skill_redie_enable", "1");
    g_pTabRefresh  = register_cvar("sc_skill_redie_tab_refresh", "1.0");
    g_pBlockPickup = register_cvar("sc_skill_redie_block_pickup", "1");

    // Регистрируем скилл: ТОЛЬКО PUB
    g_iSkillRedie = hns_skills_register(
        SKILL_NAME,
        SKILL_MIN_LEVEL,
        SKILL_MODE_PUB
    );

    // команды
    register_clcmd("say /redie",      "Cmd_Redie");
    register_clcmd("say_team /redie", "Cmd_Redie");
    register_clcmd("say /r",          "Cmd_Redie");
    register_clcmd("say_team /r",     "Cmd_Redie");

    register_clcmd("say /unredie",      "Cmd_UnRedie");
    register_clcmd("say_team /unredie", "Cmd_UnRedie");
    register_clcmd("say /ur",           "Cmd_UnRedie");
    register_clcmd("say_team /ur",      "Cmd_UnRedie");

    // block "drop" for ghosts
    register_clcmd("drop", "Cmd_Drop");

    // damage block
    RegisterHam(Ham_TakeDamage, "player", "Ham_TakeDamage_Pre", false);

    // spawn / death
    RegisterHookChain(RG_CBasePlayer_Spawn,  "RG_Spawn_Post", true);
    RegisterHookChain(RG_CBasePlayer_Killed, "RG_Killed_Post", true);

    // block buttons (no attacks/use/reload)
    register_forward(FM_CmdStart, "FM_CmdStart_Pre", false);

    // restart / newround safety
    register_event("HLTV", "Ev_NewRound", "a", "1=0", "2=0");
    register_event("TextMsg", "Ev_Restart", "a", "2=#Game_Commencing", "2=#Game_will_restart_in");
    register_logevent("LE_RoundStart", 2, "1=Round_Start");

    // block weapon pickups via touch
    register_touch("weaponbox", "player", "TouchBlockPickup");
    register_touch("armoury_entity", "player", "TouchBlockPickup");

    g_msgScoreAttrib = get_user_msgid("ScoreAttrib");

    StartTabRefreshTask();
    ResetAllHard();
}

// =====================================================
// HNS FORWARDS (сбросы)
// =====================================================
public hns_match_started()          ResetAllHard();
public hns_match_canceled()         ResetAllHard();
public hns_match_finished(iWinTeam) ResetAllHard();

public hns_round_start() ResetAllHard();
public hns_round_end()   { /* ничего */ }

// engine restarts
public Ev_NewRound()   ResetAllHard();
public Ev_Restart()    ResetAllHard();
public LE_RoundStart() ResetAllHard();

// =====================================================
// MODE + SKILL CHECK (ТОЛЬКО PUB)
// =====================================================
bool:IsPub()
{
    return (hns_get_mode() == MODE_PUB);
}

bool:CanUseRedie(id)
{
    if (!get_pcvar_num(g_pEnable)) return false;
    if (!IsPub()) return false;
    if (g_iSkillRedie < 0) return false;

    // скилл должен быть включён в /skills
    if (!hns_skills_is_enabled(id, g_iSkillRedie)) return false;

    return true;
}

// =====================================================
// COMMANDS
// =====================================================
public Cmd_Redie(id)
{
    if (!is_user_connected(id))
        return PLUGIN_HANDLED;

    if (!IsPub())
    {
        client_print(id, print_chat, "[HNS] /redie for PUB.");
        return PLUGIN_HANDLED;
    }

    if (!CanUseRedie(id))
    {
        client_print(id, print_chat, "[HNS] Включи скилл '%s' в /skills (доступ с %d lvl).", SKILL_NAME, SKILL_MIN_LEVEL);
        return PLUGIN_HANDLED;
    }

    if (is_user_alive(id))
    {
        client_print(id, print_chat, "[HNS] /redie можно использовать только после смерти.");
        return PLUGIN_HANDLED;
    }

    if (g_bGhost[id])
    {
        client_print(id, print_chat, "[HNS] Ты уже в режиме призрака.");
        return PLUGIN_HANDLED;
    }

    g_bGhost[id] = true;
    rg_round_respawn(id);

    client_print(id, print_chat, "[HNS] /ur чтобы выйти.");
    return PLUGIN_HANDLED;
}

public Cmd_UnRedie(id)
{
    if (!is_user_connected(id))
        return PLUGIN_HANDLED;

    if (!g_bGhost[id])
    {
        client_print(id, print_chat, "[HNS] Redie уже выключен.");
        return PLUGIN_HANDLED;
    }

    ResetGhost(id);
    client_print(id, print_chat, "[HNS] Redie выключен.");
    return PLUGIN_HANDLED;
}

public Cmd_Drop(id)
{
    if (1 <= id && id <= MaxClients && g_bGhost[id])
        return PLUGIN_HANDLED;

    return PLUGIN_CONTINUE;
}

// =====================================================
// SPAWN / DEATH
// =====================================================
public RG_Spawn_Post(const id)
{
    if (!is_user_alive(id))
        return HC_CONTINUE;

    // если игрок не ghost — гарантируем норм состояние (фикс невидимости)
    if (!g_bGhost[id])
    {
        RestoreNormal(id);
        ForceTabDead(id, false);
        return HC_CONTINUE;
    }

    // ghost но условия не подходят (не PUB или скилл отключили) — выключаем
    if (!CanUseRedie(id))
    {
        ResetGhost(id);
        return HC_CONTINUE;
    }

    // ghost spawn
    MakeGhost(id);
    ForceTabDead(id, true);

    return HC_CONTINUE;
}

public RG_Killed_Post(const victim, const killer, const shouldgib)
{
    if (victim >= 1 && victim <= MaxClients)
    {
        if (g_bGhost[victim])
        {
            g_bGhost[victim] = false;
            ForceTabDead(victim, false);
        }
    }

    ScheduleNaturalRoundFix();
}

// =====================================================
// DAMAGE BLOCK
// =====================================================
public Ham_TakeDamage_Pre(victim, inflictor, attacker, Float:damage, damage_bits)
{
    if (victim >= 1 && victim <= MaxClients && g_bGhost[victim])
        return HAM_SUPERCEDE;

    if (attacker >= 1 && attacker <= MaxClients && g_bGhost[attacker])
        return HAM_SUPERCEDE;

    return HAM_IGNORED;
}

// =====================================================
// BUTTONS BLOCK
// =====================================================
public FM_CmdStart_Pre(id, uc_handle, seed)
{
    if (!(1 <= id && id <= MaxClients))
        return FMRES_IGNORED;

    if (!g_bGhost[id] || !is_user_alive(id))
        return FMRES_IGNORED;

    new buttons = get_uc(uc_handle, UC_Buttons);
    buttons &= ~(IN_ATTACK | IN_ATTACK2 | IN_USE | IN_RELOAD);
    set_uc(uc_handle, UC_Buttons, buttons);

    set_member(id, m_flNextAttack, get_gametime() + 0.15);
    return FMRES_HANDLED;
}

// =====================================================
// PICKUP BLOCK
// =====================================================
public TouchBlockPickup(ent, id)
{
    if (!get_pcvar_num(g_pBlockPickup))
        return PLUGIN_CONTINUE;

    if (!(1 <= id && id <= MaxClients))
        return PLUGIN_CONTINUE;

    if (!g_bGhost[id])
        return PLUGIN_CONTINUE;

    return PLUGIN_HANDLED;
}

// =====================================================
// GHOST LOGIC
// =====================================================
MakeGhost(const id)
{
    if (!is_user_alive(id))
        return;

    set_entvar(id, var_solid, SOLID_NOT);
    set_entvar(id, var_takedamage, DAMAGE_NO);

    set_entvar(id, var_rendermode, kRenderTransAlpha);
    set_entvar(id, var_renderamt, 0.0);

    rg_set_user_footsteps(id, true);

    rg_remove_all_items(id);
    rg_give_item(id, "weapon_knife");
}

ResetGhost(const id)
{
    g_bGhost[id] = false;

    if (is_user_alive(id))
        RestoreNormal(id);

    ForceTabDead(id, false);
}

RestoreNormal(const id)
{
    set_entvar(id, var_solid, SOLID_SLIDEBOX);
    set_entvar(id, var_takedamage, DAMAGE_AIM);

    set_entvar(id, var_rendermode, kRenderNormal);
    set_entvar(id, var_renderamt, 255.0);

    rg_set_user_footsteps(id, false);
}

// =====================================================
// NATURAL ROUND END FIX
// =====================================================
ScheduleNaturalRoundFix()
{
    if (task_exists(TASK_CHECKEND))
        return;

    set_task(0.15, "Task_NaturalRoundFix", TASK_CHECKEND);
}

public Task_NaturalRoundFix()
{
    if (!IsPub())
        return;

    new aliveT_real = 0, aliveCT_real = 0;
    new aliveT_ghost = 0, aliveCT_ghost = 0;

    for (new id = 1; id <= MaxClients; id++)
    {
        if (!is_user_alive(id))
            continue;

        new TeamName:team = TeamName:rg_get_user_team(id);

        if (g_bGhost[id])
        {
            if (team == TEAM_TERRORIST) aliveT_ghost++;
            else if (team == TEAM_CT)  aliveCT_ghost++;
            continue;
        }

        if (team == TEAM_TERRORIST) aliveT_real++;
        else if (team == TEAM_CT)  aliveCT_real++;
    }

    if (aliveT_real == 0 && aliveT_ghost > 0 && aliveCT_real > 0)
    {
        KillTeamGhosts(TEAM_TERRORIST);
        return;
    }

    if (aliveCT_real == 0 && aliveCT_ghost > 0 && aliveT_real > 0)
    {
        KillTeamGhosts(TEAM_CT);
        return;
    }

    if (aliveT_real == 0 && aliveCT_real == 0 && (aliveT_ghost + aliveCT_ghost) > 0)
    {
        KillTeamGhosts(TEAM_TERRORIST);
        KillTeamGhosts(TEAM_CT);
        return;
    }
}

KillTeamGhosts(TeamName:teamNeed)
{
    for (new id = 1; id <= MaxClients; id++)
    {
        if (!is_user_alive(id))
            continue;

        if (!g_bGhost[id])
            continue;

        if (TeamName:rg_get_user_team(id) != teamNeed)
            continue;

        set_entvar(id, var_takedamage, DAMAGE_AIM);
        user_kill(id, 1);
    }
}

// =====================================================
// TAB dead flag
// =====================================================
ForceTabDead(id, bool:dead)
{
    if (!g_msgScoreAttrib)
        return;

    message_begin(MSG_ALL, g_msgScoreAttrib);
    write_byte(id);
    write_byte(dead ? SCOREATTRIB_DEAD : 0);
    message_end();
}

// =====================================================
// TAB refresh task
// =====================================================
StartTabRefreshTask()
{
    if (task_exists(TASK_TABREFRESH))
        remove_task(TASK_TABREFRESH);

    new Float:sec = get_pcvar_float(g_pTabRefresh);
    if (sec < 0.2) sec = 0.2;

    set_task(sec, "Task_RefreshTab", TASK_TABREFRESH, _, _, "b");
}

public Task_RefreshTab()
{
    if (!get_pcvar_num(g_pEnable))
        return;

    if (!IsPub())
        return;

    for (new id = 1; id <= MaxClients; id++)
    {
        if (g_bGhost[id] && is_user_connected(id) && is_user_alive(id))
            ForceTabDead(id, true);
    }
}

// =====================================================
// HARD RESET
// =====================================================
ResetAllHard()
{
    if (task_exists(TASK_CHECKEND))
        remove_task(TASK_CHECKEND);

    for (new id = 1; id <= MaxClients; id++)
    {
        if (!is_user_connected(id))
            continue;

        g_bGhost[id] = false;
        ForceTabDead(id, false);

        if (is_user_alive(id))
            RestoreNormal(id);
    }
}

// =====================================================
// DISCONNECT
// =====================================================
public client_disconnected(id)
{
    if (1 <= id && id <= MaxClients)
        g_bGhost[id] = false;
}
