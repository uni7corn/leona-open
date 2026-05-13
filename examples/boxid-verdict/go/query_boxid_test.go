package main

import "testing"

func TestFixedDryRunSignature(t *testing.T) {
	signed, err := buildSignedRequest(
		"test_secret_do_not_use",
		"box_test_000000000000000000",
		defaultEndpoint,
		"1700000000000",
		"nonce_for_dry_run",
	)
	if err != nil {
		t.Fatal(err)
	}
	if signed.Body != `{"boxId":"box_test_000000000000000000"}` {
		t.Fatalf("body mismatch: %s", signed.Body)
	}
	if signed.BodySHA256 != "c7aba2a73265ed90feeaa0eb8d8b35591dbc157e15ac1122b6bec17d00da430d" {
		t.Fatalf("body hash mismatch: %s", signed.BodySHA256)
	}
	if signed.Headers["X-Leona-Signature"] != "zRvnS0zA4OrYmNu9xEid-tZDT5EO-6-UBQnuJgh_z2E" {
		t.Fatalf("signature mismatch: %s", signed.Headers["X-Leona-Signature"])
	}
}
