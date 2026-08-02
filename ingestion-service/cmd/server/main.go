package main

import (
	"log/slog"
	"os"

	"github.com/ReetamBG/high-perf-event-ingestor/internal/api"
)

func main() {
	c := api.Config{
		Addr: ":8080",
	}

	app := api.Application{
		Conifg: c,
		DB:     api.DBConfig{},
	}

	// logger
	logger := slog.New(slog.NewTextHandler(os.Stdout, nil))
	slog.SetDefault(logger)

	h := app.Mount()
	if err := app.Run(h); err != nil {
		slog.Error("Error while starting server: %s", err)
		os.Exit(1)
	}
}
