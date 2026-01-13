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
    rev = "1e2abc6d72003b34824356a8452cfe17fd35bc0c";
    hash = "sha256-0+tT7fnJM54txwyv0m9q6kkx29L2tTuisaugL1xwRyo=";
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
})
