{ lib, pkgs, config, ...}:

let
  location = lib.attrByPath [ "parameters" "location" ] "" config.flyingcircus.enc;
  production = lib.attrByPath [ "parameters" "production" ] "" config.flyingcircus.enc;
in {
  options = {
    flyingcircus.kernelOptions = lib.mkOption {
      default = null;
      type = lib.types.nullOr lib.types.str;
      description = "Additional options for the kernel configuration";
    };
    flyingcircus.useVerificationKernel = lib.mkOption {
      default = (location == "dev") || (location == "whq") || (production  == false);
      type = lib.types.bool;
      description = ''
        Participate in using an evaluation kernel.
        This currently selects a 6.11 kernel for testing purposes.
        By default, all non-prod VMs in all locations and all VMs in our internal locations
        DEV and WHQ use the evaluation kernel.
      '';
    };
  };

  # This is a lift-and-shift from Gentoo and can be modularized and
  # structured when needed.

  config = {

      boot.kernelPackages = if config.flyingcircus.useVerificationKernel
        then pkgs.linuxPackagesFor pkgs.linuxKernelVerify
        else pkgs.linuxPackagesFor pkgs.linuxKernelStable;

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
      ## Crash-debugging related options
      IPMI_PANIC_EVENT y
      IPMI_PANIC_STRING y
      SOFTLOCKUP_DETECTOR y
      HARDLOCKUP_DETECTOR y
      BOOTPARAM_HARDLOCKUP_PANIC y
      BOOTPARAM_SOFTLOCKUP_PANIC y
      IPMI_WATCHDOG m
      ## we really only want the IPMI watchdog which doesn't use the regular
      ## kernel watchdog device (yet)
      WATCHDOG y
      I6300ESB_WDT y
      ## the i6300 is the qemu emulated one.
      ## The others we don't want to see.
      SOFT_WATCHDOG n
      DA9063_WATCHDOG n
      DA9062_WATCHDOG n
      MENF21BMC_WATCHDOG n
      MENZ069_WATCHDOG n
      WDAT_WDT n
      XILINX_WATCHDOG n
      ZIIRAVE_WATCHDOG n
      RAVE_SP_WATCHDOG n
      CADENCE_WATCHDOG n
      DW_WATCHDOG n
      MAX63XX_WATCHDOG n
      RETU_WATCHDOG n
      ACQUIRE_WDT n
      ADVANTECH_WDT n
      ALIM1535_WDT n
      ALIM7101_WDT n
      EBC_C384_WDT n
      F71808E_WDT n
      SP5100_TCO n
      SBC_FITPC2_WATCHDOG n
      EUROTECH_WDT n
      IB700_WDT n
      IBMASR n
      WAFER_WDT n
      IE6XX_WDT n
      ITCO_WDT n
      IT8712F_WDT n
      IT87_WDT n
      HP_WATCHDOG n
      KEMPLD_WDT n
      SC1200_WDT n
      PC87413_WDT n
      NV_TCO n
      60XX_WDT n
      CPU5_WDT n
      SMSC_SCH311X_WDT n
      SMSC37B787_WDT n
      TQMX86_WDT n
      VIA_WDT n
      W83627HF_WDT n
      W83877F_WDT n
      W83977F_WDT n
      MACHZ_WDT n
      SBC_EPX_C3_WATCHDOG n
      INTEL_MEI_WDT n
      NI903X_WDT n
      NIC7018_WDT n
      MEN_A21_WDT n
      XEN_WDT n
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
