Per-map config for Another Jailbreak (AJB)
==========================================

Path: addons/sourcemod/configs/ajb/maps/<mapname>.cfg
Example: jb_simple_b9.cfg

Format:

"AJB"
{
	"doors"
	{
		// Optional: 1 = do not merge built-in fallback names
		"nofallback"	"0"

		"targets"
		{
			"1"	"cells"
			"2"	"cell_door_1"
		}
	}

	"teleports"
	{
		// Only applied if "origin" is set ("x y z"). No inventing coords.
		"freeday"
		{
			"origin"	"123.0 456.0 78.0"
			"angles"	"0 90 0"
		}
		"combat_red"
		{
			"origin"	"..."
			"angles"	"0 0 0"
		}
		"combat_blu"
		{
			"origin"	"..."
			"angles"	"0 180 0"
		}
	}
}

Legacy door-only files still work:

"AJBDoors"
{
	"targets"
	{
		"1"	"cells"
	}
}

Notes:
- Door values are entity targetnames (m_iName).
- Teleports: freeday (personal FD), combat_red / combat_blu (War Day / Class Warfare).
- Get coords in-game: getpos / getpos_exact
- Admin: sm_ajb_doors_reload (doors + teleports) | sm_ajb_doors_list
- Global policy (trail, warden-only dmg): configs/ajb/settings.cfg
