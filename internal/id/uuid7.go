package id

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"strings"
	"time"
)

// NewUUID7 generates a UUIDv7 string (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx).
// Layout (draft-aligned):
// - 48-bit unix epoch milliseconds
// - version 7
// - 12-bit rand
// - variant RFC 4122
// - 62-bit rand
func NewUUID7() (string, error) {
	var b [16]byte

	// 48-bit unix ms
	ms := uint64(time.Now().UnixMilli())
	b[0] = byte(ms >> 40)
	b[1] = byte(ms >> 32)
	b[2] = byte(ms >> 24)
	b[3] = byte(ms >> 16)
	b[4] = byte(ms >> 8)
	b[5] = byte(ms)

	// Fill the remaining bytes with randomness.
	// We'll overwrite version/variant bits after.
	if _, err := rand.Read(b[6:]); err != nil {
		return "", err
	}

	// Set version 7 (high nibble of byte 6)
	b[6] = (b[6] & 0x0F) | 0x70

	// Set RFC 4122 variant (10xx xxxx) in byte 8
	b[8] = (b[8] & 0x3F) | 0x80

	return formatUUID(b[:]), nil
}

func ValidateUUID(s string) error {
	s = strings.ToLower(strings.TrimSpace(s))
	if len(s) != 36 {
		return errors.New("uuid: invalid length")
	}
	// hyphens positions: 8,13,18,23
	for _, p := range []int{8, 13, 18, 23} {
		if s[p] != '-' {
			return errors.New("uuid: missing hyphens")
		}
	}
	hexPart := strings.ReplaceAll(s, "-", "")
	if len(hexPart) != 32 {
		return errors.New("uuid: invalid hex length")
	}
	_, err := hex.DecodeString(hexPart)
	if err != nil {
		return errors.New("uuid: invalid hex")
	}
	return nil
}

func formatUUID(b []byte) string {
	// 16 bytes -> 36 chars
	var out [36]byte
	hex.Encode(out[0:8], b[0:4])
	out[8] = '-'
	hex.Encode(out[9:13], b[4:6])
	out[13] = '-'
	hex.Encode(out[14:18], b[6:8])
	out[18] = '-'
	hex.Encode(out[19:23], b[8:10])
	out[23] = '-'
	hex.Encode(out[24:36], b[10:16])
	return string(out[:])
}
