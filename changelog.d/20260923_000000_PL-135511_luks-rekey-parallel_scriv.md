### NixOS XX.XX platform

- `fc-luks keystore rekey` can now rekey multiple volumes concurrently via `-j/--parallel`, with a progress bar and per-volume failure reporting. Use with care: each job runs memory-intensive key derivation (~1 GiB). (PL-135511)
