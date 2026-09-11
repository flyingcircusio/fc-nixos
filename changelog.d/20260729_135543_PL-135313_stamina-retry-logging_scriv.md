### NixOS XX.XX platform

- Stamina retry logs now selectively redact credential-like values (e.g. S3 secret/access keys), keeping non-sensitive call arguments (e.g. usernames, buckets) for debugging. (PL-135313)
