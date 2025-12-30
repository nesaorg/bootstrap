# Nesa Bootstrap

![Nesa Bootstrap Process](https://raw.githubusercontent.com/nesaorg/bootstrap/master/images/bootstrap.gif?v=3)

Welcome to the official repository for the Nesa Bootstrap script! This repository contains the necessary tools and scripts to set up and configure your Nesa node efficiently.

## Overview

This repository contains wizardry aimed at making the deployment and configuration of a Nesa node easier. It handles everything from checking system prerequisites to configuring Docker containers, setting up node types, connecting to the Nesa network, and ultimately providing a streamlined way to get your Nesa node up and running with minimal manual intervention.

## Features

### Setup & Installation
- **One Command Install**: Download and run with a single curl command
- **Cross-Platform**: Linux, macOS, Windows (WSL), ARM64 (Apple Silicon via Rosetta 2)
- **Dependency Handling**: Installs Docker, gum, jq, and Python libraries automatically
- **GPU Detection**: Finds NVIDIA GPUs and configures CUDA acceleration; falls back to CPU if no GPU

### Wallet & Deposits
- **Wallet Generation**: Create a new secp256k1 wallet or import an existing private key (Ethereum compatible)
- **Balance Checking**: Query your NES balance directly from the CLI
- **Deposit Management**: View current deposit, check minimum requirements, add stake
- **On-Chain Registration**: Registers your node and miner on the Nesa blockchain with automatic retry

### Node Control
- **Start/Stop/Pause/Resume**: Full lifecycle management from the menu
- **Status Dashboard**: View health, uptime, and overall node status at a glance
- **Live Log Streaming**: Watch what your node is doing in real time
- **Reconfigure**: Re-run the setup wizard to change settings
- **Delete Node**: Clean uninstall that removes all containers, configs, and data

### Operations
- **Auto-Updates**: Your node pulls the latest updates automatically
- **Chain State Checks**: Verifies registration and deposit before allowing node start
- **Session Logging**: Full bootstrap activity logged to ~/.nesa/logs/bootstrap.log

## Prerequisites

Before running the bootstrap script, ensure your system meets the following requirements:

### Hardware Requirements

- **CPU**: Multi-core processor (4+ cores recommended)
- **Memory**: 16 GB RAM minimum, 32 GB recommended
- **Storage**: 100 GB free disk space (models and container images need room)
- **Network**: Stable internet connection
- **GPU**: NVIDIA GPU with 8+ GB VRAM recommended. CPU-only mode is available but slower.

### Software Requirements

- **Operating System**: Ubuntu, Debian, CentOS, macOS, Windows (with WSL). Other Linux distributions may work but are not officially supported.
- **Docker**: Required for running Nesa nodes ([installation guide](https://docs.docker.com/get-docker/))
- **Nvidia Container Toolkit**: For systems with an NVIDIA GPU ([example installation script](https://raw.githubusercontent.com/nesaorg/bootstrap/master/helpers/install_nvidia_container_toolkit.sh))
- **Curl**: To download and run the bootstrap script ([installation guide](https://curl.se/docs/install.html))

### Configuration Preparation

Before starting the bootstrap script, you may want to have the following ready:

- **Private Key** (optional): If you have an existing wallet, have your secp256k1 private key ready (same format as Ethereum). If you don't have one, the script can generate a new wallet for you.
- **NES Tokens**: You'll need NES to stake as a deposit. For testnet, get tokens from the [faucet](https://beta.nesa.ai/faucet).
- **Hugging Face API Key** (optional): Needed for some gated models. Get one at [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens).
- **Referral Code** (optional): A Nesa wallet address (nesa1...) of the person who referred you.

## Quickstart

To get started quickly, use the following command to download and execute the bootstrap script:

```bash
bash <(curl -s https://raw.githubusercontent.com/nesaorg/bootstrap/master/bootstrap.sh)
```

### Configuration Steps

1. **Node Name**: Choose a unique name (moniker) for your node.
2. **Referral Code** (optional): Enter if you were referred by another user.
3. **Hugging Face API Key** (optional): For accessing gated models.
4. **Wallet Setup**: Import an existing private key or generate a new wallet. If generating, you'll be shown your private key once (save it securely).
5. **Fund Wallet**: Your wallet needs NES tokens. The script will show your wallet address and check your balance.
6. **Registration**: The script registers your node and miner on the Nesa blockchain.
7. **Deposit**: Add the required stake (minimum shown during setup). Deposits are held in escrow with a 7-day unbonding period.
8. **Start Node**: Once registered and funded, containers start automatically.

## How Mining Works

Miners on the Nesa network run AI model inference tasks and earn NES rewards for their contributions. The network handles task distribution automatically based on your hardware capabilities. You don't need to choose models or configure distribution settings.

Your node receives inference requests, processes them using the orchestrator container, and returns results to the network. All activity is cryptographically signed with your private key, ensuring proper attribution for rewards.

**Note**: Validators are not currently open for public deployment.

## Node Identification and Security

Each node is assigned a unique node ID upon creation. This ID, along with a nonce and timestamp, is used to sign messages sent from the node to the network. This signing process ensures the authenticity of each node's communications without requiring the storage of private keys on our servers. The private key remains securely on the miner's machine and is used only for local signing operations.

## Managing Your Node

Once configured, re-running the bootstrap script opens the management menu:

- **Node Status & Logs**: View container health, uptime, and stream live logs.
- **Manage Wallet & Deposits**: Check balance, view deposit status, add more stake.
- **Start/Stop/Pause/Resume**: Control your node containers.
- **Reconfigure**: Run the setup wizard again with new settings.
- **Delete Node**: Remove all containers and configuration (irreversible).

## Advanced Setup

Configuration files are stored in `~/.nesa/env/`:

- `base.env`: Node identity (moniker, referral code, public IP)
- `orchestrator.env`: Private key, node ID, Hugging Face API key

You can edit these files directly. The script will detect existing configuration and skip the wizard on subsequent runs.

## Troubleshooting

If you encounter any issues during setup or operation, here are some general troubleshooting steps:

- **Docker Issues**: Ensure Docker is properly installed and running.
- **Permission Errors**: Add your user to the Docker group to avoid permission issues:
  ```bash
  sudo usermod -aG docker $USER
  newgrp docker
  ```
- **NVIDIA Errors**: Double-check that your NVIDIA driver, CUDA, and the NVIDIA Container Toolkit are installed correctly.

For more detailed troubleshooting steps, please refer to our [Troubleshooting Guide](./Troubleshooting.md).

## Frequently Asked Questions (FAQ)

For more detailed information on common questions and setup details, please visit our [FAQ](./FAQ.md) section.

### Quick Links

**Getting Started**
- [Do I need to be whitelisted to run a miner node?](./FAQ.md#do-i-need-to-be-whitelisted-to-run-a-miner-node)
- [Why do I need to provide a private key?](./FAQ.md#why-do-i-need-to-provide-a-private-key)
- [Can I use my Ethereum wallet?](./FAQ.md#can-i-use-my-ethereum-wallet)
- [How do I find my node ID?](./FAQ.md#how-do-i-find-my-node-id)

**Setup & Requirements**
- [Do I need to install Docker first?](./FAQ.md#do-i-need-to-install-docker-first)
- [Do I need to install CUDA?](./FAQ.md#do-i-need-to-install-cuda)
- [Can I run without a GPU?](./FAQ.md#can-i-run-without-a-gpu)
- [Does it work on Windows?](./FAQ.md#does-it-work-on-windows)
- [Does it work on Apple Silicon?](./FAQ.md#does-it-work-on-apple-silicon)

**Wallet & Deposits**
- [Where is my private key stored?](./FAQ.md#where-is-my-private-key-stored)
- [What's the minimum deposit?](./FAQ.md#whats-the-minimum-deposit)
- [How do I get NES tokens?](./FAQ.md#how-do-i-get-nes-tokens)

**Operations**
- [How do I check my node status?](./FAQ.md#how-do-i-check-my-node-status)
- [How do I view logs?](./FAQ.md#how-do-i-view-logs)
- [Why can't I start my node?](./FAQ.md#why-cant-i-start-my-node)
- [How do I back up my node?](./FAQ.md#how-do-i-back-up-my-node)
- [What is the difference between a miner and a validator?](./FAQ.md#what-is-the-difference-between-a-miner-and-a-validator)

## Community and Support

If you need additional help or want to engage with the community, join the [Nesa Discord](https://discord.gg/nesa) for support and discussions. You can also explore more detailed documentation on the [Nesa GitBook](https://open.gitbook.com/~space/Vtjgh8wLtiRmdt9OTX2C/~gitbook/pdf).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE.md) file for details.