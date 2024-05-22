Vagrant.configure("2") do |config|
  config.vm.box = "perk/ubuntu-2204-arm64"  
  qe.qemu_dir = "/usr/local/share/qemu"
  config.vm.synced_folder ".", "/vagrant", disabled: true
end