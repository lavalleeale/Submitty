Vagrant.configure("2") do |config|
    config.vm.box = 'generic/ubuntu2204'
    config.vm.provider 'qemu' do |qe|
      qe.net_device = 'virtio-net-pci'
    end
  end