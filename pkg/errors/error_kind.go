package errors

import (
	"encoding/json"
	"fmt"
	"strings"
)

// Known error kinds
const (
	UnknownError StorageOSErrorKind = iota
)

var kindLookupMap map[string]StorageOSErrorKind

func init() {
	kindLookupMap = make(map[string]StorageOSErrorKind)

	// Populate the lookup map with all the known constants
	for i := StorageOSErrorKind(0); !strings.HasPrefix(i.String(), "StorageosErrorKind("); i++ {
		kindLookupMap[i.String()] = i
	}
}

//go:generate stringer -type=StorageOSErrorKind error_kind.go
type StorageOSErrorKind int

func (s *StorageOSErrorKind) UnmarshalJSON(b []byte) error {
	str := ""
	if err := json.Unmarshal(b, &str); err != nil {
		return err
	}

	v, ok := kindLookupMap[str]
	if !ok {
		return fmt.Errorf("Failed to unmarshal ErrorKind %s", s)
	}

	*s = v
	return nil
}

func (s *StorageOSErrorKind) MarshalJSON() ([]byte, error) {
	return json.Marshal(s.String())
}
