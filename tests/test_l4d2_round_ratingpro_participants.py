from pathlib import Path
import unittest

from test_l4d2_round_ratingpro_query import extract_function


SOURCE = Path(__file__).resolve().parents[1] / "addons/sourcemod/scripting/l4d2_round_ratingpro.sp"


ROUND_COUNTERS = (
    "g_iSiDamage",
    "g_iCiKilled",
    "g_iTankDamage",
    "g_iDmgTaken",
    "g_iIncaps",
    "g_iDied",
    "g_iFfGiven",
    "g_iSiDamageTankup",
    "g_iSiKilledTankup",
    "g_iSkeets",
    "g_iLevels",
    "g_iPops",
    "g_iTongueCuts",
    "g_iCrowns",
    "g_iInfDmgTotal",
    "g_iInfBooms",
    "g_iInfDeathCharges",
    "g_iTankDmgUpright",
    "g_iTankPunch",
    "g_iTankRock",
    "g_iTankHittable",
    "g_iTankIncap",
    "g_iTankDeath",
    "g_bBecameTank",
)


class RatingProParticipantOwnershipTests(unittest.TestCase):
    """Round data is owned by SteamID, so leaving the server never drops it."""

    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8-sig")

    def test_participant_pool_is_declared(self):
        for declaration in (
            "#define MAX_PARTICIPANTS 64",
            "char g_sParticipantAuth[MAX_PARTICIPANTS][64];",
            "char g_sParticipantName[MAX_PARTICIPANTS][MAX_NAME_LENGTH];",
            "int g_iParticipantTeam[MAX_PARTICIPANTS];",
            "int g_iParticipantCount;",
        ):
            self.assertIn(declaration, self.source)

    def test_round_counters_are_keyed_by_participant(self):
        for counter in ROUND_COUNTERS:
            self.assertIn(f"int {counter}[MAX_PARTICIPANTS];" if not counter.startswith("g_b") else f"bool {counter}[MAX_PARTICIPANTS];", self.source)
            for bad_index in ("client", "attacker", "victim", "bot", "player", "tank"):
                self.assertNotIn(f"{counter}[{bad_index}]", self.source, f"{counter} must not be keyed by client slot")

    def test_disconnect_keeps_round_data(self):
        disconnect = extract_function(self.source, "public void OnClientDisconnect(int client)")
        self.assertTrue(disconnect)
        self.assertIn("g_bBiled[client] = false;", disconnect)
        self.assertIn("g_fLastQueryTime[client] = 0.0;", disconnect)
        self.assertIn("g_sClientAuth[client][0] = '\\0';", disconnect)
        for counter in ROUND_COUNTERS:
            self.assertNotIn(f"{counter}[", disconnect, counter)
        self.assertNotIn("ResetRoundStats", disconnect)

    def test_acquisition_is_by_steamid_and_survives_slot_reuse(self):
        join = extract_function(self.source, "public void OnClientPutInServer(int client)")
        self.assertTrue(join)
        # 客户端槽位被复用后必须丢掉旧的 Auth 缓存，事件到来时再按新 SteamID 建记录
        self.assertIn("g_sClientAuth[client][0] = '\\0';", join)

        acquire = extract_function(self.source, "int AcquireParticipant(int client)")
        self.assertTrue(acquire)
        self.assertIn("int participant = FindParticipantByAuth(auth);", acquire)
        self.assertIn("participant = g_iParticipantCount;", acquire)
        self.assertIn("g_iParticipantCount++;", acquire)
        self.assertIn("strcopy(g_sParticipantAuth[participant], sizeof(g_sParticipantAuth[]), auth);", acquire)

    def test_settlement_covers_offline_participants(self):
        snapshot = extract_function(self.source, "void SaveRatingSnapshot(bool hasRanges, float outputMin")
        self.assertTrue(snapshot)
        self.assertIn("for (int participant = 0; participant < g_iParticipantCount; participant++)", snapshot)
        self.assertNotIn("IsHumanClient(", snapshot)
        self.assertIn("g_hLastRatingSnapshotNames.SetString(g_sParticipantAuth[participant], g_sParticipantName[participant]);", snapshot)
        self.assertIn("g_hLastRatingSnapshot.SetArray(g_sParticipantAuth[participant], entry, sizeof(entry));", snapshot)

        settlement = extract_function(self.source, "void RecordRatingSettlement()")
        self.assertTrue(settlement)
        self.assertIn("for (int participant = 0; participant < g_iParticipantCount; participant++)", settlement)
        self.assertIn("int onlineClient = FindClientByAuth(g_sParticipantAuth[participant]);", settlement)
        self.assertIn("PrintRatingSnapshotToConsole(0, g_sParticipantAuth[participant], g_sParticipantName[participant], userId, true);", settlement)

    def test_offline_players_stay_queryable_until_next_snapshot(self):
        command = extract_function(self.source, "public Action Command_RatingPro(int client, int args)")
        self.assertTrue(command)
        self.assertIn("FindSnapshotPlayer(arg,", command)
        self.assertIn("PrintRatingSnapshotToConsole(client, offlineAuth, offlineName, 0);", command)
        self.assertIn("已退服", command)

        finder = extract_function(
            self.source,
            "int FindSnapshotPlayer(const char[] query, char[] authOut, int authSize, char[] nameOut, int nameSize)",
        )
        self.assertTrue(finder)
        self.assertIn('StrContains(query, "STEAM_", false) == 0', finder)
        self.assertIn("g_hLastRatingSnapshotNames.Snapshot()", finder)
        self.assertIn("delete snapshot;", finder)

        printer = extract_function(self.source, "void PrintRatingSnapshotToConsole(int requester, const char[] auth")
        self.assertIn('strcopy(identity, sizeof(identity), "已退服 (offline)");', printer)

    def test_history_buffers_are_keyed_by_steamid(self):
        save = extract_function(self.source, "void SaveRoundRawHistory()")
        self.assertTrue(save)
        self.assertIn("g_hRawHistory[slot].SetArray(g_sParticipantAuth[participant], values, sizeof(values));", save)
        self.assertIn(
            "g_hRawActionHistory[slot].SetArray(g_sParticipantAuth[participant], entry, sizeof(entry));",
            save,
        )

    def test_new_map_resets_the_pool(self):
        reset = extract_function(self.source, "void ResetRoundStats()")
        self.assertTrue(reset)
        self.assertIn("g_iParticipantCount = 0;", reset)
        self.assertIn("g_sParticipantAuth[participant][0] = '\\0';", reset)


if __name__ == "__main__":
    unittest.main()
