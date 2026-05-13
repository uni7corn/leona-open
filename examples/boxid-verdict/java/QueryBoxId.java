import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.Base64;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

public final class QueryBoxId {
    private static final String DEFAULT_ENDPOINT = "https://leona.xiyanshan.com/v1/verdict";
    private static final SecureRandom RANDOM = new SecureRandom();

    public static void main(String[] args) throws Exception {
        if (args.length > 0 && "--self-test".equals(args[0])) {
            selfTest();
            return;
        }

        String secret = requireEnv("LEONA_SECRET_KEY");
        String boxId = requireEnv("BOX_ID");
        String endpoint = System.getenv().getOrDefault("LEONA_ENDPOINT", DEFAULT_ENDPOINT);
        String timestamp = System.getenv().getOrDefault(
            "LEONA_TIMESTAMP",
            Long.toString(Instant.now().toEpochMilli())
        );
        String nonce = System.getenv().getOrDefault("LEONA_NONCE", randomBase64Url(16));

        SignedRequest signed = buildSignedRequest(secret, boxId, endpoint, timestamp, nonce);

        if ("1".equals(System.getenv("LEONA_DRY_RUN"))) {
            System.out.println(signed.toJson());
            return;
        }

        HttpRequest request = HttpRequest.newBuilder(URI.create(endpoint))
            .POST(HttpRequest.BodyPublishers.ofString(signed.body))
            .header("Authorization", signed.authorization)
            .header("Content-Type", "application/json")
            .header("X-Leona-Timestamp", signed.timestamp)
            .header("X-Leona-Nonce", signed.nonce)
            .header("X-Leona-Signature", signed.signature)
            .build();

        HttpResponse<String> response = HttpClient.newHttpClient()
            .send(request, HttpResponse.BodyHandlers.ofString());

        if (response.statusCode() < 200 || response.statusCode() >= 300) {
            System.err.println("Leona query failed: HTTP " + response.statusCode());
            System.err.println(response.body());
            System.exit(1);
        }
        System.out.println(response.body());
    }

    static SignedRequest buildSignedRequest(
        String secret,
        String boxId,
        String endpoint,
        String timestamp,
        String nonce
    ) throws Exception {
        String body = "{\"boxId\":\"" + escapeJson(boxId) + "\"}";
        String bodySha256 = sha256Hex(body.getBytes(StandardCharsets.UTF_8));
        String signingText = timestamp + "\n" + nonce + "\n" + bodySha256;
        String signature = hmacSha256Base64Url(secret, signingText);
        return new SignedRequest(
            endpoint,
            body,
            bodySha256,
            "Bearer " + secret,
            timestamp,
            nonce,
            signature
        );
    }

    private static void selfTest() throws Exception {
        SignedRequest signed = buildSignedRequest(
            "test_secret_do_not_use",
            "box_test_000000000000000000",
            DEFAULT_ENDPOINT,
            "1700000000000",
            "nonce_for_dry_run"
        );
        assertEquals("{\"boxId\":\"box_test_000000000000000000\"}", signed.body, "body");
        assertEquals(
            "c7aba2a73265ed90feeaa0eb8d8b35591dbc157e15ac1122b6bec17d00da430d",
            signed.bodySha256,
            "bodySha256"
        );
        assertEquals(
            "zRvnS0zA4OrYmNu9xEid-tZDT5EO-6-UBQnuJgh_z2E",
            signed.signature,
            "signature"
        );
        System.out.println("QueryBoxId self-test passed");
    }

    private static void assertEquals(String expected, String actual, String name) {
        if (!expected.equals(actual)) {
            throw new AssertionError(name + " mismatch: expected " + expected + " but got " + actual);
        }
    }

    private static String requireEnv(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException("Missing required environment variable: " + name);
        }
        return value.trim();
    }

    private static String randomBase64Url(int bytes) {
        byte[] out = new byte[bytes];
        RANDOM.nextBytes(out);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(out);
    }

    private static String hmacSha256Base64Url(String secret, String text) throws Exception {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
        return Base64.getUrlEncoder().withoutPadding()
            .encodeToString(mac.doFinal(text.getBytes(StandardCharsets.UTF_8)));
    }

    private static String sha256Hex(byte[] bytes) throws Exception {
        byte[] digest = MessageDigest.getInstance("SHA-256").digest(bytes);
        StringBuilder sb = new StringBuilder(digest.length * 2);
        for (byte b : digest) {
            sb.append(String.format("%02x", b & 0xff));
        }
        return sb.toString();
    }

    private static String escapeJson(String value) {
        return value.replace("\\", "\\\\").replace("\"", "\\\"");
    }

    static final class SignedRequest {
        final String endpoint;
        final String body;
        final String bodySha256;
        final String authorization;
        final String timestamp;
        final String nonce;
        final String signature;

        SignedRequest(
            String endpoint,
            String body,
            String bodySha256,
            String authorization,
            String timestamp,
            String nonce,
            String signature
        ) {
            this.endpoint = endpoint;
            this.body = body;
            this.bodySha256 = bodySha256;
            this.authorization = authorization;
            this.timestamp = timestamp;
            this.nonce = nonce;
            this.signature = signature;
        }

        String toJson() {
            return "{\n"
                + "  \"endpoint\": \"" + escapeJson(endpoint) + "\",\n"
                + "  \"body\": \"" + escapeJson(body) + "\",\n"
                + "  \"bodySha256\": \"" + bodySha256 + "\",\n"
                + "  \"headers\": {\n"
                + "    \"Authorization\": \"" + escapeJson(authorization) + "\",\n"
                + "    \"Content-Type\": \"application/json\",\n"
                + "    \"X-Leona-Timestamp\": \"" + timestamp + "\",\n"
                + "    \"X-Leona-Nonce\": \"" + escapeJson(nonce) + "\",\n"
                + "    \"X-Leona-Signature\": \"" + signature + "\"\n"
                + "  }\n"
                + "}";
        }
    }
}
