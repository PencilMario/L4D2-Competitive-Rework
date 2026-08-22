from pathlib import Path
import re
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
PLUGIN_PATH = REPO_ROOT / "addons" / "sourcemod" / "scripting" / "l4d_tankfight.sp"
ENGLISH_PATH = REPO_ROOT / "addons" / "sourcemod" / "translations" / "l4d_tankfight.phrases.txt"
CHINESE_PATH = (
    REPO_ROOT
    / "addons"
    / "sourcemod"
    / "translations"
    / "chi"
    / "l4d_tankfight.phrases.txt"
)

EXPECTED_KEYS = {
    "IntroTitle",
    "IntroRule",
    "IntroTeleport",
    "IntroRounds",
    "SavedPositions",
    "PositionsReady",
    "RoundEnded",
    "NextRound",
    "TankPosition",
    "AllRoundsEnded",
    "ScoreSeparator",
    "SurvivorBonus",
    "SpecialSpawnDelay",
    "UnsupportedMap",
    "NoDistanceScore",
    "TankSpawned",
    "AmmoRestored",
    "ScorePerTank",
    "PositionsNotReady",
    "PositionsHeader",
    "RoundCount",
    "RoundFlow",
    "RoundMissing",
    "TankFooter",
}


def read_required(path: Path) -> str:
    if not path.is_file():
        raise AssertionError(f"Missing required translation file: {path}")
    return path.read_text(encoding="utf-8-sig")


def parse_phrase_blocks(text: str) -> dict[str, str]:
    blocks: dict[str, str] = {}
    lines = text.splitlines()
    index = 0

    while index < len(lines):
        match = re.match(r'^\s*"([^"]+)"\s*$', lines[index])
        if not match or match.group(1) == "Phrases":
            index += 1
            continue

        key = match.group(1)
        index += 1
        if index >= len(lines) or not re.match(r"^\s*{\s*$", lines[index]):
            continue
        index += 1
        body = []
        while index < len(lines) and not re.match(r"^\s*}\s*$", lines[index]):
            body.append(lines[index])
            index += 1
        blocks[key] = "\n".join(body)
        index += 1

    return blocks


def language_value(block: str, language: str) -> str:
    match = re.search(rf'^\s*"{re.escape(language)}"\s+"(.*)"\s*$', block, re.MULTILINE)
    if not match:
        raise AssertionError(f"Missing {language} value in Phrase block:\n{block}")
    return match.group(1)


def format_tokens(value: str) -> list[str]:
    return re.findall(r"(?<!%)%(?:\.[0-9]+)?[dif]", value)


class TankFightLocalizationContractTests(unittest.TestCase):
    def test_english_and_chinese_catalogs_have_the_same_complete_key_set(self):
        english = parse_phrase_blocks(read_required(ENGLISH_PATH))
        chinese = parse_phrase_blocks(read_required(CHINESE_PATH))

        self.assertEqual(set(english), EXPECTED_KEYS)
        self.assertEqual(set(chinese), EXPECTED_KEYS)

        for key in EXPECTED_KEYS:
            english_value = language_value(english[key], "en")
            chinese_value = language_value(chinese[key], "chi")
            self.assertEqual(
                format_tokens(english_value),
                format_tokens(chinese_value),
                key,
            )

    def test_plugin_loads_and_references_every_phrase_key(self):
        source = PLUGIN_PATH.read_text(encoding="utf-8-sig")

        self.assertIn('LoadTranslations("l4d_tankfight.phrases")', source)
        for key in EXPECTED_KEYS:
            self.assertRegex(source, rf'"%t"\s*,\s*"{re.escape(key)}"')

    def test_player_visible_chat_calls_do_not_keep_literal_messages(self):
        source = PLUGIN_PATH.read_text(encoding="utf-8-sig")

        for line_number, line in enumerate(source.splitlines(), start=1):
            if line.lstrip().startswith("//"):
                continue
            if re.search(r"\b(?:CPrintToChat|PrintToChat)(?:All)?\s*\(", line):
                self.assertIn(
                    '"%t"',
                    line,
                    f"line {line_number} still has a literal chat message: {line.strip()}",
                )


if __name__ == "__main__":
    unittest.main()
