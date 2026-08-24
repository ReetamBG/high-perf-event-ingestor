package events

import (
	"context"
	"encoding/json"
	"log/slog"
	"reflect"

	"github.com/ReetamBG/high-perf-event-ingestor/internal/kafka_utils"
)

type Service interface {
	Ingest(ctx context.Context, data any) error
}

type svc struct {
	kafkaWriter *kafka_utils.Writer
}

// TODO : make provision for different events
func (s *svc) Ingest(ctx context.Context, data any) error {
	if reflect.TypeOf(data) == reflect.TypeFor[Event]() {
		data, err := json.Marshal(data)
		if err != nil {
			slog.Error("Error unmarshling data", "Error", err)
			return err
		}

		topic := "events"

		s.kafkaWriter.Write(topic, data)
	}

	return nil
}

func NewService(kafkaWriter *kafka_utils.Writer) Service {
	return &svc{
		kafkaWriter: kafkaWriter,
	}
}
