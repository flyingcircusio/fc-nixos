{
  lib,
  uv2nix,
  pyproject-nix,
  pyproject-build-systems,
  python312,
  callPackages,
  callPackage,
  fetchFromGitHub,
  ...
}:
let
  src = fetchFromGitHub {
    owner = "flyingcircusio";
    repo = "skvaider";
    rev = "52af2505874793fb1e7295e5e82fdb937171e89a";
    hash = "sha256-pn+ymn9UyF2UQznmDInJe5Xrl44VBvDaFd3zoC2TwlQ=";
  };

  # Load a uv workspace from a workspace root.
  # Uv2nix treats all uv projects as workspace projects.
  workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = src; };

  # Create package overlay from workspace.
  overlay = workspace.mkPyprojectOverlay {
    sourcePreference = "wheel";
  };

  pythonSet =
    (callPackage pyproject-nix.build.packages {
      python = python312;
    }).overrideScope
      (
        lib.composeManyExtensions [
          pyproject-build-systems.default
          overlay
        ]
      );

  util = callPackages pyproject-nix.build.util { };

in
(pythonSet.mkVirtualEnv "skvaider-env" workspace.deps.default).overrideAttrs (old: {
  venvIgnoreCollisions = [
    "*"
  ];
  passthru.src = src;
  passthru.embeddings-reference-json = ./generate-embedding-reference-tool/embeddings-skvaider-llama-cpp.json;
})
