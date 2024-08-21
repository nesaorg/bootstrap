# Nesa Bootstrap

Welcome to the official repository for the Nesa Bootstrap script! This repository contains the necessary tools and scripts to set up and configure your Nesa node efficiently!

## Overview

This repository contains wizardry aimed at making the deployment and configuration of a Nesa node easier. It handles everything from checking system prerequisites to configuring Docker containers, setting up node types, connecting to the Nesa network, and ultimately providing a streamlined way to get your Nesa node up and running with minimal manual intervention.


## Features

- **Cross-Platform Support**: Supports Linux, macOS, and Windows (via WSL).
- **Automated Setup**: Automatically installs required dependencies like Docker, Gum, and jq.
- **Node Configuration**: Allows configuration of nodes as Validators or Miners, with support for both distributed and non-distributed miners.
- **Swarm Support**: Supports joining existing swarms or creating new ones for distributed mining tasks.
- **Model Selection**: Easily select or specify a model to run on your miner node.

## Prerequisites

Before running the bootstrap script, ensure your system meets the following requirements:

### Hardware Requirements

- **CPU**: Multi-core processor
- **Memory**: Minimum 4 GB RAM
- **Storage**: 50 GB free disk space (or more depending on the model size)
- **Network**: Stable internet connection
- **GPU**: CUDA-enabled GPUs recommended. MPS is also supported. CPU mining is available, but not for all models.

### Software Requirements

- **Operating System**: Ubuntu, Debian, CentOS, macOS, Windows (with WSL). Other Linux distributions may work but are not officially supported.
- **Docker**: Required for running Nesa nodes ([installation guide](https://docs.docker.com/get-docker/))
- **Nvidia Container Toolkit**: For systems with an NVIDIA GPU ([installation guide](https://github.com/nesaorg/bootstrap/blob/master/install_nvidia_container_toolkit.sh))
- **Curl**: To download and run the bootstrap script ([installation guide](https://curl.se/docs/install.html))

## Quickstart

To get started quickly, use the following command to download and execute the bootstrap script:

```bash
bash <(curl -s https://raw.githubusercontent.com/nesaorg/bootstrap/master/bootstrap.sh)
```

### Configuration Steps

1. **Choose a Moniker**: Provide a unique name for your node.
2. **Select Node Type**: Decide whether your node will act as a Validator or Miner.
3. **Provide Wallet Private Key**: Enter your wallet private key for validator staking, miner registration and to receive rewards.
4. **Setup Swarm (if applicable)**: For Distributed Miners, choose to join an existing swarm or start a new one.
5. **Model Selection**: Select the model you want your miner node to run.
6. **Finalize Configuration**: Review and confirm the configuration before starting your node.

## Node Types

### Validator

### Miner



## Advanced Setup

For users who need more control over the setup process, the script offers an "Advanced Wizardy" mode that allows you to fine-tune your node's configuration manually via the config files in `~/.nesa/env` manually. It is recommended to run the script once in Wizardry to generate the base config. Then you can feel free to modify the config files to your liking, if needed. Running the script again in "Advaced Wizardry" mode will load the existing config from previous runs or manaul edits, allowing you to skip the initial setup steps.

## Troubleshooting

- **Docker Issues**: Ensure Docker is properly installed and running.
- **Permission Errors**: Run the script with `sudo` if you encounter permission issues.
- **Gum/JQ Installation**: If the script fails to install these dependencies, install them manually following the instructions provided in the [Gum](https://github.com/charmbracelet/gum) and [jq](https://stedolan.github.io/jq/download/) documentation.

## Community and Support

If you need additional help or want to engage with the community, join the [Nesa Discord](https://discord.gg/nesa) for support and discussions. You can also explore more detailed documentation on the [Nesa GitBook](https://open.gitbook.com/~space/Vtjgh8wLtiRmdt9OTX2C/~gitbook/pdf).

## License