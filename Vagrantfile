Vagrant.configure("2") do |config|
  config.vm.box = "perk/ubuntu-2204-arm64"  
  config.vm.provider "qemu" do |qe|
    qe.qemu_dir = "/usr/local/share/qemu"
    qe.machine = "virt,accel=kvm,highmen=on -enable-kvm"
  end
  config.vm.synced_folder ".", "/vagrant", disabled: true
end