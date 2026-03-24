#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

int g_BeamSprite;
int g_HaloSprite;
Handle g_DrawTimer[MAXPLAYERS+1];

public Plugin myinfo = {
    name = "Tank Rock Trajectory",
    author = "Your Name",
    description = "Draws trajectory when Tank throws rock",
    version = "1.0",
    url = ""
};

public void OnPluginStart() {
    HookEvent("ability_use", Event_AbilityUse);
    HookEvent("player_disconnect", Event_PlayerDisconnect);
}

public void OnMapStart() {
    g_BeamSprite = PrecacheModel("materials/sprites/laserbeam.vmt");
    g_HaloSprite = PrecacheModel("materials/sprites/halo01.vmt");
}

public void Event_AbilityUse(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || !IsClientInGame(client)) return;

    char ability[64];
    event.GetString("ability", ability, sizeof(ability));

    if (StrEqual(ability, "ability_throw")) {
        delete g_DrawTimer[client];
        g_DrawTimer[client] = CreateTimer(0.05, Timer_DrawTrajectory, GetClientUserId(client), TIMER_REPEAT);
    }
}

public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0) delete g_DrawTimer[client];
}

public Action L4D_TankRock_OnRelease(int tank, int rock, float vecPos[3], float vecAng[3], float vecVel[3], float vecRot[3]) {
    delete g_DrawTimer[tank];
    return Plugin_Continue;
}

Action Timer_DrawTrajectory(Handle timer, int userid) {
    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client)) {
        g_DrawTimer[client] = null;
        return Plugin_Stop;
    }

    float eyePos[3], eyeAng[3], velocity[3];
    GetClientEyePosition(client, eyePos);
    GetClientEyeAngles(client, eyeAng);

    GetThrowVelocity(eyeAng, velocity);
    DrawParabola(eyePos, velocity);

    return Plugin_Continue;
}

void GetThrowVelocity(float angles[3], float velocity[3]) {
    float pitch = DegToRad(angles[0]);
    float yaw = DegToRad(angles[1]);
    float speed = 1000.0;

    velocity[0] = Cosine(pitch) * Cosine(yaw) * speed;
    velocity[1] = Cosine(pitch) * Sine(yaw) * speed;
    velocity[2] = -Sine(pitch) * speed;
}

void DrawParabola(float startPos[3], float vel[3]) {
    float pos[3], lastPos[3], velocity[3];
    pos = startPos;
    lastPos = startPos;
    velocity = vel;

    float gravity = 800.0;
    float dt = 0.05;

    for (int i = 0; i < 50; i++) {
        lastPos = pos;

        pos[0] += velocity[0] * dt;
        pos[1] += velocity[1] * dt;
        pos[2] += velocity[2] * dt;

        velocity[2] += gravity * dt;

        TR_TraceRayFilter(lastPos, pos, MASK_SOLID, RayType_EndPoint, TraceFilter_World);
        if (TR_DidHit()) break;

        TE_SetupBeamPoints(lastPos, pos, g_BeamSprite, g_HaloSprite, 0, 0, 0.1, 2.0, 2.0, 1, 0.0, {255, 0, 0, 255}, 0);
        TE_SendToAll();
    }
}

bool TraceFilter_World(int entity, int mask) {
    return entity == 0;
}

