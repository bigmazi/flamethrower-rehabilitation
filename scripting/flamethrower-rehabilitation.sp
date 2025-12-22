#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <dhooks>

public Plugin myinfo = {
	name = "[TF2] Flamethrower Rehabilitation",
	author = "bigmazi",
	description = "Overhauls flamethrower mechanics",
	version = "1.1.0.0",
	url = "https://steamcommunity.com/id/bmazi"
};



// Constants
// ----------------------------------------------------------------------------

#define PLAYERS_ARRAY_SIZE (MAXPLAYERS + 1)

#define HISTORY_RING_SIZE 512
#define HISTORY_RING_MASK (HISTORY_RING_SIZE - 1)

#define RAMPUP_RING_SIZE 512
#define RAMPUP_RING_MASK (RAMPUP_RING_SIZE - 1)

#define tf_point_t__m_flSpawnTime 28



// Types
// ----------------------------------------------------------------------------

enum struct Rampup
{
	int attackerRef;
	int victimRef;
	float amount;
	float lastIncrementTime;
}



// Data
// ----------------------------------------------------------------------------

int g_offset__m_vecPoints;
int g_offset__m_vecPoints__m_Size; // Windows: 0x4A8, Linux: 0x4C0
int g_offset__m_RefEHandle; // 848

float g_timestampsHistory[PLAYERS_ARRAY_SIZE][HISTORY_RING_SIZE];
float g_directionsHistory[PLAYERS_ARRAY_SIZE][HISTORY_RING_SIZE][3];
int g_historyCursors[PLAYERS_ARRAY_SIZE];

Rampup g_rampup[RAMPUP_RING_SIZE];
int g_rampupCursor;

float g_customDamageFactor;

ConVar sm_ftrehab_plugin_enabled;
ConVar sm_ftrehab_reverse_flames_priority;
ConVar sm_ftrehab_bluemoon_rampup;
ConVar sm_ftrehab_angular_speed_affects_damage;
ConVar sm_ftrehab_angular_speed_estimation_depth;
ConVar sm_ftrehab_angular_speed_estimation_time_window;
ConVar sm_ftrehab_angular_speed_start_penalty;
ConVar sm_ftrehab_angular_speed_end_penalty;
ConVar sm_ftrehab_display_angular_speed_multiplier;
ConVar sm_ftrehab_refill_dummy_bots;
ConVar sm_ftrehab_custom_rampup_enabled;
ConVar sm_ftrehab_custom_rampup_increment_per_hit;
ConVar sm_ftrehab_custom_rampup_linger_time;
ConVar sm_ftrehab_custom_rampup_drain_time;
ConVar sm_ftrehab_custom_rampup_first_tick_deals_max_damage;
ConVar sm_ftrehab_custom_rampup_increment_is_affected_by_angular_speed;
ConVar sm_ftrehab_display_custom_rampup;



// Utility functions
// ----------------------------------------------------------------------------

stock float Lerp(float a, float b, float amount)
{
	return a + (b - a) * amount;
}

stock float Clamp(float x, float a, float b)
{
	if (x < a) return a;
	if (x > b) return b;
	return x;
}

stock float ClampRemap(float x, float a, float b, float A, float B)
{
	float amount = (x - a) / (b - a);
	amount = Clamp(amount, 0.0, 1.0);
	return Lerp(A, B, amount);
}

stock any Load32(Address addr)
{
	return LoadFromAddress(addr, NumberType_Int32);
}

stock void Store32(Address addr, any data)
{
	StoreToAddress(addr, data, NumberType_Int32);
}

stock Address OffsetPointer(Address base, int offset)
{
	return view_as<Address>(view_as<int>(base) + offset);
}

stock int BytesInIntegers(int integers)
{
	return integers << 2;
}

stock int OwnerOf(int entity)
{
	return GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
}

stock DHookSetup Detour(
	GameData conf, const char[] functionName,
	DHookCallback pre = INVALID_FUNCTION, DHookCallback post = INVALID_FUNCTION)
{
	DHookSetup setup = DHookCreateFromConf(conf, functionName);
	
	if (!setup)
		SetFailState("Couldn't setup detour for \"%s\"!", functionName);
	
	if (pre != INVALID_FUNCTION)
	{
		bool enabled = DHookEnableDetour(setup, false, pre);
		
		if (!enabled)
			SetFailState("Couldn't detour \"%s\" (pre)!", functionName);
	}
	
	if (post != INVALID_FUNCTION)
	{
		bool enabled = DHookEnableDetour(setup, true, post);
		
		if (!enabled)
			SetFailState("Couldn't detour \"%s\" (post)!", functionName);
	}	
	
	return setup;
}



// Domain-specific procedures
// ----------------------------------------------------------------------------

void CacheOffsets()
{
	int m_unNextPointIndex = FindSendPropInfo("CTFFlameManager", "m_unNextPointIndex");	
	g_offset__m_vecPoints = m_unNextPointIndex + 8;
	g_offset__m_vecPoints__m_Size = g_offset__m_vecPoints + 12;
	
	int m_angRotation = FindSendPropInfo("CBaseEntity", "m_angRotation");
	g_offset__m_RefEHandle = m_angRotation + 12;
}

void ApplySdkHooks(int manager)
{
	SDKHook(manager, SDKHook_Touch, tf_flame_manager_Touch_Pre);
	SDKHook(manager, SDKHook_TouchPost, tf_flame_manager_Touch_Post);
	
	SDKHook(manager, SDKHook_Think, tf_flame_manager_Think_Pre);
}

void ReverseFlamesArray(int manager)
{
	if (!sm_ftrehab_reverse_flames_priority.BoolValue)
		return;
	
	Address pThis = GetEntityAddress(manager);
	
	Address pSize = OffsetPointer(pThis, g_offset__m_vecPoints__m_Size);
	Address ppArray = OffsetPointer(pThis, g_offset__m_vecPoints);
	Address pArray = Load32(ppArray);
	
	int size = Load32(pSize);
	int halfsize = size >> 1;	
	
	for (int i = 0; i < halfsize; i++)
	{
		Address pLow = OffsetPointer(pArray, BytesInIntegers(i));
		Address pHigh = OffsetPointer(pArray, BytesInIntegers(size - i - 1));
		
		int low = Load32(pLow);
		int high = Load32(pHigh);
		
		Store32(pLow, high);
		Store32(pHigh, low);
	}
}

float EstimateAngularSpeed(int player, int frame)
{
	int maxDepth = sm_ftrehab_angular_speed_estimation_depth.IntValue;
	float timeWindow = sm_ftrehab_angular_speed_estimation_time_window.FloatValue;
	
	float result = 0.0;
	
	int frame_a = frame;
	float time_a = g_timestampsHistory[player][frame_a];
	
	float a[3]; float b[3];
	a[0] = g_directionsHistory[player][frame_a][0];
	a[1] = g_directionsHistory[player][frame_a][1];
	a[2] = g_directionsHistory[player][frame_a][2];
	
	for (int depth = 1; depth < maxDepth; depth++)
	{
		int frame_b = (frame + HISTORY_RING_SIZE - depth) & HISTORY_RING_MASK;
		
		float time_b = g_timestampsHistory[player][frame_b];
		float dt = time_a - time_b;
		
		if (dt > timeWindow || dt <= 0.0)
			break;
		
		b[0] = g_directionsHistory[player][frame_b][0];
		b[1] = g_directionsHistory[player][frame_b][1];
		b[2] = g_directionsHistory[player][frame_b][2];
		
		float dot = GetVectorDotProduct(a, b);
		dot = Clamp(dot, 0.0, 1.0);
		
		float angle = ArcCosine(dot);		
		float angularSpeed = angle / dt;
		
		if (angularSpeed > result)
			result = angularSpeed;
	}
	
	return result * 180.0 / FLOAT_PI;
}

float EstimateFlameDensityFactor(int player, Address pFlame)
{
	float spawnTime = GetFlameSpawnTime(pFlame);
	int frame = MatchWithHistoryFrame(player, spawnTime);
	
	if (frame == -1)
		return 1.0;
	
	float angularSpeed = EstimateAngularSpeed(player, frame);
	
	float start = sm_ftrehab_angular_speed_start_penalty.FloatValue;
	float end = sm_ftrehab_angular_speed_end_penalty.FloatValue;
	
	float factor = ClampRemap(
		angularSpeed,
		start, end,
		1.0, 0.5
	);
	
	return factor;
}

float GetFlameSpawnTime(Address pFlame)
{
	Address pSpawnTime = OffsetPointer(pFlame, tf_point_t__m_flSpawnTime);
	return Load32(pSpawnTime);
}

int MatchWithHistoryFrame(int player, float targetTime)
{
	int baseFrame = g_historyCursors[player];
	
	for (int offset = 0; offset < HISTORY_RING_SIZE; offset++)
	{
		int frame = (baseFrame + HISTORY_RING_SIZE - offset) & HISTORY_RING_MASK;
		float time = g_timestampsHistory[player][frame];
		
		if (time <= targetTime)
			return frame;
	}
	
	return -1;
}

float ApplyCustomRampup(int attacker, int victimRef, float angularSpeedDamageFactor)
{
	int attackerRef = EntIndexToEntRef(attacker);
	
	int ringIdx = -1;
	
	for (int offset = 0; offset < RAMPUP_RING_SIZE; offset++)
	{
		int cursor = (g_rampupCursor + RAMPUP_RING_SIZE - offset) & RAMPUP_RING_MASK;
		
		bool foundExisting =
			g_rampup[cursor].attackerRef == attackerRef &&
			g_rampup[cursor].victimRef == victimRef;
		
		if (foundExisting)
		{
			ringIdx = cursor;
			break;
		}
	}
	
	if (ringIdx == -1)
	{
		g_rampupCursor += 1;
		ringIdx = g_rampupCursor;
		
		g_rampup[ringIdx].attackerRef = attackerRef;
		g_rampup[ringIdx].victimRef = victimRef;		
		g_rampup[ringIdx].amount = 0.0;		
		g_rampup[ringIdx].lastIncrementTime = -1000.0;		
	}
	
	float now = GetGameTime();
	float timeSinceLastIncrement = now - g_rampup[ringIdx].lastIncrementTime;
	
	float drainedAmount = ClampRemap(
		timeSinceLastIncrement - sm_ftrehab_custom_rampup_linger_time.FloatValue,
		0.0, sm_ftrehab_custom_rampup_drain_time.FloatValue,
		0.0, 1.0
	);
	
	float amountAfterDrain = Clamp(
		g_rampup[ringIdx].amount - drainedAmount,
		0.0, 1.0
	);
	
	float damageFactor = Lerp(0.5, 1.0, amountAfterDrain);
	
	if (damageFactor == 0.5)
	{
		if (sm_ftrehab_custom_rampup_first_tick_deals_max_damage.BoolValue)
		{
			damageFactor = 1.0;
		}
	}
	
	float increment = sm_ftrehab_custom_rampup_increment_per_hit.FloatValue
	
	if (sm_ftrehab_custom_rampup_increment_is_affected_by_angular_speed.BoolValue)
	{
		increment *= angularSpeedDamageFactor;
	}
	
	g_rampup[ringIdx].amount = Clamp(
		amountAfterDrain + increment,
		0.0, 1.0
	);
	
	g_rampup[ringIdx].lastIncrementTime = now;
	
	return damageFactor;
}



// Hooks
// ----------------------------------------------------------------------------

void tf_flame_manager_Touch_Pre(int manager, int other)
{
	ReverseFlamesArray(manager);
}

void tf_flame_manager_Touch_Post(int manager, int other)
{
	ReverseFlamesArray(manager);
}

void tf_flame_manager_Think_Pre(int manager)
{	
	bool isFiring = !!GetEntProp(manager, Prop_Send, "m_bIsFiring");
	
	if (!isFiring)
		return;
	
	int weapon = OwnerOf(manager);
	int player = OwnerOf(weapon);
	
	g_historyCursors[player] = (g_historyCursors[player] + 1) & HISTORY_RING_MASK;
	int cursor = g_historyCursors[player];
	
	g_timestampsHistory[player][cursor] = GetGameTime();
	
	GetClientEyeAngles(
		player,
		g_directionsHistory[player][cursor]
	);
	
	GetAngleVectors(
		g_directionsHistory[player][cursor],
		g_directionsHistory[player][cursor],
		NULL_VECTOR,
		NULL_VECTOR
	);
}

MRESReturn CTFFlameManager_GetFlameDamageScale_Pre(
	int manager, DHookReturn result, DHookParam params)
{
	g_customDamageFactor = 1.0;
	
	if (!sm_ftrehab_plugin_enabled.BoolValue)
		return MRES_Ignored;
	
	int weapon = OwnerOf(manager);
	
	if (weapon != -1)
	{
		int attacker = OwnerOf(weapon);
		
		if (attacker != -1)
		{
			if (sm_ftrehab_angular_speed_affects_damage.BoolValue)
			{
				Address pFlame = DHookGetParamAddress(params, 1);
				g_customDamageFactor = EstimateFlameDensityFactor(attacker, pFlame);
			}
			
			if (sm_ftrehab_display_angular_speed_multiplier.BoolValue)
			{
				PrintCenterText(attacker, "%d", RoundFloat(g_customDamageFactor * 100.0));
			}
			
			if (sm_ftrehab_custom_rampup_enabled.BoolValue)
			{
				Address pVictim = view_as<Address>(DHookGetParam(params, 2));				
				int hVictim = Load32(OffsetPointer(pVictim, g_offset__m_RefEHandle));				
				int victimRef = hVictim | 0x80000000;
				
				if (IsValidEntity(victimRef))
				{
					float rampupFactor = ApplyCustomRampup(
						attacker, victimRef, g_customDamageFactor);
					
					if (g_customDamageFactor > rampupFactor)
					{
						g_customDamageFactor = rampupFactor;
					}
					
					if (sm_ftrehab_display_custom_rampup.BoolValue)
					{
						PrintCenterText(
							attacker, "Rampup: %d%%", RoundFloat(rampupFactor * 100.0));
					}
				}
			}
		}
	}
	
	if (sm_ftrehab_bluemoon_rampup.BoolValue)
	{
		return MRES_Ignored;
	}
	else
	{
		DHookSetParam(params, 2, 0);
		return MRES_ChangedHandled;
	}
	
}

MRESReturn CTFFlameManager_GetFlameDamageScale_Post(
	int manager, DHookReturn result, DHookParam params)
{	
	if (sm_ftrehab_refill_dummy_bots.BoolValue)
	{
		ServerCommand("bot_refill");
	}
	
	float resultValue = DHookGetReturn(result);
	resultValue *= g_customDamageFactor;
	DHookSetReturn(result, resultValue);
	
	return MRES_ChangedOverride;
}



// Forwards
// ----------------------------------------------------------------------------

public void OnPluginStart()
{
	CacheOffsets();
	
	sm_ftrehab_refill_dummy_bots = CreateConVar(
		"sm_ftrehab_refill_dummy_bots",
		"0",
		"(For development) Whenever damage computations are made, \"bot_refill\" is executed",
		0,
		true, 0.0,
		true, 1.0
	);
	
	sm_ftrehab_display_custom_rampup = CreateConVar(
		"sm_ftrehab_display_custom_rampup",
		"0",
		"(For development) If enabled, damage multiplier that is based on custom rampup will be displayed to the player",
		0,
		true, 0.0,
		true, 1.0
	);
	
	sm_ftrehab_display_angular_speed_multiplier = CreateConVar(
		"sm_ftrehab_display_angular_speed_multiplier",
		"0",
		"(For development) If enabled, damage multiplier that is based on angular speed will be displayed to the player",
		0,
		true, 0.0,
		true, 1.0
	);
	
	sm_ftrehab_custom_rampup_increment_is_affected_by_angular_speed = CreateConVar(
		"sm_ftrehab_custom_rampup_increment_is_affected_by_angular_speed",
		"1",
		"Custom rampup increment should be multiplied by angular speed damage factor",
		0,
		true, 0.0,
		true, 1.0
	);
	
	sm_ftrehab_custom_rampup_first_tick_deals_max_damage = CreateConVar(
		"sm_ftrehab_custom_rampup_first_tick_deals_max_damage",
		"0",
		"If rampup amount is exactly at minimum, maximum damage will be dealt (this is how the weapon behaves in unmodified game!)",
		0,
		true, 0.0,
		true, 1.0
	);
	
	sm_ftrehab_custom_rampup_drain_time = CreateConVar(
		"sm_ftrehab_custom_rampup_drain_time",
		"0.5",
		"It takes THIS many seconds to drain rampup from max to min",
		0,
		true, 0.001		
	);
	
	sm_ftrehab_custom_rampup_linger_time = CreateConVar(
		"sm_ftrehab_custom_rampup_linger_time",
		"0.2",
		"When not refreshed, rampup won't be drained for THIS many seconds",
		0,
		true, 0.0
	);
	
	sm_ftrehab_custom_rampup_increment_per_hit = CreateConVar(
		"sm_ftrehab_custom_rampup_increment_per_hit",
		"0.15",
		"Amount of rampup gain per hit (from 0.0 to 1.0 where these numbers represent min and max damage respectively)",
		0,
		true, 0.0
	);
	
	sm_ftrehab_custom_rampup_enabled = CreateConVar(
		"sm_ftrehab_custom_rampup_enabled",
		"1",
		"Enables custom damage rampup",
		0,
		true, 0.0,
		true, 1.0
	);
	
	sm_ftrehab_angular_speed_end_penalty = CreateConVar(
		"sm_ftrehab_angular_speed_end_penalty",
		"900",
		"The damage penalty is at maximum whenever the angular speed is estimated to be greater than THIS value (deg/s)",
		0,
		true, 0.0
	);
	
	sm_ftrehab_angular_speed_start_penalty = CreateConVar(
		"sm_ftrehab_angular_speed_start_penalty",
		"400",
		"There will be no damage penalty so long the angular speed is estimated to be lower than THIS value (deg/s)",
		0,
		true, 0.0
	);
	
	sm_ftrehab_angular_speed_estimation_depth = CreateConVar(
		"sm_ftrehab_angular_speed_estimation_depth",
		"20",
		"Use THIS many frames at most for angular speed estimation",
		0,
		true, 1.0,
		true, 500.0
	);
	
	sm_ftrehab_angular_speed_estimation_time_window = CreateConVar(
		"sm_ftrehab_angular_speed_estimation_time_window",
		"0.35",
		"Look THIS far back (in seconds) into history for angular speed estimation",
		0,
		true, 0.1,
		true, 5.0
	);
	
	sm_ftrehab_angular_speed_affects_damage = CreateConVar(
		"sm_ftrehab_angular_speed_affects_damage",
		"1",
		"If enabled, player's angular speed affects flamethrower damage",
		0,
		true, 0.0,
		true, 1.0
	);
	
	sm_ftrehab_bluemoon_rampup = CreateConVar(
		"sm_ftrehab_bluemoon_rampup",
		"0",
		"0 = Disable Blue Moon rampup, 1 = Keep it as is",
		0,
		true, 0.0,
		true, 1.0
	);
	
	sm_ftrehab_reverse_flames_priority = CreateConVar(
		"sm_ftrehab_reverse_flames_priority",
		"1",
		"If enabled, reverses flames priority (i.e. the damage will be based on the youngest possible flame)",
		0,
		true, 0.0,
		true, 1.0
	);
	
	sm_ftrehab_plugin_enabled = CreateConVar(
		"sm_ftrehab_plugin_enabled",
		"1",
		"Enables the effect of \"Flamethrower Rehabilitation\" plugin",
		0,
		true, 0.0,
		true, 1.0
	);
	
	GameData conf = new GameData("tf2.flamethrower-rehabilitation");
	
	if (!conf)
		SetFailState("Couldn't load \"%s\" file!", "tf2.flamethrower-fix");
	
	Detour(
		conf,
		"CTFFlameManager::GetFlameDamageScale",
		CTFFlameManager_GetFlameDamageScale_Pre,
		CTFFlameManager_GetFlameDamageScale_Post
	);
	
	delete conf;
	
	for (int ent = -1; (ent = FindEntityByClassname(ent, "tf_flame_manager")) != -1;)
	{
		ApplySdkHooks(ent);
	}
	
	AutoExecConfig(true, "flamethrower-rehabilitation");	
}

public void OnEntityCreated(int ent, const char[] cls)
{
	if (!StrEqual(cls, "tf_flame_manager"))
		return;
	
	ApplySdkHooks(ent);
}

public void OnMapStart()
{
	for (int player = 1; player <= MAXPLAYERS; player++)
	{
		for (int slot = 0; slot < HISTORY_RING_SIZE; slot++)
		{
			g_timestampsHistory[player][slot] = -1000.0;
		}
	}
	
	for (int cursor = 0; cursor < RAMPUP_RING_SIZE; cursor++)
	{
		g_rampup[cursor].attackerRef = -1;
		g_rampup[cursor].victimRef = -1;
	}
}