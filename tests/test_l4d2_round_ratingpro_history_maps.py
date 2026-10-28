from pathlib import Path
import unittest
from test_l4d2_round_ratingpro_query import extract_function


SOURCE = (
    Path(__file__).resolve().parents[1]
    / "addons"
    / "sourcemod"
    / "scripting"
    / "l4d2_round_ratingpro.sp"
)


class RatingProHistoryMapsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8-sig")

    def test_each_history_slot_records_its_map(self):
        self.assertIn("char g_sRawHistoryMap[RAW_HISTORY_SLOTS][MAP_NAME_LENGTH];", self.source)
        body = extract_function(self.source, "void SaveRoundRawHistory()")
        self.assertIn(
            "GetCurrentMap(g_sRawHistoryMap[slot], sizeof(g_sRawHistoryMap[]));", body
        )

    def test_ring_buffer_is_read_chronologically(self):
        self.assertIn("int GetRawHistorySlotByIndex(int chronologicalIndex)", self.source)
        body = extract_function(self.source, "int GetRawHistorySlotByIndex(int chronologicalIndex)")
        self.assertIn("g_iRawHistoryCount < RAW_HISTORY_SLOTS", body)
        self.assertIn(
            "return (g_iRawHistoryNextSlot + chronologicalIndex) % RAW_HISTORY_SLOTS;",
            body,
        )

    def test_collect_history_maps_dedupes_and_filters_by_steamid(self):
        body = extract_function(
            self.source,
            "int CollectHistoryMaps(const char[] auth, char[] buffer, int size, const char[] separator)",
        )
        # 拼接逻辑只负责格式化，去重与 SteamID 过滤下沉到 CollectHistoryMapNames。
        self.assertIn("int mapCount = CollectHistoryMapNames(auth, maps);", body)
        self.assertIn("StrCat(buffer, size, separator);", body)

        names = extract_function(
            self.source,
            "int CollectHistoryMapNames(const char[] auth, char maps[RAW_HISTORY_SLOTS][MAP_NAME_LENGTH])",
        )
        self.assertIn("GetRawHistorySlotByIndex(index)", names)
        self.assertIn("StrEqual(maps[seen], g_sRawHistoryMap[slot], false)", names)
        self.assertIn("g_hRawActionHistory[slot].GetArray(auth, historyEntry, sizeof(historyEntry))", names)

    def test_snapshot_carries_map_coverage(self):
        snapshot = extract_function(
            self.source,
            "void SaveRatingSnapshot(bool hasRanges, float outputMin",
        )
        self.assertIn(
            'g_iSnapshotMapCount = CollectHistoryMaps("", g_sSnapshotMaps, sizeof(g_sSnapshotMaps), SNAPSHOT_MAP_SEPARATOR);',
            snapshot,
        )
        self.assertIn(
            "entry.mapCount = CollectHistoryMaps(g_sParticipantAuth[participant], entry.maps, sizeof(entry.maps), SNAPSHOT_MAP_SEPARATOR);",
            snapshot,
        )
        self.assertIn("char maps[SNAPSHOT_MAP_LIST_CELLS];", self.source)
        self.assertIn("int mapCount;", self.source)

    def test_snapshot_output_prints_covered_maps(self):
        coverage = extract_function(self.source, "void PrintSnapshotCoverage(int requester, bool logToFile)")
        self.assertIn('"覆盖地图 (%d 座): %s"', coverage)
        self.assertIn('FormatMapList(g_sSnapshotMaps, mapList, sizeof(mapList));', coverage)

        entry_coverage = extract_function(
            self.source, "void PrintEntryCoverage(int requester, bool logToFile, int mapCount, const char[] maps)"
        )
        self.assertIn('"[统计范围] 覆盖地图 (%d 座): %s"', entry_coverage)
        self.assertIn("FormatMapList(maps, mapList, sizeof(mapList));", entry_coverage)

        printer = extract_function(
            self.source, "void PrintRatingSnapshotToConsole(int requester, const char[] auth"
        )
        self.assertTrue(printer, "PrintRatingSnapshotToConsole must accept a SteamID key")
        self.assertEqual(printer.count("PrintSnapshotCoverage(requester, logToFile);"), 3)
        self.assertEqual(printer.count("PrintEntryCoverage(requester, logToFile, entry.mapCount, entry.maps);"), 2)

    def test_settlement_log_header_keeps_settlement_map_and_adds_coverage(self):
        body = extract_function(self.source, "void RecordRatingSettlement()")
        self.assertIn("结算地图: %s | 结算时间: %s | 快照编号: #%d", body)
        self.assertIn("PrintSnapshotCoverage(0, true);", body)
        # 结算日志不应自行重算历史窗口，覆盖地图由快照统一提供
        self.assertNotIn("RAW_HISTORY_SLOTS", body)


if __name__ == "__main__":
    unittest.main()
