{ lib, pkgs, config, ...}:

{

	options = {
		flyingcircus.kernelOptions = lib.mkOption {
		  default = null;
		  type = lib.types.nullOr lib.types.str;
		  description = "Additional options for the kernel configuration";
		};
	};

	# This is a lift-and-shift from Gentoo and can be modularized and
	# structured when needed.

	config = {

      boot.kernelPackages = pkgs.linuxKernel.packages.linux_5_15;

      # Use this spelling if you need to try out custom kernels, try out patches
      # or otherwise deviate from our nixpkgs upstream.
      #
			# boot.kernelPackages = let kernelPackage = pkgs.linux_5_15; in
			# 	lib.mkForce (pkgs.linuxPackagesFor (kernelPackage.override {
			# 	  argsOverride = {
			# 	    src = pkgs.fetchurl {
			# 	      url = "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.15.166.tar.xz";
			# 	      hash = "sha256-LFbawrcIWcFrTvZRvvsNKMInSYvT7uCOikWjV/Itddc=";
			# 	    };
			# 	    version = "5.5";
			# 	    modDirVersion = "5.15.166";
			# 	    kernelPatches = kernelPackage.kernelPatches ++ [
			# 	      {
			# 	        name = "some-patch-name";
			# 	        patch = (pkgs.fetchpatch {
			# 	          url = "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/patch/?id=d5618eaea8868e2534c375b8a512693658068cf8";
			# 	          hash = "sha256-w5ntJNyOdpLbojJWCGxGYs7ikbrd2W4zby3xv3VJqjY=";
			# 	        });
			# 	      }
			# 	    ];
			# 	  };
			# 	}));

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
			RANDOM_TRUST_CPU y
			WARN_ALL_UNSEEDED_RANDOM y
			'';

		boot.kernelPatches = lib.mkIf ( config.flyingcircus.kernelOptions != null ) [ {
			name = "fcio-kernel-options";
			patch = null;
			extraConfig = config.flyingcircus.kernelOptions;
		}];
	};
}
