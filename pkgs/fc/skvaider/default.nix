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
    rev = "3d15223a0d485dd32354305821fc126046708485";
    hash = "sha256-DcGrPRmeoHOD8ShovvUz1kXTy6wCxgXoj1AVbZ9gO3Y=";
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
