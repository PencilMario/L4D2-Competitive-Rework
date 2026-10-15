from pathlib import Path
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


class RatingProInfectorDamageContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8-sig")

    def test_non_tank_infected_damage_excludes_incapacitated_survivor(self):
        func_body = extract_function(self.source, "public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)")
        self.assertTrue(func_body, "Event_PlayerHurt function must be defined")

        # Must inspect survivor incapacitated state before adding non-tank infected damage
        self.assertIn("!IsSurvivorIncapacitated(victim)", func_body)
        self.assertRegex(
            func_body,
            r'if\s*\(\s*!IsSurvivorIncapacitated\(victim\)\s*\)\s*\{\s*g_iInfDmgTotal\[attacker\]\s*\+=\s*damage;',
            "g_iInfDmgTotal must only accumulate when victim is not incapacitated",
        )

    def test_tank_infected_damage_excludes_incapacitated_survivor(self):
        func_body = extract_function(self.source, "void TrackTankHit(int tank, int survivor, int damage, Event event)")
        self.assertTrue(func_body, "TrackTankHit function must be defined")

        # Must accumulate both upright tank damage and infector damage inside the non-incapacitated block
        self.assertIn("!IsSurvivorIncapacitated(survivor)", func_body)
        self.assertRegex(
            func_body,
            r'if\s*\(\s*!IsSurvivorIncapacitated\(survivor\)\s*\)\s*\{[^}]*g_iInfDmgTotal\[tank\]\s*\+=\s*damage;[^}]*g_iTankDmgUpright\[tank\]\s*\+=\s*damage;',
            "g_iInfDmgTotal for Tank must only accumulate inside !IsSurvivorIncapacitated block",
        )

    def test_infector_raw_definition(self):
        func_body = extract_function(self.source, "float GetInfectorRaw(int client)")
        self.assertTrue(func_body, "GetInfectorRaw function must be defined")
        self.assertIn("g_iInfDmgTotal[client]", func_body)
        self.assertIn("g_iInfBooms[client] * 8", func_body)
        self.assertIn("g_iInfDeathCharges[client] * 25", func_body)


if __name__ == "__main__":
    unittest.main()
