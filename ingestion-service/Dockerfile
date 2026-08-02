FROM golang:1.26 AS build-stage

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -o /bin/app ./cmd/server/main.go


# Transfer to a lean image

FROM gcr.io/distroless/base-debian11 as build-relase-stage

COPY --from=build-stage /bin/app /app

EXPOSE 8080

USER nonroot:nonroot

ENTRYPOINT [ "/app" ]

# CMD ["/bin/app"]
