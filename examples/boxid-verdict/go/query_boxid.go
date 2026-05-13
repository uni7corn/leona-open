package main

import (
	"bytes"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"
)

const defaultEndpoint = "https://leona.xiyanshan.com/v1/verdict"

type signedRequest struct {
	Endpoint   string            `json:"endpoint"`
	Body       string            `json:"body"`
	BodySHA256 string            `json:"bodySha256"`
	Headers    map[string]string `json:"headers"`
}

func main() {
	secret := requireEnv("LEONA_SECRET_KEY")
	boxID := requireEnv("BOX_ID")
	endpoint := os.Getenv("LEONA_ENDPOINT")
	if endpoint == "" {
		endpoint = defaultEndpoint
	}
	timestamp := os.Getenv("LEONA_TIMESTAMP")
	if timestamp == "" {
		timestamp = fmt.Sprintf("%d", time.Now().UnixMilli())
	}
	nonce := os.Getenv("LEONA_NONCE")
	if nonce == "" {
		nonce = randomBase64URL(16)
	}

	signed, err := buildSignedRequest(secret, boxID, endpoint, timestamp, nonce)
	must(err)

	if os.Getenv("LEONA_DRY_RUN") == "1" {
		out, err := json.MarshalIndent(signed, "", "  ")
		must(err)
		fmt.Println(string(out))
		return
	}

	req, err := http.NewRequest(http.MethodPost, endpoint, bytes.NewReader([]byte(signed.Body)))
	must(err)
	for name, value := range signed.Headers {
		req.Header.Set(name, value)
	}

	resp, err := http.DefaultClient.Do(req)
	must(err)
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	must(err)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		fmt.Fprintf(os.Stderr, "Leona query failed: HTTP %d\n%s\n", resp.StatusCode, respBody)
		os.Exit(1)
	}
	fmt.Println(string(respBody))
}

func buildSignedRequest(secret, boxID, endpoint, timestamp, nonce string) (signedRequest, error) {
	body, err := json.Marshal(map[string]string{"boxId": boxID})
	if err != nil {
		return signedRequest{}, err
	}
	bodyHash := sha256.Sum256(body)
	bodySHA256 := hex.EncodeToString(bodyHash[:])
	signingText := fmt.Sprintf("%s\n%s\n%s", timestamp, nonce, bodySHA256)
	signature := hmacBase64URL(secret, signingText)
	return signedRequest{
		Endpoint:   endpoint,
		Body:       string(body),
		BodySHA256: bodySHA256,
		Headers: map[string]string{
			"Authorization":     "Bearer " + secret,
			"Content-Type":      "application/json",
			"X-Leona-Timestamp": timestamp,
			"X-Leona-Nonce":     nonce,
			"X-Leona-Signature": signature,
		},
	}, nil
}

func requireEnv(name string) string {
	value := os.Getenv(name)
	if value == "" {
		fmt.Fprintf(os.Stderr, "Missing required environment variable: %s\n", name)
		os.Exit(2)
	}
	return value
}

func randomBase64URL(size int) string {
	buf := make([]byte, size)
	_, err := rand.Read(buf)
	must(err)
	return base64.RawURLEncoding.EncodeToString(buf)
}

func hmacBase64URL(secret, text string) string {
	mac := hmac.New(sha256.New, []byte(secret))
	_, err := mac.Write([]byte(text))
	must(err)
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func must(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
