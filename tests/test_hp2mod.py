"""Tests for the hp2mod tooling (standard library only; no game needed).

Run: python3 -m unittest discover tests
"""
import os
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "scripts"))

import hp2mod  # noqa: E402
import generate_lang_credits  # noqa: E402
import merge_dialog_text  # noqa: E402
import s3  # noqa: E402


class PatchTests(unittest.TestCase):
    def roundtrip(self, a: bytes, b: bytes):
        patch = hp2mod.make_patch(a, b, "HGame/Classes/X.uc")
        self.assertEqual(hp2mod.apply_patch(a, patch), b)

    def test_crlf_edit(self):
        a = b"".join(f"line {i}\r\n".encode() for i in range(40))
        b = a.replace(b"line 20\r\n", b"line 20\r\n// added\r\n").replace(b"line 3\r\n", b"")
        self.roundtrip(a, b)

    def test_no_trailing_newline(self):
        self.roundtrip(b"one\ntwo", b"one\nTWO")
        self.roundtrip(b"one\ntwo\n", b"one\ntwo\nthree")

    def test_insert_at_start_and_end(self):
        a = b"a\nb\nc\n"
        self.roundtrip(a, b"new\na\nb\nc\n")
        self.roundtrip(a, b"a\nb\nc\nnew\n")

    def test_context_mismatch_fails(self):
        patch = hp2mod.make_patch(b"a\nb\nc\n", b"a\nB\nc\n", "x")
        with self.assertRaises(hp2mod.ToolError):
            hp2mod.apply_patch(b"a\nb\nZ\n", patch)

    def test_repository_patches_parse(self):
        # Every tracked patch must at least be well-formed for the applier.
        for p in (ROOT / "patches").rglob("*.patch"):
            data = p.read_bytes()
            self.assertTrue(data.startswith(b"--- a/"), p.name)
            self.assertIn(b"\n@@ -", data, p.name)


class MergeTests(unittest.TestCase):
    def test_unclosed_emotion_tag(self):
        self.assertEqual(merge_dialog_text.fix_emotion_tag("[NormalDobby tells"), "[Normal]Dobby tells")
        self.assertEqual(merge_dialog_text.fix_emotion_tag("[Happy]fine"), "[Happy]fine")
        self.assertEqual(merge_dialog_text.fix_emotion_tag("Hello"), "Hello")


class CreditsTests(unittest.TestCase):
    def test_missing_language_is_skipped(self):
        old = generate_lang_credits.LANGS_DIR
        generate_lang_credits.LANGS_DIR = Path(tempfile.mkdtemp())
        try:
            self.assertIsNone(generate_lang_credits.credits_file("pol"))
        finally:
            generate_lang_credits.LANGS_DIR = old


@unittest.skipIf(os.name == "nt", "Wine path mapping is Linux/macOS only")
class WinePathTests(unittest.TestCase):
    def test_inside_and_outside_prefix(self):
        prefix = Path(tempfile.mkdtemp())
        os.environ["WINEPREFIX"] = str(prefix)
        try:
            (prefix / "drive_c" / "HP2Mod").mkdir(parents=True)
            self.assertEqual(hp2mod.ucc_path(prefix / "drive_c" / "HP2Mod" / "tmp"), "C:\\HP2Mod\\tmp")
            self.assertTrue(hp2mod.ucc_path(Path("/tmp/x")).startswith("Z:"))
        finally:
            del os.environ["WINEPREFIX"]


class AssetZipTests(unittest.TestCase):
    def test_members_skip_raw_packages_and_old_sources(self):
        tmp = Path(tempfile.mkdtemp())
        langs = tmp / "audio_source" / "langs"
        (langs / "fre" / "audio").mkdir(parents=True)
        (langs / "fre" / "audio" / "PC_X_1.wav").write_bytes(b"RIFF")
        (langs / "fre" / "HpDialog.fre").write_text("[All]\n")
        (langs / "fre" / "AllDialog.FRE_uax").write_bytes(b"x")
        (langs / "rus" / "_2002_subtitle_only").mkdir(parents=True)
        (langs / "rus" / "_2002_subtitle_only" / "HpDialog.rus").write_text("old")
        (tmp / "stock_original" / "HGame" / "Classes").mkdir(parents=True)
        (tmp / "stock_original" / "HGame" / "Classes" / "A.uc").write_text("class A;")
        old = (hp2mod.ASSETS, hp2mod.LANGS_DIR, hp2mod.STOCK_ORIGINAL)
        hp2mod.ASSETS, hp2mod.LANGS_DIR, hp2mod.STOCK_ORIGINAL = tmp, langs, tmp / "stock_original"
        try:
            names = sorted(arc for _, arc in hp2mod.zip_members())
        finally:
            hp2mod.ASSETS, hp2mod.LANGS_DIR, hp2mod.STOCK_ORIGINAL = old
        self.assertEqual(names, ["audio_source/langs/fre/HpDialog.fre",
                                 "audio_source/langs/fre/audio/PC_X_1.wav",
                                 "stock_original/HGame/Classes/A.uc"])


class SigV4Tests(unittest.TestCase):
    """AWS's published Signature V4 examples for S3 (examplebucket)."""
    AK, SK = "AKIAIOSFODNN7EXAMPLE", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
    NOW = __import__("datetime").datetime(2013, 5, 24, tzinfo=__import__("datetime").timezone.utc)

    def sig(self, method, url, headers, payload):
        h = s3.sign(method, url, headers, payload, self.AK, self.SK, "us-east-1", now=self.NOW)
        return h["authorization"].rsplit("Signature=", 1)[1]

    def test_get_object_with_range(self):
        self.assertEqual(self.sig("GET", "https://examplebucket.s3.amazonaws.com/test.txt",
                                  {"Range": "bytes=0-9"}, s3.EMPTY_SHA256),
                         "f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41")

    def test_put_object(self):
        body = b"Welcome to Amazon S3."
        import hashlib
        self.assertEqual(self.sig("PUT", "https://examplebucket.s3.amazonaws.com/test$file.text",
                                  {"Date": "Fri, 24 May 2013 00:00:00 GMT",
                                   "x-amz-storage-class": "REDUCED_REDUNDANCY"},
                                  hashlib.sha256(body).hexdigest()),
                         "98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd")

    def test_get_bucket_lifecycle(self):
        self.assertEqual(self.sig("GET", "https://examplebucket.s3.amazonaws.com/?lifecycle",
                                  {}, s3.EMPTY_SHA256),
                         "fea454ca298b7da1c68078a5d1bdbfbbe0d65c699e0f91ac7a200a0136783543")

    def test_list_objects(self):
        self.assertEqual(self.sig("GET", "https://examplebucket.s3.amazonaws.com/?max-keys=2&prefix=J",
                                  {}, s3.EMPTY_SHA256),
                         "34b48302e7b5fa45bde8084f4b7868a86f0a534bc59db6670ed5711ef69dc6f7")


class CliTests(unittest.TestCase):
    def test_help_and_paths(self):
        with self.assertRaises(SystemExit) as cm:
            hp2mod.main(["--help"])
        self.assertEqual(cm.exception.code, 0)
        self.assertEqual(hp2mod.main(["paths"]), 0)


if __name__ == "__main__":
    unittest.main()
