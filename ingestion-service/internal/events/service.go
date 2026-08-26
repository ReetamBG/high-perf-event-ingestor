package events

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"

	"github.com/ReetamBG/high-perf-event-ingestor/internal/kafka_utils"
)

type Service interface {
	Ingest(ctx context.Context, data Event) error
}

type svc struct {
	kafkaWriter *kafka_utils.Writer
}

var ErrQueueFull = errors.New("ingest queue full")

// TODO : make provision for different events later
func (s *svc) Ingest(ctx context.Context, data Event) error {
	payload, err := json.Marshal(data)
	if err != nil {
		slog.Error("Error unmarshling data", "Error", err)
		return err
	}

	topic := "events"

	status := s.kafkaWriter.Write(topic, payload)
	if !status {
		return ErrQueueFull
	}

	return nil
}

func NewService(kafkaWriter *kafka_utils.Writer) Service {
	return &svc{
		kafkaWriter: kafkaWriter,
	}
}
