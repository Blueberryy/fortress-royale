/*
 * Copyright (C) 2020  Mikusch & 42
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

void Vehicles_Init()
{
	//Load common vehicle sounds
	if (g_LoadSoundscript)
		LoadSoundScript("scripts/game_sounds_vehicles.txt");
}

void Vehicles_SetupFinished()
{
	int pos;
	VehicleConfig config;
	while (VehiclesConfig_GetMapVehicle(pos, config))
	{
		config.entity = Vehicles_CreateEntity(config);
		VehiclesConfig_SetMapVehicle(pos, config);
		pos++;
	}
}

void Vehicles_Spawn(int entity)
{
	char targetname[CONFIG_MAXCHAR];
	GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
	
	VehicleConfig vehicle;
	if (VehiclesConfig_GetPrefabByName(targetname, vehicle))
	{
		DispatchKeyValue(entity, "vehiclescript", vehicle.vehiclescript);
		SetEntProp(entity, Prop_Data, "m_nVehicleType", vehicle.type);
		SetEntPropFloat(entity, Prop_Data, "m_flMinimumSpeedToEnterExit", fr_vehicle_lock_speed.FloatValue);
	}
	
	DispatchKeyValue(entity, "spawnflags", "1"); //SF_PROP_VEHICLE_ALWAYSTHINK
	
	AcceptEntityInput(entity, "HandBrakeOn");
	
	SDKHook(entity, SDKHook_Think, Vehicles_Think);
	SDKHook(entity, SDKHook_OnTakeDamage, Vehicles_OnTakeDamage);
}

void Vehicles_SpawnPost(int entity)
{
	//This needs to be done in SpawnPost, otherwise the vehicle is not properly initialized and will crash the server on removal
	if (GameRules_GetProp("m_bInWaitingForPlayers"))
		RemoveEntity(entity);
}

void Vehicles_OnEntityDestroyed(int entity)
{
	char classname[256];
	GetEntityClassname(entity, classname, sizeof(classname));
	if (StrEqual(classname, "prop_vehicle_driveable"))
	{
		int client = GetEntPropEnt(entity, Prop_Send, "m_hPlayer");
		if (0 < client <= MaxClients)
			SDKCall_HandlePassengerExit(entity, client);
	}
	
	VehicleConfig config;
	int pos = VehiclesConfig_GetMapVehicleByEntity(entity, config);
	if (pos >= 0)
	{
		config.entity = INVALID_ENT_REFERENCE;
		VehiclesConfig_SetMapVehicle(pos, config);
	}
}

public int Vehicles_CreateEntity(VehicleConfig config)
{
	int vehicle = CreateEntityByName("prop_vehicle_driveable");
	if (vehicle != INVALID_ENT_REFERENCE)
	{
		SetEntPropString(vehicle, Prop_Data, "m_iName", config.name);
		
		DispatchKeyValue(vehicle, "model", config.model);
		DispatchKeyValue(vehicle, "vehiclescript", config.vehiclescript);
		DispatchKeyValue(vehicle, "spawnflags", "1"); //SF_PROP_VEHICLE_ALWAYSTHINK
		SetEntProp(vehicle, Prop_Data, "m_nSkin", config.skin);
		SetEntProp(vehicle, Prop_Data, "m_nVehicleType", config.type);
		
		if (DispatchSpawn(vehicle))
		{
			SetEntPropFloat(vehicle, Prop_Data, "m_flMinimumSpeedToEnterExit", fr_vehicle_lock_speed.FloatValue);
			
			AcceptEntityInput(vehicle, "HandBrakeOn");
			
			float origin[3], angles[3];
			StringToVector(config.origin, origin);
			StringToVector(config.angles, angles);
			TeleportEntity(vehicle, origin, angles, NULL_VECTOR);
		}
		
		return EntIndexToEntRef(vehicle);
	}
	
	return INVALID_ENT_REFERENCE;
}

void Vehicles_CreateEntityAtCrosshair(VehicleConfig config, int client)
{
	int entity = Vehicles_CreateEntity(config);
	if (entity != -1)
	{
		float position[3];
		GetClientEyePosition(client, position);
		if (TR_PointOutsideWorld(position) || !MoveEntityToClientEye(entity, client, MASK_SOLID | MASK_WATER))
		{
			RemoveEntity(entity);
			return;
		}
	}
}

public void Vehicles_Think(int vehicle)
{
	int client = GetEntPropEnt(vehicle, Prop_Data, "m_hPlayer");
	int sequence = GetEntProp(vehicle, Prop_Data, "m_nSequence");
	bool exitAnimOn = view_as<bool>(GetEntProp(vehicle, Prop_Data, "m_bExitAnimOn"));
	
	bool handleEntryExit;
	
	if (sequence == 10 && 0 < client <= MaxClients)
	{
		//HACK: Certain vehicles use sequence with ID 10, which fails to properly play and softlocks the player
		//Don't bother with any of the animation stuff, just let the client into the vehicle
		handleEntryExit = true;
	}
	else
	{
		bool sequenceFinished = view_as<bool>(GetEntProp(vehicle, Prop_Data, "m_bSequenceFinished"));
		bool enterAnimOn = view_as<bool>(GetEntProp(vehicle, Prop_Data, "m_bEnterAnimOn"));
		
		SDKCall_StudioFrameAdvance(vehicle);
		handleEntryExit = sequenceFinished && (enterAnimOn || exitAnimOn);
	}
	
	if (handleEntryExit)
	{
		ShowKeyHintText(client, "%t", "Vehicle_HowToDrive");
		AcceptEntityInput(vehicle, "TurnOn");
		SDKCall_HandleEntryExitFinish(vehicle, exitAnimOn, !exitAnimOn);
	}
}

public Action Vehicles_OnTakeDamage(int entity, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	if (damagetype & DMG_CRUSH)
		return;
	
	//Damage to the vehicle gets propagated to the driver
	int client = GetEntPropEnt(entity, Prop_Send, "m_hPlayer");
	if (0 < client <= MaxClients)
		SDKHooks_TakeDamage(client, inflictor, attacker, damage * fr_vehicle_passenger_damagemultiplier.FloatValue, damagetype, weapon, damageForce, damagePosition);
}
