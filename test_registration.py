#!/usr/bin/env python3
"""
Test script for node registration, miner registration, and deposit flow.
"""

import os
import sys
import json
import time
from dataclasses import dataclass
from typing import List

import httpx
import betterproto
from mospy import Account, Transaction
from mospy.clients import HTTPClient
from google.protobuf import any_pb2 as any_pb

LCD_URL = "https://lcd.dev.nesa.ai"
CHAIN_ID = "nesa"


# Message definitions
@dataclass(eq=False, repr=False)
class MsgRegisterNode(betterproto.Message):
    creator: str = betterproto.string_field(1)
    node_id: str = betterproto.string_field(2)
    public_name: str = betterproto.string_field(3)
    version: str = betterproto.string_field(4)
    network_address: str = betterproto.string_field(5)
    wallet_address: str = betterproto.string_field(6)
    vram: int = betterproto.uint64_field(7)
    network_rps: float = betterproto.double_field(8)
    using_relay: bool = betterproto.bool_field(9)


@dataclass(eq=False, repr=False)
class MsgRegisterMiner(betterproto.Message):
    creator: str = betterproto.string_field(1)
    node_id: str = betterproto.string_field(2)
    start_block: int = betterproto.uint64_field(3)
    end_block: int = betterproto.uint64_field(4)
    block_ids: List[int] = betterproto.uint32_field(5)
    torch_dtype: str = betterproto.string_field(6)
    quant_type: str = betterproto.string_field(7)
    cache_tokens_left: int = betterproto.uint64_field(8)
    inference_rps: float = betterproto.double_field(9)
    model_name: str = betterproto.string_field(10)


@dataclass(eq=False, repr=False)
class Coin(betterproto.Message):
    denom: str = betterproto.string_field(1)
    amount: str = betterproto.string_field(2)


@dataclass(eq=False, repr=False)
class MsgAddMinerDeposit(betterproto.Message):
    depositor: str = betterproto.string_field(1)
    node_id: str = betterproto.string_field(2)
    amount: Coin = betterproto.message_field(3)


def check_node_registered(node_id: str) -> bool:
    """Check if node is registered on chain."""
    url = f"{LCD_URL}/nesachain/dht/get_node/{node_id}"
    try:
        resp = httpx.get(url, timeout=10)
        if resp.status_code == 200:
            data = resp.json()
            return data.get("node", {}).get("node_id") == node_id
        return False
    except Exception as e:
        print(f"Error checking node: {e}")
        return False


def check_miner_registered(node_id: str) -> dict:
    """Check if miner is registered and get deposit info."""
    url = f"{LCD_URL}/nesachain/dht/get_miner/{node_id}"
    try:
        resp = httpx.get(url, timeout=10)
        if resp.status_code == 200:
            data = resp.json()
            miner = data.get("miner", {})
            if miner:
                return {
                    "registered": True,
                    "deposit": int(miner.get("deposit", {}).get("amount", 0)),
                    "bond_status": miner.get("bond_status", 0)
                }
        return {"registered": False, "deposit": 0, "bond_status": 0}
    except Exception as e:
        print(f"Error checking miner: {e}")
        return {"registered": False, "deposit": 0, "bond_status": 0}


def broadcast_tx(tx: Transaction) -> dict:
    """Broadcast transaction and return result."""
    msg_any = any_pb.Any()
    # Get the first message from the transaction
    # We need to manually add our message

    tx_bytes = tx.get_tx_bytes_as_string()

    payload = {"tx_bytes": tx_bytes, "mode": "BROADCAST_MODE_SYNC"}

    with httpx.Client(timeout=30.0) as client:
        response = client.post(f"{LCD_URL}/cosmos/tx/v1beta1/txs", json=payload)
        return response.json()


def register_node(account: Account, node_id: str) -> tuple[bool, str]:
    """Register node on chain."""
    print(f"Registering node {node_id}...")

    msg = MsgRegisterNode(
        creator=account.address,
        node_id=node_id,
        public_name="nesa-miner",
        version="v1.0.0",
        network_address="127.0.0.1:8080",
        wallet_address=account.address,
        vram=8000000000,
        network_rps=100.0,
        using_relay=False
    )

    # Load account data
    client = HTTPClient(api=LCD_URL)
    client.load_account_data(account=account)

    # Build transaction
    tx = Transaction(account=account, gas=200000, chain_id=CHAIN_ID)
    tx.set_fee(amount=1000, denom="unes")

    # Add message
    msg_any = any_pb.Any()
    msg_any.value = bytes(msg)
    msg_any.type_url = "/dht.v1.MsgRegisterNode"
    tx._tx_body.messages.append(msg_any)

    # Broadcast
    result = broadcast_tx(tx)

    if "tx_response" in result:
        tx_response = result["tx_response"]
        code = tx_response.get("code", 0)
        txhash = tx_response.get("txhash", "unknown")
        if code == 0:
            return True, txhash
        else:
            return False, tx_response.get("raw_log", "Unknown error")

    return False, str(result)


def register_miner(account: Account, node_id: str, model_name: str = "nesaorg/llama-3.2-1b-instruct-ee") -> tuple[bool, str]:
    """Register miner on chain."""
    print(f"Registering miner {node_id} for model {model_name}...")

    msg = MsgRegisterMiner(
        creator=account.address,
        node_id=node_id,
        start_block=1,
        end_block=2,
        block_ids=[0],
        torch_dtype="fp16",
        quant_type="fp4",
        cache_tokens_left=0,
        inference_rps=100.0,
        model_name=model_name
    )

    # Load account data (fresh)
    client = HTTPClient(api=LCD_URL)
    client.load_account_data(account=account)

    # Build transaction
    tx = Transaction(account=account, gas=200000, chain_id=CHAIN_ID)
    tx.set_fee(amount=1000, denom="unes")

    # Add message
    msg_any = any_pb.Any()
    msg_any.value = bytes(msg)
    msg_any.type_url = "/dht.v1.MsgRegisterMiner"
    tx._tx_body.messages.append(msg_any)

    # Broadcast
    result = broadcast_tx(tx)

    if "tx_response" in result:
        tx_response = result["tx_response"]
        code = tx_response.get("code", 0)
        txhash = tx_response.get("txhash", "unknown")
        if code == 0:
            return True, txhash
        else:
            return False, tx_response.get("raw_log", "Unknown error")

    return False, str(result)


def add_deposit(account: Account, node_id: str, amount_microunes: int) -> tuple[bool, str]:
    """Add miner deposit."""
    print(f"Adding deposit of {amount_microunes} unes to miner {node_id}...")

    msg = MsgAddMinerDeposit(
        depositor=account.address,
        node_id=node_id,
        amount=Coin(denom="unes", amount=str(amount_microunes))
    )

    # Load account data (fresh)
    client = HTTPClient(api=LCD_URL)
    client.load_account_data(account=account)

    # Build transaction
    tx = Transaction(account=account, gas=150000, chain_id=CHAIN_ID)
    tx.set_fee(amount=1000, denom="unes")

    # Add message
    msg_any = any_pb.Any()
    msg_any.value = bytes(msg)
    msg_any.type_url = "/dht.v1.MsgAddMinerDeposit"
    tx._tx_body.messages.append(msg_any)

    # Broadcast
    result = broadcast_tx(tx)

    if "tx_response" in result:
        tx_response = result["tx_response"]
        code = tx_response.get("code", 0)
        txhash = tx_response.get("txhash", "unknown")
        if code == 0:
            return True, txhash
        else:
            return False, tx_response.get("raw_log", "Unknown error")

    return False, str(result)


def main():
    # Get private key from env
    private_key = os.environ.get("NODE_PRIV_HEX") or os.environ.get("NODE_PRIV_KEY")
    if not private_key:
        print("ERROR: NODE_PRIV_HEX or NODE_PRIV_KEY environment variable not set")
        sys.exit(1)
    # Strip quotes if present
    private_key = private_key.strip('"').strip("'")

    # Get node ID from file or generate
    node_id_file = os.path.expanduser("~/.nesa/identity/node_id.id")
    if os.path.exists(node_id_file):
        with open(node_id_file) as f:
            node_id = f.read().strip()
    else:
        print(f"ERROR: Node ID file not found at {node_id_file}")
        sys.exit(1)

    print(f"Node ID: {node_id}")

    # Create account
    account = Account(private_key=private_key, hrp="nesa")
    print(f"Wallet: {account.address}")

    # Step 1: Check node registration
    print("\n=== Step 1: Check Node Registration ===")
    if check_node_registered(node_id):
        print("✓ Node already registered")
    else:
        print("Node not registered, registering...")
        success, result = register_node(account, node_id)
        if success:
            print(f"✓ Node registered! TX: {result}")
            print("Waiting 5 seconds for confirmation...")
            time.sleep(5)
        else:
            print(f"✗ Node registration failed: {result}")
            sys.exit(1)

    # Step 2: Check miner registration
    print("\n=== Step 2: Check Miner Registration ===")
    miner_info = check_miner_registered(node_id)
    if miner_info["registered"]:
        print(f"✓ Miner already registered")
        print(f"  Deposit: {miner_info['deposit']} unes")
        print(f"  Bond Status: {miner_info['bond_status']}")
    else:
        print("Miner not registered, registering...")
        success, result = register_miner(account, node_id)
        if success:
            print(f"✓ Miner registered! TX: {result}")
            print("Waiting 5 seconds for confirmation...")
            time.sleep(5)
        else:
            print(f"✗ Miner registration failed: {result}")
            sys.exit(1)

    # Step 3: Add deposit if needed
    print("\n=== Step 3: Check/Add Deposit ===")
    miner_info = check_miner_registered(node_id)
    min_deposit = 1000  # 1000 unes = 0.001 UNES

    if miner_info["deposit"] >= min_deposit:
        print(f"✓ Deposit already sufficient: {miner_info['deposit']} unes")
    else:
        deposit_amount = min_deposit  # Add minimum
        print(f"Adding deposit of {deposit_amount} unes...")
        success, result = add_deposit(account, node_id, deposit_amount)
        if success:
            print(f"✓ Deposit added! TX: {result}")
        else:
            print(f"✗ Deposit failed: {result}")
            sys.exit(1)

    # Final check
    print("\n=== Final Status ===")
    time.sleep(3)
    miner_info = check_miner_registered(node_id)
    print(f"Miner registered: {miner_info['registered']}")
    print(f"Deposit: {miner_info['deposit']} unes ({miner_info['deposit']/1000000:.6f} UNES)")
    print(f"Bond Status: {miner_info['bond_status']}")

    print("\n✓ Done!")


if __name__ == "__main__":
    main()
