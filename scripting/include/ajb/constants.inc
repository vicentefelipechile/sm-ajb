// =========================================================================================================
// Another Jailbreak — Shared constants
// =========================================================================================================

#if defined _ajb_constants_included
 #endinput
#endif
#define _ajb_constants_included

#define AJB_LIBRARY             "ajb"

// SourceMod convention: every plugin exposes a version ConVar (sm_ajb_version).
// Bump this single define when shipping a release; myinfo + ConVar both read it.
#define AJB_PLUGIN_VERSION      "1.0.0"

#define AJB_TRANSLATIONS_FILE   "ajb.phrases"

#define AJB_TEAM_UNASSIGNED     0
#define AJB_TEAM_SPECTATOR      1
#define AJB_TEAM_RED            2
#define AJB_TEAM_BLU            3

// m_iObjectType / player_builtobject "object"
#define AJB_OBJ_DISPENSER       0
#define AJB_OBJ_TELEPORTER      1
#define AJB_OBJ_SENTRYGUN       2


#define AJB_MAX_DOOR_NAMES      64
#define AJB_MAX_DOOR_NAME_LEN   64
#define AJB_MAX_MAP_PREFIX_LEN  32

#define AJB_CONFIG_DIR          "configs/ajb"
#define AJB_MAP_CONFIG_DIR      "configs/ajb/maps"
