{ lib, config, ...}:

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
		flyingcircus.kernelOptions = 
			''
			ASYNC_TX_DMA y
			CPU_FREQ_STAT y
			BLK_DEV_MD y
			MQ_IOSCHED_DEADLINE m
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

		# Allow all sysrq keys to help debugging.
    boot.kernel.sysctl."kernel.sysrq" = "0x1";

		boot.kernelPatches = lib.mkMerge [ 

			[ (lib.mkIf ( config.flyingcircus.kernelOptions != null ) {
				name = "fcio-kernel-options";
				patch = null;
				extraConfig = config.flyingcircus.kernelOptions;
			}) ]

			[ {
				name = "xfs-cil-fix";
				patch = ./0001-xfs-Fix-CIL-throttle-hang-when-CIL-space-used-going.patch;
			} ]

		];

	};
}
