package openaicompat

import (
	"fmt"
	"regexp"
	"sync"

	"github.com/QuantumNous/new-api/const_var"
)

var compiledRegexCache sync.Map // map[string]*regexp.Regexp

func matchAnyRegex(patterns []string, s string) bool {
	if len(patterns) == 0 || s == "" {
		return false
	}
	for _, pattern := range patterns {
		if pattern == "" {
			continue
		}
		key := fmt.Sprintf("%s:%s", const_var.REDIS_KEY_PREFIX, pattern)
		re, ok := compiledRegexCache.Load(key)
		if !ok {
			compiled, err := regexp.Compile(pattern)
			if err != nil {
				// Treat invalid patterns as non-matching to avoid breaking runtime traffic.
				continue
			}
			re = compiled
			compiledRegexCache.Store(key, re)
		}
		if re.(*regexp.Regexp).MatchString(s) {
			return true
		}
	}
	return false
}
