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

func main() {
	secret := requireEnv("LEONA_SECRET_KEY")
	boxID := requireEnv("BOX_ID")
	endpoint := os.Getenv("LEONA_ENDPOINT")
	if endpoint == "" {
		endpoint = defaultEndpoint
	}

	body, err := json.Marshal(map[string]string{"boxId": boxID})
	must(err)

	timestamp := fmt.Sprintf("%d", time.Now().UnixMilli())
	nonce := randomBase64URL(16)
	bodyHash := sha256.Sum256(body)
	signingText := fmt.Sprintf("%s\n%s\n%s", timestamp, nonce, hex.EncodeToString(bodyHash[:]))
	signature := hmacBase64URL(secret, signingText)

	req, err := http.NewRequest(http.MethodPost, endpoint, bytes.NewReader(body))
	must(err)
	req.Header.Set("Authorization", "Bearer "+secret)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Leona-Timestamp", timestamp)
	req.Header.Set("X-Leona-Nonce", nonce)
	req.Header.Set("X-Leona-Signature", signature)

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
