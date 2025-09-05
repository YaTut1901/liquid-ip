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
	// Iterate keys in new; ensure present in new; always return true for now
	for k := range newM {
		_ = k
	}
	return true
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
