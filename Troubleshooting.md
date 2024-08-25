# Troubleshooting

### 1. I have an NVIDIA GPU, but I'm seeing this error:
`Error response from daemon: could not select device driver "nvidia" with capabilities: [[gpu]] Error: Docker Compose failed to start.`

- **Solution:** Ensure that all the following components are installed:
  - NVIDIA Driver
  - CUDA
  - NVIDIA Container Toolkit

  For a streamlined installation method on Ubuntu, you can use the helper script included in the bootstrap repository to install the NVIDIA Container Toolkit:
  ```bash
  bash <(curl -s https://raw.githubusercontent.com/nesaorg/bootstrap/master/helpers/install_nvidia_container_toolkit.sh)
  ```
  For NVIDIA Driver and CUDA, refer to the following guide:
  - **NVIDIA Driver Installation:** Follow [NVIDIA's official installation guide](https://docs.nvidia.com/cuda/cuda-installation-guide-linux/index.html) for your specific distribution.
  - **CUDA Installation:** Follow [this guide](https://developer.nvidia.com/cuda-downloads) for CUDA installation instructions.

### 2. What does the error `Cannot connect to the Docker daemon at unix:///Users/fielding/.docker/run/docker.sock. Is the docker daemon running?` mean?
- **Solution:** This error indicates that the Docker daemon is not running or that your user does not have permission to access it. To resolve this:
  1. Ensure that the Docker daemon is running. You can start it with:
     ```bash
     sudo systemctl start docker
     ```
  2. If the Docker daemon is running, you may need to add your user to the Docker group to run Docker commands without `sudo`. Run the following commands:
     ```bash
     sudo usermod -aG docker $USER
     newgrp docker
     ```
  3. After adding your user to the Docker group, you should be able to use Docker commands without `sudo`.

### 3. How do I restart, reset, or reconfigure my miner node?
- **Solution:** Re-running the bootstrap script is the best way to reconfigure your miner node. The script will auto-load your previous configuration for convenience. If you prefer, you can edit the `.env` files for advanced configurations, but it’s generally easier to use the wizard mode of the bootstrap script. For backing up your node, see the next question.

### 4. How do I back up my miner node?
- **Solution:** To back up your miner node, simply back up the `~/.nesa` directory. If you are working on a remote machine, you can use the following `scp` command:
  ```bash
  scp -r user@remote_host:~/.nesa /local_backup_directory
  ```

### 5. How do I know if my miner is working correctly?
- **Solution:** Monitor your node's dashboard using the link provided in the bootstrap script header. Your node should have a response count above 0 to confirm that it is working correctly. Not all requests will have a response due to jobs testing the node's capabilities, but that’s normal. If your node appears online but has a 0 response count, ensure port `31333` is forwarded/open on your firewall. If you notice your node is marked as down, it may have failed a job; it will be marked as back up as soon as it sends another heartbeat.

### 6. My node is online but has 0 responses. What should I do?
- **Solution:** Ensure that port `31333` is forwarded to your miner and open on your firewall. This port is necessary for communication with the network and processing jobs. If the port is correctly configured and you still see 0 responses, check your logs and ensure everything is configured correctly.

### 7. How do I stop my miner containers?
- **Solution:** To stop all the miner containers, run the following command:
  ```bash
  cd ~/.nesa/docker && docker compose -f compose.yml -f compose.community.yml down
  ```

### 8. How do I know if my miner node is updated?
- **Solution:** Updates are automatically pulled down by your miner. You can verify this at any point by checking the `docker logs watchtower` logs.

### 9. I’m having issues with my miner. What should I do?
- **Solution:** If you encounter issues, check the logs for your orchestrator by running:
  ```bash
  docker logs orchestrator
  ```
  Paste the output in a support ticket on Discord for further assistance.


Disclaimer: My LLM supervisor that runs on nesa network formatted this as markdown🤞
