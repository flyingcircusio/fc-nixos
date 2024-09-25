{ lib, pkgs, config, ...}:

let
	defaultUseVerificationKernel =
		if
			(config.flyingcircus.enc.parameters.location == "dev") ||
			(config.flyingcircus.enc.parameters.location == "whq") ||
			(config.flyingcircus.enc.parameters.production  == false)
		then true
		else false;
in {
	options = {
		flyingcircus.kernelOptions = lib.mkOption {
		  default = null;
		  type = lib.types.nullOr lib.types.str;
		  description = "Additional options for the kernel configuration";
		};
		flyingcircus.useVerificationKernel = lib.mkOption {
			default = defaultUseVerificationKernel;
			type = lib.types.bool;
			description = "Participate in using an evaluation kernel.";
		};
	};

	# This is a lift-and-shift from Gentoo and can be modularized and
	# structured when needed.

	config = {

      boot.kernelPackages = if config.flyingcircus.useVerificationKernel
      	then pkgs.linuxPackagesFor pkgs.linuxKernelVerify
      	else pkgs.linuxKernel.packages.linux_5_15;

      # Use this spelling if you need to try out custom kernels, try out patches
      # or otherwise deviate from our nixpkgs upstream.
      #
      # boot.kernelPackages = let kernelPackage = pkgs.linux_6_10; in
      #   lib.mkForce (pkgs.linuxPackagesFor (kernelPackage.override {
      #     argsOverride = {
      #       src = pkgs.fetchurl {
      #         url = "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.11.tar.xz";
      #         hash = "sha256-VdLGwCXrwngQx0jWYyXdW8YB6NMvhYHZ53ZzUpvayy4=";
      #       };
      #       version = "6.11";
      #       modDirVersion = "6.11.0";
      #       # kernelPatches = kernelPackage.kernelPatches ++ [
      #       #   {
      #       #     name = "some-patch-name";
      #       #     patch = (pkgs.fetchpatch {
      #       #       url = "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/patch/?id=d5618eaea8868e2534c375b8a512693658068cf8";
      #       #       hash = "sha256-w5ntJNyOdpLbojJWCGxGYs7ikbrd2W4zby3xv3VJqjY=";
      #       #     });
      #       #   }
      #       # ];
      #     };
      #   }));


		flyingcircus.kernelOptions =
			''
			ASYNC_TX_DMA y
			CPU_FREQ_STAT y
			BLK_DEV_MD y
			MQ_IOSCHED_DEADLINE y
			IPMI_PANIC_EVENT y
			IPMI_PANIC_STRING y
			LATENCYTOP y
			NET_IPGRE_BROADCAST y
			SCHEDSTATS y
			SCSI_DH y
			VLAN_8021Q_GVRP y
			XFS_POSIX_ACL y
			XFS_QUOTA y
			WARN_ALL_UNSEEDED_RANDOM y
			'' + (if !config.flyingcircus.useVerificationKernel
				then ''
				RANDOM_TRUST_CPU y
				'' else "");

		boot.kernelPatches = lib.mkIf ( config.flyingcircus.kernelOptions != null ) [ {
			name = "fcio-kernel-options";
			patch = null;
			extraConfig = config.flyingcircus.kernelOptions;
		}];
	};
}
