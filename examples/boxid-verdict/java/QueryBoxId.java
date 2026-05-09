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
        String secret = requireEnv("LEONA_SECRET_KEY");
        String boxId = requireEnv("BOX_ID");
        String endpoint = System.getenv().getOrDefault("LEONA_ENDPOINT", DEFAULT_ENDPOINT);

        String body = "{\"boxId\":\"" + escapeJson(boxId) + "\"}";
        String timestamp = Long.toString(Instant.now().toEpochMilli());
        String nonce = randomBase64Url(16);
        String bodySha256 = sha256Hex(body.getBytes(StandardCharsets.UTF_8));
        String signingText = timestamp + "\n" + nonce + "\n" + bodySha256;
        String signature = hmacSha256Base64Url(secret, signingText);

        HttpRequest request = HttpRequest.newBuilder(URI.create(endpoint))
            .POST(HttpRequest.BodyPublishers.ofString(body))
            .header("Authorization", "Bearer " + secret)
            .header("Content-Type", "application/json")
            .header("X-Leona-Timestamp", timestamp)
            .header("X-Leona-Nonce", nonce)
            .header("X-Leona-Signature", signature)
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
}
