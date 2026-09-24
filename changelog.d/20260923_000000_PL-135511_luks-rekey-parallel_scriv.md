### NixOS XX.XX platform

- `fc-luks keystore rekey` can now rekey multiple volumes concurrently, defaulting to half the available CPUs and tunable via `-j/--parallel`, with a progress bar and per-volume failure reporting. Each job runs memory-intensive key derivation (~1 GiB). (PL-135511)
