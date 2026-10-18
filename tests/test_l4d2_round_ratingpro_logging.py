from pathlib import Path
import unittest
from test_l4d2_round_ratingpro_query import extract_function

SOURCE = Path(__file__).resolve().parents[1] / "addons/sourcemod/scripting/l4d2_round_ratingpro.sp"


class RatingProLoggingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8-sig")

    def test_both_settlement_paths(self):
        body = extract_function(self.source, "public Action Timer_PrintBestRating(Handle timer)")
        self.assertEqual(body.count("RecordRatingSettlement();"), 2)
        for branch in body.split("SaveRatingSnapshot(")[1:]:
            self.assertIn("RecordRatingSettlement();", branch)

    def test_every_settlement_creates_a_file_without_four_map_gate(self):
        body = extract_function(self.source, "void RecordRatingSettlement()")
        self.assertIn('OpenFile(logPath, "wt")', body)
        self.assertNotIn("g_iLogMapCount", self.source)
        self.assertNotIn("g_sLogMaps", self.source)
        self.assertNotIn("RAW_HISTORY_SLOTS", body)

    def test_unique_file_and_map_metadata(self):
        body = extract_function(self.source, "void RecordRatingSettlement()")
        for expected in ("FileExists(logPath)", "%Y%m%d_%H%M%S", "g_sSnapshotMap", "SetLogName"):
            self.assertIn(expected, body)

    def test_shared_output(self):
        body = extract_function(self.source, "void PrintRatingSnapshotToConsole(")
        self.assertIn("bool logToFile = false", body)
        self.assertNotIn("PrintToConsole(requester,", body)
        self.assertIn("PrintToConsoleOrLog(requester, logToFile,", body)
        sink = extract_function(self.source, "void PrintToConsoleOrLog(")
        for expected in ("char buffer[2048]", "WritetoLogFileRaw(buffer)", 'PrintToConsole(requester, "%s", buffer)'):
            self.assertIn(expected, sink)
        self.assertIn("PrintRatingSnapshotToConsole(0, client, true)", self.source)
