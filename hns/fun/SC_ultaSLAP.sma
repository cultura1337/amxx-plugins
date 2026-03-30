#include <amxmodx>
#include <fakemeta>
#include <cstrike>
#include <engine>
#include <fakemeta_util>
#include <hamsandwich>

#define VELOCITY_BACK 900.0 // Увеличенное значение отталкивающей силы
#define ABILITY_RADIUS 150.0 // Радиус способности
#define MAX_SLAPS_PER_PERIOD 1
#define SLAP_PERIOD 90.0 // Период перезарядки на 1.5 минуты (90 секунд)

new g_maxplayers;
new g_slapCount[33]; // Счетчик использований команды /slap для каждого игрока
new Float:g_lastSlapTime[33]; // Время последнего использования команды /slap для каждого игрока
new g_usePressed[33]; // Флаг для отслеживания нажатия кнопки +use

public plugin_init()
{
    register_plugin("Slap Ability", "3.0", "cultura");
    g_maxplayers = get_maxplayers();
    register_event("ResetHUD", "EventResetHUD", "be");
    register_event("HLTV", "EventNewRound", "a", "1=0", "2=0");
    register_clcmd("say /slap", "CmdSlap");
    register_forward(FM_CmdStart, "CmdStart");
}

public EventResetHUD(id)
{
    // Этот хук можно использовать для сброса состояния игрока при появлении, если необходимо
}

public EventNewRound()
{
    // Сбросить счетчик использования /slap и время последнего использования в начале каждого раунда
    for (new id = 1; id <= g_maxplayers; id++)
    {
        if (is_user_connected(id))
        {
            g_slapCount[id] = 0; // Сброс счетчика использований в начале раунда
            g_lastSlapTime[id] = 0.0; // Сброс времени последнего использования
            g_usePressed[id] = 0; // Сброс флага нажатия кнопки +use
        }
    }
}

public CmdStart(id, uc_handle, seed)
{
    // Проверка, что игрок жив и подключен
    if (!is_user_alive(id) || !is_user_connected(id))
        return FMRES_IGNORED;

    static buttons;
    buttons = get_uc(uc_handle, UC_Buttons);

    // Проверка нажатия и отпуска кнопки +use
    if (buttons & IN_USE)
    {
        if (!g_usePressed[id])
        {
            // Кнопка была нажата, выполняем действие
            g_usePressed[id] = 1; // Устанавливаем флаг, что кнопка нажата
            CmdSlap(id);
        }
    }
    else
    {
        // Кнопка отпущена, сбрасываем флаг
        g_usePressed[id] = 0;
    }

    return FMRES_IGNORED;
}

public CmdSlap(id)
{
    if (!is_user_connected(id) || !is_user_alive(id))
    {
        client_print(id, print_chat, "You are not connected or alive.");
        return PLUGIN_CONTINUE;
    }

    // Проверка, что игрок террорист
    if (cs_get_user_team(id) != CS_TEAM_T)
    {
        client_print(id, print_chat, "Only TERRORIST can USE this ability.");
        return PLUGIN_CONTINUE;
    }

    // Проверка перезарядки (cooldown) и количества использований
    new Float:currentTime = get_gametime();
    if (g_slapCount[id] >= MAX_SLAPS_PER_PERIOD)
    {
        if (currentTime - g_lastSlapTime[id] < SLAP_PERIOD)
        {
            client_print(id, print_chat, "Try again in %.0f seconds.", SLAP_PERIOD - (currentTime - g_lastSlapTime[id]));
            return PLUGIN_CONTINUE;
        }
        else
        {
            // Сбросить счетчик использований и обновить время последнего использования
            g_slapCount[id] = 0;
            g_lastSlapTime[id] = currentTime;
        }
    }

    // Найти игроков в радиусе и проверить наличие контр-террористов
    new ent = -1, Float:fOrigin[3];
    pev(id, pev_origin, fOrigin);

    new hasCT = 0; // Initialize as 0 (false)
    new Float:fRadius = ABILITY_RADIUS;

    while ((ent = engfunc(EngFunc_FindEntityInSphere, ent, fOrigin, fRadius)))
    {
        if (is_user_connected(ent) && ent != id)
        {
            // Проверка, что игрок - контр-террорист
            if (cs_get_user_team(ent) == CS_TEAM_CT)
            {
                hasCT = 1; // Set to 1 (true) if a CT player is found
                break;
            }
        }
    }

    if (!hasCT)
    {
        client_print(id, print_chat, "No CT players in radius to slap.");
        return PLUGIN_CONTINUE;
    }

    // Найти игроков в радиусе и применить отталкивание
    ent = -1;
    new Float:fVelocity[3], Float:fVictimOrigin[3], Float:fDistance, Float:fNewSpeed;

    while ((ent = engfunc(EngFunc_FindEntityInSphere, ent, fOrigin, fRadius)))
    {
        if (is_user_connected(ent) && ent != id)
        {
            // Проверка, что игрок - контр-террорист
            if (cs_get_user_team(ent) == CS_TEAM_CT)
            {
                pev(ent, pev_origin, fVictimOrigin);

                fDistance = get_distance_f(fOrigin, fVictimOrigin);
                
                // Добавляем случайность к отталкивающей силе
                fNewSpeed = VELOCITY_BACK * (1.0 - (fDistance / fRadius)) + random_float(200.0, 500.0);
                
                get_speed_vector(fOrigin, fVictimOrigin, fNewSpeed, fVelocity);

                // Увеличиваем вертикальную составляющую для более сильного отталкивания вверх
                fVelocity[2] = random_float(500.0, 800.0);
                
                set_pev(ent, pev_velocity, fVelocity);

                ExecuteHam(Ham_TakeDamage, ent, id, id, random_float(10.0, 20.0), DMG_ALWAYSGIB | DMG_BULLET); // Уменьшено значение урона

                // Отладочное сообщение, что игрок был оттолкнут
                client_print(ent, print_chat, "You have been slapped!");
            }
        }
    }

    // Увеличить счетчик использований команды
    g_slapCount[id]++;

    // Обновить время последнего использования команды
    g_lastSlapTime[id] = currentTime;

    return PLUGIN_CONTINUE;
}

get_speed_vector(const Float:origin1[3], const Float:origin2[3], Float:speed, Float:new_velocity[3])
{
    new_velocity[0] = origin2[0] - origin1[0];
    new_velocity[1] = origin2[1] - origin1[1];
    new_velocity[2] = origin2[2] - origin1[2];
    new Float:num = floatsqroot(speed * speed / (new_velocity[0] * new_velocity[0] + new_velocity[1] * new_velocity[1] + new_velocity[2] * new_velocity[2]));
    new_velocity[0] *= num;
    new_velocity[1] *= num;
    new_velocity[2] *= num;

    return 1;
}
