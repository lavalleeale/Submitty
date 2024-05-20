Vagrant.configure("2") do |config|
    config.vm.box = 'generic/ubuntu2204'
    config.vm.provider 'qemu' do |qe|
    qe.arch = 'x86_64'
    qe.machine = 'q35'
    qe.cpu = 'max'
  end
end