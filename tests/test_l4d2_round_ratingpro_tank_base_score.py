from pathlib import Path
import re
import unittest


SOURCE = (
    Path(__file__).resolve().parents[1]
    / "addons"
    / "sourcemod"
    / "scripting"
    / "l4d2_round_ratingpro.sp"
)


def extract_function(source: str, signature: str) -> str:
    """Extract a function body by counting braces starting from signature."""
    idx = source.find(signature)
    if idx == -1:
        return ""
    brace_open = source.find("{", idx)
    if brace_open == -1:
        return ""
    depth = 0
    i = brace_open
    while i < len(source):
        char = source[i]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[idx : i + 1]
        i += 1
    return source[idx:]


class TankBaseScoreContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8-sig")

    def test_tank_spawn_and_replace_events_hooked(self):
        source = self.source
        self.assertRegex(source, r'HookEvent\(\s*"tank_spawn"\s*,\s*Event_TankSpawn\b')
        self.assertRegex(source, r'HookEvent\(\s*"bot_player_replace"\s*,\s*Event_BotPlayerReplace\b')
        self.assertRegex(source, r'HookEvent\(\s*"player_spawn"\s*,\s*Event_PlayerSpawn\b')

    def test_became_tank_variable_and_reset(self):
        source = self.source
        self.assertIn("bool g_bBecameTank[MAXPLAYERS + 1];", source)

        reset_body = extract_function(source, "void ResetRoundStats()")
        self.assertTrue(reset_body)
        self.assertIn("g_bBecameTank[client] = false;", reset_body)

    def test_mark_client_as_tank_behavior(self):
        source = self.source
        mark_body = extract_function(source, "void MarkClientAsTank(int client)")
        self.assertTrue(mark_body)
        self.assertIn("RememberClient(client);", mark_body)
        self.assertIn("g_bBecameTank[client] = true;", mark_body)

    def test_get_tank_raw_awards_base_one_score_when_became_tank(self):
        source = self.source
        func_body = extract_function(source, "float GetTankRaw(int client)")
        self.assertTrue(func_body)
        self.assertRegex(func_body, r"g_bBecameTank\[client\]\s*\?\s*1\.0\s*:\s*0\.0")
        self.assertIn("baseRaw + float(", func_body)

    def test_has_any_raw_signal_includes_became_tank(self):
        source = self.source
        signal_body = extract_function(source, "bool HasAnyRawSignal(int client)")
        self.assertTrue(signal_body)
        self.assertIn("g_bBecameTank[client]", signal_body)

    def test_snapshot_stores_became_tank(self):
        source = self.source
        self.assertIn("bool becameTank;", source)
        snapshot_body = extract_function(
            source,
            "void SaveRatingSnapshot(bool hasRanges",
        )
        self.assertTrue(snapshot_body)
        self.assertIn("entry.becameTank = g_bBecameTank[client];", snapshot_body)


if __name__ == "__main__":
    unittest.main()
