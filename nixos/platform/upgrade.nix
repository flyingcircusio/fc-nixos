# Things to do when upgrading from 19.03.
# Actions must be idempotent.
# Can be removed when all our VMs are on 20.09 or newer.
{ pkgs, ... }:

{
  flyingcircus.activationScripts.upgrade-acme-create-chain-pem = ''
    # Nginx service now expects a chain.pem which we didn't have on 19.03 as a separate file.
    for certdir in /var/lib/acme/*; do
        if [[ -e $certdir/fullchain.pem && ! -e $certdir/chain.pem ]]; then
            echo "NixOS upgrade: creating $certdir/chain.pem"
            # It's important to preserve the permissions and ownership here
            cp -p $certdir/fullchain.pem $certdir/chain.pem
            ${pkgs.gawk}/bin/awk -i inplace 'found==1 {print} /END CERTIFICATE/ {found=1}' $certdir/chain.pem
        fi
    done
  '';
}
