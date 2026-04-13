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
    rev = "e767c77e0618ac38e9fe5b73abaa557fb590715a";
    hash = "sha256-oG/SEOqL0RwvSGlj7pYii1ZBoRUMFZ2O6S67XyEmMNA=";
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
  passthru.testEnv =
    (pythonSet.mkVirtualEnv "skvaider-test-env" workspace.deps.all).overrideAttrs
      (_: {
        venvIgnoreCollisions = [ "*" ];
      });
})
