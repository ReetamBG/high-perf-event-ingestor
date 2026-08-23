package jwt

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strings"

	"github.com/ReetamBG/high-perf-event-ingestor/internal/env"
	"github.com/golang-jwt/jwt/v5"
)

type contextKey string

const claimsKey contextKey = "jwtClaims"

var jwtSecret = []byte(env.GetString("JWT_SECRET", ""))

// CustomClaims defines the structure of your JWT payload
type CustomClaims struct {
	UserID string `json:"userId"`
	Role   string `json:"role"`
	jwt.RegisteredClaims
}

// JWTMiddleware validates the token and adds claims to the context
func JWTMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")
		if authHeader == "" {
			http.Error(w, "Authorization header missing", http.StatusUnauthorized)
			return
		}

		// Check for Bearer prefix
		parts := strings.Split(authHeader, " ")
		if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
			http.Error(w, "Invalid authorization format", http.StatusUnauthorized)
			return
		}

		tokenString := parts[1]
		claims := &CustomClaims{}

		// Parse and validate token
		token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (interface{}, error) {
			// Crucial: Validate the signing method to prevent algorithm-switching attacks
			if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
			}
			return jwtSecret, nil
		})

		if err != nil || !token.Valid {
			http.Error(w, "Invalid or expired token", http.StatusUnauthorized)
			return
		}

		// Inject claims into the request context
		ctx := context.WithValue(r.Context(), claimsKey, claims)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// Helper function to easily retrieve claims in protected handlers
func GetClaims(ctx context.Context) (*CustomClaims, error) {
	claims, ok := ctx.Value(claimsKey).(*CustomClaims)
	if !ok {
		return nil, errors.New("no claims found in context")
	}
	return claims, nil
}
