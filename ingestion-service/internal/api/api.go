package api

import (
	"log"
	"net/http"
	"time"

	"github.com/ReetamBG/high-perf-event-ingestor/internal/events"
	"github.com/ReetamBG/high-perf-event-ingestor/internal/jwt"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

type Config struct {
	Addr string
}

type Application struct {
	AppConfig     Config
	EventsHandler *events.Handler
}

func (app *Application) Mount() http.Handler {
	mux := chi.NewRouter()

	// middlewares
	mux.Use(middleware.RequestID)
	mux.Use(middleware.ClientIPFromRemoteAddr) // get the request IP
	// mux.Use(middleware.Logger)  // no need logger for prod as too many logs
	mux.Use(middleware.Recoverer) // recover from crashes
	mux.Use(middleware.Timeout(60 * time.Second))

	mux.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(200)
		w.Write([]byte("All good"))
	})

	mux.With(jwt.JWTMiddleware).Post("/events/ingest", app.EventsHandler.Ingest) // protected with jwt

	return mux
}

func (app *Application) Run(h http.Handler) error {
	s := http.Server{
		Addr:         app.AppConfig.Addr,
		Handler:      h,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  time.Minute,
	}

	log.Printf("Server running on port: %s\n", app.AppConfig.Addr)
	return s.ListenAndServe()
}
