import ./make-test.nix ({ lib, ... }:
{
  name = "nginx";
  machine =
    { ... }:
    {
      imports = [ ../nixos ];
      flyingcircus.services.nginx.enable = true;
    };
  testScript = { nodes, ... }: 
  let 
    sensuChecks = nodes.machine.config.flyingcircus.services.sensu-client.checks;
    nginxConfigCheck = sensuChecks.nginx_config.command;
    nginxWorkerAgeCheck = sensuChecks.nginx_worker_age.command;
    nginxStatusCheck = sensuChecks.nginx_status.command;

  in ''
    $machine->waitForUnit('nginx.service');

    subtest "nginx works", sub {
      $machine->succeed("curl -v http://localhost/nginx_status | grep 'server accepts handled requests'");
    };

    subtest "service user should be able to write to local config dir", sub {
      $machine->succeed('sudo -u nginx touch /etc/local/nginx/vhosts.json');
    };

    subtest "all sensu checks should be green", sub {
      $machine->succeed('${nginxConfigCheck}');
      $machine->succeed('${nginxWorkerAgeCheck}');
      $machine->succeed('${nginxStatusCheck}');
    };

    subtest "status check should be red after shutting down nginx", sub {
      $machine->succeed('systemctl stop nginx.service');
      $machine->mustFail('${nginxStatusCheck}');
    };
  '';
})
