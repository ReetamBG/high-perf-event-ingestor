package json_util

import (
	"encoding/json"
	"net/http"
)

func Write(w http.ResponseWriter, statusCode int, content any) error {
	data, err := json.Marshal(content)
	if err != nil {
		return err
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)

	_, err = w.Write(data)

	return err
}

func ReadBody(r *http.Request, dest *any) error {
	return json.NewDecoder(r.Body).Decode(dest)
}
