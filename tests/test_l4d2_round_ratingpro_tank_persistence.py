from pathlib import Path
import unittest


SOURCE = (
    Path(__file__).resolve().parents[1]
    / "addons"
    / "sourcemod"
    / "scripting"
    / "l4d2_round_ratingpro.sp"
)


class TankRatingPersistenceContractTests(unittest.TestCase):
    def test_missing_non_tank_slots_use_the_players_recorded_average(self):
        source = SOURCE.read_text(encoding="utf-8-sig")
        historical_raw = source.split("float GetHistoricalRaw(const char[] auth, int field)", 1)[1]
        historical_raw = historical_raw.split("float GetTankRaw(int participant)", 1)[0]

        self.assertIn("int recordedSlots = 0;", historical_raw)
        self.assertIn("total += values[field];\n\t\t\trecordedSlots++;", historical_raw)
        self.assertIn("if (recordedSlots == 0)", historical_raw)
        self.assertIn("return total * float(RAW_HISTORY_SLOTS) / float(recordedSlots);", historical_raw)
        self.assertNotIn("SetArray", historical_raw)
        self.assertNotIn("values[field] >", historical_raw)

    def test_non_tank_raw_values_use_a_four_slot_ring_buffer(self):
        source = SOURCE.read_text(encoding="utf-8-sig")

        self.assertIn("#define RAW_HISTORY_SLOTS 4", source)
        self.assertIn("g_iRawHistoryNextSlot", source)
        self.assertIn("StringMap g_hRawHistory[RAW_HISTORY_SLOTS]", source)
        self.assertIn("g_hRawHistory[slot].SetArray(g_sParticipantAuth[participant], values, sizeof(values));", source)
        self.assertIn("SaveRoundRawHistory();", source)
        self.assertIn("GetHistoricalOutputRaw", source)
        self.assertIn("GetHistoricalDefenseRaw", source)
        self.assertIn("GetHistoricalFocusRaw", source)
        self.assertIn("GetHistoricalInfectorRaw", source)

    def test_final_rating_uses_the_selected_power_curve(self):
        source = SOURCE.read_text(encoding="utf-8-sig")

        self.assertIn("#define RATING_EXPONENT 0.75", source)
        self.assertIn("Pow(raw / 10.0, RATING_EXPONENT) * 10.0", source)

    def test_tank_range_uses_persisted_raw_when_round_has_no_tank_event(self):
        source = SOURCE.read_text(encoding="utf-8-sig")

        self.assertIn("StringMap g_hLastTankRaw", source)
        self.assertIn("GetClientAuthId(client, AuthId_Steam2", source)
        self.assertIn("GetEffectiveTankRaw", source)
        self.assertIn("float tank = GetEffectiveTankRaw(participant);", source)

    def test_round_end_updates_latest_tank_raw_before_rating_is_recomputed(self):
        source = SOURCE.read_text(encoding="utf-8-sig")

        self.assertIn("SaveLatestTankRaw();", source)
        self.assertIn("SaveLatestTankRaw();\n\tSaveRoundRawHistory();", source)

    def test_tank_action_history_entry_and_persistence(self):
        source = SOURCE.read_text(encoding="utf-8-sig")

        # Struct must include action detail fields
        self.assertIn("enum struct TankHistoryEntry", source)
        self.assertIn("bool becameTank;", source)
        self.assertIn("int tankDmgUpright;", source)
        self.assertIn("int punch;", source)
        self.assertIn("int rock;", source)
        self.assertIn("int hittable;", source)
        self.assertIn("int incap;", source)
        self.assertIn("int death;", source)

        # SaveLatestTankRaw must persist TankHistoryEntry into g_hLastTankRaw
        self.assertIn("TankHistoryEntry tankEntry;", source)
        self.assertIn("tankEntry.punch = g_iTankPunch[participant];", source)
        self.assertIn("tankEntry.rock = g_iTankRock[participant];", source)
        self.assertIn("tankEntry.hittable = g_iTankHittable[participant];", source)
        self.assertIn("tankEntry.incap = g_iTankIncap[participant];", source)
        self.assertIn("tankEntry.death = g_iTankDeath[participant];", source)
        self.assertIn("tankEntry.becameTank = g_bBecameTank[participant];", source)
        self.assertIn("g_hLastTankRaw.SetArray(g_sParticipantAuth[participant], tankEntry, sizeof(tankEntry));", source)

    def test_snapshot_restores_tank_actions_on_historical_fallback(self):
        source = SOURCE.read_text(encoding="utf-8-sig")

        # SaveRatingSnapshot must restore historical actions when fallback is active
        self.assertIn("entry.tankSource = 2;", source)
        self.assertIn("TankHistoryEntry histTank;", source)
        self.assertIn("g_hLastTankRaw.GetArray(g_sParticipantAuth[participant], histTank, sizeof(histTank))", source)
        self.assertIn("entry.punch = histTank.punch;", source)
        self.assertIn("entry.rock = histTank.rock;", source)
        self.assertIn("entry.hittable = histTank.hittable;", source)
        self.assertIn("entry.incap = histTank.incap;", source)
        self.assertIn("entry.death = histTank.death;", source)
        self.assertIn("entry.becameTank = histTank.becameTank;", source)

    def test_console_breakdown_displays_all_tank_actions(self):
        source = SOURCE.read_text(encoding="utf-8-sig")

        # Must display 出克基础分, 直立伤害, 拳击, 砸石, 铁, 击倒, 击杀 regardless of tank source
        self.assertIn(
            "Tank表现原始分 (当前生效值%.1f): 出克基础分+%d, 直立伤害+%d, 拳击+%d (x10), 砸石+%d (x20), 铁+%d (x35), 击倒+%d (x45), 击杀+%d (x60)",
            source,
        )


if __name__ == "__main__":
    unittest.main()
