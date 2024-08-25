# Frequently Asked Questions (FAQ)

## Table of Contents
- [Frequently Asked Questions (FAQ)](#frequently-asked-questions-faq)
  - [Table of Contents](#table-of-contents)
    - [1. Do I need to be whitelisted to run a miner node?](#1-do-i-need-to-be-whitelisted-to-run-a-miner-node)
    - [2. Why do I need to provide a private key when setting up a miner node?](#2-why-do-i-need-to-provide-a-private-key-when-setting-up-a-miner-node)
    - [3. How do I find my node's ID (formerly public\_key/peer\_id)?](#3-how-do-i-find-my-nodes-id-formerly-public_keypeer_id)
    - [4. I installed the validator, but I want to run a miner instead. What should I do?](#4-i-installed-the-validator-but-i-want-to-run-a-miner-instead-what-should-i-do)
    - [5. What’s the difference between a Distributed Miner and a Non-Distributed Miner?](#5-whats-the-difference-between-a-distributed-miner-and-a-non-distributed-miner)
    - [6. Can I run a miner node without a GPU?](#6-can-i-run-a-miner-node-without-a-gpu)
    - [7. How do I obtain a Hugging Face API key?](#7-how-do-i-obtain-a-hugging-face-api-key)
    - [8. How do I pick a model when setting up my miner?](#8-how-do-i-pick-a-model-when-setting-up-my-miner)
    - [9. What is the difference between a miner and a validator?](#9-what-is-the-difference-between-a-miner-and-a-validator)
    - [10. What is the difference between Wizardry and Advanced Wizardry in the bootstrap script?](#10-what-is-the-difference-between-wizardry-and-advanced-wizardry-in-the-bootstrap-script)
    - [11. Is there current Windows support for running a miner?](#11-is-there-current-windows-support-for-running-a-miner)

### 1. Do I need to be whitelisted to run a miner node?
No, you do not need to be whitelisted to run a miner node. Anyone can participate as a miner on the Nesa network. However, being whitelisted can make it easier to obtain your Nesa wallet private key, which is used when setting up your miner. We recommend using [Leap Wallet](https://www.leapwallet.io/) to obtain your private key, as Keplr does not allow private key export unless it was imported as a private key. Simply follow the guide provided in the documentation to get started.

You don't have to have Nesa's testnet configured on leap to get your private key. You can simply create a new wallet and export the private key. Refer to this section of the documentation if you want to setup your wallet for the testnet, [Step 3: Configure Nesa Chain](https://docs.nesa.ai/nesa/using-nesa/getting-started/wallet-setup#step-3-configure-nesa-chain). This section is wallet agnostic and will work with any wallet that supports the Nesa chain.

### 2. Why do I need to provide a private key when setting up a miner node?
While the private key is not currently utilized on the testnet, it will be required on the mainnet. The private key will be used by the miner to pay the gas fees when registering itself online and will be the wallet that receives rewards in real-time from blockchain transactions when contributing to inference. Including the key now is good practice to prepare for when the fee and reward functionality kicks in after TGE. To make testnet rewards meaningful, we will distribute mainnet nes tokens to the testnet wallets that have been used to mine on the testnet after the TGE.

### 3. How do I find my node's ID (formerly public_key/peer_id)?
Re-run the bootstrap script in advanced mode, and check the header for your node ID and dashboard link. This ID is used by our networking stack and for rewards on the testnet. It can be found in the header of the bootstrap script and the last prompt where it shows the entire config before bootstrapping your node. There is also a link directly to your node's dashboard, but you can also visit [https://nodes.nesa.ai](https://nodes.nesa.ai) and search for your node by its node ID.

The following image shows the node id in the header of the bootstrap script, and the node id in both the header and the config preview presented before finalizing the bootstrapping process. [![Node ID in the bootstrap script]](https://raw.githubusercontent.com/nesaorg/bootstrap/master/images/node_id.png)

### 4. I installed the validator, but I want to run a miner instead. What should I do?
Currently, we are not onboarding validators. We recommend focusing on running a miner instead. Re-run the bootstrap script, select the miner option, and ensure that you only select miner. The updated script no longer requires using the spacebar for multiple selections; simply pressing enter will select the option.

### 5. What’s the difference between a Distributed Miner and a Non-Distributed Miner?
- **Distributed Miner:** Joins existing swarms for collaborative mining, splitting the model into blocks and running inference on a sequence of miners. You can either join an existing swarm or start a new one.
- **Non-Distributed Miner:** Operates independently without collaboration, running the entire model on a single machine. This option has fewer moving parts, but you must choose a model that fits your hardware specifications.

### 6. Can I run a miner node without a GPU?
Yes, you can run a miner node without a GPU. The node will primarily rely on your CPU and RAM for processing. Currently, we support CUDA, MPS, and CPU backends, so you have flexibility depending on your hardware setup.

### 7. How do I obtain a Hugging Face API key?
To obtain a Hugging Face API key, follow these steps:
1. Visit the [Hugging Face website](https://huggingface.co/).
2. Sign up or log in to your account.
3. Navigate to your [API tokens page](https://huggingface.co/settings/tokens) under your account settings.
4. Click “New token” to generate an API key.
5. Copy the generated key and use it in your miner configuration.

### 8. How do I pick a model when setting up my miner?
When setting up your miner:
- **Distributed Miner:** If you choose to join an existing swarm, you’ll see a list of models with active swarms. 
- **Non-Distributed Miner or starting a new swarm:** You should check the list of models we fully support at [beta.nesa.ai](https://beta.nesa.ai). You can also try any Hugging Face model within the categories we generally support, including:
   - **Object Detection:** `object-detection`
   - **HF Vision Tasks:** `image-segmentation`, `depth-estimation`
   - **HF Non-Dist Tasks:** `text-generation`, `text-classification`, `token-classification`, `translation`, `summarization`, `question-answering`, `sentiment-analysis`
   - **Timm Vision Tasks:** `image-classification`, `feature-extractor`

### 9. What is the difference between a miner and a validator?
- **Miners**: On the Nesa network, miners perform inference tasks using their computing power. They process data and run models, contributing directly to the network's AI operations. Miners earn rewards based on their contributions to these tasks. Miners are focused on providing computational power to run AI models.
- **Validators**: Validators help secure the network by participating in consensus, committing new blocks to the blockchain, and voting on proposals. They ensure that the network operates correctly and securely. Validators are crucial for maintaining the integrity of the blockchain, and they are selected based on specific criteria, including their ability to stake coins and their participation in governance.

### 10. What is the difference between Wizardry and Advanced Wizardry in the bootstrap script?
- **Wizardry**: This is the standard setup mode where the script walks you through the configuration process step-by-step, prompting you for inputs where necessary. It's designed to guide you through the installation with minimal complexity.
- **Advanced Wizardry**: This mode is intended for more advanced users who might want to set up multiple nodes or customize specific configurations beyond the standard options. It allows you to pre-configure settings in one go, manually set variables that aren't customizable in the regular wizardry mode, and skip the wizardry prompts if you’ve already set up your configuration previously.

### 11. Is there current Windows support for running a miner?
Yes, there is support for running a miner on Windows. Follow the guide in the documentation to get started. Ensure you have Docker Desktop installed with WSL 2 enabled and run the bootstrap script as instructed.
