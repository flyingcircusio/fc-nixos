# Base environment for interactive work. See also ./packages.nix for a list of
# packages/commands available by default.
{ config, lib, ... }:

let
  enc = config.flyingcircus.enc;
  parameters = lib.attrByPath [ "parameters" ] {} enc;
  isProd = (lib.attrByPath [ "location" ] "dev" parameters) != "dev"
    && lib.attrByPath [ "production" ] false parameters;
  opt = lib.optionalString;

in
{
  config = {
    environment.interactiveShellInit = ''
      export TMOUT=43200
    '';

    environment.shellInit = lib.mkAfter (''
      # help building locally compiled programs
      export LIBRARY_PATH=$HOME/.nix-profile/lib
      # header files
      export CPATH=$HOME/.nix-profile/include
      export C_INCLUDE_PATH=$CPATH
      export CPLUS_INCLUDE_PATH=$CPATH
      # pkg-config
      export PKG_CONFIG_PATH=$HOME/.nix-profile/lib/pkgconfig:$HOME/.nix-profile/share/pkgconfig
      # user init from shell snippets, see
      # https://nixos.org/nixpkgs/manual/#sec-declarative-package-management
      if [[ -d $HOME/.nix-profile/etc/profile.d ]]; then
        for f in $HOME/.nix-profile/etc/profile.d/*.sh; do
          if [[ -r $f ]]; then
            source $f
          fi
        done
      fi
      unset f

      if [[ "$USER" != root ]]; then

        # We don't need that hack anymore because our combined channel works
        # as expected by Nix tools now.
        if [[ -e $HOME/.nix-defexpr/nixos ]]; then
          rm $HOME/.nix-defexpr/nixos
        fi

        # Delete empty dir, nix-env will recreate it with the correct channel links
        if [[ ! "$(ls -A $HOME/.nix-defexpr 2> /dev/null)" ]]; then
          rmdir $HOME/.nix-defexpr 2> /dev/null || true
        fi
      fi
    '' +
      (opt
        (enc ? name && parameters ? location && parameters ? environment)
        # FCIO_* only exported if ENC data is present.
        ''
          # Grant easy access to the machine's ENC data for some variables to
          # shell scripts.
          export FCIO_LOCATION="${parameters.location}"
          export FCIO_ENVIRONMENT="${parameters.environment}"
          export FCIO_HOSTNAME="${enc.name}"
        ''
      )
    );

    users.motd = ''
      Welcome to the Flying Circus!

      Status:     https://status.flyingcircus.io/
      Docs:       https://flyingcircus.io/doc/
      Release:    ${config.system.nixos.label}

    '' +
    (opt (enc ? name && parameters ? location && parameters ? environment)
      ''
        Hostname:   ${enc.name}  Environment: ${parameters.environment}  Location: ${parameters.location}
      '') +
    (opt (parameters ? service_description)
      ''
        Services:   ${parameters.service_description}${opt isProd "  [production]"}
      '') +
      (let
         roles = lib.concatStringsSep ", " (enc.roles or []);
      in
        ''
          Roles:      ${roles}

        '');

    programs.bash.promptInit =
      let
        user = "00;32m";
        root = "01;31m";
        prod = "00;36m";
        dir = "01;34m";
      in ''
        ### prompting
        PROMPT_DIRTRIM=2

        case ''${TERM} in
          [aEkx]term*|rxvt*|gnome*|konsole*|screen|linux|cons25|*color)
            use_color=1 ;;
          *)
            use_color=0 ;;
        esac

        # window title
        case ''${TERM} in
          [aEkx]term*|rxvt*|gnome*|konsole*|interix)
            PS1='\n\[\e]0;\u@\h:\w\007\]' ;;
          screen*)
            PS1='\n\[\ek\u@\h:\w\e\\\]' ;;
          *)
            PS1='\n' ;;
        esac

        if ((use_color)); then
          if [[ $UID == 0 ]]; then
            PS1+='\[\e[${root}\]\u@\h '
          else
            PS1+='\[\e[${user}\]\u@\h '
          fi
      '' + (opt isProd ''
          PS1+='\[\e[${prod}\][prod] '
      '') +
      ''
          PS1+='\[\e[${dir}\]\w \$\[\e[0m\] '
        else
          PS1+='\u@\h ${opt isProd "[prod] "}\w \$ '
        fi

        unset use_color
      '';

    programs.zsh.enable = true;

  };
}
