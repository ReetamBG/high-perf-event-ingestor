package main

import (
	"fmt"
	"log/slog"
	"os"
	"time"

	"github.com/ReetamBG/high-perf-event-ingestor/internal/api"
	"github.com/ReetamBG/high-perf-event-ingestor/internal/env"
	"github.com/ReetamBG/high-perf-event-ingestor/internal/events"
	"github.com/ReetamBG/high-perf-event-ingestor/internal/kafka_utils"
)

func main() {
	// logger
	logger := slog.New(slog.NewTextHandler(os.Stdout, nil))
	slog.SetDefault(logger)

	// configs
	ac := api.Config{
		Addr: fmt.Sprintf(":%s", env.GetString("PORT", "8080")),
	}

	defaultBrokers := []string{"redpanda-0:9092"}
	kafkaConfig := kafka_utils.KafkaConfig{
		Brokers:           env.GetSlice("BROKERS", defaultBrokers),
		AutoTopicCreation: true,
		MaxAttempts:       3,
		WriteTimeout:      10 * time.Second,

		// async writes
		BatchSize:    500,
		BatchTimeout: time.Millisecond * 10,
	}

	// init services and handlers

	// infrastructure
	kafkaWriter := kafka_utils.NewWriter(kafkaConfig)
	defer kafkaWriter.CloseConnection()
	// TODO : add proper graceful shutdown (idk what chatgpt said too complex for now)
	// TODO : Graceful shutdown: handle SIGINT/SIGTERM, gracefully stop HTTP server, then flush/close the async Kafka producer before process exit.

	// services
	eventsService := events.NewService(kafkaWriter)

	// handlers
	eventsHandler := events.NewHandler(eventsService)

	app := api.Application{
		AppConfig:     ac,
		EventsHandler: eventsHandler,
	}

	h := app.Mount()
	if err := app.Run(h); err != nil {
		slog.Error("Error while starting server", "error", err)
		os.Exit(1)
	}
}
