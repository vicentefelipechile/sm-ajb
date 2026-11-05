// =========================================================================================================
// Another Jailbreak - Shared Dodgeball arena limits
// =========================================================================================================

#if defined _ajb_dodgeball_included
	#endinput
#endif
#define _ajb_dodgeball_included

#define DB_RADIUS_DEFAULT 1500.0
#define DB_RADIUS_STEP    128.0
#define DB_RADIUS_MIN     128.0
#define DB_RADIUS_MAX     8192.0

stock bool AJB_DB_IsRadiusValid(float radius)
{
	return radius >= 0.0 && radius <= DB_RADIUS_MAX;
}

stock float AJB_DB_AdjustRadius(float radius, bool increase)
{
	if (radius <= 1.0)
	{
		return increase ? DB_RADIUS_DEFAULT : 0.0;
	}
	float next = radius + (increase ? DB_RADIUS_STEP : -DB_RADIUS_STEP);
	if (next < DB_RADIUS_MIN) return DB_RADIUS_MIN;
	if (next > DB_RADIUS_MAX) return DB_RADIUS_MAX;
	return next;
}

stock bool AJB_DB_IsOutsideArena(const float origin[3], const float center[3], float radiusSquared)
{
	if (radiusSquared <= 1.0) return false;
	float dx = origin[0] - center[0];
	float dy = origin[1] - center[1];
	return dx * dx + dy * dy > radiusSquared;
}
