#! @shell@
# Generate a complete OpenVPN key setup using EasyRSA. This script is idempotent
# and should from an activation script: ${generatePki}/generate-pki
set -e
umask 022

DIR="@caDir@"
RG="@resource_group@"
LOCATION="@location@"
EASYRSA="@easyrsa@"
OPENVPN="@openvpn@"

export PATH="@gawk@/bin:$PATH"

ersa="$EASYRSA/bin/easyrsa --batch --days=999999"
stamp="${DIR}/.stamp-generate-pki"

if [[ -e "$stamp" ]]; then
    # idempotent invocation
    exit
fi

rm -rf "$DIR"
mkdir "$DIR"
cd "$DIR"
$EASYRSA/bin/easyrsa-init

$ersa init-pki
$ersa --req-cn="OpenVPN CA/FCIO/$RG/$LOCATION" build-ca nopass

gen_pair() {
    local cn="$1"
    local role="$2"
    crt="pki/issued/${cn}.crt"
    key="pki/private/${cn}.key"
    $ersa build-${role}-full "$cn" nopass
    ln -fs "$crt" ${role}.crt
    ln -fs "$key" ${role}.key
}

gen_pair "vpn-${LOCATION}.${RG}.fcio.net" server
gen_pair "client-${LOCATION}.${RG}.fcio.net" client

$ersa gen-dh

$OPENVPN/bin/openvpn --genkey --secret ta.key

touch "$stamp"
