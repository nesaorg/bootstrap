# Frequently Asked Questions

## Table of Contents

**Getting Started**
- [Do I need to be whitelisted to run a miner node?](#do-i-need-to-be-whitelisted-to-run-a-miner-node)
- [Why do I need to provide a private key?](#why-do-i-need-to-provide-a-private-key)
- [Can I use my Ethereum wallet?](#can-i-use-my-ethereum-wallet)
- [How do I find my node ID?](#how-do-i-find-my-node-id)

**Setup & Requirements**
- [Do I need to install Docker first?](#do-i-need-to-install-docker-first)
- [Do I need to install CUDA?](#do-i-need-to-install-cuda)
- [Can I run without a GPU?](#can-i-run-without-a-gpu)
- [Does it work on Windows?](#does-it-work-on-windows)
- [Does it work on Apple Silicon?](#does-it-work-on-apple-silicon)

**Wallet & Deposits**
- [Where is my private key stored?](#where-is-my-private-key-stored)
- [What if I lose my private key?](#what-if-i-lose-my-private-key)
- [What's the minimum deposit?](#whats-the-minimum-deposit)
- [How do I get NES tokens?](#how-do-i-get-nes-tokens)

**Operations**
- [How do I check my node status?](#how-do-i-check-my-node-status)
- [How do I view logs?](#how-do-i-view-logs)
- [Why can't I start my node?](#why-cant-i-start-my-node)
- [How do I back up my node?](#how-do-i-back-up-my-node)
- [How do I update my node?](#how-do-i-update-my-node)
- [How do I completely remove my node?](#how-do-i-completely-remove-my-node)

**Other**
- [Why don't I see options to choose between distributed and non-distributed mining?](#why-dont-i-see-options-to-choose-between-distributed-and-non-distributed-mining)
- [Why don't I see the option to specify a model anymore?](#why-dont-i-see-the-option-to-specify-a-model-anymore)
- [I installed the validator, but I want to run a miner instead. What should I do?](#i-installed-the-validator-but-i-want-to-run-a-miner-instead-what-should-i-do)
- [What is the difference between a miner and a validator?](#what-is-the-difference-between-a-miner-and-a-validator)
- [How do I obtain a Hugging Face API key?](#how-do-i-obtain-a-hugging-face-api-key)
- [How does the referral system work?](#how-does-the-referral-system-work)
- [What does my node actually do?](#what-does-my-node-actually-do)

---

## Getting Started

### Do I need to be whitelisted to run a miner node?

No, you do not need to be whitelisted to run a miner node. Anyone can participate as a miner on the Nesa network.

### Why do I need to provide a private key?

The private key serves several important functions:

1. **Node Authentication**: It's used to securely identify and authenticate your node on the network.
2. **Transaction Signing**: It signs transactions for registering your node and managing deposits.
3. **Reward Distribution**: It associates your node with your wallet, ensuring that you receive rewards for your contributions.

You can either import an existing private key or generate a new one during setup. If you generate a new one, make sure to save it immediately as it will only be shown once.

### Can I use my Ethereum wallet?

Yes. Nesa uses secp256k1, the same elliptic curve as Ethereum. Your ETH private key will work. Just enter it during wallet setup and the script derives your `nesa1...` address from it.

### How do I find my node ID?

Re-run the bootstrap script and check the header, which displays your node ID and dashboard link. You can also find it in `~/.nesa/identity/node_id.id` or visit [node.nesa.ai](https://node.nesa.ai) and search for your node.

---

## Setup & Requirements

### Do I need to install Docker first?

No. The script detects if Docker is missing and installs it automatically on Linux. On macOS and Windows, it will prompt you to install Docker Desktop manually since those require GUI installers.

If Docker is installed but not running, you'll see instructions to start it:
```bash
sudo systemctl start docker
```

### Do I need to install CUDA?

No. The node container ships with CUDA built-in. You just need:
1. NVIDIA drivers on your host (so `nvidia-smi` works)
2. NVIDIA Container Toolkit installed

The script detects your GPU and shows installation instructions if the toolkit is missing. If you don't have a GPU, the script automatically runs in CPU-only mode.

### Can I run without a GPU?

Yes, you can run a miner node without a GPU. The node will primarily rely on your CPU and RAM for processing. Currently we support CUDA and CPU backends, so you have flexibility depending on your hardware setup. Performance will be lower without a GPU, but your node will work and earn rewards.

### Does it work on Windows?

Yes, via WSL2. Install WSL2 with Ubuntu, then run the bootstrap script inside WSL. If you have an NVIDIA GPU, ensure Docker Desktop is configured to use the WSL2 backend with GPU passthrough enabled.

### Does it work on Apple Silicon?

Yes. Your node runs via Rosetta 2 emulation on M1/M2/M3/M4 Macs. You'll see a note during setup confirming this is expected. GPU acceleration isn't available on Mac, so it runs in CPU-only mode.

---

## Wallet & Deposits

### Where is my private key stored?

In `~/.nesa/env/orchestrator.env` as `NODE_PRIV_KEY`. This file has standard Unix permissions (readable by your user only). If you delete this file without backing up the key, it cannot be recovered.

### What if I lose my private key?

There is no recovery mechanism. When generating a new wallet, the script displays your private key once with a clear warning to save it. The key is stored locally, but if you lose both the file and your backup, the wallet is gone.

### What's the minimum deposit?

The minimum is set by the network and may change. During setup, the script queries the current minimum and shows it to you. You can also check via **Manage Wallet & Deposits** in the main menu.

Deposits are held in escrow with a 7-day unbonding period if you want to withdraw.

### How do I get NES tokens?

For testnet, use the faucet at [beta.nesa.ai/faucet](https://beta.nesa.ai/faucet). Connect your wallet or enter your `nesa1...` address to receive test tokens.

---

## Operations

### How do I check my node status?

Re-run the bootstrap script and select **Node Status & Logs** from the main menu. You'll see:
- Container status (running, stopped, paused)
- Health check results
- Uptime for each container

You can also view your node on the dashboard at [node.nesa.ai](https://node.nesa.ai).

### How do I view logs?

From the main menu, select **Node Status & Logs**, then choose:
- **View Live Logs**: Streams logs in real time (Ctrl+C to stop)
- **View Last 100 Lines**: Shows recent log output
- **View Watchtower Logs**: Shows auto-update activity

You can also use Docker directly:
```bash
docker logs orchestrator
docker logs -f orchestrator  # follow mode
```

### Why can't I start my node?

The script checks blockchain state before allowing start. Common blockers:

| Message | Meaning |
|---------|---------|
| Node not registered | Fund wallet and register via Manage Wallet & Deposits |
| Miner not registered | Complete miner registration in Manage Wallet & Deposits |
| Deposit below minimum | Add more stake via Manage Wallet & Deposits |

### How do I back up my node?

Back up the `~/.nesa` directory. This contains your private key, node ID, and configuration:

```bash
cp -r ~/.nesa ~/nesa-backup
```

For remote machines:
```bash
scp -r user@remote:~/.nesa ./nesa-backup
```

### How do I update my node?

Updates happen automatically via Watchtower, which checks for new container images every 5 minutes. Check update activity with:
```bash
docker logs watchtower
```

The bootstrap script itself doesn't auto-update. To get the latest version, re-download and run it:
```bash
bash <(curl -s https://raw.githubusercontent.com/nesaorg/bootstrap/master/bootstrap.sh)
```

### How do I completely remove my node?

From the main menu, select **Delete Node**. This removes:
- All Docker containers
- Configuration files (`~/.nesa/env/`)
- Logs (`~/.nesa/logs/`)
- Cache (`~/.nesa/cache/`)
- Identity files (`~/.nesa/identity/`)

You'll be asked to type DELETE and confirm. This is irreversible.

---

## Other

### Why don't I see options to choose between distributed and non-distributed mining?

To simplify the setup process, we've streamlined the node configuration. The network now handles the distribution of tasks internally based on your hardware capabilities, optimizing for efficiency without requiring user input on these technical details.

Here's a brief explanation of what happens under the hood:
- **Distributed Mining**: The network may split models into blocks and run inference across a sequence of miners collaboratively.
- **Non-Distributed Mining**: Your node runs the entire model on a single machine.

The network automatically decides which mode to use based on your hardware specs.

### Why don't I see the option to specify a model anymore?

We've simplified the setup process to focus on network health and optimization. Instead of individual miners choosing specific models, the network now automatically balances and distributes tasks based on overall network needs and individual node capabilities. This approach allows us to:
- Optimize network performance by efficiently allocating resources
- Ensure a balanced distribution of tasks across all miners
- Simplify the setup process, reducing potential configuration errors
- Adapt quickly to changing network demands and model requirements

Your node will be utilized effectively, contributing to the overall health and performance of the Nesa network.

### I installed the validator, but I want to run a miner instead. What should I do?

Validators are not currently open for public deployment. Re-run the bootstrap script and it will set you up as a miner. If you have old validator containers running, use **Delete Node** from the menu to clean up, then run the bootstrap again.

### What is the difference between a miner and a validator?

- **Miners**: On the Nesa network, miners perform inference tasks using their computing power. They process data and run models, contributing directly to the network's AI operations. Miners earn rewards based on their contributions to these tasks.

- **Validators**: Validators help secure the network by participating in consensus, committing new blocks to the blockchain, and voting on proposals. They ensure that the network operates correctly and securely. Validators are crucial for maintaining the integrity of the blockchain.

**Note**: Validators are not currently open for public deployment. Focus on running a miner.

### How do I obtain a Hugging Face API key?

1. Visit [huggingface.co](https://huggingface.co) and sign up or log in
2. Navigate to [Settings → Access Tokens](https://huggingface.co/settings/tokens)
3. Click **New token** and copy the generated key

The API key is optional and only needed for gated models.

### How does the referral system work?

During setup, you can enter a referral code (a `nesa1...` wallet address). This links your node to the referrer for rewards tracking. While optional, providing a valid referral code will offer benefits to both you and the referrer. Details on referral rewards will be announced by the Nesa team.

### What does my node actually do?

Your node runs AI inference tasks assigned by the Nesa network. When a user sends a query:
1. The network routes it to available miners based on hardware capabilities
2. Your node processes the inference request
3. Results are returned and cryptographically verified
4. You earn NES rewards for successful completions

The network handles all task distribution. You don't choose models or configure anything beyond the initial setup.
