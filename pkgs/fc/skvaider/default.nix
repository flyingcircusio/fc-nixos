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
    rev = "a07c593ccf96dd236fb3a87611ee7fee3dc99b9f";
    hash = "sha256-tkKy6HY11i43igeS9Kl+sefFk19+X/7eldU/AgfqwtE=";
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
