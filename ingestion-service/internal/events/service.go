package events

import (
	"context"
	"fmt"
)

type Service interface {
	Ingest(ctx context.Context, data any)
}

type svc struct {
	// DB or whatever dependencies
}

func (s *svc) Ingest(ctx context.Context, data any) {
	fmt.Println(data)
}

func NewService() Service {
	return &svc{
		// with whatever dependencies needed
	}
}
