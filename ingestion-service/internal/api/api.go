package api

import (
	"log"
	"net/http"
	"time"

	"github.com/ReetamBG/high-perf-event-ingestor/internal/events"
	"github.com/ReetamBG/high-perf-event-ingestor/internal/kafka_utils"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

type Config struct {
	Addr string
}

type Application struct {
	AppConifg   Config
	KafkaConfig kafka_utils.KafkaConfig
}

func (app *Application) Mount() http.Handler {
	mux := chi.NewRouter()

	// middlewares
	mux.Use(middleware.RequestID)
	mux.Use(middleware.ClientIPFromRemoteAddr) // get the request IP
	mux.Use(middleware.Logger)
	mux.Use(middleware.Recoverer) // recover from crashes
	mux.Use(middleware.Timeout(60 * time.Second))

	mux.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(200)
		w.Write([]byte("All good"))
	})

	kafkaWriter := kafka_utils.NewWriter(app.KafkaConfig)
	eventsService := events.NewService(kafkaWriter)
	eventsHandler := events.NewHandler(eventsService)
	mux.Post("/events/ingest", eventsHandler.Ingest)

	return mux
}

func (app *Application) Run(h http.Handler) error {
	s := http.Server{
		Addr:         app.AppConifg.Addr,
		Handler:      h,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  time.Minute,
	}

	log.Printf("Server running on port: %s\n", app.AppConifg.Addr)
	return s.ListenAndServe()
}
