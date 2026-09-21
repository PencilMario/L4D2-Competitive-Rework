from pathlib import Path
import unittest


PLUGIN_PATH = (
    Path(__file__).resolve().parents[1]
    / "addons"
    / "sourcemod"
    / "scripting"
    / "l4d2_list_missions.sp"
)


class ListMissionsCommandTests(unittest.TestCase):
    def test_sm_maps_is_an_alias_for_sm_map_list(self):
        source = PLUGIN_PATH.read_text(encoding="utf-8-sig")

        self.assertRegex(
            source,
            r'RegConsoleCmd\("sm_map_list",\s*CMD_Maps,\s*"更换三方图"\);',
        )
        self.assertRegex(
            source,
            r'RegConsoleCmd\("sm_maps",\s*CMD_Maps,\s*"更换三方图"\);',
        )


if __name__ == "__main__":
    unittest.main()
