package events

import (
	"errors"
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

	var data Event

	if err := json_utils.ReadBody(r, &data); err != nil {
		slog.Error("Error reading body", "Error", err)
		json_utils.Write(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}

	// TODO: add user id from JWT into the event

	if err := h.Svc.Ingest(r.Context(), data); err != nil {
		if errors.Is(err, ErrQueueFull) {
			w.Header().Set("Retry-After", "1")
			json_utils.Write(w, http.StatusTooManyRequests, map[string]string{"error": "too many requests, retry later"})
			return
		}

		json_utils.Write(w, http.StatusInternalServerError, map[string]string{"error": "internal server error"})
		return
	}

	w.WriteHeader(http.StatusAccepted)
}
