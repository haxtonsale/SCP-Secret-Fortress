static const char SCP18Model[] = "models/scp_fixed/scp18/w_scp18.mdl";
static const char SCP18HitSound[] = "weapons/samurai/tf_marked_for_death_impact_01.wav";
static const char SCP18ClientHitSound[] = "weapons/grappling_hook_impact_flesh.wav";
static const char SCP18BreakSound[] = "weapons/ball_buster_break_02.wav";

//static const float SCP18VelocityFactor = 1.08;
static const float SCP18VelocityBoost = 40.0;
static const float SCP18GravityFactor = 0.5;
static const float SCP18GravityAccelTime = 3.0;
static const float SCP18MaxVelocity = 10000.0;
static const float SCP18MaxDamage = 1000.0;
static const float SCP18Lifetime = 20.0;

enum struct SCP18Enum
{
	int EntRef;
	int EntIndex;
	int Thrower;
	int Class;
	int Bounces;
	float SpawnTime;
	float Magnitude;
	float Position[3];
	float Velocity[3];
	int ClientHits[MAXPLAYERS];
}

// list of all scp 18 entities
static ArrayList SCP18List;

// cached convars
bool SCP18FriendlyFire;
float SCP18Gravity;

public void Init_SCP18()
{	
	if(SCP18List != INVALID_HANDLE)
		delete SCP18List;
	
	SCP18List = new ArrayList(sizeof(SCP18Enum));
	
	PrecacheSound(SCP18HitSound, true);
	PrecacheSound(SCP18ClientHitSound, true);
	PrecacheSound(SCP18BreakSound, true);
}

// temporary storage for the trace... thanks sourcemod :(
SCP18Enum SCP18Trace;

float SCP18Damage;
float SCP18Volume;
int SCP18Pitch;

public bool SCP18_Trace(int entity, int mask)
{
	if (entity > 0 && entity <= MaxClients)
	{
		// only deal damage to a client once per bounce trajectory
		if (SCP18Trace.ClientHits[entity] != SCP18Trace.Bounces)
		{
			if ((entity == SCP18Trace.Thrower) || SCP18FriendlyFire || !IsFriendly(Client[entity].Class, SCP18Trace.Class) || IsFakeClient(entity))
			{
				SDKHooks_TakeDamage(entity, SCP18Trace.EntIndex, SCP18Trace.Thrower, SCP18Damage, DMG_CLUB);
				SCP18Trace.ClientHits[entity] = SCP18Trace.Bounces;
				
				EmitSoundToAll(SCP18ClientHitSound, entity, SNDCHAN_BODY, SNDLEVEL_NORMAL, _, SCP18Volume, SCP18Pitch);				
			}
		}
	}
	
	// TODO: door destruction logic
	//char buffer[8];
	//// anything prefixed with func_ can be safely regarded as a brush entity
	//return (GetEntityClassname(entity, buffer, sizeof(buffer)) && (!strncmp(buffer, "func_", 5, false)));
	
	// keep going
	return true;
}

public void SCP18_TryTouchTeleport(float mins[3], float maxs[3], float dest[3])
{
	int count = SCP18List.Length;
	for (int i = 0; i < count; i++)
	{
		SCP18Enum scp18;
		SCP18List.GetArray(i, scp18);
		
		if (IsPointTouchingBox(scp18.Position, mins, maxs))
		{
			CopyVector(dest, scp18.Position);
			SCP18List.SetArray(i, scp18);
		}
	}
}

public void SCP18_Tick()
{
	if (SCP18List == INVALID_HANDLE)
		return;
		
	// faster to cache this off
	SCP18FriendlyFire = CvarFriendlyFire.BoolValue;
	SCP18Gravity = CvarGravity.FloatValue;
	
	float gravity[3] = { 0.0, 0.0, 0.0 };
	gravity[2] = SCP18Gravity * -SCP18GravityFactor;
	int count = SCP18List.Length;
	float tickinterval = GetTickInterval();
	float time = GetGameTime();
				
	// go backwards as we might delete entries as we go
	for (int i = count-1; i >= 0; i--)
	{
		SCP18Enum scp18;
		SCP18List.GetArray(i, scp18);
		
		scp18.EntIndex = EntRefToEntIndex(scp18.EntRef);
		
		// no longer exists? get rid of it
		if (scp18.EntIndex <= MaxClients)
		{
			SCP18List.Erase(i);
			continue;
		}
		
		// if we are at max velocity, check if we have exceeded our lifetime
		if (scp18.Magnitude == SCP18MaxVelocity && ((scp18.SpawnTime + SCP18Lifetime) < time))
		{
			EmitSoundToAll(SCP18BreakSound, scp18.EntIndex, SNDCHAN_AUTO, SNDLEVEL_NORMAL, _, SNDVOL_NORMAL);
			CreateTimer(0.1, Timer_RemoveEntity, scp18.EntRef, TIMER_FLAG_NO_MAPCHANGE);
			SCP18List.Erase(i);
			continue;
		}
		
		float position[3], nextposition[3], hitposition[3], hitnormal[3], velocity[3], direction[3], reflection[3];
		
		CopyVector(scp18.Position, position);
		CopyVector(scp18.Velocity, velocity);
		
		// apply gravity on throw only
		if (scp18.Bounces == 0)
		{
			// slowly apply it
			float gravityaccel = time - scp18.SpawnTime;
			if (gravityaccel > SCP18GravityAccelTime)
				gravityaccel = SCP18GravityAccelTime;
			gravityaccel /= SCP18GravityAccelTime;
			
			float newgravity[3];
			CopyVector(gravity, newgravity);
			ScaleVector(newgravity, gravityaccel);
			AddVectors(velocity, newgravity, velocity);
		}
		
		ScaleVector(velocity, tickinterval);		
		AddVectors(position, velocity, nextposition);
		
		// trace from current position to next predicted position, ignore any players
		TR_TraceRayFilter(position, nextposition, MASK_SOLID, RayType_EndPoint, Trace_WorldAndBrushes);
		
		// TODO: don't bounce from doors?
		if (TR_DidHit())
		{
			TR_GetEndPosition(hitposition);
			TR_GetPlaneNormal(INVALID_HANDLE, hitnormal);
			
			// disappear if we hit the sky
			if (TR_GetSurfaceFlags() & SURF_SKY)
			{
				AcceptEntityInput(scp18.EntIndex, "Kill");
				SCP18List.Erase(i);
				continue;
			}		
					
			// calculate reflection from the hit point
			SubtractVectors(nextposition, position, direction);
			NormalizeVector(direction, direction);
			ScaleVector(hitnormal, GetVectorDotProduct(direction, hitnormal) * 2.0);		
			SubtractVectors(direction, hitnormal, reflection);
						
			scp18.Bounces++;					

			// gain some speed depending on how fast we are currently going	
			// -- a fixed amount seems to work better
			//scp18.Magnitude *= RemapValueInRange(scp18.Magnitude, 0.0, SCP18MaxVelocity, SCP18VelocityFactor, 1.0);	
			scp18.Magnitude += SCP18VelocityBoost;
			
			if (scp18.Magnitude > SCP18MaxVelocity) // don't go too insane!
				scp18.Magnitude = SCP18MaxVelocity;
				
			ScaleVector(reflection, scp18.Magnitude);	
			CopyVector(hitposition, scp18.Position);
			CopyVector(reflection, scp18.Velocity);
			
			TeleportEntity(scp18.EntIndex, hitposition, NULL_VECTOR, reflection);		
			
			EmitSoundToAll(SCP18HitSound, scp18.EntIndex, SNDCHAN_BODY, SNDLEVEL_NORMAL, _, SNDVOL_NORMAL);
		}
		else
		{
			CopyVector(nextposition, scp18.Position);
			CopyVector(nextposition, hitposition);
			
			// keep going in straight line
			TeleportEntity(scp18.EntIndex, nextposition, NULL_VECTOR, scp18.Velocity);
		}
		
		// only deal damage after 1st bounce
		if (scp18.Bounces > 0)
		{		
			// copy into a temporary global variable
			SCP18List.GetArray(i, SCP18Trace);
			// pre calculate damage + volume
			float Ratio = SCP18Trace.Magnitude / SCP18MaxVelocity;
			SCP18Damage = SCP18MaxDamage * Ratio;
			SCP18Volume = LerpValue(Ratio, 0.3, 1.0);
			SCP18Pitch = RoundFloat(LerpValue(Ratio, 85.0, 115.0));
			
			// redo the trace to damage players, with the possibly truncated end position from the trace before
			TR_TraceRayFilter(position, hitposition, MASK_SOLID, RayType_EndPoint, SCP18_Trace);
			
			// copy over any client hits
			for (int j = 1; j <= MaxClients; j++)
				scp18.ClientHits[j] = SCP18Trace.ClientHits[j];				
		}
		
		SCP18List.SetArray(i, scp18);
	}
}

public bool SCP18_Button(int client, int weapon, int &buttons, int &holding)
{
	if(!holding && !Items_InDelayedAction(client))
	{
		bool short = view_as<bool>(buttons & IN_ATTACK2);
		if(short || (buttons & IN_ATTACK))
		{
			holding = short ? IN_ATTACK2 : IN_ATTACK;

			// remove after a delay so the viewmodel throw animation can play out
			Items_StartDelayedAction(client, 0.3, Items_GrenadeAction, client);

			ViewModel_SetAnimation(client, "use");
			Config_DoReaction(client, "throwgrenade");		

			int entity = CreateEntityByName("prop_dynamic");
			if(IsValidEntity(entity))
			{
				DispatchKeyValue(entity, "solid", "0");

				static float ang[3], pos[3], vel[3];
				GetEntPropVector(client, Prop_Send, "m_vecOrigin", pos);
				GetClientEyeAngles(client, ang);
				pos[2] += 63.0;

				Items_GrenadeTrajectory(ang, vel, 300.0);

				if(short)
					ScaleVector(vel, 0.25);

				SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", client);
				SetEntProp(entity, Prop_Send, "m_iTeamNum", GetClientTeam(client));

				SetEntityModel(entity, SCP18Model);

				DispatchSpawn(entity);
				
				// allow it to move, smoothly
				SetEntityMoveType(entity, MOVETYPE_NOCLIP);		
				SetEntityFlags(entity, GetEntityFlags(entity) & (~FL_STATICPROP));
				
				// sets the kill icon
				SetVariantString("classname deflect_ball"); 
				AcceptEntityInput(entity, "AddOutput");				
				
				TeleportEntity(entity, pos, ang, vel);
				
				SCP18Enum scp18;
				scp18.EntRef = EntIndexToEntRef(entity);
				scp18.EntIndex = entity;
				scp18.Thrower = client;
				scp18.SpawnTime = GetGameTime();
				scp18.Bounces = 0;
				CopyVector(pos, scp18.Position);
				CopyVector(vel, scp18.Velocity);
				scp18.Magnitude = NormalizeVector(vel, vel);
				scp18.Class = Client[client].Class;
				for (int i = 1; i <= MaxClients; i++)
					scp18.ClientHits[i] = 0;		
				SCP18List.PushArray(scp18);
			}
		}
	}
	
	return false;
}