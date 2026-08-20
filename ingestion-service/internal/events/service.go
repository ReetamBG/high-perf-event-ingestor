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
	kafkaWriter kafka_utils.Writer
}

func (s *svc) Ingest(ctx context.Context, data any) error {
	if reflect.TypeOf(data) == reflect.TypeFor[Todo]() {
		data, err := json.Marshal(data)
		if err != nil {
			slog.Error("Error unmarshling data", "Error", err)
			return err
		}

		values := [][]byte{
			data,
		}

		topics := []string{"events"}

		s.kafkaWriter.Write(topics, values)
	}

	return nil
}

func NewService(kafkaWriter kafka_utils.Writer) Service {
	return &svc{
		kafkaWriter: kafkaWriter,
	}
}
