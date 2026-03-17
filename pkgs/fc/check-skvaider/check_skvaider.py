#!/usr/bin/env python3
"""Check skvaider functions properly."""

import argparse
import random
import sys

import requests

COMPLETION_MODEL = "gpt-oss:120b"  # XXX make configurable
EMBEDDING_MODEL = "embeddinggemma:300m"  # XXX make configurable
EXPECTED_MODELS = 2


def is_model(choices, model):
    for candidate in choices:
        if candidate in model.lower():
            return True
    return False


def check_model_list(session, base, models):
    response = session.get(base + "/openai/v1/models")
    response.raise_for_status()
    models.update(response.json())
    assert len(models["data"]) >= EXPECTED_MODELS, (
        f"too few models: {len(models['data'])} < {EXPECTED_MODELS}"
    )
    assert models["data"][0]["object"] == "model", (
        "object is not a model: models['data'][0]['object']"
    )
    assert "id" in models["data"][0], "model is missing `id`"
    assert "created" in models["data"][0], "model is missing `created`"
    assert "owned_by" in models["data"][0], "model is missing `owned_by`"


def check_model_details(session, base, models):
    model_id = random.choice(models["data"])["id"]

    response = session.get(base + f"/openai/v1/models/{model_id}")
    response.raise_for_status()

    model = response.json()
    assert model["object"] == "model", "object is not a model: model['object']"
    assert model["id"], f"model has wrong id: {model['id']}"
    assert "created" in model, "model is missing `created`"
    assert "owned_by" in model, "model is missing `owned_by`"


def check_embeddings(session, base, models):
    response = session.post(
        base + "/openai/v1/embeddings",
        json={
            "input": "The food was delicious and the waiter...",
            "model": EMBEDDING_MODEL,
            "encoding_format": "float",
        },
    )
    response.raise_for_status()

    result = response.json()

    assert result["object"] == "list", "response is not a list"
    assert len(result["data"]) >= 1, "response is an empty list"
    assert result["data"][0]["object"] == "embedding"
    assert len(result["data"][0]["embedding"]) > 64, (
        "embedding shorter than 64 dimensions"
    )
    assert isinstance(result["data"][0]["embedding"][0], float), (
        "embedding element is not a float"
    )


def check_chat_completions(session, base, models):
    response = session.post(
        base + "/openai/v1/chat/completions",
        json={
            "model": COMPLETION_MODEL,
            "messages": [{"role": "user", "content": "Hello"}],
            "stream": False,
            # it's a thinking model, it requires a good amount of tokens to ensure a response.
            "max_tokens": 1000,
        },
    )
    response.raise_for_status()

    result = response.json()
    assert result["object"] == "chat.completion", "not a completion object"
    assert "content" in result["choices"][0]["message"], "no content"
    assert (
        "reasoning_content" in result["choices"][0]["message"]
        or "reasoning" in result["choices"][0]["message"]
    ), "no reasoning content"
    assert "role" in result["choices"][0]["message"], "no role"


def check_completions(session, base, models):
    response = session.post(
        base + "/openai/v1/completions",
        json={
            "model": COMPLETION_MODEL,
            "prompt": "say hello",
            "stream": False,
            # it's a thinking model, it requires a good amount of tokens to ensure a response.
            "max_tokens": 1000,
        },
    )
    response.raise_for_status()

    result = response.json()

    assert result["object"] == "text_completion", (
        f"not a completion object: {result}"
    )
    assert "text" in result["choices"][0], (
        f"missing text in completion: {result}"
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("url")
    parser.add_argument("keyfile")
    args = parser.parse_args()

    key = open(args.keyfile).read().strip()
    url = args.url

    session = requests.Session()
    session.headers.update({"Authorization": f"Bearer {key}"})

    models = {}

    oks = set()
    errors = {}
    warnings = {}

    for check in [
        check_model_list,
        check_model_details,
        check_chat_completions,
        check_completions,
        check_embeddings,
    ]:
        try:
            check(session, url, models)
        except Exception as e:
            errors.update({check.__name__: str(e)})
        else:
            oks.add(check.__name__)

    if errors:
        print("CHECKS CRITICAL - {}".format(", ".join(errors.keys())))
    elif warnings:
        print("CHECKS WARNING - {}".format(", ".join(warnings.keys())))
    else:
        print("CHECKS OK - {}".format(", ".join(oks)))

    for check, error in errors.items():
        print(f"CRITICAL {check}: {error}")
    for check, warning in warnings.items():
        print(f"WARN {check}: {warning}")
    for check in oks:
        print(f"OK {check}")

    if errors:
        sys.exit(2)
    elif warnings:
        sys.exit(1)
    else:
        sys.exit(0)


if __name__ == "__main__":
    main()
