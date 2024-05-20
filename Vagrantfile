Vagrant.configure("2") do |config|
    config.vm.box = "perk/ubuntu-2204-arm64"
  
    config.vm.provider "qemu" do |qe|
      # qe.arch = "x86_64"
      # qe.machine = "q35"
      # qe.cpu = "max"
      # qe.smp = "cpus=2,sockets=1,cores=2,threads=1"
      # qe.net_device = "virtio-net-pci"
      qe.machine = "virt,accel=tcg,highmem=off"
      # qe.extra_qemu_args = %w(thread=multi,tb-size=512)
      # qe.qemu_dir = "/usr/local/share/qemu"
    end
  end