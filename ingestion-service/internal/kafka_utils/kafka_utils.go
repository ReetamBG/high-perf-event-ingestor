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

	// async writes
	BatchSize    int
	BatchTimeout time.Duration
}

type Writer struct {
	*kafka.Writer
}

// TODO: add backpressure when kafka is full
func NewWriter(config KafkaConfig) *Writer {
	w := &kafka.Writer{
		Addr:                   kafka.TCP(config.Brokers...),
		Balancer:               &kafka.LeastBytes{},
		AllowAutoTopicCreation: config.AutoTopicCreation,
		MaxAttempts:            config.MaxAttempts,
		WriteTimeout:           config.WriteTimeout,

		// async writes (allows for batch writes)
		Async:        true,
		BatchSize:    config.BatchSize,
		BatchTimeout: config.BatchTimeout,

		// async error and success hook (need this cuz async writes cannot be handled using http responses)
		// no need to handle retries here as the writer auto retries enabled using MaxAttempts above
		// this function is invoked if all MaxAttempts fails
		// in that case, send to Dead Letter Queue (DLQ)
		Completion: func(messages []kafka.Message, err error) {
			if err != nil {
				slog.Error("Async write to kafka broker failed after retries", "error", err, "messages", len(messages))

				// for _, msg := range messages {
				// log.Println(msg)
				// TODO: send to DLQ here
				// TODO: Use a different topic for this, connect sink connector input to this topic
				// }

				slog.Info("Sent messages to DLQ", "messages", len(messages))
			}

		},
	}

	return &Writer{
		Writer: w,
	}
}

func (w *Writer) Write(topic string, data []byte) {
	w.WriteMessages(context.Background(),
		kafka.Message{
			Topic: topic,
			Value: data,
		},
	)

	// return err  // no point returning error now as its async
}

func (w *Writer) CloseConnection() error {
	err := w.Close()
	if err != nil {
		slog.Error("failed to close writer", "Error: ", err)
	}

	return err
}
