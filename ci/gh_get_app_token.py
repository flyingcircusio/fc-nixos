from argparse import ArgumentParser
from logging import INFO, basicConfig

from github import Auth, GithubIntegration


def main():
    basicConfig(level=INFO)
    argparser = ArgumentParser("GitHub get App Token")
    argparser.add_argument("--app-id", help="App ID", required=True)
    argparser.add_argument(
        "--private-key-path", help="Path to the private key", required=True
    )
    argparser.add_argument(
        "--installation_id",
        help="GitHub App installation ID. If not given the first one is picked",
        required=False,
    )
    args = argparser.parse_args()

    # This script very easily just return
    with open(args.private_key_path, "r") as pk_file:
        private_key = pk_file.read()
    auth = Auth.AppAuth(args.app_id, private_key)

    gh_int = GithubIntegration(auth=auth)
    installation_id = args.installation_id
    if not installation_id:
        installation_id = gh_int.get_installations()[0].id
    access_token = gh_int.get_access_token(installation_id)
    print(
        "access token:",
        access_token.token,
        "expires at:",
        access_token.expires_at.isoformat(),
    )


if __name__ == "__main__":
    main()
