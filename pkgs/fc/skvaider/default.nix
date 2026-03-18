{
  lib,
  uv2nix,
  pyproject-nix,
  pyproject-build-systems,
  python312,
  callPackage,
  fetchFromGitHub,
  ...
}:
let
  # src = /home/ctheune/skvaider;
  src = fetchFromGitHub {
    owner = "flyingcircusio";
    repo = "skvaider";
    rev = "a712edc87cce2bc86ae85b5f489932620d871fc7";
    hash = "sha256-iwT64ONdzdKjsBasdwikvCnV5AZwahfBqgIqusWSNAw=";
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

in
(pythonSet.mkVirtualEnv "skvaider-env" workspace.deps.default).overrideAttrs (old: {
  venvIgnoreCollisions = [
    "*"
  ];
  passthru.src = src;
})
