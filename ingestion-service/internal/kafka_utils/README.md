```
                  HTTP requests
                       │
                       ▼
                 TryWrite()
                       │
              ┌────────┴────────┐
              │                 │
          queue space        queue full
              │                 │
              ▼                 ▼
           channel             429
              │
              ▼
        ┌─────────────┐
        │ drain()     │
        │             │
        │ collect     │
        │ up to 500   │
        │ OR 10ms     │
        └──────┬──────┘
               │
               ▼
        WriteMessages()
          Async:false
               │
          ┌────┴────┐
          │         │
       success    failure
          │         │
          ▼         ▼
       continue   retry/DLQ
```
