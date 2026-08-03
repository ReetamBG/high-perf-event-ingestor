package events

import (
	"net/http"

	json_util "github.com/ReetamBG/high-perf-event-ingestor/internal/json"
)

type Handler struct {
	Svc Service
}

func NewHandler(s Service) *Handler {
	return &Handler{
		Svc: s,
	}
}

func (h *Handler) Ingest(w http.ResponseWriter, r *http.Request) {
	defer r.Body.Close()

	var data any
	if err := json_util.ReadBody(r, &data); err != nil {
		json_util.Write(w, http.StatusOK, map[string]string{"error": "invalid request body"})
		return
	}

	h.Svc.Ingest(r.Context(), data)

	json_util.Write(w, http.StatusAccepted, data)
}
