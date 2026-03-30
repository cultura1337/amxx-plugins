#include <amxmodx>
#include <fakemeta>

#if defined _reapi_included
#include <reapi>
#else
#define rg_create_entity(%0) engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, %0))
#define set_entvar set_pev
#define var_rendercolor pev_rendercolor
#endif

public client_putinserver(id) {
    client_cmd(id, "cl_weather 1");
}


public plugin_precache()
{
    // Создание дождя
    new rain = rg_create_entity("env_rain");
	//rg_create_entity("env_snow")
    set_entvar(rain, pev_origin, Float:{0.0, 0.0, 50.0}); // Позиция дождя ближе к игрокам
    set_entvar(rain, pev_scale, 10.0); // Увеличение размера капель дождя
    set_entvar(rain, pev_health, 500); // Увеличение интенсивности дождя

    // Предзагрузка звуков
    precache_sound("ambience/rain.wav");
    precache_sound("storm/thunder-theme.wav");

    // Создание тумана
    new entity = rg_create_entity("env_fog");
    #define m_fDensity 36
    set_pdata_float(entity, m_fDensity, 0.0008, 4); // Лёгкий туман
    set_entvar(entity, var_rendercolor, Float:{0.0, 0.0, 0.0}); // Чёрный цвет тумана

    // Воспроизведение звуков
    set_task(50.0, "play_rain_sound");
    set_task(random_float(60.0, 360.0), "play_thunder_sound"); // Звук грома с интервалом
}

public plugin_init()
{
    register_plugin("Weather", "3.0", "Cultura");
    server_cmd("sv_skyname hav");
    engfunc(EngFunc_LightStyle, 5, "k"); // Настройка освещения
}

public play_rain_sound() {
    emit_sound(0, CHAN_STATIC, "ambience/rain.wav", 0.2, ATTN_NONE, 0, PITCH_NORM);
}

public play_thunder_sound() {
    emit_sound(0, CHAN_STATIC, "storm/thunder-theme.wav", 0.1, ATTN_NONE, 0, PITCH_NORM);
    set_task(random_float(60.0, 360.0), "play_thunder_sound"); // Повторение случайного интервала для звука грома
}
