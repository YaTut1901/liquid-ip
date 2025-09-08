package jsonval

import (
	"encoding/json"
	"fmt"
	"strings"
)

type JSONMap map[string]interface{}

func Parse(b []byte) (JSONMap, error) {
	var m JSONMap
	if err := json.Unmarshal(b, &m); err != nil {
		return nil, fmt.Errorf("invalid json: %w", err)
	}
	return m, nil
}

func PlaceholderValidate(oldM, newM JSONMap, schema JSONMap) bool {
	// Default rule: every key present in old must exist in new
	for k := range oldM {
		if _, ok := newM[k]; !ok {
			return false
		}
	}
	return true
}

// MissingKeys returns keys present in oldM but absent in newM.
func MissingKeys(oldM, newM JSONMap) []string {
	var out []string
	for k := range oldM {
		if _, ok := newM[k]; !ok {
			out = append(out, k)
		}
	}
	return out
}

func StatusFromJSON(m JSONMap) (uint8, error) {
	v, ok := m["status"]
	if !ok {
		return 0, fmt.Errorf("status missing")
	}
	s, ok := v.(string)
	if !ok {
		return 0, fmt.Errorf("status not string")
	}
	s = strings.ToUpper(strings.TrimSpace(s))
	switch s {
	case "UNKNOWN":
		return 0, nil
	case "VALID":
		return 1, nil
	case "INVALID":
		return 2, nil
	case "UNDER_ATTACK":
		return 3, nil
	default:
		return 0, fmt.Errorf("unknown status: %s", s)
	}
}
