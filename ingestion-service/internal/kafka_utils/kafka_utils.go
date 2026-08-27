package kafka_utils

import (
	"context"
	"log/slog"
	"sync"
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
	QueueSize    int // for backpressure
}

type Writer struct {
	*kafka.Writer
	DLQWriter *kafka.Writer

	// for backpressure when kafka is full
	Queue        chan kafka.Message
	BatchSize    int
	BatchTimeout time.Duration

	wg sync.WaitGroup
}

func NewWriter(config KafkaConfig) *Writer {
	w := &kafka.Writer{
		Addr:                   kafka.TCP(config.Brokers...),
		Balancer:               &kafka.LeastBytes{},
		AllowAutoTopicCreation: config.AutoTopicCreation,
		MaxAttempts:            config.MaxAttempts,
		WriteTimeout:           config.WriteTimeout,

		// async writes (allows for batch writes) - disabled as we handle it explicitly on our side now
		// disabled as we are adding backpressure from our own side
		// Async:        true,
		// BatchSize:    config.BatchSize,
		// BatchTimeout: config.BatchTimeout,

		Async: false,

		// Completion handles final Kafka write failures after all retries.
		// Failed messages can be routed to the producer-side DLQ.
		// purely kept for logging here - errors handled directly at write site
		Completion: func(messages []kafka.Message, err error) {
			if err != nil {
				slog.Error("Write to kafka broker failed after retries", "error", err, "messages", len(messages))
			}
		},
	}

	// DLQ with async writes - fire and forget
	DLQWriter := &kafka.Writer{
		Addr:                   kafka.TCP(config.Brokers...),
		Balancer:               &kafka.LeastBytes{},
		AllowAutoTopicCreation: config.AutoTopicCreation,
		MaxAttempts:            config.MaxAttempts,
		WriteTimeout:           config.WriteTimeout,
		Async:                  true,
		Completion: func(messages []kafka.Message, err error) {
			if err != nil {
				slog.Error("Write to DLQ failed after retries", "error", err, "messages", len(messages))
			}
		},
	}

	writer := &Writer{
		Writer:       w,
		DLQWriter:    DLQWriter,
		Queue:        make(chan kafka.Message, config.QueueSize),
		BatchSize:    config.BatchSize,
		BatchTimeout: config.BatchTimeout,
	}

	for _ = range 8 {
		writer.wg.Go(writer.drain) // start draining the queue
	}

	return writer
}

func (w *Writer) Write(topic string, data []byte) bool {
	select {
	// if can add to queue then okay
	case w.Queue <- kafka.Message{Topic: topic, Value: data}:
		return true

	// otherwise kafka is full => slow writes => queue filled up
	default:
		return false
	}
}

// drains the messages from queue (channel) and writes to kafka
// writes when BatchSize is attained or when BatchTimeout is reached
func (w *Writer) drain() {
	batch := make([]kafka.Message, 0, w.BatchSize)
	ticker := time.NewTicker(w.BatchTimeout)
	defer ticker.Stop()

	for {
		select {
		// if messages are there in queue add to batch
		case msg, ok := <-w.Queue:
			if !ok {
				if len(batch) > 0 {
					if err := w.WriteMessages(context.Background(), batch...); err != nil {
						w.writeToDLQ(context.Background(), batch)
					}
				}
				return
			}

			batch = append(batch, msg)
			// push them when batch fills
			if len(batch) >= w.BatchSize {
				if err := w.WriteMessages(context.Background(), batch...); err != nil {
					w.writeToDLQ(context.Background(), batch)
				}
				batch = batch[:0]
			}

		// or if timer expires before batch fills then also send
		// essentially acts as BatchSize or BatchTimeout whichever occurs first
		case <-ticker.C:
			if len(batch) > 0 {
				if err := w.WriteMessages(context.Background(), batch...); err != nil {
					w.writeToDLQ(context.Background(), batch)
				}
				batch = batch[:0]
			}
		}
	}

}

func (w *Writer) writeToDLQ(ctx context.Context, messages []kafka.Message) {
	for i := range messages {
		messages[i].Topic = resolveDLQTopic(messages[i].Topic)
	}
	_ = w.DLQWriter.WriteMessages(ctx, messages...) // async write no need to handler err
}

func (w *Writer) CloseConnection() error {
	close(w.Queue) // close the queue - will flush it
	w.wg.Wait()    // wait for goroutines to return

	// close the primary writer after that
	if err := w.Close(); err != nil {
		slog.Error("failed to close writer", "error", err)
		return err
	}

	// close the DLQ writer after that
	if err := w.DLQWriter.Close(); err != nil {
		slog.Error("failed to close DLQ writer", "error", err)
		return err
	}

	return nil
}

func resolveDLQTopic(topic string) string {
	return topic + ".dlq"
}
