from pathlib import Path
import unittest


SOURCE = (
    Path(__file__).resolve().parents[1]
    / "addons"
    / "sourcemod"
    / "scripting"
    / "l4d2_round_ratingpro.sp"
)


class RatingProActionAggregationTests(unittest.TestCase):
    def setUp(self):
        self.source = SOURCE.read_text(encoding="utf-8-sig")

    def test_action_aggregation_struct_and_storage(self):
        # Must define RawHistoryActionEntry
        self.assertIn("enum struct RawHistoryActionEntry", self.source)
        self.assertIn("StringMap g_hRawActionHistory[RAW_HISTORY_SLOTS]", self.source)

    def test_aggregate_historical_actions_function(self):
        self.assertIn("void AggregateHistoricalActions(int client, RatingSnapshotEntry entry)", self.source)
        # Aggregation logic
        self.assertIn("entry.recordedSlots++;", self.source)
        self.assertIn("entry.siDmg += historyEntry.siDmg;", self.source)
        self.assertIn("entry.ciKill += historyEntry.ciKill;", self.source)
        self.assertIn("entry.tankDmg += historyEntry.tankDmg;", self.source)
        self.assertIn("entry.dmgTaken += historyEntry.dmgTaken;", self.source)
        self.assertIn("entry.dmg += historyEntry.dmg;", self.source)
        self.assertIn("entry.booms += historyEntry.booms;", self.source)
        self.assertIn("entry.deathCharges += historyEntry.deathCharges;", self.source)

    def test_save_snapshot_uses_aggregated_actions(self):
        snapshot_code = self.source.split("void SaveRatingSnapshot(", 1)[1]
        snapshot_code = snapshot_code.split("public Action Command_RatingPro(", 1)[0]
        self.assertIn("AggregateHistoricalActions(client, entry);", snapshot_code)
        # Tank upright/punch/rock remain direct from client
        self.assertIn("entry.tankDmgUpright = g_iTankDmgUpright[client];", snapshot_code)

    def test_console_log_reflects_aggregated_stats(self):
        console_code = self.source.split("void PrintRatingSnapshotToConsole(", 1)[1]
        self.assertIn("跨章节累计", console_code)
        self.assertIn("entry.recordedSlots", console_code)
        self.assertNotIn("当章记录", console_code)
        self.assertNotIn("当章%.1f", console_code)


if __name__ == "__main__":
    unittest.main()
