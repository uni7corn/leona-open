import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import query_boxid


class QueryBoxIdSignatureTest(unittest.TestCase):
    def test_fixed_dry_run_signature(self):
        signed = query_boxid.build_signed_request(
            secret="test_secret_do_not_use",
            box_id="box_test_000000000000000000",
            endpoint=query_boxid.DEFAULT_ENDPOINT,
            timestamp="1700000000000",
            nonce="nonce_for_dry_run",
        )

        self.assertEqual(signed["body"], '{"boxId":"box_test_000000000000000000"}')
        self.assertEqual(
            signed["bodySha256"],
            "c7aba2a73265ed90feeaa0eb8d8b35591dbc157e15ac1122b6bec17d00da430d",
        )
        self.assertEqual(
            signed["headers"]["X-Leona-Signature"],
            "zRvnS0zA4OrYmNu9xEid-tZDT5EO-6-UBQnuJgh_z2E",
        )


if __name__ == "__main__":
    unittest.main()
