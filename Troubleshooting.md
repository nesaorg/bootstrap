# Troubleshooting

## Docker Issues

### Docker daemon not running

**Error**: `Cannot connect to the Docker daemon. Is the docker daemon running?`

**Solution**:
```bash
# Start Docker
sudo systemctl start docker

# Enable on boot
sudo systemctl enable docker
```

On macOS/Windows, open Docker Desktop and ensure it's running.

### Permission denied

**Error**: `permission denied while trying to connect to the Docker daemon socket`

**Solution**: Add your user to the docker group:
```bash
sudo usermod -aG docker $USER
newgrp docker
```

Then log out and back in, or restart your terminal.

### Docker Compose failed

**Error**: `Error: Docker Compose failed to start`

**Solution**: Check if containers are already running or in a bad state:
```bash
docker ps -a
docker rm -f orchestrator watchtower log-signer
```

Then re-run the bootstrap script.

---

## GPU & NVIDIA Issues

### No GPU detected

**Error**: `could not select device driver "nvidia" with capabilities: [[gpu]]`

**Solution**: Install the NVIDIA Container Toolkit:
```bash
# Ubuntu/Debian
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

Or use the helper script:
```bash
bash <(curl -s https://raw.githubusercontent.com/nesaorg/bootstrap/master/helpers/install_nvidia_container_toolkit.sh)
```

### nvidia-smi not found

Your NVIDIA drivers aren't installed. Install them from [NVIDIA's website](https://www.nvidia.com/download/index.aspx) or via your package manager:
```bash
# Ubuntu
sudo apt install nvidia-driver-535  # or latest version
sudo reboot
```

### Running in CPU-only mode unexpectedly

If you have a GPU but the script says "CPU-only mode":
1. Check that `nvidia-smi` works: `nvidia-smi`
2. Check Docker can see the GPU: `docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi`
3. If step 2 fails, reinstall the NVIDIA Container Toolkit

---

## Python & Dependency Issues

### pip install fails with "externally-managed-environment"

**Error**: `error: externally-managed-environment`

This happens on newer macOS (Homebrew Python) and some Linux distros. The script handles this automatically by creating a virtual environment at `~/.nesa/venv`. If you still see this error:

```bash
# Create venv manually
python3 -m venv ~/.nesa/venv
source ~/.nesa/venv/bin/activate
pip install ecdsa base58 cryptography mospy-wallet httpx betterproto ripemd-hash
```

### Python not found

Install Python 3:
```bash
# Ubuntu/Debian
sudo apt install python3 python3-pip python3-venv

# macOS
brew install python3

# CentOS/RHEL
sudo yum install python3 python3-pip
```

### ripemd160 not available

**Error**: `unsupported hash type ripemd160`

OpenSSL 3.0+ disables ripemd160 by default. The script installs a pure Python implementation (`ripemd-hash`). If you still see this error:
```bash
pip install ripemd-hash
```

---

## Chain & Registration Issues

### Account not found

**Error**: `account nesa1... not found`

Your wallet needs to receive tokens before it exists on-chain. Use the testnet faucet:
1. Go to [beta.nesa.ai/faucet](https://beta.nesa.ai/faucet)
2. Enter your wallet address
3. Wait a few seconds and retry

### Sequence mismatch

**Error**: `account sequence mismatch`

This happens when transactions are sent too quickly. The script auto-retries up to 5 times with backoff. If it persists:
1. Wait 30 seconds
2. Re-run the operation

### Node already registered

**Error**: `node already registered`

This is fine. Your node was registered in a previous run and the script will skip registration and continue.

### Deposit below minimum

**Error**: `Cannot start node - deposit is below minimum`

Go to **Manage Wallet & Deposits** and add more stake. The minimum is shown in the menu.

### Registration failed

If node or miner registration fails repeatedly:
1. Check your wallet has enough NES for gas fees
2. Check network connectivity
3. Try again in a few minutes (chain may be congested)
4. Check Discord for any network issues

---

## Terminal & Display Issues

### Script shows garbled output

**Cause**: Your terminal doesn't support the TUI elements.

**Solution**: Set basic terminal mode:
```bash
BASIC_TERMINAL=true bash <(curl -s https://raw.githubusercontent.com/nesaorg/bootstrap/master/bootstrap.sh)
```

### Colors invisible on light terminal

The script auto-detects dark/light themes, but detection isn't perfect. If colors are hard to read, the script adjusts automatically on next run, or you can edit your terminal's color scheme.

### Input not working on serial console

Serial consoles (ttyS*, ttyAMA*) use simplified input. If you're on a cloud VM console or headless server, the script should auto-detect this. If not:
```bash
BASIC_TERMINAL=true bash <(curl ...)
```

---

## Network Issues

### Connection refused / timeout

**Cause**: Network connectivity issues or firewall blocking.

**Solution**:
1. Check internet: `curl -s https://api.nesa.ai`
2. Check if ports are blocked by firewall
3. If behind corporate proxy, ensure Docker is configured to use it

### Port 31333 issues

Some features require port 31333 to be accessible. If your node shows 0 responses on the dashboard:
1. Check firewall: `sudo ufw allow 31333/tcp`
2. Check router port forwarding if behind NAT
3. Verify with: `nc -zv your-public-ip 31333`

---

## Container Issues

### Container keeps restarting

Check logs for the actual error:
```bash
docker logs orchestrator --tail 100
```

Common causes:
- Out of memory: Check RAM usage with `free -h`
- Disk full: Check with `df -h`
- Configuration error: Check `~/.nesa/env/orchestrator.env`

### Watchtower not updating

Check Watchtower logs:
```bash
docker logs watchtower
```

Watchtower checks every 5 minutes. If updates aren't happening:
1. Check network connectivity
2. Verify image registry is accessible: `docker pull ghcr.io/nesaorg/orchestrator:testnet-latest`

### How to stop all containers

```bash
cd ~/.nesa/docker && docker compose down
```

Or use the **Stop Node** option in the main menu.

---

## Getting Help

If you've tried these solutions and still have issues:

1. Collect logs:
   ```bash
   docker logs orchestrator > node.log 2>&1
   cp ~/.nesa/logs/bootstrap.log ./bootstrap.log
   ```

2. Join [Nesa Discord](https://discord.gg/nesa) and post in the support channel with:
   - Your operating system
   - The error message
   - The log files (node.log and bootstrap.log)
