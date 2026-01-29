Create a `config.toml` file with the following content:
```toml
skvaider_token = "TOKEN_PLACEHOLDER";
skvaider_url = "https://ai.<LOCATION>.fcio.net/openai/v1"
```

And run the tool with

```bash
uv run main.py --config config.toml embeddings --output embeddings.json
```

It also includes tooling to generate an embeddings comparison report similar, which was used to confirm that the old and new setups produce similar results.
