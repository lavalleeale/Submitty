Vagrant.configure("2") do |config|
  config.vm.box = "perk/ubuntu-2204-arm64"
  config.vm.box_version = "20230712"
  config.vm.provider :libvirt do |libvirt|
    libvirt.machine_virtual_size = '50G'
  end
  
  config.vm.synced_folder ".", "/vagrant", disabled: true
end