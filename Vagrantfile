# -*- mode: ruby -*-
# vi: set ft=ruby :
$script = <<SCRIPT
    export CONSUL_IPBIND=$(ifconfig | grep "inet " | grep '172.20' | awk -F'[: ]+' '{ print $4 }')
    export DATACENTER='consul-vagrant'
    export ENCRYPT_KEY='hTdlXbWe0zKlk16UV1nVpQ=='
    export CONSUL_JOIN_HOSTS='"172.20.20.10", "172.20.20.11", "172.20.20.12"'
    chmod +x /vagrant/Install-Consul.sh
    /vagrant/Install-Consul.sh
SCRIPT

# Vagrantfile API/syntax version. Don't touch unless you know what you're doing!
VAGRANTFILE_API_VERSION = "2"

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
    config.vm.box = "puppetlabs/centos-6.6-64-nocm"
    config.vm.provision "shell", inline: $script
    config.vm.provider "virtualbox" do |v|
        v.linked_clone = true
    end

    config.vm.define "n1" do |me|
      me.vm.hostname = "n1"
      me.vm.network "private_network", ip: "172.20.20.10"
      me.vm.network :forwarded_port, guest: 8500, host: 8500, id: "consul-http", auto_correct: true, adapter: 2
      
      $hostScript = "cp /etc/consul.d/bootstrap/consul.json /etc/consul.d/consul.json && sudo service consul start"
      me.vm.provision "shell", inline: $hostScript
    end

    config.vm.define "n2" do |me|
      me.vm.hostname = "n2"
      me.vm.network "private_network", ip: "172.20.20.11"
      
      $hostScript = "cp /etc/consul.d/server/consul.json /etc/consul.d/consul.json && sudo service consul start"
      me.vm.provision "shell", inline: $hostScript
    end

    config.vm.define "n3" do |me|
      me.vm.hostname = "n3"
      me.vm.network "private_network", ip: "172.20.20.12"
      
      $hostScript = "cp /etc/consul.d/server/consul.json /etc/consul.d/consul.json && sudo service consul start"
      me.vm.provision "shell", inline: $hostScript
    end
end