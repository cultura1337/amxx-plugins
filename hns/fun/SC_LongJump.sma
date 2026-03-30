//20.06.24 add func btn "f"

#include <amxmodx>
#include <engine>
#include <fakemeta>
#include <hamsandwich>

const Float:LEAP_COOLDOWN = 5.0;
const Float:LEAP_FORCE = 350.0;
const Float:LEAP_HEIGHT = 300.0;
const Float:UPDATE_INTERVAL = 1.0;

new Float:g_lastLeapTime[33];

public plugin_init()
{
    register_plugin("Leap Plugin", "0.3", "cultura");

    register_forward(FM_PlayerPreThink, "fw_PlayerPreThink");
    set_task(UPDATE_INTERVAL, "task_update_cooldown", _, _, _, "b");
}

public fw_PlayerPreThink(id)
{
    if (!is_user_alive(id))
        return;

    if (is_flashlight_on(id))
    {
        perform_leap(id);
    }
}

stock is_flashlight_on(id)
{
    return pev(id, pev_effects) & EF_DIMLIGHT;
}

stock perform_leap(id)
{
    new Float:currentTime = get_gametime();

    if (currentTime - g_lastLeapTime[id] < LEAP_COOLDOWN)
        return;

    if (!(pev(id, pev_flags) & FL_ONGROUND) || get_player_speed(id) < 80.0)
        return;

    new Float:velocity[3];
    calculate_velocity_by_aim(id, LEAP_FORCE, velocity);
    velocity[2] = LEAP_HEIGHT;
    set_pev(id, pev_velocity, velocity);

    g_lastLeapTime[id] = currentTime;
}

stock calculate_velocity_by_aim(id, Float:force, Float:velocity[3])
{
    new Float:angle[3];
    new Float:aimVec[3];
    pev(id, pev_v_angle, angle);
    angle_vector(angle, ANGLEVECTOR_FORWARD, aimVec);

    velocity[0] = aimVec[0] * force;
    velocity[1] = aimVec[1] * force;
    velocity[2] = aimVec[2] * force;
}

stock Float:get_player_speed(id)
{
    new Float:velocity[3];
    pev(id, pev_velocity, velocity);

    return vector_length(velocity);
}

public task_update_cooldown()
{
    new maxPlayers = get_maxplayers();
    new Float:currentTime = get_gametime();

    for (new id = 1; id <= maxPlayers; id++)
    {
        if (is_user_connected(id) && is_user_alive(id))
        {
            new Float:cooldownRemaining = LEAP_COOLDOWN - (currentTime - g_lastLeapTime[id]);
            if (cooldownRemaining > 0.0)
            {
                set_hudmessage(255, 255, 255, -1.0, 0.7231, 0, 1.0, 1.0, 0.1, 0.2, 4);
                show_hudmessage(id, "Jump CD: %.1f seconds", cooldownRemaining);
            }
        }
    }
}
