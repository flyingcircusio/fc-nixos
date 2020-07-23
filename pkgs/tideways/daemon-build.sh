source $stdenv/setup

echo "unpacking $src..."
tar xvfa $src
mkdir -p $out

# see https://github.com/NixOS/patchelf/issues/66
cp tideways-daemon*/tideways-daemon $out/tideways-daemon.wrapped

echo "#!/bin/sh" > $out/tideways-daemon
echo $(< $NIX_CC/nix-support/dynamic-linker) $out/tideways-daemon.wrapped \"\$@\" >> $out/tideways-daemon
    chmod +x $out/tideways-daemon
