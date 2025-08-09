# GitOps repository

The structure
```
hello-world-delivery/
├── Chart.yaml                  # Umbrella chart that depends on your base chart
├── values.yaml                 # Shared defaults for all envs
├── envs/
│   ├── dev/
│   │   └── values.yaml         # Dev overrides
│   ├── stage/
│   │   └── values.yaml         # Stage overrides
│   └── prod/
│       └── values.yaml         # Prod overrides
└── README.md
```

