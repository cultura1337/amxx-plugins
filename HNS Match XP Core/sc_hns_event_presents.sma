#include <amxmodx>
#include <amxmisc>
#include <engine>
#include <fakemeta>
#include <reapi>
#include <hns_matchsystem>
#include <hns_xp_core>

#define PLUGIN  "HNS EVENT: TAKE PRESENTS"
#define VERSION "1.1"
#define AUTHOR  "cultura"

#define MAX_PRESENTS 32
#define MAX_PLAYERS  32

#define PRESENT_SMALL   1
#define PRESENT_MEDIUM  2
#define PRESENT_BIG     3

#define HUD_RIGHT  4
#define HUD_CENTER 5

new bool:g_bEventActive
new bool:g_bEventPlanned

new g_iCollected[33]
new g_iHudSync

new g_pAutoEvent
new g_pEventChance
new g_pMinRounds

new g_iRoundsAfterEvent

// ================= INIT =================

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR)

    register_concmd("amx_event", "CmdEvent", ADMIN_RCON)

    register_logevent("OnRoundStart", 2, "1=Round_Start")
    register_logevent("OnRoundEnd",   2, "1=Round_End")

    g_pAutoEvent   = register_cvar("hns_event_auto",   "1")
    g_pEventChance = register_cvar("hns_event_chance", "5") // 1 из N
    g_pMinRounds   = register_cvar("hns_event_delay",  "3")

    g_iHudSync = CreateHudSyncObj()
}

public plugin_precache()
{
    precache_model("models/xmaspres1.mdl")
    precache_model("models/xmaspres2.mdl")

    precache_sound("subcultura/jingle.wav")
    precache_sound("subcultura/unwrapping.wav")
}

// ================= COMMAND =================

public CmdEvent(id, lvl, cid)
{
    if (!cmd_access(id, lvl, cid, 1))
        return PLUGIN_HANDLED

    g_bEventPlanned = true
    console_print(id, "[EVENT] TAKE PRESENTS will start next round")
    return PLUGIN_HANDLED
}

// ================= ROUND =================

public OnRoundStart()
{
    if (hns_get_mode() != MODE_PUB)
        return

    g_iRoundsAfterEvent++

    if (g_bEventActive)
        return

    if (get_playersnum() < 2)
        return

    if (g_bEventPlanned ||
        (get_pcvar_num(g_pAutoEvent)
        && g_iRoundsAfterEvent >= get_pcvar_num(g_pMinRounds)
        && random_num(1, get_pcvar_num(g_pEventChance)) == 1))
    {
        g_bEventActive  = true
        g_bEventPlanned = false
        g_iRoundsAfterEvent = 0

        arrayset(g_iCollected, 0, sizeof g_iCollected)

        set_task(15.0, "EventStart")   // старт через 15 сек
        set_task(15.0, "SpawnPresents")
    }
}

public EventStart()
{
    if (!g_bEventActive)
        return

    client_cmd(0, "spk subcultura/jingle.wav")

    set_hudmessage(255, 140, 0, -1.0, 0.30, 1, 5.0, 5.0, 0.1, 0.2, HUD_CENTER)
    show_hudmessage(0, "EVENT: TAKE PRESENTS")
}

public OnRoundEnd()
{
    if (!g_bEventActive)
        return

    GiveRewards()
    RemovePresents()

    g_bEventActive = false
}

// ================= PRESENTS =================

public SpawnPresents()
{
    if (!g_bEventActive)
        return

    new Float:origin[3]

    for (new i = 0; i < MAX_PRESENTS; i++)
    {
        origin[0] = random_float(-900.0, 900.0)
        origin[1] = random_float(-900.0, 900.0)
        origin[2] = random_float(200.0, 350.0)

        CreatePresent(origin)
    }
}

CreatePresent(Float:origin[3])
{
    new ent = create_entity("info_target")
    if (!ent) return

    entity_set_string(ent, EV_SZ_classname, "event_present")

    new rnd = random(100)
    new type = (rnd < 50) ? PRESENT_SMALL : (rnd < 85) ? PRESENT_MEDIUM : PRESENT_BIG
    entity_set_int(ent, EV_INT_iuser1, type)

    entity_set_model(ent, random_num(0,1) ? "models/xmaspres1.mdl" : "models/xmaspres2.mdl")
    entity_set_origin(ent, origin)

    entity_set_int(ent, EV_INT_solid, SOLID_TRIGGER)
    entity_set_int(ent, EV_INT_movetype, MOVETYPE_BOUNCE)
    entity_set_float(ent, EV_FL_gravity, 0.6)

    new Float:vel[3]
    vel[0] = random_float(-250.0, 250.0)
    vel[1] = random_float(-250.0, 250.0)
    vel[2] = random_float(200.0, 400.0)
    entity_set_vector(ent, EV_VEC_velocity, vel)
}

// ================= TOUCH =================

public pfn_touch(ent, id)
{
    if (!g_bEventActive || !is_user_alive(id))
        return

    static classname[32]
    entity_get_string(ent, EV_SZ_classname, classname, charsmax(classname))

    if (!equal(classname, "event_present"))
        return

    new type = entity_get_int(ent, EV_INT_iuser1)
    g_iCollected[id] += type

    client_cmd(id, "spk subcultura/unwrapping.wav")
    remove_entity(ent)
}

// ================= HUD =================

public client_PreThink(id)
{
    if (!g_bEventActive || !is_user_alive(id))
        return

    ShowTopHud(id)
}

ShowTopHud(id)
{
    new players[32], num
    get_players(players, num, "ah")

    new sorted[32], count
    for (new i; i < num; i++)
        sorted[count++] = players[i]

    // сортировка
    for (new i; i < count; i++)
    {
        for (new j = i + 1; j < count; j++)
        {
            if (g_iCollected[sorted[j]] > g_iCollected[sorted[i]])
            {
                new tmp = sorted[i]
                sorted[i] = sorted[j]
                sorted[j] = tmp
            }
        }
    }

    new text[256], len
    len += formatex(text[len], charsmax(text) - len, "TAKE PRESENTS^n")

    for (new i; i < count && i < 3; i++)
    {
        len += formatex(
            text[len], charsmax(text) - len,
            "%d. %n - %d^n",
            i + 1, sorted[i], g_iCollected[sorted[i]]
        )
    }

    len += formatex(text[len], charsmax(text) - len,
        "^nYou: %d", g_iCollected[id])

    set_hudmessage(0, 255, 0, 0.73, 0.18, 0, 0.0, 0.25, 0.0, 0.0, HUD_RIGHT)
    ShowSyncHudMsg(id, g_iHudSync, "%s", text)
}

// ================= XP =================

GiveRewards()
{
    new players[32], num
    get_players(players, num, "ah")

    new mult = 1
    if (num >= 8) mult = 4
    else if (num >= 6) mult = 3
    else if (num >= 4) mult = 2

    for (new i; i < num; i++)
    {
        new id = players[i]
        if (!g_iCollected[id]) continue

        new xp = random_num(0, 300) * mult
        hns_xp_add_xp(id, xp)

        client_print(id, print_chat,
            "[EVENT] You collected %d presents and got %d XP",
            g_iCollected[id], xp)
    }
}

RemovePresents()
{
    new ent = -1
    while ((ent = find_ent_by_class(ent, "event_present")) > 0)
        remove_entity(ent)
}
