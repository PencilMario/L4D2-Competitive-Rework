#if defined _l4d_tank_control_eq_included
    #endinput
#endif
#define _l4d_tank_control_eq_included

/**
 * @brief Retrieves the selected tank's client index.
 *
 * @return			Client id of the selected tank, -1 if no one is selected.
 */
native int GetTankSelection();

/**
 * @brief Gets the tank pass count for a specific player.
 *
 * @param client	Client index to check.
 * @return			Number of times the player has passed tank control, 0 if invalid client.
 */
native int GetTankPassedCount(int client);

/**
 * @brief Forces selection of the next tank in queue.
 *
 * @return			Client index of selected tank, 0 if none available.
 */
native int ForceSelectNextTank();

/**
 * @brief Removes a player from the tank queue.
 *
 * @param client	Client index to remove from queue.
 * @return			1 if removed successfully, 0 if not found or invalid client.
 */
native int RemoveFromTankQueue(int client);

/**
 * @brief Adds a player to the tank history (players who have played tank).
 *
 * @param client	Client index to add to history.
 * @return			1 if added successfully, 0 if already in history or invalid client.
 */
native int AddToTankHistory(int client);

forward void TankControl_OnTryOfferingTankBot(char sQueuedTank[64]);
forward void TankControl_OnTankSelection(char sQueuedTank[64]);

public SharedPlugin __pl_l4d_tank_control_eq =
{
    name = "l4d_tank_control_eq",
    file = "l4d_tank_control_eq.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_l4d_tank_control_eq_SetNTVOptional()
{
    MarkNativeAsOptional("GetTankSelection");
    MarkNativeAsOptional("GetTankPassedCount");
    MarkNativeAsOptional("ForceSelectNextTank");
    MarkNativeAsOptional("RemoveFromTankQueue");
}
#endif