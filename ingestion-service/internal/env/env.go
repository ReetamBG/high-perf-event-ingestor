package env

import (
	"os"
	"strconv"
	"strings"
)

func GetString(key string, defaultVal string) string {
	val, exists := os.LookupEnv(key)
	if !exists {
		return defaultVal
	}
	return val
}

func GetInt(key string, defaultVal int) int {
	val, exists := os.LookupEnv(key)
	if !exists {
		return defaultVal
	}

	intVal, err := strconv.Atoi(val)
	if err != nil {
		return defaultVal
	}

	return intVal
}

func GetSlice(key string, defaultValue []string) []string {
	vals, exists := os.LookupEnv(key)
	if !exists {
		return defaultValue
	}

	slice := strings.Split(vals, ",")
	if len(slice) == 0 {
		return defaultValue
	}

	return slice
}
