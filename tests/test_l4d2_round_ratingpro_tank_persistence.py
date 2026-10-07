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
    def test_final_rating_uses_the_selected_power_curve(self):
        source = SOURCE.read_text(encoding="utf-8-sig")

        self.assertIn("#define RATING_EXPONENT 0.75", source)
        self.assertIn("Pow(raw / 10.0, RATING_EXPONENT) * 10.0", source)

    def test_tank_range_uses_persisted_raw_when_round_has_no_tank_event(self):
        source = SOURCE.read_text(encoding="utf-8-sig")

        self.assertIn("StringMap g_hLastTankRaw", source)
        self.assertIn("GetClientAuthId(client, AuthId_Steam2", source)
        self.assertIn("GetEffectiveTankRaw", source)
        self.assertIn("float tank = GetEffectiveTankRaw(client);", source)

    def test_round_end_updates_latest_tank_raw_before_rating_is_recomputed(self):
        source = SOURCE.read_text(encoding="utf-8-sig")

        self.assertIn("SaveLatestTankRaw();", source)
        self.assertIn("SaveLatestTankRaw();\n\n\tfloat outputMin;", source)


if __name__ == "__main__":
    unittest.main()
