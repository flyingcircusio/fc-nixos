# -*- mode: ruby -*-
# vi: set ft=ruby :

required_plugins = %w( vagrant-nixos-plugin )
required_plugins.each do |plugin|
      abort("Plugin required: vagrant plugin install #{plugin}") unless Vagrant.has_plugin? plugin
end

Vagrant.configure("2") do |config|
  config.vm.box = "flyingcircus/nixos-20.09-dev-x86_64"
  # config.vm.box_version = "946.84f87f3"
  config.vm.provider "virtualbox" do |v|
      v.memory = 2000
      v.cpus = 2
  end

  config.vm.provision :nixos,
    verbose: true,
    run: 'always',
    path: "vagrant-provision.nix"

  config.vm.provision :shell,
    run: "always",
    # The nixos provisioner somehow kills the automatic shared folder mount.
    inline: "mountpoint -q /vagrant || mount -t vboxsf -o uid=1000,gid=100 vagrant /vagrant"

  config.vm.hostname = "fc-nixos"
  config.vm.network "private_network", mac: "020000021146", ip: "192.168.21.146" # ethfe
  config.vm.network "private_network", mac: "020000031146", ip: "192.168.31.146" # ethsrv
end
