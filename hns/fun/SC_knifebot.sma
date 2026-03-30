#include <amxmodx>
#include <cstrike>
#include <hamsandwich>
#include <engine>

#define PLUGIN "KB"
#define VERSION "1.4"

new Float:closeDistance = 60.0; // Растояние
new bool:g_autoKnife[33]; // Массив для хранения статуса автоатаки для каждого игрока
new bool:g_cooldown[33]; // Массив для хранения статуса перезарядки для каждого игрока

new const Float:attackDuration = 30.0; // Продолжительность
new const Float:cooldownDuration = 60.0; // Перезарядка

public plugin_init() {
    register_plugin(PLUGIN, VERSION, "cultura");

    RegisterHam(Ham_Player_PreThink, "player", "OnPlayerPreThink", 1);

    register_clcmd("ultimate", "CmdAutoKnife"); // Можно забиндить bind q +ultimate
}

// Команда для переключения статуса автоатаки
public CmdAutoKnife(id) {
    if (g_cooldown[id]) {
        client_print(id, print_chat, "[KB] Coldawn");
        return PLUGIN_HANDLED;
    }

    g_autoKnife[id] = !g_autoKnife[id]; // Переключение статуса автоатаки

    if (g_autoKnife[id]) {
        client_print(id, print_chat, "[KB] Activated");
        show_hudmessage(id, "Activated");
        
        ScreenFade(id, attackDuration, 255, 0, 0, 100); // Красный экран

        set_task(attackDuration, "DisableAutoKnife", id);
        set_task(attackDuration + cooldownDuration, "ResetCooldown", id);

        g_cooldown[id] = true;
    } else {
        client_print(id, print_chat, "[KB] Diactivated");
    }

    return PLUGIN_HANDLED;
}

// Основная функция автоатаки
public OnPlayerPreThink(id) {
    if (!is_user_alive(id) || !g_autoKnife[id] || cs_get_user_team(id) != CS_TEAM_CT) {
        return HAM_IGNORED;
    }

    new players[32], num;
    get_players(players, num, "a");

    for (new i = 0; i < num; i++) {
        new player = players[i];

        if (player == id || cs_get_user_team(player) != CS_TEAM_T) {
            continue;
        }

        new Float:ctOrigin[3], Float:tOrigin[3];
        entity_get_vector(id, EV_VEC_origin, ctOrigin);
        entity_get_vector(player, EV_VEC_origin, tOrigin);

        if (get_distance_f(ctOrigin, tOrigin) <= closeDistance) {
            client_print(id, print_chat, "[Auto Knife] Цель в пределах досягаемости, атакую.");
            ForcePlayerToKnife(id);
            break;
        }
    }

    return HAM_IGNORED;
}

// Функция для принудительного использования ножа игроком
stock ForcePlayerToKnife(id) {
    if (!is_user_alive(id)) {
        return;
    }

    new weapon = get_user_weapon(id);
    if (weapon != CSW_KNIFE) {
        engclient_cmd(id, "weapon_knife");
    }

    client_cmd(id, "+attack");
    set_task(0.1, "StopAttack", id);
}

// Функция для остановки атаки
public StopAttack(id) {
    if (!is_user_alive(id)) {
        return;
    }
    client_cmd(id, "-attack");
}

// 
stock ScreenFade(plr, Float:fDuration, red, green, blue, alpha)
{
    new i = plr ? plr : get_maxplayers();
    if (!i)
    {
        return 0;
    }

    message_begin(plr ? MSG_ONE : MSG_ALL, get_user_msgid("ScreenFade"), {0, 0, 0}, plr);
    write_short(floatround(4096.0 * fDuration, floatround_round));
    write_short(floatround(4096.0 * fDuration, floatround_round));
    write_short(4096);
    write_byte(red);
    write_byte(green);
    write_byte(blue);
    write_byte(alpha);
    message_end();

    return 1;
}

// Отключение автоатаки
public DisableAutoKnife(id) {
    g_autoKnife[id] = false;
    client_print(id, print_chat, "[Auto Knife] Автоатака ножом отключена.");
}

// Сброс перезарядки
public ResetCooldown(id) {
    g_cooldown[id] = false;
    client_print(id, print_chat, "[Auto Knife] Автоатака ножом готова к использованию.");
}
