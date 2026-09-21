#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

int g_BeamSprite;
int g_HaloSprite;
Handle g_PredictTimer[MAXPLAYERS+1];
Handle g_PostReleaseTimer[MAXPLAYERS+1];
float g_ReleasePos[MAXPLAYERS+1][3];
float g_ReleaseVel[MAXPLAYERS+1][3];
float g_RockGravityScale[MAXPLAYERS+1];
ConVar g_cvEnabled;
ConVar g_cvPostReleaseDuration;
ConVar g_cvUseRockPosition;
ConVar g_cvDrawInterval;
ConVar g_cvMaxPredictTime;
ConVar g_cvHitIndicator;
ConVar g_cvVisibleTeam;
ConVar g_cvOtherPlayerInterval;

bool g_bWillHit[MAXPLAYERS+1];
int g_iFrameCount[MAXPLAYERS+1];

// Fixed offsets for each throw sequence (local space)
static const float OFFSET_1H_OVERHAND[3] = {127.2, -20.9, 93.9};
static const float OFFSET_UNDERHAND[3] = {86.3, -52.4, 34.5};
static const float OFFSET_2H_OVERHAND[3] = {17.4, 0.7, 104.4};

// Colors
static const int COLOR_HIT[4] = {255, 0, 0, 255};
static const int COLOR_NORMAL[4] = {255, 100, 0, 200};
static const int COLOR_CYAN[4] = {0, 255, 255, 200};

public Plugin myinfo = {
    name = "Tank Rock Trajectory Predictor",
    author = "Sir.P",
    description = "Predicts rock trajectory before throw",
    version = "1.0",
    url = ""
};

public void OnPluginStart() {
    g_cvEnabled = CreateConVar("rock_trajectory_enabled", "1", "Enable rock trajectory predictor. 0=Off, 1=On", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvPostReleaseDuration = CreateConVar("rock_trajectory_post_release", "5.0", "Duration in seconds to keep drawing trajectory after rock is released. 0=Off", FCVAR_NOTIFY, true, 0.0);
    g_cvUseRockPosition = CreateConVar("rock_trajectory_use_rock_pos", "0", "Use actual rock position (1) or fixed offset from tank (0)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvDrawInterval = CreateConVar("rock_trajectory_draw_interval", "0.1", "Draw interval in seconds. Min 0.01 (100fps), Max 0.1 (10fps)", FCVAR_NOTIFY, true, 0.1, true, 0.5);
    g_cvMaxPredictTime = CreateConVar("rock_trajectory_max_time", "10.0", "Maximum prediction time in seconds", FCVAR_NOTIFY, true, 1.0, true, 30.0);
    g_cvHitIndicator = CreateConVar("rock_trajectory_hit_indicator", "1", "Show hit indicator when trajectory will hit survivor. 0=Off, 1=On", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvVisibleTeam = CreateConVar("rock_trajectory_visible_team", "7", "Which teams can see trajectory (bitflags). 1=Spectators, 2=Survivors, 4=Infected. Add values for multiple teams (7=All)", FCVAR_NOTIFY, true, 0.0, true, 7.0);
    g_cvOtherPlayerInterval = CreateConVar("rock_trajectory_other_interval", "3", "Send to non-tank players every N frames. 1=Every frame, 3=Every 3rd frame", FCVAR_NOTIFY, true, 1.0, true, 10.0);
    HookEvent("ability_use", Event_AbilityUse);
}

public void OnMapStart() {
    g_BeamSprite = PrecacheModel("materials/sprites/laserbeam.vmt");
    g_HaloSprite = PrecacheModel("materials/sprites/halo01.vmt");
}

public void OnEntityCreated(int entity, const char[] classname) {
    if (!g_cvEnabled.BoolValue) return;

    if (strcmp(classname, "tank_rock") == 0) {
        SDKHook(entity, SDKHook_SpawnPost, OnRockSpawn);
    }
}

void OnRockSpawn(int rock) {
    RequestFrame(Frame_GetRockTank, EntIndexToEntRef(rock));
}

void Frame_GetRockTank(int ref) {
    int rock = EntRefToEntIndex(ref);
    if (rock == INVALID_ENT_REFERENCE) return;

    int tank = GetEntPropEnt(rock, Prop_Data, "m_hThrower");
    if (tank > 0 && tank <= MaxClients) {
        float gravScale = GetEntPropFloat(rock, Prop_Data, "m_flGravity");
        g_RockGravityScale[tank] = (gravScale > 0.0) ? gravScale : 1.0;

        delete g_PredictTimer[tank];
        float interval = g_cvDrawInterval.FloatValue;
        g_PredictTimer[tank] = CreateTimer(interval, Timer_PredictTrajectory, GetClientUserId(tank), TIMER_REPEAT);
    }
}

public Action L4D_TankRock_OnRelease(int tank, int rock, float vecPos[3], float vecAng[3], float vecVel[3], float vecRot[3]) {
    delete g_PredictTimer[tank];

    float duration = g_cvPostReleaseDuration.FloatValue;
    if (duration > 0.0 && tank > 0 && tank <= MaxClients) {
        // capture predicted start pos and velocity at the moment of release
        float startAng[3];
        if (!GetAttachmentVectors(tank, "debris", g_ReleasePos[tank], startAng)) {
            GetClientAbsOrigin(tank, g_ReleasePos[tank]);
            g_ReleasePos[tank][2] += 50.0;
        }
        float eyeAng[3];
        GetClientEyeAngles(tank, eyeAng);
        GetThrowVelocity(eyeAng, g_ReleaseVel[tank]);

        delete g_PostReleaseTimer[tank];
        DrawParabolaLongLife(g_ReleasePos[tank], g_ReleaseVel[tank], g_RockGravityScale[tank], tank, duration);
    }

    return Plugin_Continue;
}

public void Event_AbilityUse(Event event, const char[] name, bool dontBroadcast) {
}

Action Timer_PredictTrajectory(Handle timer, int userid) {
    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client)) {
        g_PredictTimer[client] = null;
        return Plugin_Stop;
    }

    float startPos[3], startAng[3], eyeAng[3], velocity[3];

    if (g_cvUseRockPosition.BoolValue) {
        if (!GetAttachmentVectors(client, "debris", startPos, startAng)) {
            GetClientAbsOrigin(client, startPos);
            startPos[2] += 50.0;
        }
    } else {
        // Use fixed offset based on throw sequence
        int sequence = GetEntProp(client, Prop_Send, "m_nSequence");
        float localOffset[3];

        if (sequence == 49) {
            localOffset = OFFSET_1H_OVERHAND;
        } else if (sequence == 50) {
            localOffset = OFFSET_UNDERHAND;
        } else if (sequence == 51) {
            localOffset = OFFSET_2H_OVERHAND;
        } else {
            localOffset[0] = 0.0;
            localOffset[1] = 0.0;
            localOffset[2] = 64.0;
        }

        // Convert local offset to world space
        float tankPos[3], tankAngles[3];
        GetClientAbsOrigin(client, tankPos);
        GetEntPropVector(client, Prop_Data, "m_angRotation", tankAngles);

        float yaw = tankAngles[1] * 0.017453293;
        startPos[0] = tankPos[0] + localOffset[0] * Cosine(yaw) - localOffset[1] * Sine(yaw);
        startPos[1] = tankPos[1] + localOffset[0] * Sine(yaw) + localOffset[1] * Cosine(yaw);
        startPos[2] = tankPos[2] + localOffset[2];
    }

    GetClientEyeAngles(client, eyeAng);
    GetThrowVelocity(eyeAng, velocity);
    DrawParabola(startPos, velocity, g_RockGravityScale[client], client);

    // Draw start point marker when using fixed offset
    if (!g_cvUseRockPosition.BoolValue) {
        int color[4];
        color = (g_cvHitIndicator.BoolValue && g_bWillHit[client]) ? COLOR_HIT : COLOR_CYAN;
        float size = 15.0;
        float corners[4][3];

        // Get view direction
        float pitch = DegToRad(eyeAng[0]);
        float yaw = DegToRad(eyeAng[1]);

        // Right vector (perpendicular to view)
        float right[3];
        right[0] = -Sine(yaw);
        right[1] = Cosine(yaw);
        right[2] = 0.0;

        // Up vector (perpendicular to view and right)
        float up[3];
        up[0] = -Cosine(yaw) * Sine(pitch);
        up[1] = -Sine(yaw) * Sine(pitch);
        up[2] = Cosine(pitch);

        // Square corners facing camera
        for (int i = 0; i < 3; i++) {
            corners[0][i] = startPos[i] - right[i] * size - up[i] * size;
            corners[1][i] = startPos[i] + right[i] * size - up[i] * size;
            corners[2][i] = startPos[i] + right[i] * size + up[i] * size;
            corners[3][i] = startPos[i] - right[i] * size + up[i] * size;
        }

        // Draw square
        for (int i = 0; i < 4; i++) {
            TE_SetupBeamPoints(corners[i], corners[(i+1)%4], g_BeamSprite, g_HaloSprite, 0, 10, 0.1, 2.0, 2.0, 1, 0.0, color, 0);
            TE_SendToTeam(client, true);
        }
    }

    return Plugin_Continue;
}

void DrawParabolaLongLife(float startPos[3], float vel[3], float gravScale, int tank, float life) {
    float pos[3], lastPos[3], velocity[3];
    pos = startPos;
    lastPos = startPos;
    velocity = vel;

    float gravity = -FindConVar("sv_gravity").FloatValue * gravScale;
    float dt = g_cvDrawInterval.FloatValue;
    float maxTime = g_cvMaxPredictTime.FloatValue;
    int maxSteps = RoundToFloor(maxTime / dt);

    int beamColor[4] = {255, 100, 0, 200};
    float impactPos[3];
    bool hasImpact = false;

    for (int i = 0; i < maxSteps; i++) {
        lastPos = pos;

        pos[0] += velocity[0] * dt;
        pos[1] += velocity[1] * dt;
        pos[2] += velocity[2] * dt;
        velocity[2] += gravity * dt;

        TR_TraceRayFilter(lastPos, pos, MASK_SOLID, RayType_EndPoint, TraceFilter_World);
        if (TR_DidHit()) {
            TR_GetEndPosition(impactPos);
            hasImpact = true;
            break;
        }

        TE_SetupBeamPoints(lastPos, pos, g_BeamSprite, g_HaloSprite, 0, 0, life, 2.0, 2.0, 1, 0.0, beamColor, 0);
        TE_SendToTeam(tank, false);
    }

    // Draw start point marker
    if (!g_cvUseRockPosition.BoolValue) {
        float yaw = ArcTangent2(vel[1], vel[0]);
        float pitch = ArcSine(-vel[2] / GetVectorLength(vel));

        float right[3];
        right[0] = -Sine(yaw);
        right[1] = Cosine(yaw);
        right[2] = 0.0;

        float up[3];
        up[0] = -Cosine(yaw) * Sine(pitch);
        up[1] = -Sine(yaw) * Sine(pitch);
        up[2] = Cosine(pitch);

        float size = 15.0;
        float corners[4][3];
        for (int i = 0; i < 3; i++) {
            corners[0][i] = startPos[i] - right[i] * size - up[i] * size;
            corners[1][i] = startPos[i] + right[i] * size - up[i] * size;
            corners[2][i] = startPos[i] + right[i] * size + up[i] * size;
            corners[3][i] = startPos[i] - right[i] * size + up[i] * size;
        }

        for (int i = 0; i < 4; i++) {
            TE_SetupBeamPoints(corners[i], corners[(i+1)%4], g_BeamSprite, g_HaloSprite, 0, 10, life, 2.0, 2.0, 1, 0.0, COLOR_CYAN, 0);
            TE_SendToTeam(tank, true);
        }
    }

    // Draw impact marker
    if (hasImpact) {
        float distance = GetVectorDistance(startPos, impactPos);
        float height = 80.0 + (distance / 50.0);
        if (height > 300.0) height = 300.0;

        float top[3];
        top = impactPos;
        top[2] += height;
        TE_SetupBeamPoints(impactPos, top, g_BeamSprite, g_HaloSprite, 0, 0, life, 3.0, 3.0, 1, 0.0, COLOR_CYAN, 0);
        TE_SendToTeam(tank);

        float groundPos[3];
        groundPos = impactPos;
        groundPos[2] += 2.0;
        TE_SetupBeamRingPoint(groundPos, 10.0, 30.0, g_BeamSprite, g_HaloSprite, 0, 10, life, 3.0, 0.0, COLOR_CYAN, 10, 0);
        TE_SendToTeam(tank);
    }
}

void GetThrowVelocity(float angles[3], float velocity[3]) {
    float pitch = DegToRad(angles[0]);
    float yaw = DegToRad(angles[1]);
    float speed = FindConVar("z_tank_throw_force").FloatValue;

    velocity[0] = Cosine(pitch) * Cosine(yaw) * speed;
    velocity[1] = Cosine(pitch) * Sine(yaw) * speed;
    velocity[2] = -Sine(pitch) * speed;
}

void DrawParabola(float startPos[3], float vel[3], float gravScale = 1.0, int tank = 0) {
    float pos[3], lastPos[3], velocity[3];
    pos = startPos;
    lastPos = startPos;
    velocity = vel;

    float gravity = -FindConVar("sv_gravity").FloatValue * gravScale;
    float dt = g_cvDrawInterval.FloatValue;
    float beamLife = dt * 1.2;

    float maxTime = g_cvMaxPredictTime.FloatValue;
    int maxSteps = RoundToFloor(maxTime / dt);

    float impactPos[3];
    bool hasImpact = false;
    bool willHit = false;
    float rockRadius = FindConVar("z_tank_rock_radius").FloatValue;

    if (g_cvHitIndicator.BoolValue && tank > 0) {
        for (int i = 1; i <= MaxClients; i++) {
            if (i != tank && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
                float survivorPos[3];
                GetClientAbsOrigin(i, survivorPos);
                survivorPos[2] += 40.0; // Check at center height

                // Check trajectory with line segment distance
                float tempPos[3], tempLastPos[3], tempVel[3];
                tempPos = startPos;
                tempLastPos = startPos;
                tempVel = vel;

                for (int j = 0; j < maxSteps; j++) {
                    tempLastPos = tempPos;

                    tempPos[0] += tempVel[0] * dt;
                    tempPos[1] += tempVel[1] * dt;
                    tempPos[2] += tempVel[2] * dt;
                    tempVel[2] += gravity * dt;

                    float dist = GetDistanceToSegment(survivorPos, tempLastPos, tempPos);
                    if (dist <= rockRadius) {
                        willHit = true;
                        break;
                    }
                }
                if (willHit) break;
            }
        }
        if (tank > 0 && tank <= MaxClients) g_bWillHit[tank] = willHit;
    }

    for (int i = 0; i < maxSteps; i++) {
        lastPos = pos;

        pos[0] += velocity[0] * dt;
        pos[1] += velocity[1] * dt;
        pos[2] += velocity[2] * dt;

        velocity[2] += gravity * dt;

        TR_TraceRayFilter(lastPos, pos, MASK_SOLID, RayType_EndPoint, TraceFilter_World);
        if (TR_DidHit()) {
            TR_GetEndPosition(impactPos);
            hasImpact = true;
            break;
        }

        int beamColor[4];
        beamColor = willHit ? COLOR_HIT : COLOR_NORMAL;

        TE_SetupBeamPoints(lastPos, pos, g_BeamSprite, g_HaloSprite, 0, 0, beamLife, 2.0, 2.0, 1, 0.0, beamColor, 0);
        TE_SendToTeam(tank, false);
    }

    if (hasImpact) {
        float distance = GetVectorDistance(startPos, impactPos);
        DrawImpactMarker(impactPos, beamLife, willHit, distance, tank, true);
    }
}

void DrawImpactMarker(float pos[3], float life, bool isHit, float distance, int tank = 0, bool isMarker = false) {
    int color[4];
    color = isHit ? COLOR_HIT : COLOR_CYAN;

    // vertical line - height based on distance
    float height = 80.0 + (distance / 50.0);
    if (height > 300.0) height = 300.0;

    float top[3];
    top = pos;
    top[2] += height;
    TE_SetupBeamPoints(pos, top, g_BeamSprite, g_HaloSprite, 0, 0, life, 3.0, 3.0, 1, 0.0, color, 0);
    TE_SendToTeam(tank, isMarker);

    // circle on ground using BeamRingPoint
    float groundPos[3];
    groundPos = pos;
    groundPos[2] += 2.0;
    TE_SetupBeamRingPoint(groundPos, 10.0, 60.0, g_BeamSprite, g_HaloSprite, 0, 10, life, 3.0, 0.0, color, 10, 0);
    TE_SendToTeam(tank, isMarker);
}

bool TraceFilter_World(int entity, int mask) {
    return entity == 0;
}

float GetDistanceToSegment(float point[3], float segStart[3], float segEnd[3]) {
    float vec[3], pointVec[3];
    SubtractVectors(segEnd, segStart, vec);
    SubtractVectors(point, segStart, pointVec);

    float segLenSq = vec[0]*vec[0] + vec[1]*vec[1] + vec[2]*vec[2];
    if (segLenSq < 0.0001) return GetVectorDistance(point, segStart);

    float t = (pointVec[0]*vec[0] + pointVec[1]*vec[1] + pointVec[2]*vec[2]) / segLenSq;
    if (t < 0.0) return GetVectorDistance(point, segStart);
    if (t > 1.0) return GetVectorDistance(point, segEnd);

    float proj[3];
    proj[0] = segStart[0] + vec[0] * t;
    proj[1] = segStart[1] + vec[1] * t;
    proj[2] = segStart[2] + vec[2] * t;

    return GetVectorDistance(point, proj);
}

void TE_SendToTeam(int tank = 0, bool isMarker = false) {
    int visibleTeam = g_cvVisibleTeam.IntValue;
    int interval = g_cvOtherPlayerInterval.IntValue;

    if (tank > 0 && tank <= MaxClients) {
        g_iFrameCount[tank]++;
    }

    if (visibleTeam == 7 && interval == 1) {
        TE_SendToAll();
        return;
    }

    int[] clients = new int[MaxClients];
    int count = 0;

    for (int i = 1; i <= MaxClients; i++) {
        if (!IsClientInGame(i)) continue;

        int team = GetClientTeam(i);
        bool canSee = false;

        if (team == 1 && (visibleTeam & 1)) canSee = true;
        else if (team == 2 && (visibleTeam & 2)) canSee = true;
        else if (team == 3 && (visibleTeam & 4)) canSee = true;

        if (canSee) {
            // Always send markers (start square, impact indicator), throttle trajectory lines
            if (i == tank || isMarker || (tank > 0 && g_iFrameCount[tank] % interval == 0)) {
                clients[count++] = i;
            }
        }
    }

    if (count > 0) TE_Send(clients, count);
}
