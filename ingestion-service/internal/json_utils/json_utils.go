package json_utils

import (
	"net/http"

	"github.com/bytedance/sonic"
)

func Write(w http.ResponseWriter, statusCode int, content any) error {
	data, err := sonic.Marshal(content)
	if err != nil {
		return err
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)

	_, err = w.Write(data)

	return err
}

func ReadBody(r *http.Request, dest any) error {
	return sonic.ConfigDefault.NewDecoder(r.Body).Decode(dest)
}
