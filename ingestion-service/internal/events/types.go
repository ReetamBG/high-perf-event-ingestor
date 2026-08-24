package events

import "time"

type Event struct {
	EventID    string    `json:"eventId"`
	EventType  string    `json:"eventType"`
	Timestamp  time.Time `json:"timestamp"`
	UserID     string    `json:"userId"`
	SessionID  string    `json:"sessionId"`
	GameID     string    `json:"gameId"`
	DeviceID   string    `json:"deviceId"`
	Platform   string    `json:"platform"`
	Country    string    `json:"country"`
	AppVersion string    `json:"appVersion"`
}
