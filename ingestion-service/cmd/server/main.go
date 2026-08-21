package main

import (
	"fmt"
	"log/slog"
	"os"
	"time"

	"github.com/ReetamBG/high-perf-event-ingestor/internal/api"
	"github.com/ReetamBG/high-perf-event-ingestor/internal/env"
	"github.com/ReetamBG/high-perf-event-ingestor/internal/kafka_utils"
)

func main() {
	// logger
	logger := slog.New(slog.NewTextHandler(os.Stdout, nil))
	slog.SetDefault(logger)

	ac := api.Config{
		Addr: fmt.Sprintf(":%s", env.GetString("PORT", "8080")),
	}

	defaultBrokers := []string{"redpanda-0:9092"}
	kc := kafka_utils.KafkaConfig{
		Brokers:           env.GetSlice("BROKERS", defaultBrokers),
		AutoTopicCreation: true,
		MaxAttempts:       3,
		WriteTimeout:      10 * time.Second,
	}

	app := api.Application{
		AppConifg:   ac,
		KafkaConfig: kc,
	}

	h := app.Mount()
	if err := app.Run(h); err != nil {
		slog.Error("Error while starting server", "error", err)
		os.Exit(1)
	}
}
