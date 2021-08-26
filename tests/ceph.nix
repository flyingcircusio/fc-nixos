import ./make-test-python.nix ({ ... }:
{
  name = "ceph";
  nodes = {
    host1 =
      { config, ... }:
      {

        virtualisation.memorySize = 3000;
        virtualisation.vlans = with config.flyingcircus.static.vlanIds; [ srv sto stb ];
        virtualisation.emptyDiskImages = [ 2000 2000 ];

        imports = [ ../nixos ../nixos/roles ];


        environment.etc."nixos/enc.json".text = ''
          {"name": "host1", "parameters": {"secret_salt": "fdmsajkfhr93gf9udahukdhg78923tgiuvbdiafdsa"}}
          '';
        environment.etc."nixos/services.json".text = ''
           [{
            "address": "host1.gocept.net",
            "ips": [
             "192.168.4.5",
            ],
            "location": "test",
            "password": "this-is-not-used",
            "service": "ceph_mon-mon"
           }]
          '';

        flyingcircus.roles.ceph_osd.enable = true;
        flyingcircus.roles.ceph_mon.enable = true;

        flyingcircus.static.ceph.fsids.test.test = "d118a9a4-8be5-4703-84c1-87eada2e6b60";

        flyingcircus.enc.parameters = {
          secrets."ceph/admin_key" = "asdf";
          location = "test";
          resource_group = "test";
          interfaces.srv = {
            mac = "52:54:00:12:03:01";
            bridged = false;
            networks = {
              "192.168.3.0/24" = [ "192.168.1.5" ];
            };
            gateways = {};
          };
          interfaces.sto = {
            mac = "52:54:00:12:04:01";
            bridged = false;
            networks = {
              "192.168.4.0/24" = [ "192.168.4.5" ];
            };
            gateways = {};
          };
          interfaces.stb = {
            mac = "52:54:00:12:08:01";
            bridged = false;
            networks = {
              "192.168.8.0/24" = [ "192.168.8.5" ];
            };
            gateways = {};
          };
        };
      };
  };

  testScript = ''

    def host1_show(cmd):
      print(host1.execute(cmd)[1])

    host1_show('ip l')
    host1_show('ls -lah /etc/ceph/')
    host1_show('cat /etc/ceph/ceph.client.osd.keyring')
    host1_show('cat /etc/ceph/ceph.conf')
    host1_show('cat /etc/ceph/ceph.osd.conf')
    host1_show('cat /etc/ceph/ceph.mon.conf')
    host1_show('lsblk')
    host1_show('sfdisk -J /dev/vdb')

    host1.succeed("fc-ceph osd prepare-journal /dev/vdb")
    host1.succeed("fc-ceph mon create --size 1g")
    host1.succeed("ceph -s")

    # XXX this currently breaks when seeding the initial mon keyring
    # i guess we are still using puppet to generate mon keys?!?!
    # at least the flow is a bit unclear at the moment.

  '';
})
