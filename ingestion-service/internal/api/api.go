package api

import (
	"log"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

type Application struct {
	Conifg Config
	DB     DBConfig
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

	return mux
}

func (app *Application) Run(h http.Handler) error {
	s := http.Server{
		Addr:         app.Conifg.Addr,
		Handler:      h,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  time.Minute,
	}

	log.Printf("Server running on port: %s\n", app.Conifg.Addr)
	return s.ListenAndServe()
}

type Config struct {
	Addr string
}

type DBConfig struct {
}
