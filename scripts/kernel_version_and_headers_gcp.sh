#!/bin/bash

for node in "gcp-2"; do
    echo "Downgrade kernel on node $node..."
	ssh $node /bin/bash << EOF 
        sudo apt install -y linux-image-unsigned-5.8.0-1039-gcp
        # TODO (pinoOgni) this works fine but when the machine is rebooted another kernel version is used again
        sudo sed -i 's/GRUB_DEFAULT.*/GRUB_DEFAULT="Advanced options for Ubuntu 20.04.5 LTS (20.04) (on \/dev\/sda1)>Ubuntu, with Linux 5.8.0-1039-gcp (on \/dev\/sda1)"/g' /etc/default/grub.d/50-cloudimg-settings.cfg
        sudo update-grub2
        sudo reboot
EOF
done

sleep 60

for node in "gcp-2"; do
    echo "Installing gtp5g module on node $node..."
	ssh $node /bin/bash << EOF 
        sudo apt install -y linux-headers-5.8.0-1039-gcp
        rm -rf gtp5g # in this way we are sure that we are using a clean code
        git clone -b v0.3.1 https://github.com/free5gc/gtp5g.git
        cd gtp5g && make && sudo make install && cd ..
EOF
done

