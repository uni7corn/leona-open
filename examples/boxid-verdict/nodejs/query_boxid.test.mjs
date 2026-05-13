import assert from "node:assert/strict";
import test from "node:test";

import { buildSignedRequest } from "./query_boxid.mjs";

test("fixed dry-run signature", () => {
  const signed = buildSignedRequest({
    secret: "test_secret_do_not_use",
    boxId: "box_test_000000000000000000",
    endpoint: "https://leona.xiyanshan.com/v1/verdict",
    timestamp: "1700000000000",
    nonce: "nonce_for_dry_run",
  });

  assert.equal(signed.body, '{"boxId":"box_test_000000000000000000"}');
  assert.equal(
    signed.bodySha256,
    "c7aba2a73265ed90feeaa0eb8d8b35591dbc157e15ac1122b6bec17d00da430d",
  );
  assert.equal(
    signed.headers["X-Leona-Signature"],
    "zRvnS0zA4OrYmNu9xEid-tZDT5EO-6-UBQnuJgh_z2E",
  );
});
