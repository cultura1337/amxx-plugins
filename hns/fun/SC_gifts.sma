#include <amxmodx>
#include <amxmisc>
#include <engine>
#include <cstrike>
#include <fun>

#define MAXSPAWNS 64
#define PRESENTAMOUNT 2
#define TOTALCOLORS 27

new Float:origins[MAXSPAWNS][3];
new bool:isLoaded = false;
new totalOrigins;

new Float:colors[TOTALCOLORS][3] = {
    {255.0, 0.0, 0.0},
    {165.0, 0.0, 0.0},
    {255.0, 100.0, 100.0},
    {0.0, 0.0, 255.0},
    {0.0, 0.0, 136.0},
    {95.0, 200.0, 255.0},
    {0.0, 150.0, 255.0},
    {0.0, 255.0, 0.0},
    {180.0, 255.0, 175.0},
    {0.0, 155.0, 0.0},
    {255.0, 255.0, 255.0},
    {255.0, 255.0, 0.0},
    {189.0, 182.0, 0.0},
    {255.0, 255.0, 109.0},
    {255.0, 150.0, 0.0},
    {255.0, 190.0, 90.0},
    {222.0, 110.0, 0.0},
    {243.0, 138.0, 255.0},
    {255.0, 0.0, 255.0},
    {150.0, 0.0, 150.0},
    {100.0, 0.0, 100.0},
    {200.0, 0.0, 0.0},
    {220.0, 220.0, 0.0},
    {192.0, 192.0, 192.0},
    {190.0, 100.0, 10.0},
    {114.0, 114.0, 114.0},
    {0.0, 0.0, 0.0}
};

public plugin_init() {
    register_plugin("Present Spawner", "0.1", "MaximusBrood");
    register_clcmd("amx_spawnpresent", "cmd_Spawn", ADMIN_CHAT, "Spawns a present with money!");
    register_clcmd("amx_removepresents", "cmd_Remove", ADMIN_CHAT, "Removes all presents");
    register_clcmd("amx_addspawnlocation", "cmd_AddSpawn", ADMIN_RCON, "Adds a present spawnlocation to file");

    register_logevent("event_RoundStarted", 2, "0=World triggered", "1=Round_Start");

    LoadData();
}

public plugin_precache() {
    precache_model("models/xmaspres1.mdl");
    precache_model("models/xmaspres2.mdl");
    return PLUGIN_CONTINUE;
}

public LoadData() {
    new datadir[64], filepath[64], mapname[32];
    get_datadir(datadir, 63);
    get_mapname(mapname, 31);
    format(filepath, 63, "%s/presentspawner/%s.ini", datadir, mapname);

    if (file_exists(filepath)) {
        new a, len, output[256];
        for (a = 0; a < MAXSPAWNS && read_file(filepath, a, output, 255, len); a++) {
            if (output[0] == ';' || !output[0]) continue;

            new x[16], y[16], z[16];
            parse(output, x, 15, y, 15, z, 15);

            origins[a][0] = float(str_to_num(x));
            origins[a][1] = float(str_to_num(y));
            origins[a][2] = float(str_to_num(z));
        }
        isLoaded = true;
        totalOrigins = a;
    }
}

public event_RoundStarted() {
    if (!isLoaded)
        return PLUGIN_CONTINUE;

    new a, b;
    for (a = 0; a < totalOrigins; a++) {
        for (b = 0; b < PRESENTAMOUNT; b++) {
            CreateEnt(origins[a]);
        }
    }

    return PLUGIN_CONTINUE;
}

public cmd_AddSpawn(id, level, cid) {
    if (!cmd_access(id, level, cid, 1))
        return PLUGIN_HANDLED;

    new datadir[64], filepath[64], mapname[32];
    get_datadir(datadir, 63);
    get_mapname(mapname, 31);
    format(filepath, 63, "%s/presentspawner/%s.ini", datadir, mapname);

    new totallines;
    totallines = file_size(filepath, 1);

    if (totallines > MAXSPAWNS) {
        client_print(id, print_console, "[AMXX] Can't add area, reached max number of spawns (%d)", MAXSPAWNS);
        return PLUGIN_HANDLED;
    }

    new x, y, z, totaltext[16];
    new Float:curOrigin[3];
    entity_get_vector(id, EV_VEC_origin, curOrigin);
    x = floatround(curOrigin[0]);
    y = floatround(curOrigin[1]);
    z = floatround(curOrigin[2]);

    format(totaltext, 15, "%d %d %d", x, y, z);
    write_file(filepath, totaltext);

    client_print(id, print_console, "[AMXX] Present spawn successfully added to file");

    LoadData();
    return PLUGIN_HANDLED;
}

public cmd_Spawn(id, level, cid) {
    if (!cmd_access(id, level, cid, 1))
        return PLUGIN_HANDLED;

    new Float:curOrigin[3];
    entity_get_vector(id, EV_VEC_origin, curOrigin);

    set_task(2.5, "CreateEnt", 0, curOrigin, 3);
    return PLUGIN_HANDLED;
}

public CreateEnt(Float:origin[3]) {
    new ent = create_entity("info_target");
    new Float:velocity[3];

    // Случайное направление движения
    velocity[0] = float(random(400) - 200); // Случайное значение от -200 до 200 по оси X
    velocity[1] = float(random(400) - 100); // Случайное значение от -200 до 200 по оси Y
    velocity[2] = float(random(300) + 200); // Случайное значение от 200 до 500 по оси Z

    new filename[32];
    format(filename, 31, "models/xmaspres%d.mdl", random_num(1, 2));

    entity_set_string(ent, EV_SZ_classname, "xmas_present");

    if (random_num(1, 4) != 4) {
        new rand = random_num(1, TOTALCOLORS);

        entity_set_int(ent, EV_INT_renderfx, kRenderFxGlowShell);
        entity_set_float(ent, EV_FL_renderamt, 1000.0);
        entity_set_int(ent, EV_INT_rendermode, kRenderTransAlpha);
        entity_set_vector(ent, EV_VEC_rendercolor, colors[rand]);
    }

    entity_set_model(ent, filename);
    entity_set_origin(ent, origin);
    entity_set_int(ent, EV_INT_effects, 32);
    entity_set_int(ent, EV_INT_solid, SOLID_BBOX);
    entity_set_int(ent, EV_INT_movetype, MOVETYPE_BOUNCE);
    entity_set_float(ent, EV_FL_gravity, 0.5); // Устанавливаем гравитацию, чтобы подарки медленно падали
    entity_set_vector(ent, EV_VEC_velocity, velocity);

    return PLUGIN_HANDLED;
}

public cmd_Remove(id, level, cid) {
    if (!cmd_access(id, level, cid, 1))
        return PLUGIN_HANDLED;

    new ent;

    while ((ent = find_ent_by_class(ent, "xmas_present")) != 0) {
        remove_entity(ent);
    }

    client_print(id, print_chat, "[AMXX] All presents are removed!");

    return PLUGIN_HANDLED;
}

public pfn_touch(ptr, ptd) {
    new classname[32];

    if (ptd == 0 || ptr == 0)
        return PLUGIN_HANDLED;

    entity_get_string(ptr, EV_SZ_classname, classname, 31);

    if (equal(classname, "xmas_present")) {
        new randNum = random_num(1, 10); // Случайное число от 1 до 10 для определения эффекта

        // Определяем действие на основе случайного числа
        if (randNum <= 9) { // 90% шанс на подброс игрока вверх
            new Float:curVelocity[3];
            entity_get_vector(ptd, EV_VEC_velocity, curVelocity);

            // Увеличиваем вертикальную составляющую скорости для подбрасывания игрока вверх
            curVelocity[2] = 1000.0; 

            entity_set_vector(ptd, EV_VEC_velocity, curVelocity);

            client_print(ptd, print_chat, "[AMXX] Whoa! The present launched you into the air!");

        } else { // 10% шанс на выдачу гранаты
            new item[32]; // Переменная для хранения имени предмета
            new subRandNum = random_num(1, 3); // Определяем, какая граната будет выдана

            if (subRandNum == 1) { // Smoke Grenade
                format(item, 31, "weapon_smokegrenade");
            } else if (subRandNum == 2) { // Flashbang
                format(item, 31, "weapon_flashbang");
            } else { // HE Grenade
                format(item, 31, "weapon_hegrenade");
            }

            // Выдаем предмет игроку
            if (give_item(ptd, item)) {
                client_print(ptd, print_chat, "[AMXX] Hooray! You received a %s from an xmas present!", item);
            } else {
                client_print(ptd, print_chat, "[AMXX] Oops! Failed to receive %s from an xmas present!", item);
            }
        }

        // Удаляем подарок
        remove_entity(ptr);
    }

    return PLUGIN_CONTINUE;
}

