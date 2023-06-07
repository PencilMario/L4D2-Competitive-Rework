#if defined _nativevotes_rework_included
 #endinput
#endif
#define _nativevotes_rework_included


#define NATIVEVOTES_ALL_TEAMS       255 /**< Formerly defined by TF2, may be the same in L4D2 */
#define NATIVEVOTES_TEAM_UNASSIGNED 0  /**< For completeness, do not otherwise use */
#define NATIVEVOTES_TEAM_SPECTATOR  1  /**< Spectators */
#define NATIVEVOTES_TEAM_1          2  /**< Survivors */
#define NATIVEVOTES_TEAM_2          3  /**< Infected */

#define NATIVEVOTES_SERVER_INDEX    99

// These may seem backwards, but this is the order that the votes appear in the vote screen
#define NATIVEVOTES_VOTE_INVALID    -1 /**< Vote was invalid, currently only valid internally */
#define NATIVEVOTES_VOTE_YES        1  /**< Vote was yes */
#define NATIVEVOTES_VOTE_NO         0  /**< Vote was no */


enum VoteAction
{
	VoteAction_Start = (1<<0),
	VoteAction_Display = (1<<1),
	VoteAction_Select = (1<<2),
	VoteAction_Cancel = (1<<3),
	VoteAction_Finish = (1<<4),
	VoteAction_End = (1<<5)
};

enum
{
	VoteEnd_VotingDone = -1,           /**< Voting finished */
	VoteEnd_VotingCancelled = -2       /**< Voting was cancelled */
}

/**
 * Vote types.
 */
enum NativeVotesType
{
	NativeVotesType_None = 0,
	NativeVotesType_Custom_YesNo,      /**< Details are vote text. */
	NativeVotesType_ChgCampaign,       /**< Details are campaign name */
	NativeVotesType_ChgDifficulty,     /**< Details are difficulty number */
	NativeVotesType_ReturnToLobby,     /**< Details are ignored */
	NativeVotesType_AlltalkOn,         /**< Details are ignored (handled internally by extension) */
	NativeVotesType_AlltalkOff,        /**< Details are ignored (handled internally by extension) */
	NativeVotesType_Restart,           /**< Details are ignored */
	NativeVotesType_Kick,              /**< Target is player userid, details are auto-set by target */
	NativeVotesType_ChgLevel,          /**< Details are level number */
};


methodmap NativeVote < KeyValues
{
	// Creates a new, empty vote.
	//
	// @param handler       Function which will receive vote actions.
	// @param hVoteType     Vote type, cannot be changed after set
	public native NativeVote(NativeVotes_Handler handler, NativeVotesType voteType);

	// Frees all handles related to a vote.
	//
	// THIS MUST BE CALLED TO AVOID HANDLE LEAKS
	public native void Close();

	// Sets the vote's details for votes that support details
	// If this is a custom vote, use SetTitle to set the vote's title.
	//
	// @param sFmt              Message string format
	// @param ...               Message string arguments.
	public native void SetDetails(const char[] sFmt, any ...);
	
	// Returns the text of a vote's details if set.
	//
	// @param buffer            Buffer to store details.
	// @param maxlength         Maximum length of the buffer.
	public native void GetDetails(char[] buffer, int maxlength);

	// Sets the target userid for vote
	// This should be used instead of SetArgument for votes that target players
	// 
	// @param iClient           Client index of target player or 0 to clear target
	public native void SetTarget(int iClient);

	// Returns the vote's target client index, 0 for client disconnected, or -1 for no target.
	//
	// @return                  Client index of target player, 0 for client disconnected, or -1 for no target.
	public native int GetTarget();

	// Broadcasts a vote to a list of clients. The most selected item will be 
	// returned through VoteAction_Finish.
	//
	// @param iClients          Array of clients to broadcast to.
	// @param numClients        Number of clients in the array.
	// @param iShowTime         Maximum time to leave vote on the screen.
	// @return                  True on success, false if a this vote already has a
	//                          vote session in progress.
	// @error                   A vote is already in progress.
	public native bool DisplayVote(int[] iClients, int numClients, int iShowTime);

	// Display default vote passed screen for this vote type
	//
	// You MUST call one of the DisplayPass or DisplayFail functions
	// to hide the vote screen for users who didn't vote, and to clear out their selection
	// for the next vote.
	//
	// The format string/any args are a Valve format string or the item that won the vote.
	//
	// @param sFmt              Message string format
	// @param ...               Message string arguments.
	public native void DisplayPass(const char[] sFmt="", any ...);

	// Display vote failure screen to all users in a vote.
	//
	// You MUST call one of the DisplayPass or DisplayFail functions
	// to hide the vote screen for users who didn't vote, and to clear out their selection
	// for the next vote.
	public native void DisplayFail();

	// Retrieve the vote type
	property NativeVotesType VoteType {
		public native get();
	}

	// Get or set the team this vote is for
	// NATIVEVOTES_ALL_TEAMS is used for all teams.
	property int Team {
		public native get();
		public native set(int iTeam);
	}

	// Get or set the client index of the player who initiated the vote.
	// Use NATIVEVOTES_SERVER_INDEX if initiated by the server itself.
	//
	// Defaults to NATIVEVOTES_SERVER_INDEX if not explicitly set.
	property int Initiator {
		public native get();
		public native set(int iInitiator);
	}
}

/**
 * Is a specific vote type supported by this game?
 * 
 * @param hVoteType         Vote type
 */
native bool NativeVotes_IsVoteTypeSupported(NativeVotesType hVoteType);

/**
 * Creates a new, empty vote.
 * 
 * @param handler           Function which will receive vote actions.
 * @param hVoteType         Vote type, cannot be changed after set
 * @param actions           Optionally set which actions to receive.  VoteStart,
 *                          VoteCancel, VoteEnd, and End will always be received
 *                          regardless of whether they are set or not.  They are
 *                          also the only default actions.
 * @return                  A new vote Handle on INVALID_HANDLE if a vote type is unsupported by this game.
 */
native NativeVote NativeVotes_Create(NativeVotes_Handler hVoteHandler, NativeVotesType hVoteType);

/**
 * Frees all handles related to a vote.
 * 
 * THIS MUST BE CALLED TO AVOID HANDLE LEAKS
 * 
 * @param hVote             Vote handle
 */
native void NativeVotes_Close(Handle hVote);

/**
 * Sets the vote's details for votes that support details
 * If this is a custom vote, use NativeVotes_SetTitle to set the vote's title.
 *
 * @param hVote             Vote Handle.
 * @param sFmt              Message string format.
 * @param ...               Message string arguments.
 * @error                   Invalid Handle.
 */
native void NativeVotes_SetDetails(Handle hVote, const char[] sFmt, any ...);

/**
 * Returns the text of a vote's details if set.
 *
 * @param hVote             Vote Handle.
 * @param buffer            Buffer to store details.
 * @param maxlength         Maximum length of the buffer.
 * @error                   Invalid Handle.
 */
native void NativeVotes_GetDetails(Handle hVote, char[] buffer, int maxlength);

/**
 * Sets the target userid for vote
 * This should be used instead of SetArgument for votes that target players
 * 
 * Also sets target SteamID
 * 
 * @param hVote             Vote Handle.
 * @param iClient           Client index of target player or 0 to clear target
 * @error                   Invalid Handle.
 */
native void NativeVotes_SetTarget(Handle hVote, int iClient);

/**
 * Returns the vote's target client index, 0 for client disconnected, or -1 for no target.
 *
 * @param hVote             Vote Handle.
 * @return                  Client index of target player, 0 for client disconnected, or -1 for no target.
 * @error                   Invalid Handle.
 */
native int NativeVotes_GetTarget(Handle hVote);

/**
 * Get the SteamID2 of a vote's target
 * Useful if the target has disconnected from the server during a vote.
 * This was added in specifically for Kick/Ban votes
 *
 * @param hVote             Vote Handle.
 * @param buffer            Buffer to store steamId.  Should be 19 characters or more..
 * @param maxlength         Maximum length of the buffer.
 * @error                   Invalid Handle.
 */
native void NativeVotes_GetTargetSteam(Handle hVote, char[] buffer, int maxlength);

/**
 * Returns whether a vote is in progress.
 *
 * @return                  True if a NativeVotes vote is in progress, false otherwise.
 */
native bool NativeVotes_IsVoteInProgress();

/**
 * Cancels the vote in progress.
 *
 * @error                   If no vote is in progress.
 */
native void NativeVotes_Cancel();

/**
 * Called when a vote action is completed.
 *
 * @param hVote             The vote being acted upon.
 * @param hAction           The action of the vote.
 * @param iParam1           First action parameter (usually the client).
 * @param iParam2           Second action parameter (usually the item).
 */
typedef NativeVotes_Handler = function Action(NativeVote hVote, VoteAction hAction, int iParam1, int iParam2);

/**
 * Returns the number of seconds you should "wait" before displaying
 * a public vote.  This number is the time remaining until
 * (last_vote + sm_vote_delay).
 *
 * @return                  Number of seconds to wait, or 0 for none.
 */
native int NativeVotes_CheckVoteDelay();

/**
 * Returns whether a client is in the pool of clients allowed 
 * to participate in the current vote.  This is determined by 
 * the client list passed to NativeVotes_Display().
 *
 * @param iClient           Client index.
 * @return                  True if client is allowed to vote, false otherwise.
 * @error                   If no vote is in progress or client index is invalid.
 */
native bool NativeVotes_IsClientInVotePool(int iClient);

/**
 * Retrieve the vote type
 * 
 * @param hVote             NativeVotes Handle.
 * @return                  The built in vote type
 * @error                   Invalid Handle
 */
native NativeVotesType NativeVotes_GetType(Handle hVote);

/**
 * Set the team this vote is for, or NATIVEVOTES_ALL_TEAMS for all teams.
 * 
 * Defaults to NATIVEVOTES_ALL_TEAMS if not explicitly set.
 * 
 * @param hVote             NativeVotes Handle.
 * @param iTeam             Team number this vote is for
 * @error                   Invalid Handle
 */
native void NativeVotes_SetTeam(Handle hVote, int iTeam);

/**
 * Retrieve the team this vote is for
 * 
 * @param hVote             NativeVotes Handle.
 * @return                  Team index or NATIVEVOTES_ALL_TEAMS for all teams.
 * @error                   Invalid Handle
 */
native int NativeVotes_GetTeam(Handle hVote);

/**
 * Set the client index of the player who initiated the vote.
 * Use NATIVEVOTES_SERVER_INDEX if initiated by the server itself.
 * 
 * Defaults to NATIVEVOTES_SERVER_INDEX if not explicitly set.
 * 
 * @param hVote             NativeVotes Handle.
 * @param iClient           Client who initiated the vote or NATIVEVOTES_SERVER_INDEX
 * @error                   Invalid Handle
 */
native void NativeVotes_SetInitiator(Handle hVote, int iClient);

/**
 * Retrieve the client index of the player who initiated the vote or NATIVEVOTES_SERVER_INDEX if 
 * initiated by the server itself.
 * 
 * @param hVote             Vote handle
 * @return                  Client index or NATIVEVOTES_SERVER_INDEX
 * @error                   Invalid Handle
 */
native int NativeVotes_GetInitiator(Handle hVote);

/**
 * Broadcasts a vote to a list of clients. The most selected item will be 
 * returned through VoteAction_Finish.
 *
 * @param hVote             Vote Handle.
 * @param iClients          Array of clients to broadcast to.
 * @param iCountClients     Number of clients in the array.
 * @param iShowTime         Maximum time to leave menu on the screen.
 * @return                  True on success, false if a vote is already in progress.
 * @error                   Invalid Handle, or a vote is already in progress.
 */
native bool NativeVotes_DisplayVote(Handle hVote, int[] iClients, int iCountClients, int iShowTime);

/**
 * Display default vote passed screen for this vote type
 *
 * You MUST call one of the NativeVotes_DisplayPass or NativeVotes_DisplayFail functions
 * to hide the vote screen for users who didn't vote, and to clear out their selection
 * for the next vote.
 * 
 * The format string/any args are a Valve format string or the item that won the vote.
 *
 * @param hVote             Vote handle
 * @param sFmt              Message string format
 * @param ...               Message string arguments.
 */
native void NativeVotes_DisplayPass(Handle hVote, const char[] sFmt="", any ...);

/**
 * Display vote failure screen to all users in a vote.
 *
 * You MUST call one of the NativeVotes_DisplayPass or NativeVotes_DisplayFail functions
 * to hide the vote screen for users who didn't vote, and to clear out their selection
 * for the next vote.
 * 
 * @param hVote             Vote handle
 */
native void NativeVotes_DisplayFail(Handle hVote);

/**
 * Quick stock to determine whether voting is allowed.  This doesn't let you 
 * fine-tune a reason for not voting, so it's not recommended for lazily 
 * telling clients that voting isn't allowed.
 * 
 * @return                  True if voting is allowed, false if voting is in progress
 *                          or the cooldown is active.
 */
stock bool NativeVotes_IsNewVoteAllowed()
{
	if (NativeVotes_IsVoteInProgress() || NativeVotes_CheckVoteDelay() != 0)
	{
		return false;
	}

	return true;
}

/**
 * Do not edit below this line!
 */
public SharedPlugin __pl_nativevotes_rework = 
{
	name = "nativevotes_rework",
	file = "nativevotes_rework.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_nativevotes_rework_SetNTVOptional()
{
	MarkNativeAsOptional("NativeVotes_Create");
	MarkNativeAsOptional("NativeVotes_Close");
	MarkNativeAsOptional("NativeVotes_SetDetails");
	MarkNativeAsOptional("NativeVotes_GetDetails");
	MarkNativeAsOptional("NativeVotes_SetTarget");
	MarkNativeAsOptional("NativeVotes_GetTarget");
	MarkNativeAsOptional("NativeVotes_DisplayVote");
	MarkNativeAsOptional("NativeVotes_DisplayPass");
	MarkNativeAsOptional("NativeVotes_DisplayFail");
	MarkNativeAsOptional("NativeVotes_GetType");
	MarkNativeAsOptional("NativeVotes_SetTeam");
	MarkNativeAsOptional("NativeVotes_GetTeam");
	MarkNativeAsOptional("NativeVotes_SetInitiator");
	MarkNativeAsOptional("NativeVotes_GetInitiator");
	MarkNativeAsOptional("NativeVotes_IsVoteTypeSupported");
	MarkNativeAsOptional("NativeVotes_Cancel");
	MarkNativeAsOptional("NativeVotes_IsVoteInProgress");
	MarkNativeAsOptional("NativeVotes_CheckVoteDelay");
	MarkNativeAsOptional("NativeVotes_IsClientInVotePool");
}
#endif
