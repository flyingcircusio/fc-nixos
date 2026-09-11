# Common nixpkgs config used by platform code (nixos/platform/default.nix)
# and our customized nixpkgs from ./default.nix.
{

  # We need to keep nixpkgs.config kinda centralized and homogenous to avoid
  # combinatorial issues with the important-packages list.
  # See PL-135603.
  cudaSupport = true;
  cudaCapabilities = [
    "12.0" # Blackwell / RTX PRO 6000 (Workstation)
  ];
  cudaForwardCompat = true;
  rocmSupport = false;

  allowedUnfreePackageNames = [
    # TODO: megacli is only used on physical machines but pulled in by
    # fc-sensuplugins and thus needed on all machines. Should be moved to
    # the raid service after decoupling fc-sensuplugins.
    "megacli"
    "consul"

    # lib.licenses.nvidiaCudaRedist — CUDA Toolkit End User License Agreement
    "cuda-merged"
    "cuda_cuobjdump"
    "cuda_gdb"
    "cuda_nvcc"
    "cuda_nvdisasm"
    "cuda_nvprune"
    "cuda_cccl"
    "cuda_cudart"
    "cuda_cupti"
    "cuda_cuxxfilt"
    "cuda_nvml_dev"
    "cuda_nvrtc"
    "cuda_nvtx"
    "cuda_profiler_api"
    "cuda_sanitizer_api"
    "libcublas"
    "libcufft"
    "libcurand"
    "libcusolver"
    "libnvjitlink"
    "libcusparse"
    "libnpp"
    "libcufile"
    # lib.licenses.cudnnCuSPARSELt — cuSPARSELt EULA (different from CUDA EULA)
    "libcusparse_lt"
    # lib.licenses.cudnn — cuDNN SUPPLEMENT TO SOFTWARE LICENSE AGREEMENT
    # (different from CUDA EULA; redistributable = false — internal use only)
    "cudnn"
    # lib.licenses.unfreeRedistributable — NVIDIA Software License
    "nvidia-settings"
    "nvidia-x11"

  ];

  permittedInsecurePackages = [
    "openssl-1.1.1w" # EOL 2023-09-11, needed for Percona and older PHP versions.
    "python-2.7.18.12" # Needed for some legacy customer applications.
    "ruby-2.7.8" # EOL 2023-03-31, needed for Sensu checks
    "jitsi-meet-1.0.8792" # insecure libolm but this only affects optional e2ee which we don't really support.
    "nodejs-slim-20.20.2" # EOL, required by github-runner
    "nodejs-20.20.2" # EOL, required by github-runner
    "python3.13-vllm-0.16.0" # too fast moving for regular nixos release cycle?
  ];
}
