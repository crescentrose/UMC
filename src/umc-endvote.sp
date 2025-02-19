// SPDX-License-Identifier: GPL-3.0-only

#pragma semicolon 1

#include <sourcemod>
#include <umc-core>
#include <umc_utils>
#include <umc-endvote>

#undef REQUIRE_PLUGIN
#include <mapchooser>

#pragma newdecls required

public Plugin myinfo =
{
    name        = "[UMC] End of Map Vote",
    author      = "Steell, Powerlord, Mr.Silence, VIORA",
    description = "Extends Ultimate Mapchooser to allow End of Map Votes.",
    version     = PL_VERSION,
    url         = "https://github.com/crescentrose/umc"
};

ConVar cvar_filename, cvar_scramble, cvar_vote_time, cvar_strict_noms,
    cvar_runoff, cvar_runoff_sound, cvar_runoff_max, cvar_vote_allowduplicates,
    cvar_vote_threshold, cvar_fail_action, cvar_runoff_fail_action, cvar_endvote,
    cvar_extend_rounds, cvar_extend_frags, cvar_extend_time, cvar_extensions,
    cvar_start_frags, cvar_start_time, cvar_start_rounds, cvar_vote_mem,
    cvar_vote_type, cvar_vote_startsound, cvar_vote_endsound, cvar_vote_catmem,
    cvar_vote_roundend, cvar_flags, cvar_delay, cvar_changetime, cvar_maxrounds,
    cvar_fraglimit, cvar_winlimit;

KeyValues map_kv, umc_mapcycle;

// Memory queues. Used to store the previously played maps.
ArrayList vote_mem_arr, vote_catmem_arr;

Handle vote_timer; // Timer which handles end-of-map vote based off of time remaining.

// Flags
bool timer_alive;      // Is the time-based vote timer ticking?
bool vote_enabled;     // Are we able to run a vote? Means that the timer is running.
bool vote_roundend;    // Are we going to start a vote when this round is over?
bool vote_completed;   // Has an end of map vote been completed?
bool vote_failed;      // Did the vote fail due to no players?

//Keeps track of the time before the end-of-map vote starts.
float vote_delaystart;

//Counts the rounds.
int round_counter = 0;

//Counts how many times each team has won.
#define MAXTEAMS 10
int team_wincounts[MAXTEAMS];

//Counts the number of available extensions.
int extend_counter;

// Name of current map
char current_map_name[MAP_LENGTH];

//Sounds to be played at the start and end of votes.
char vote_start_sound[PLATFORM_MAX_PATH], vote_end_sound[PLATFORM_MAX_PATH],
    runoff_sound[PLATFORM_MAX_PATH];
     
/* Forwards */
Handle time_update_forward, round_update_forward, win_update_forward,
    frag_update_forward, time_tick_forward, round_tick_forward, win_tick_forward,
    frag_tick_forward;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    RegPluginLibrary("mapchooser");

    CreateNative("HasEndOfMapVoteFinished", Native_CheckVoteDone);
    CreateNative("EndOfMapVoteEnabled", Native_EndOfMapVoteEnabled);
    
    RegPluginLibrary("umc-endvote");
    
    return APLRes_Success;
}

// Called when the plugin is finished loading.
public void OnPluginStart() {
    cvar_changetime = CreateConVar(
        "sm_umc_endvote_changetime",
        "2",
        "When to change the map after a successful vote:\n 0 - Instant,\n 1 - Round End,\n 2 - Map End",
        0, true, 0.0, true, 2.0
    );

    cvar_delay = CreateConVar(
        "sm_umc_endvote_roundend_delaystart",
        "0",
        "Delays the vote by the number of seconds specified for votes that are triggered by mp_maxrounds or mp_winlimit.",
        0, true, 0.0
    );
    
    cvar_flags = CreateConVar(
        "sm_umc_endvote_adminflags",
        "",
        "Specifies which admin flags are necessary for a player to participate in a vote. If empty, all players can participate."
    );

    cvar_vote_roundend = CreateConVar(
        "sm_umc_endvote_onroundend",
        "0",
        "Determines whether End of Map Votes should be delayed until the end of the round in which they were triggered.",
        0, true, 0.0, true, 1.0
    );

    cvar_fail_action = CreateConVar(
        "sm_umc_endvote_failaction",
        "0",
        "Specifies what action to take if the vote doesn't reach the set theshold.\n 0 - Do Nothing,\n 1 - Perform Runoff Vote",
        0, true, 0.0, true, 1.0
    );
    
    cvar_runoff_fail_action = CreateConVar(
        "sm_umc_endvote_runoff_failaction",
        "0",
        "Specifies what action to take if the runoff vote reaches the maximum amount of runoffs and the set threshold has not been reached.\n 0 - Do Nothing,\n 1 - Change Map to Winner",
        0, true, 0.0, true, 1.0
    );
    
    cvar_runoff_max = CreateConVar(
        "sm_umc_endvote_runoff_max",
        "0",
        "Specifies the maximum number of maps to appear in a runoff vote.\n 1 or 0 sets no maximum.",
        0, true, 0.0
    );

    cvar_vote_allowduplicates = CreateConVar(
        "sm_umc_endvote_allowduplicates",
        "1",
        "Allows a map to appear in the vote more than once. This should be enabled if you want the same map in different categories to be distinct.",
        0, true, 0.0, true, 1.0
    );
    
    cvar_vote_threshold = CreateConVar(
        "sm_umc_endvote_threshold",
        "0",
        "If the winning option has less than this percentage of total votes, a vote will fail and the action specified in \"sm_umc_endvote_failaction\" cvar will be performed.",
        0, true, 0.0, true, 1.0
    );
    
    cvar_runoff = CreateConVar(
        "sm_umc_endvote_runoffs",
        "0",
        "Specifies a maximum number of runoff votes to run for any given vote.\n 0 = unlimited.",
        0, true, 0.0
    );
    
    cvar_runoff_sound = CreateConVar(
        "sm_umc_endvote_runoff_sound",
        "",
        "If specified, this sound file (relative to sound folder) will be played at the beginning of a runoff vote. If not specified, it will use the normal vote start sound."
    );
    
    cvar_vote_catmem = CreateConVar(
        "sm_umc_endvote_groupexclude",
        "0",
        "Specifies how many past map groups to exclude from the end of map vote.",
        0, true, 0.0
    );
    
    cvar_vote_startsound = CreateConVar(
        "sm_umc_endvote_startsound",
        "",
        "Sound file (relative to sound folder) to play at the start of an end-of-map vote."
    );
    
    cvar_vote_endsound = CreateConVar(
        "sm_umc_endvote_endsound",
        "",
        "Sound file (relative to sound folder) to play at the completion of an end-of-map vote."
    );
    
    cvar_strict_noms = CreateConVar(
        "sm_umc_endvote_nominate_strict",
        "0",
        "Specifies whether the number of nominated maps appearing in the vote for a map group should be limited by the group's \"maps_invote\" setting.",
        0, true, 0.0, true, 1.0
    );

    cvar_extend_rounds = CreateConVar(
        "sm_umc_endvote_extend_roundstep",
        "5",
        "Specifies how many more rounds each extension adds to the round limit.",
        0, true, 1.0
    );

    cvar_extend_time = CreateConVar(
        "sm_umc_endvote_extend_timestep",
        "15",
        "Specifies how many more minutes each extension adds to the time limit.",
        0, true, 1.0
    );

    cvar_extend_frags = CreateConVar(
        "sm_umc_endvote_extend_fragstep",
        "10",
        "Specifies how many more frags each extension adds to the frag limit.",
        0, true, 1.0
    );

    cvar_extensions = CreateConVar(
        "sm_umc_endvote_extends",
        "0",
        "Number of extensions allowed each map.\n 0 disables the Extend Map option.",
        0, true, 0.0
    );

    cvar_endvote = CreateConVar(
        "sm_umc_endvote_enabled",
        "1",
        "Specifies if Ultimate Mapchooser should run an end of map vote.",
        0, true, 0.0, true, 1.0
    );

    cvar_vote_type = CreateConVar(
        "sm_umc_endvote_type",
        "0",
        "Controls end of map vote type:\n 0 - Maps,\n 1 - Groups,\n 2 - Tiered Vote (vote for a group, then vote for a map from the group).",
        0, true, 0.0, true, 2.0
    );

    cvar_start_time = CreateConVar(
        "sm_umc_endvote_starttime",
        "6",
        "Specifies when to start the vote based on time remaining in minutes.",
        0, true, 1.0
    );

    cvar_start_rounds = CreateConVar(
        "sm_umc_endvote_startrounds",
        "2",
        "Specifies when to start the vote based on rounds remaining. Use 0 on TF2 to start vote during bonus round time",
        0, true, 0.0
    );

    cvar_start_frags = CreateConVar(
        "sm_umc_endvote_startfrags",
        "10",
        "Specifies when to start the vote based on frags remaining.",
        0, true, 1.0
    );

    cvar_vote_time = CreateConVar(
        "sm_umc_endvote_duration",
        "20",
        "Specifies how long a vote should be available for.",
        0, true, 10.0
    );

    cvar_filename = CreateConVar(
        "sm_umc_endvote_cyclefile",
        "umc_mapcycle.txt",
        "File to use for Ultimate Mapchooser's map rotation."
    );

    cvar_vote_mem = CreateConVar(
        "sm_umc_endvote_mapexclude",
        "4",
        "Specifies how many past maps to exclude from the end of map vote. 1 = Current Map Only",
        0, true, 0.0
    );

    cvar_scramble = CreateConVar(
        "sm_umc_endvote_menuscrambled",
        "0",
        "Specifies whether vote menu items are displayed in a random order.",
        0, true, 0.0, true, 1.0
    );

    // Create the config if it doesn't exist, and then execute it.
    AutoExecConfig(true, "umc-endvote");

    // Set up our "timers" for the end-of-map vote.
    cvar_maxrounds = FindConVar("mp_maxrounds");
    cvar_fraglimit = FindConVar("mp_fraglimit");
    cvar_winlimit  = FindConVar("mp_winlimit");
    
    if (cvar_maxrounds != INVALID_HANDLE || cvar_winlimit != INVALID_HANDLE) {
        HookEvent("round_end",                Event_RoundEnd); //Generic
        HookEventEx("teamplay_round_stalemate", Event_RoundEndTF2); // TF2
        HookEventEx("teamplay_win_panel",     Event_RoundEndTF2); //TF2
        HookEventEx("arena_win_panel",        Event_RoundEndTF2); //TF2
        HookEventEx("teamplay_restart_round", Event_RestartRound); //TF2  
    }
    
    // Hook score.
    if (cvar_fraglimit != INVALID_HANDLE)
        HookEvent("player_death", Event_PlayerDeath);
    
    //Hook all necessary cvar changes
    HookConVarChange(cvar_vote_mem,   Handle_VoteMemoryChange);
    HookConVarChange(cvar_endvote,    Handle_VoteChange);
    HookConVarChange(cvar_start_time, Handle_TriggerChange);
    
    // Initialize our memory arrays
    int numCells = ByteCountToCells(MAP_LENGTH);
    vote_mem_arr = new ArrayList(numCells);
    vote_catmem_arr = new ArrayList(numCells);
    
    // Load the translations file
    LoadTranslations("ultimate-mapchooser.phrases");

    // Forwards
    time_update_forward  = CreateGlobalForward("UMC_EndVote_OnTimeTimerUpdated", ET_Ignore, Param_Cell);
    round_update_forward = CreateGlobalForward("UMC_EndVote_OnRoundTimerUpdated", ET_Ignore, Param_Cell);
    win_update_forward   = CreateGlobalForward("UMC_EndVote_OnWinTimerUpdated", ET_Ignore, Param_Cell, Param_Cell);
    frag_update_forward  = CreateGlobalForward("UMC_EndVote_OnFragTimerUpdated", ET_Ignore, Param_Cell, Param_Cell);
    time_tick_forward    = CreateGlobalForward("UMC_EndVote_OnTimeTimerTicked", ET_Ignore, Param_Cell);
    round_tick_forward   = CreateGlobalForward("UMC_EndVote_OnRoundTimerTicked", ET_Ignore, Param_Cell);
    win_tick_forward     = CreateGlobalForward("UMC_EndVote_OnWinTimerTicked", ET_Ignore, Param_Cell, Param_Cell);
    frag_tick_forward    = CreateGlobalForward("UMC_EndVote_OnFragTimerTicked", ET_Ignore, Param_Cell, Param_Cell);
}

public void OnConfigsExecuted() {
    //Votes are not enabled.
    vote_enabled = false;
    vote_roundend = false;
    vote_completed = false;
    vote_failed = false;
    
    //No timer is setup so delay is undefined
    vote_delaystart = -1.0;
    
    //Set the amount of remaining extensions allowed for the map.
    extend_counter = 0;
    
    //No rounds have finished yet.
    round_counter = 0;
    
    //Reset the stored team scores.
    for (int i = 0; i < MAXTEAMS; i++)
        team_wincounts[i] = 0;
     
    bool mapcycleLoaded = ReloadMapcycle();
    
    // Make end-of-map vote timers if the mapcycle was loaded successfully AND
    // the end-of-map vote cvar is enabled AND the timer is not currently alive.
    if (mapcycleLoaded && GetConVarBool(cvar_endvote) && !timer_alive)
        MakeVoteTimer();
    
    // Grab the name of the current map.
    GetCurrentMap(current_map_name, sizeof(current_map_name));
    LogUMCMessage("DEBUG: Current map name is %s", current_map_name);
    
    char groupName[MAP_LENGTH];
    UMC_GetCurrentMapGroup(groupName, sizeof(groupName));
    
    if (mapcycleLoaded && StrEqual(groupName, INVALID_GROUP, false))
        KvFindGroupOfMap(umc_mapcycle, current_map_name, groupName, sizeof(groupName));
    
    // Add the map to all the memory queues.
    int mapmem = GetConVarInt(cvar_vote_mem);
    int catmem = GetConVarInt(cvar_vote_catmem);
    AddToMemoryArray(current_map_name, vote_mem_arr, mapmem);
    AddToMemoryArray(groupName, vote_catmem_arr, (mapmem > catmem) ? mapmem : catmem);
    
    if (mapcycleLoaded)
        RemovePreviousMapsFromCycle();
}

public void OnMapStart() {
    SetupVoteSounds();
}

// Called when a player dies. Used for end-of-map vote based on frags.
public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
    int fraglimit = GetConVarInt(cvar_fraglimit);
    if (vote_enabled && fraglimit > 0) {
        int fragger = GetClientOfUserId(GetEventInt(event, "attacker"));
        
        if (!fragger)
            return;
         
        int startfrags = GetConVarInt(cvar_start_frags);
        int frags = GetClientFrags(fragger) + 1;
    
        if (frags >= (fraglimit - startfrags)) {
            LogUMCMessage("Frag limit triggered end of map vote.");
            DestroyTimers();
            SetupMapVote();
        }
        
        //Call the frag timer forward.
        Call_StartForward(frag_tick_forward);
        Call_PushCell(float(fraglimit - GetConVarInt(cvar_start_frags) - frags));
        Call_PushCell(fragger);
        Call_Finish();
    }
}

// Called if the the amount of map time left is changed at any point.
// Needed to update our vote timer.
public void OnMapTimeLeftChanged() {
    // Update the end-of-map vote timer if we haven't already completed an RTV.
    if (vote_enabled)
        UpdateTimers();

    if (vote_failed) {
        UpdateTimers();
        UpdateOtherTimers();
        vote_completed = false;
        vote_enabled = true;
        vote_failed = false;
    }
}

//Called when a round ends.
public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (vote_roundend) {
        vote_roundend = false;
        StartMapVoteRoundEnd();
    }
    
    int winner = GetEventInt(event, "winner");
    
    //Do nothing if there wasn't a winning team.
    if (winner == 0 || winner == 1)
        return;

    if (winner >= MAXTEAMS)
        SetFailState("Mod exceeded maximum team count - please file a bug report.");
    
    // Update the round "timer"
    round_counter++;
    team_wincounts[winner]++;
    
    if (vote_enabled) {
        CheckWinLimit(team_wincounts[winner], winner);
        CheckMaxRounds();
    }
}

//Called when a round ends in tf2.
public void Event_RoundEndTF2(Event event, const char[] name, bool dontBroadcast) {
    int timeleft;
    GetMapTimeLeft(timeleft);

    // we always want to trigger a vote if there is no more time on the clock
    if (vote_roundend || timeleft == 0) {
        vote_roundend = false;
        StartMapVoteRoundEnd();
    }

    int bluescore = GetEventInt(event, "blue_score");
    int redscore  = GetEventInt(event, "red_score");
    
    if (GetEventInt(event, "round_complete") == 1 || StrEqual(name, "arena_win_panel")) {
        round_counter++;
        
        if (vote_enabled) {
            CheckMaxRounds();
            
            int winningTeam = GetEventInt(event, "winning_team");
            
            switch (winningTeam)
            {
                case 3:
                    CheckWinLimit(bluescore, winningTeam);
                case 2:
                    CheckWinLimit(redscore, winningTeam);
                default:
                    return;
            }
        }
    }
}

public void Event_RestartRound(Event evnt, const char[] name, bool dontBroadcast) {
    round_counter = 0;
    
    if (cvar_maxrounds != INVALID_HANDLE) {
        //Update our vote warnings.
        Call_StartForward(round_update_forward);
        Call_PushCell(GetConVarInt(cvar_maxrounds) - GetConVarInt(cvar_start_rounds));
        Call_Finish();
    }
    
    for (int i = 0; i < MAXTEAMS; i++)
        team_wincounts[i] = 0;
        
    if (cvar_winlimit != INVALID_HANDLE) {
        Call_StartForward(win_update_forward);
        Call_PushCell(GetConVarInt(cvar_winlimit) - GetConVarInt(cvar_start_rounds));
        Call_PushCell(0);
        Call_Finish();
    }
}

public void OnMapEnd() {
    // Vote timer is not running
    timer_alive = false;
    if (vote_timer != null) {
        KillTimer(vote_timer);
        vote_timer = null;
    }
}

// Parses the mapcycle file and returns a KV handle representing the mapcycle.
KeyValues GetMapcycle() {
    char filename[PLATFORM_MAX_PATH];
    GetConVarString(cvar_filename, filename, sizeof(filename));
    
    Handle result = GetKvFromFile(filename, "umc_rotation");
    
    if (result == null) {
        LogError("SETUP: Mapcycle failed to load!");
        return null;
    }
    
    return view_as<KeyValues>(result);
}

// TODO: remove method
void SetupVoteSounds() {
    // Grab sound files from cvars.
    GetConVarString(cvar_vote_startsound, vote_start_sound, sizeof(vote_start_sound));
    GetConVarString(cvar_vote_endsound, vote_end_sound, sizeof(vote_end_sound));
    GetConVarString(cvar_runoff_sound, runoff_sound, sizeof(runoff_sound));
    
    // Gotta cache 'em all!
    CacheSound(vote_start_sound);
    CacheSound(vote_end_sound);
    CacheSound(runoff_sound);
}

// Sets up timers for an end-of-map vote.
void MakeVoteTimer() {
    //A vote has not been completed if we're making a new timer.
    vote_completed = false;
    
    // The end-of-map vote is now enabled.
    vote_enabled = true;
    
    // Make the end-of-map vote timer.
    if (timer_alive) {
        timer_alive = false;
        KillTimer(vote_timer);
        vote_timer = null;
    }

    vote_timer = MakeTimer();
    UpdateOtherTimers();
}

// Updates the non-mp_timelimit "timers."
void UpdateOtherTimers() {
    int start;
    
    if (cvar_maxrounds != INVALID_HANDLE) {
        start = GetConVarInt(cvar_maxrounds) - GetConVarInt(cvar_start_rounds) - round_counter;
        if (start > 0)
            LogUMCMessage("End of map vote will appear after %i more rounds.", start);
         
        // Update our vote warnings.
        Call_StartForward(round_update_forward);
        Call_PushCell(start);
        Call_Finish();
    }
    
    if (cvar_winlimit != INVALID_HANDLE) {
        int winScore;
        int winTeam = GetWinningTeam(winScore);
        start = GetConVarInt(cvar_winlimit) - GetConVarInt(cvar_start_rounds) - winScore;

        if (start > 0)
            LogUMCMessage("End of map vote will appear after %i more wins.", start);
        
        // Update our vote warnings.
        Call_StartForward(win_update_forward);
        Call_PushCell(start);
        Call_PushCell(winTeam);
        Call_Finish();
    }
    
    if (cvar_fraglimit != INVALID_HANDLE) {
        int fragCount;
        int topFragger = GetTopFragger(fragCount);
        start = GetConVarInt(cvar_fraglimit) - GetConVarInt(cvar_start_frags) - fragCount;

        if (start > 0)
            LogUMCMessage("End of map vote will appear after %i more frags.", start);
        
        //Update our vote warnings.
        Call_StartForward(frag_update_forward);
        Call_PushCell(start);
        Call_PushCell(topFragger);
        Call_Finish();
    }
}

// Reloads the mapcycle. Returns true on success, false on failure.
bool ReloadMapcycle()
{
    if (umc_mapcycle != null)
        delete umc_mapcycle;

    if (map_kv != null)
        delete map_kv;

    umc_mapcycle = GetMapcycle();
    
    return umc_mapcycle != INVALID_HANDLE;
}

void RemovePreviousMapsFromCycle() {
    map_kv = CreateKeyValues("umc_rotation");
    KvCopySubkeys(umc_mapcycle, map_kv);
    FilterMapcycleFromArrays(
        view_as<KeyValues>(map_kv),
        view_as<ArrayList>(vote_mem_arr),
        view_as<ArrayList>(vote_catmem_arr), 
        GetConVarInt(cvar_vote_catmem)
    );
}

// Called when the cvar for the maximum number of rounds has been changed. Used for end-of-map vote based on rounds.
public void Handle_MaxroundsChange(ConVar convar, const char[] oldVal, char[] newVal) {
    int start = StringToInt(newVal) - GetConVarInt(cvar_start_rounds) - round_counter;
    int old = StringToInt(oldVal);
    
    // Log
    if (start > 0) {
        LogUMCMessage("End of map vote will appear after %i more rounds.", start);
    }
    else if (old > 0) {
        LogUMCMessage("End of map vote round trigger disabled.");
    }
    
    Call_StartForward(round_update_forward);
    Call_PushCell(start);
    Call_Finish();
}

//Called when the cvar for the win limit has been changed. Used for end-of-map vote based on rounds.
public void Handle_WinlimitChange(ConVar cvar, const char[] oldVal, const char[] newVal) {
    int winScore;
    int winningTeam = GetWinningTeam(winScore);
    int start = StringToInt(newVal) - GetConVarInt(cvar_start_rounds) - winScore;
    int old = StringToInt(oldVal);
    
    if (start > 0) {
        LogUMCMessage("End of map vote will appear after %i more wins.", start);
    }
    else if (old > 0) {    
        LogUMCMessage("End of map vote round trigger disabled.");
    }
    else  {
        LogUMCMessage("DEBUG: New limit and old value are not greater than 0 for winlimit... potential problem?");
    }
    
    Call_StartForward(win_update_forward);
    Call_PushCell(start);
    Call_PushCell(winningTeam);
    Call_Finish();
}

// Called when the cvar for the maximum number of frags has been changed. Used for end-of-map vote
// based on frags.
public void Handle_FraglimitChange(ConVar cvar, const char[] oldVal, const char[] newVal) {
    int newlimit = StringToInt(newVal);

    if (newlimit > 0) {
        LogUMCMessage("End of map vote will appear after %i frags.", StringToInt(newVal) - GetConVarInt(cvar_start_frags));
    }
    else if (StringToInt(oldVal) > 0) {
        LogUMCMessage("End of map vote frag trigger disabled.");
    }
    else {
        LogUMCMessage("DEBUG: New limit and old value are not greater than 0 for fraglimit... potential problem?");
    }
    
    int topFrags;
    int topFragger = GetTopFragger(topFrags);
    
    Call_StartForward(frag_update_forward);
    Call_PushCell(float(newlimit - GetConVarInt(cvar_start_frags) - topFrags));
    Call_PushCell(topFragger);
    Call_Finish();
}

// Called when the number of excluded previous maps from end-of-map votes has changed.
public void Handle_VoteMemoryChange(ConVar cvar, const char[] oldVal, const char[] newVal) {
    // Trim the memory array for end-of-map votes.
    // We pass 1 extra to the argument in order to account for the current map, which should always be excluded.
    TrimArray(vote_mem_arr, StringToInt(newVal));
}

// Called when the cvar which enabled end-of-map votes has changed.
public void Handle_VoteChange(ConVar cvar, const char[] oldVal, const char[] newVal) {
    // Regardless of the change, destroy all existing end-of-map vote timers.
    DestroyTimers();
    vote_enabled = false;
    
    //Make new timers if the new value of the cvar is 1.
    if (StringToInt(newVal) == 1)
        MakeVoteTimer();
}

//Called when the cvar which specifies the time trigger for the end-of-round vote is changed.
public void Handle_TriggerChange(ConVar cvar, const char[] oldVal, const char[] newVal) {
    UpdateTimers();
}

// native HasEndOfMapVoteFinished();
public int Native_CheckVoteDone(Handle plugin, int numParams) {
    return vote_completed;
}

// native EndOfMapVoteEnabled();
public int Native_EndOfMapVoteEnabled(Handle plugin, int numParams) {
    return vote_enabled;
}

//************************************************************************************************//
//                                         END OF MAP VOTE                                        //
//************************************************************************************************//
// Fetches the index of the winning team.
int GetWinningTeam(int &score) {
    int wincount;
    int max = team_wincounts[0];
    int winning = 0;
    for (int i = 1; i < MAXTEAMS; i++) {
        wincount = team_wincounts[i];
        if (wincount > max) {
            max = wincount;
            winning = i;
        }
    }
    score = max;
    return winning;
}

// Fetches the index of the winning team.
int GetTopFragger(int &score) {
    int fragcount;
    int max = team_wincounts[0];
    int winning = 0;
    for (int i = 1; i <= MaxClients; i++) {
        if (!IsClientInGame(i))
            continue;
        
        fragcount = GetClientFrags(i);
        if (fragcount > max) {
            max = fragcount;
            winning = i;
        }
    }
    score = max;
    return winning;
}

// Starts a vote if the given score is high enough.
void CheckWinLimit(int winner_score, int winning_team) {
    int startRounds = GetConVarInt(cvar_start_rounds);
    if (cvar_winlimit == INVALID_HANDLE) 
        return;

    int winlimit = GetConVarInt(cvar_winlimit);
    if (winlimit == 0)
        return;

    int timeleft;
    GetMapTimeLeft(timeleft);

    // TF2 forces map change if the time remaining is less than 5 minutes
    if (winner_score >= (winlimit - startRounds) || (timeleft <= 310 && timeleft >= 0)) {
        LogUMCMessage("Win limit triggered end of map vote.");
        DestroyTimers();
        StartMapVoteRoundEnd();
    }
    
    Call_StartForward(win_tick_forward);
    Call_PushCell(winlimit - startRounds - winner_score);
    Call_PushCell(winning_team);
    Call_Finish();
}

// Starts a vote if the given round count is high enough
void CheckMaxRounds() {
    if (cvar_maxrounds == INVALID_HANDLE)
        return;

    int maxrounds; 
    maxrounds = GetConVarInt(cvar_maxrounds);
    
    if (maxrounds > 0) {
        int startRounds = GetConVarInt(cvar_start_rounds);

        if (round_counter >= (maxrounds - startRounds)) {
            LogUMCMessage("Round limit triggered end of map vote.");
            DestroyTimers();
            StartMapVoteRoundEnd();
        }
        
        Call_StartForward(round_tick_forward);
        Call_PushCell(maxrounds - startRounds - round_counter);
        Call_Finish();
    }
}

// Makes the timer which will activate the end-of-map vote at a certain time.
Handle MakeTimer() {
    Handle timer;
    if (SetTimerTriggerTime()) {
        // Make the timer
        timer = CreateTimer(
            1.0,
            Handle_MapVoteTimer,
            _,
            TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT
        );
        
        timer_alive = timer != null;
        
        if (!timer_alive)
            LogError("End of map timer could not be created. Please file a bug report with the author.");
    }
    else {
        timer_alive = false;
        LogUMCMessage("Unable to create end of map vote time-trigger, trigger time already passed.");
    }

    return timer;
}


// Called when the end-of-vote timer (vote_timer) is finished.
public Action Handle_MapVoteTimer(Handle timer) {
    // Handle vote warnings if vote warnings are enabled.
    Call_StartForward(time_tick_forward);
    Call_PushCell(RoundFloat(vote_delaystart));
    Call_Finish();

    //Continue ticking if there is still time left on the counter.
    if (vote_delaystart > 0) {
        //Tick another second off the timer counter.
        vote_delaystart--;
        return Plugin_Continue;
    }
    
    // If there isn't time left on the timer the timer is no longer alive.
    timer_alive = false;
    vote_timer = null;
    vote_delaystart = -1.0;
    
    // Start the end-of-map vote.
    SetupMapVote();
    
    return Plugin_Stop;
}

// Sets the time trigger for the end of map timer.
bool SetTimerTriggerTime() {
    // Get current timeleft.
    int timeleft;
    float triggertime, starttime;
    GetMapTimeLeft(timeleft);
    
    if (timeleft <= 0)
        return false;
    
    starttime = GetConVarFloat(cvar_start_time) * 60;
    
    // Duration until the vote starts.
    triggertime = timeleft - starttime;
    bool result;
    
    // Make the timer if the time to start the vote hasn't already passed.
    if (timeleft >= 0 && starttime > 0 && triggertime > 0) {
        // Setup counter until the end-of-map vote triggers.
        vote_delaystart = triggertime - 1;
        result = true;
        
        LogUMCMessage("End of map vote will appear after %.f seconds", triggertime);
    }
    else {
        // Never trigger the vote.
        vote_delaystart = -1.0;
        result = false;
    }
    
    // Update Vote Warnings if vote warnings are enabled.
    Call_StartForward(time_update_forward);
    Call_PushCell(RoundToFloor(triggertime));
    Call_Finish();
    
    return result;
}

//Update the end-of-map vote timer.
void UpdateTimers() {
    // Reset the timer if we haven't already completed a vote the cvar to run an end-of-round vote is enabled.
    if (timer_alive) {
        if (!SetTimerTriggerTime()) {
            timer_alive = false;
            KillTimer(vote_timer);
            vote_timer = null;
        }
        else {
            LogUMCMessage("Map vote timer successfully updated.");
        }
    }
    else {
        vote_timer = MakeTimer();
    }
}

// Disables all end-of-map vote timers.
void DestroyTimers() {
    LogUMCMessage("End of map vote disabled.");

    //Delete the time trigger if the timer is alive.
    if (timer_alive) {
        timer_alive = false;
        KillTimer(vote_timer);
        vote_timer = null;
    }
}

// Sets up a map vote.
void SetupMapVote() {
    if (GetConVarBool(cvar_vote_roundend)) {    
        vote_roundend = true;
    }
    else {
        StartMapVote();
    }
}

// Starts a map vote due to the round ending.
void StartMapVoteRoundEnd() {
    float delay = GetConVarFloat(cvar_delay);
    if (delay == 0.0) {
        StartMapVote();
    }
    else {   
        CreateTimer(delay, Handle_VoteDelayTimer, _, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Handle_VoteDelayTimer(Handle timer) {
    StartMapVote();
    return Plugin_Stop;
}

// Initiates the map vote.
public void StartMapVote() {
    if (!vote_enabled)
        return;

    //Log a message
    LogUMCMessage("Starting an end of map vote.");
    
    //Log an error and retry vote if another vote is currently running for some reason.
    if (!UMC_IsNewVoteAllowed("core")) {
        LogUMCMessage("There is a vote already in progress, cannot start a new vote.");
        MakeRetryVoteTimer(StartMapVote);
        return;
    }
    
    vote_enabled = false;
    vote_completed = true;
    char flags[64];
    GetConVarString(cvar_flags, flags, sizeof(flags));
    
    int clients[MAXPLAYERS+1];
    int numClients;
    GetClientsWithFlags(flags, clients, sizeof(clients), numClients);
    
    // Start the UMC vote.
    vote_failed = !UMC_StartVote(
        "core",
        map_kv,                                                               // Mapcycle
        umc_mapcycle,                                                         // Full mapcycle
        view_as<UMC_VoteType>(GetConVarInt(cvar_vote_type)),                  // Vote Type (map, group, tiered)
        GetConVarInt(cvar_vote_time),                                         // Vote duration
        GetConVarBool(cvar_scramble),                                         // Scramble
        vote_start_sound,                                                     // Start Sound
        vote_end_sound,                                                       // End Sound
        GetConVarInt(cvar_extensions) > extend_counter,                       // Extend option
        GetConVarFloat(cvar_extend_time),                                     // How long to extend the timelimit by,
        GetConVarInt(cvar_extend_rounds),                                     // How much to extend the roundlimit by,
        GetConVarInt(cvar_extend_frags),                                      // How much to extend the fraglimit by,
        false,                                                                // Don't Change option
        GetConVarFloat(cvar_vote_threshold),                                  // Threshold
        view_as<UMC_ChangeMapTime>(GetConVarInt(cvar_changetime)),            // Success Action (when to change the map)
        view_as<UMC_VoteFailAction>(GetConVarInt(cvar_fail_action)),          // Fail Action (runoff / nothing)
        GetConVarInt(cvar_runoff),                                            // Max Runoffs
        GetConVarInt(cvar_runoff_max),                                        // Max maps in the runoff
        view_as<UMC_RunoffFailAction>(GetConVarInt(cvar_runoff_fail_action)), // Runoff Fail Action
        runoff_sound,                                                         // Runoff Sound
        GetConVarBool(cvar_strict_noms),                                      // Nomination Strictness
        GetConVarBool(cvar_vote_allowduplicates),                             // Ignore Duplicates
        clients,
        numClients
    );

    if (vote_failed)
        LogUMCMessage("Could not start UMC vote.");
}

//************************************************************************************************//
//                                   ULTIMATE MAPCHOOSER EVENTS                                   //
//************************************************************************************************//

//Called when UMC has set a next map.
public int UMC_OnNextmapSet(Handle kv, const char[] map, const char[] group, const char[] display) {
    DestroyTimers();
    vote_enabled = false;
    vote_roundend = false;
    vote_failed = false;

    return 0;
}

//Called when UMC requests that the mapcycle should be reloaded.
public int UMC_RequestReloadMapcycle() {
    if (!ReloadMapcycle()) {
        DestroyTimers();
        vote_enabled = false;
    }
    else {
        RemovePreviousMapsFromCycle();
    }

    return 0;
}

//Called when UMC requests that the mapcycle is printed to the console.
public int UMC_DisplayMapCycle(int client, bool filtered) {
    PrintToConsole(client, "Module: End of Map Vote");
    if (filtered) {
        KeyValues filteredMapcycle = view_as<KeyValues>(UMC_FilterMapcycle(map_kv, umc_mapcycle, false, true));
        PrintKvToConsole(filteredMapcycle, client);
        delete filteredMapcycle;
    }
    else {
        PrintKvToConsole(umc_mapcycle, client);
    }

    return 0;
}
