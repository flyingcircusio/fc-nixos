# app goal: create snapshots of embeddings to allow us to preserve numerical stability of the flying circus AI model API over time
import argparse
import asyncio

import httpx
import numpy as np
import toml
from pydantic import BaseModel
from sklearn.metrics.pairwise import cosine_similarity


class Config(BaseModel):
    skvaider_token: str
    skvaider_url: str


class APIClient:
    token: str
    url: str
    timeout: httpx.Timeout
    headers: dict
    client: httpx.AsyncClient

    def __init__(self, config: Config):
        self.token = config.skvaider_token
        self.url = config.skvaider_url
        self.timeout = httpx.Timeout(60.0, read=60.0)
        self.headers = {"Authorization": f"Bearer {self.token}"}
        self.client = httpx.AsyncClient(
            timeout=self.timeout, headers=self.headers
        )

    async def list_models(self):
        response = await self.client.get(f"{self.url}/models")
        response.raise_for_status()
        return response.json()

    # {'object': 'list', 'data': [{'id': 'gpt-oss:20b', 'object': 'model', 'created': 0, 'owned_by': 'skvaider'}, {'id': 'gpt-oss:120b', 'object': 'model', 'created': 0, 'owned_by': 'skvaider'}, {'id': 'mistral-small3.2:latest', 'object': 'model', 'created': 0, 'owned_by': 'skvaider'}, {'id': 'bge-m3:567m', 'object': 'model', 'created': 0, 'owned_by': 'skvaider'}, {'id': 'embeddinggemma:300m', 'object': 'model', 'created': 0, 'owned_by': 'skvaider'}, {'id': 'nomic-embed-text:v1.5', 'object': 'model', 'created': 0, 'owned_by': 'skvaider'}]}
    # 1: gpt-oss:20b
    # 2: gpt-oss:120b
    # 3: mistral-small3.2:latest
    # 4: bge-m3:567m
    # 5: embeddinggemma:300m
    # 6: nomic-embed-text:v1.5

    # 4, 5, 6 are embedding models

    def is_embedding_model_domain_known(self, model_id: str) -> bool:
        model_id = model_id.lower()
        embedding_models = [
            "bge-m3:567m",
            "embeddinggemma:300m",
            "nomic-embed-text:v1.5",
        ]
        return model_id in embedding_models

    async def get_embedding(
        self, model_id: str, input_text: str | list[str]
    ) -> dict:
        if not self.is_embedding_model_domain_known(model_id):
            raise ValueError(
                f"Model {model_id} is not a known embedding model."
            )
        json_data = {"model": model_id, "input": input_text}
        response = await self.client.post(
            f"{self.url}/embeddings", json=json_data
        )
        response.raise_for_status()
        return response.json()


class Dataset:
    data: list[str]

    def __init__(self, dataset_path: str):
        with open(dataset_path, "r") as f:
            self.data = [
                line.strip() for line in f.readlines() if line.strip()
            ]  # remove empty lines


async def embeddings_command(
    config: Config, dataset_path: str, output_path: str
):
    # Load dataset
    dataset = Dataset(dataset_path)

    client = APIClient(config)
    models = await client.list_models()
    print("Available models:", models)

    # For all models, for all data points, get embeddings
    final_embeddings: dict[
        str, dict[str, list[float]]
    ] = {}  # model_id -> {input_text: embedding}
    for model in models["data"]:
        model_id = model["id"]
        if not client.is_embedding_model_domain_known(model_id):
            continue
        print(f"Processing model: {model_id}")
        final_embeddings[model_id] = {}
        # send as batch
        embeddings_response = await client.get_embedding(model_id, dataset.data)
        for item in embeddings_response["data"]:
            input_text = dataset.data[item["index"]]
            embedding_vector = item["embedding"]
            final_embeddings[model_id][input_text] = embedding_vector
            print(
                f"  Obtained embedding for input index {item['index']}: {input_text[:30]}... (len={len(embedding_vector)})"
            )
        print(
            f"Completed model: {model_id}, obtained {len(final_embeddings[model_id])} embeddings."
        )

    # Save final embeddings to output file
    import json

    with open(output_path, "w") as f:
        json.dump(final_embeddings, f, separators=(",", ":"))
    print(f"Saved embeddings to {output_path}")


async def compare_command(
    config: Config,
    embeddings_path1: str,
    embeddings_path2: str,
    output_path: str,
):
    import json

    from scipy.spatial.distance import cosine

    # Load embeddings files
    with open(embeddings_path1, "r") as f:
        embeddings1 = json.load(f)
    with open(embeddings_path2, "r") as f:
        embeddings2 = json.load(f)

    # Compare embeddings for each model present in both files
    common_models = set(embeddings1.keys()).intersection(
        set(embeddings2.keys())
    )
    comparison_results = []

    # calc magnitude of difference for each input
    for model_id in common_models:
        model_embeddings1 = embeddings1[model_id]
        model_embeddings2 = embeddings2[model_id]
        common_inputs = set(model_embeddings1.keys()).intersection(
            set(model_embeddings2.keys())
        )
        differences = []
        for input_text in common_inputs:
            vec1 = np.array(model_embeddings1[input_text]).reshape(1, -1)
            vec2 = np.array(model_embeddings2[input_text]).reshape(1, -1)
            cos_sim = cosine_similarity(vec1, vec2)[0][0]
            differences.append((input_text, cos_sim))
        avg_similarity = (
            sum(sim for _, sim in differences) / len(differences)
            if differences
            else 0.0
        )
        comparison_results.append((model_id, avg_similarity, differences))

    # Save comparison results to markdown file
    with open(output_path, "w") as f:
        f.write("# Embeddings Comparison Report\n\n")
        for model_id, avg_similarity, differences in comparison_results:
            f.write(f"## Model: {model_id}\n")
            f.write(f"- Average Cosine Similarity: {avg_similarity:.6f}\n")
            f.write("### Individual Input Similarities:\n")
            f.write("| Input Text (truncated) | Cosine Similarity |\n")
            f.write("|-----------------------|-------------------|\n")
            for input_text, cos_sim in differences:
                f.write(f"| {input_text[:30]}... | {cos_sim:.6f} |\n")
            f.write("\n")

    print(f"Saved comparison report to {output_path}")


async def main():
    # load arguments
    parser = argparse.ArgumentParser(description="Skvaider API Client")
    parser.add_argument(
        "--config", type=str, default="config.toml", help="Path to config.toml"
    )

    # add subcommand
    subparser = parser.add_subparsers(dest="command")

    # embeddings subcommand
    e_parser = subparser.add_parser(
        "embeddings", help="Get embeddings for dataset"
    )
    e_parser.add_argument(
        "--dataset",
        type=str,
        default="dataset.txt",
        help="Path to dataset file",
    )
    e_parser.add_argument(
        "--output",
        type=str,
        default="embeddings_output.json",
        help="Path to output embeddings JSON file",
    )

    # compare subcommand
    c_parser = subparser.add_parser(
        "compare", help="Compare embeddings between models"
    )
    c_parser.add_argument(
        "--embeddings1",
        type=str,
        required=True,
        help="Path to first embeddings JSON file",
    )
    c_parser.add_argument(
        "--embeddings2",
        type=str,
        required=True,
        help="Path to second embeddings JSON file",
    )
    c_parser.add_argument(
        "--output",
        type=str,
        default="embeddings_comparison.md",
        help="Path to output comparison markdown file",
    )

    args = parser.parse_args()
    # load config.toml
    with open(args.config, "r") as f:
        config_data = toml.load(f)
    config = Config(**config_data)

    # if command is embeddings
    if args.command == "embeddings":
        await embeddings_command(config, args.dataset, args.output)
    elif args.command == "compare":
        await compare_command(
            config, args.embeddings1, args.embeddings2, args.output
        )
    else:
        parser.print_help()


if __name__ == "__main__":
    asyncio.run(main())
