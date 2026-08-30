```
                  HTTP requests
                       │
                       ▼
                    Write()
                       │
              ┌────────┴────────┐
              │                 │
          queue space        queue full
              │                 │
              ▼                 ▼
           channel             429
              │
              ▼
      ┌───────────────┐
      │ drain()       │
      │               │
      │ collect       │
      │ up to         │
      │ BatchSize     │
      │ OR            │
      │ BatchTimeout  │
      └────────┬──────┘
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
