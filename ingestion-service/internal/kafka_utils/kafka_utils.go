package kafka_utils

import (
	"context"
	"log/slog"
	"time"

	"github.com/segmentio/kafka-go"
)

type KafkaConfig struct {
	Brokers           []string
	AutoTopicCreation bool
	MaxAttempts       int
	WriteTimeout      time.Duration
}

type Writer struct {
	*kafka.Writer
}

func NewWriter(config KafkaConfig) *Writer {
	w := &kafka.Writer{
		Addr:                   kafka.TCP(config.Brokers...),
		Balancer:               &kafka.LeastBytes{},
		AllowAutoTopicCreation: config.AutoTopicCreation,
		MaxAttempts:            config.MaxAttempts,
		WriteTimeout:           config.WriteTimeout,
	}

	return &Writer{
		Writer: w,
	}
}

func (w *Writer) Write(topics []string, values [][]byte) error {
	messages := []kafka.Message{}
	for i := range values {
		messages = append(messages, kafka.Message{
			Topic: topics[i],
			Value: values[i],
		})
	}

	err := w.WriteMessages(context.Background(), messages...)
	if err != nil {
		slog.Error("failed to write messages", "Error", err)
	}

	return err
}

func (w *Writer) CloseConnection() error {
	err := w.Close()
	if err != nil {
		slog.Error("failed to close writer", "Error: ", err)
	}

	return err
}
