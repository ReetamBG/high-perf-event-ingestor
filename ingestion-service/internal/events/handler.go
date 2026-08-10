package events

import (
	"log/slog"
	"net/http"

	"github.com/ReetamBG/high-perf-event-ingestor/internal/json_utils"
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

	var data Todo

	if err := json_utils.ReadBody(r, &data); err != nil {
		slog.Error("Error reading body", "Error", err)
		json_utils.Write(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}

	if err := h.Svc.Ingest(r.Context(), data); err != nil {
		json_utils.Write(w, http.StatusInternalServerError, map[string]string{"error": "internal server error"})
	}

	w.WriteHeader(http.StatusAccepted)
}
