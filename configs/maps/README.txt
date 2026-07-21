Per-map door configs for Another Jailbreak (AJB)
================================================

Path: addons/sourcemod/configs/ajb/maps/<mapname>.cfg
Example: jb_simple_b9.cfg

Format:

"AJBDoors"
{
	// Optional: 1 = do not merge built-in fallback names (use only this file)
	"nofallback"	"0"

	"targets"
	{
		"1"	"cells"
		"2"	"cell_door_1"
		"3"	"logic_open_cells"
	}
}

Notes:
- Values are entity targetnames (m_iName) the map uses for cell doors / relays / buttons.
- If no cfg exists, AJB uses common fallback names and scans entities whose name
  contains cell / jail / prison / cage.
- Admin: sm_ajb_doors_reload | sm_ajb_doors_list
- Prefer listing exact names for reliable open/close.
