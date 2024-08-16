#!/bin/bash
#
#
#    ▄▄▄▄▄▄  
#   ███▀▀▀██▄      nesaorg/bootstrap 
#   ███   ███ ███████ ███████  █████
#   ███   ███ ██      ██      ██   ██
#   ▄▄▄   ███ █████   ███████ ███████ 
#   ███   ███ ██           ██ ██   ██
#   ███   ███ ███████ ███████ ██   ██ 
#   install_nvidia_container_toolkit.sh    
#
#   Helper script to install NVIDIA Container Toolkit.


command_exists() {
    command -v "$1" >/dev/null 2>&1
}


check_nvidia_installed() {
    if ! command_exists nvidia-smi; then
        echo "NVIDIA drivers are not installed. Please install NVIDIA drivers and try again."
        exit 1
    fi

    if ! command_exists nvidia-container-runtime; then
        echo "Installing NVIDIA Container Toolkit..."

        sudo curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
            && sudo curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
            sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
            sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

        sudo apt-get update
        sudo apt-get install -y nvidia-container-toolkit

        sudo nvidia-ctk runtime configure --runtime=docker
        sudo systemctl restart docker
    fi
}





check_nvidia_installed