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
#   bootstrap.sh      fielding@nesa.ai 
#
#
#                       

#
# vars
#

# set -x
terminal_size=$(stty size)
terminal_height=${terminal_size% *}
terminal_width=${terminal_size#* }
prompt_height=${PROMPT_HEIGHT:-1}
main_color=43
logo=$(gum style '   ▄▄▄▄▄▄  
  ███▀▀▀██▄   
  ███   ███ 
  ███   ███  
  ▄▄▄   ███ 
  ███   ███ 
  ███   ███')

CHAIN_ID="nesa-testnet-3"
domain="test.nesa.sh"
chain_container="ghcr.io/nesaorg/nesachain:testnet-latest"

import_key_expect_url="https://raw.githubusercontent.com/nesaorg/bootstrap/master/import_key.expect"

address="pending"
is_validator="no"
is_miner="no"
status="booting"
init_pwd=$PWD


# this will never load from the env file, but if they know to override it via ENV vars then they can
WORKING_DIRECTORY=${WORKING_DIRECTORY:-"$HOME/.nesa"}
env_dir="$WORKING_DIRECTORY/env"

agent_env_file="$env_dir/agent.env"
bsns_s_env_file="$env_dir/bsns-s.env"
orchestrator_env_file="$env_dir/orchestrator.env"
base_env_file="$env_dir/base.env"
config_env_file="$env_dir/.env"


#
# basic helper functions
#

# print if the output if ts on screen
print_test() {
    local no_color
    local max_length
    max_length=$(max_line_length "$no_color")
    no_color=$(printf '%b' "${1}" | sed -e 's/\x1B\[[0-9;]*[JKmsu]//g')

    [ "$(printf '%s' "${no_color}" | wc -l)" -gt $((terminal_height - prompt_height)) ] && return 1
    [ "$max_length" -gt "$terminal_width" ] && return 1

    gum style --align center --width="${terminal_width}" "${1}" ''
    printf '%b' "\033[A"
}

update_header() {
    info=$(gum style "[1;38;5;${main_color}m  ${MONIKER}[0m.${domain}
  ----------------
  [1;38;5;${main_color}maddress:       [0m${address}
  [1;38;5;${main_color}mvalidator:     [0m${is_validator}
  [1;38;5;${main_color}mminer:         [0m${is_miner}
  [1;38;5;${main_color}mstatus:        [0m${status}")
    header=$(gum join --horizontal --align top "${logo}" '  ' "${info}")

    print_test "${header}"
    echo -e "\n"
}

# check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# error handling function
handle_install_failure() {
    echo "Failed to install Gum using available methods due to permissions or unsupported OS..."
    echo "Please install Gum manually by visiting: https://github.com/charmbracelet/gum"
    exit 1
}

# install gum using Go
install_gum_go() {
    echo "Installing Gum using Go..."
    go install github.com/charmbracelet/gum@latest || handle_install_failure
}

# install gum based on the operating system and availability of Go
install_gum() {
    # Try to install using Go if available
    if command_exists go; then
        install_gum_go
        return
    fi

    case "$(uname -s)" in
    Darwin)
        echo "Installing Gum using Homebrew..."
        brew install gum || handle_install_failure
        ;;
    Linux)
        if command_exists apt-get; then
            echo "Installing Gum on Ubuntu/Debian..."
            sudo mkdir -p /etc/apt/keyrings
            curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
            echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
            sudo apt update && sudo apt install gum || handle_install_failure
        elif command_exists pacman; then
            echo "Installing Gum using pacman..."
            sudo pacman -S gum || handle_install_failure
        elif command_exists nix-env; then
            echo "Installing Gum using Nix..."
            nix-env -iA nixpkgs.gum || handle_install_failure
        else
            handle_install_failure
        fi
        ;;
    CYGWIN* | MINGW32* | MSYS* | MINGW*)
        if command_exists winget; then
            echo "Installing Gum using WinGet..."
            winget install charmbracelet.gum || handle_install_failure
        elif command_exists scoop; then
            echo "Installing Gum using Scoop..."
            scoop install charm-gum || handle_install_failure
        else
            handle_install_failure
        fi
        ;;
    *)
        handle_install_failure
        ;;
    esac
}

check_gum_installed() {
    if ! command_exists gum; then
        echo "Attempting to install gum..."
        install_gum
    fi
}

check_jq_installed() {
    if ! command -v jq &>/dev/null; then
        install_jq
    fi
}

install_jq() {
    case "$(uname -s)" in
    Linux)
        if command -v apt-get &>/dev/null; then
            gum spin -s line --title "Installing jq with apt-get..." -- sudo apt-get update && sudo apt-get install -y jq
        elif command -v yum &>/dev/null; then
            gum spin -s line --title "Installing jq with yum..." -- sudo yum install -y jq
        elif command -v pacman &>/dev/null; then
            gum spin -s line --title "Installing jq with pacman..." -- sudo pacman -Sy jq
        elif command -v zypper &>/dev/null; then
            gum spin -s line --title "Installing jq with zypper..." -- sudo zypper install -y jq
        elif command -v dnf &>/dev/null; then
            gum spin -s line --title "Installing jq with dnf..." -- sudo dnf install -y jq
        else
            echo "Package manager not found. Please install jq manually."
            exit 1
        fi
        ;;
    Darwin)
        if command -v brew &>/dev/null; then
            gum spin -s line --title "Installing jq with brew..." -- brew install jq
        else
            echo "Homebrew is not installed. Please install jq manually."
            exit 1
        fi
        ;;
    *)
        echo "Unsupported OS. Please install jq manually."
        exit 1
        ;;
    esac
}


# check if Docker is installed
check_docker_installed() {
    if ! command_exists docker; then
        echo "Docker is not installed. Please install Docker and try again."
        exit 1
    fi
}

# calculate max line length of the input
max_line_length() {
    local max_len
    local line_len
    max_len=0

    IFS=$'\n'
    for line in $1; do
        line_len=${#line}
        if ((line_len > max_len)); then
            max_len=$line_len
        fi
    done
    echo "$max_len"
}

download_import_key_expect() {
    # curl -o import_key.expect "$IMPORT_KEY_EXPECT_URL"

    cp import_key.expect "$WORKING_DIRECTORY/"
    chmod +x "$WORKING_DIRECTORY/import_key.expect"

}

setup_work_dir() {
    if [ ! -d "$WORKING_DIRECTORY" ]; then
        mkdir -p "$WORKING_DIRECTORY"
    fi

    cd "$WORKING_DIRECTORY" || {
        echo -e "Error changing to working directory: $WORKING_DIRECTORY"
        exit 1
    }


    # Clone or pull the latest changes if the repo already exists
    if [ ! -d "docker" ]; then
        gum spin -s line --title "Cloning the nesaorg/docker repository..." -- git clone https://github.com/nesaorg/docker.git
    else
        cd docker
        gum spin -s line --title "Pulling latest updates from nesaorg/docker repository..." -- git pull
        cd ..
    fi

    # Create symlink for env directory
    if [ -d "docker" ]; then
        ln -sfn "$env_dir" "docker/env"
    else
        echo "Error: Docker directory does not exist."
        exit 1
    fi
}



get_swarms_map() {
    local url="https://lcd.test.nesa.ai/nesachain/dht/get_orchestrators"
    local json_data
    local map=()

    json_data=$(curl -s "$url")

    # filtering out malformed orchestrators
    map=$(echo "$json_data" | jq -r '
        .orchestrators |
        map(select(.node_id | (contains("/") | not))) |
        map(
            {
                "node_id": (.node_id | split("|")[0]),
                "model_id": ((.node_id | split("|")[1]) + "/" + (.node_id | split("|")[2])),
            }
        )
    ')

    echo "$map"
}

get_model_names() {
    local map="$1"
    local model_names

    model_names=$(echo "$map" | jq -r '.[] | .model_id' | sort | uniq)

    echo "$model_names"
}

get_node_id() {
    local map="$1"
    local model_id="$2"
    local node_id

    node_id=$(echo "$map" | jq -r --arg model_id "$model_id" '
        .[] | select(.model_id == $model_id) | .node_id
    ')

    echo "$node_id"
}

# this is temporary, once DHT is updated we can stop doing this
recreate_node_id() {
    local map="$1"
    local model_id="$2"
    local node_info

    node_info=$(echo "$map" | jq -r --arg model_id "$model_id" '
        .[] | select(.model_id == $model_id) | "\(.node_id)|\(.organization)|\(.model_name)"
    ')

    echo "$node_info"
}

fetch_network_address() {
    local node_id="$1"
    local url="https://lcd.test.nesa.ai/nesachain/dht/get_node/$node_id"
    local json_data
    local network_address

    # Fetch JSON data
    json_data=$(curl -s "$url")

    # Parse JSON to get the network address
    network_address=$(echo "$json_data" | jq -r '.node.network_address')

    echo "$network_address"
}



save_to_env_file() {
    # Note: Variables might be used in multiple env files, that is okay.
    # Config environment variables
    echo "CHAIN_ID=$CHAIN_ID" > "$config_env_file"
    echo "MODEL_NAME=$MODEL_NAME" >> "$config_env_file"
    echo "IS_VALIDATOR=$is_validator" >> "$config_env_file"
    echo "IS_MINER=$is_miner" >> "$config_env_file"
    echo "NODE_HOSTNAME=$NODE_HOSTNAME" >> "$config_env_file"
    echo "OP_EMAIL=$OP_EMAIL" >> "$config_env_file"

    # Agent environment variables
    echo "VIRTUAL_HOST=$NODE_HOSTNAME" > "$agent_env_file"
    echo "LETSENCRYPT_HOST=$NODE_HOSTNAME" >> "$agent_env_file"
    echo "LETSENCRYPT_EMAIL=$OP_EMAIL" >> "$agent_env_file"K
    echo "CHAIN_ID=$CHAIN_ID" > "$config_env_file"
    echo "NODE_HOSTNAME=$NODE_HOSTNAME" >> "$agent_env_file"
    echo "MODEL_NAME=$MODEL_NAME" >> "$config_env_file"
    echo "NODE_PRIV_KEY=$NODE_PRIV_KEY" >> "$agent_env_file"
    # BSNS-S environment variables
    echo "INITIAL_PEER=$INITIAL_PEER" > "$bsns_s_env_file"
    echo "MONIKER=$MONIKER" >> "$bsns_s_env_file"

    # Orchestrator environment variables
    echo "IS_DIST=$IS_DIST" > "$orchestrator_env_file"
    echo "HUGGINGFACE_API_KEY=$HUGGINGFACE_API_KEY" >> "$orchestrator_env_file"
    echo "MONIKER=$MONIKER" >> "$orchestrator_env_file"

    # Base environment variables
    echo "MONIKER=$MONIKER" > "$base_env_file"
    echo "CHAIN_ID=$CHAIN_ID" > "$config_env_file"

}



compose_up() {
    local compose_files
    compose_files="compose.yml"

    if [[ "$node_type" == *"Miner"* ]]; then
        if [[ "$miner_type" == *"Non-Distributed Miner"* ]]; then
            compose_files+=" -f compose.agent.yml -f compose.orchestrator.yml"
        elif [[ "$miner_type" == *"Distributed Miner"* ]]; then
            if [[ "$distributed_type" == *"Start a new swarm"* ]]; then
                compose_files+=" -f compose.agent.yml -f compose.orchestrator.yml -f compose.bsns-c.yml"
            else
                compose_files+=" -f compose.bsns-s.yml"
            fi
        fi
    fi

    echo "Using compose files: $compose_files"
    
    # gum spin -s line --title "Starting Docker Compose..." --
    docker compose -f "$compose_files" up -d --wait

    if [[ $? -ne 0 ]]; then
        echo "Error: Docker Compose failed to start."
        exit 1
    else
        echo "Docker Compose started successfully."
    fi
}



load_from_env_file() {
    if [ -f "$config_env_file" ]; then
        source "$config_env_file"
    elif [ "$1" == "advanced" ]; then
        echo "$config_env_file does not exist. Please run in wizard mode to create the config file."
        exit 1
    else
        mkdir -p "$env_dir"
        touch "$config_env_file"
    fi

    if [ -f "$agent_env_file" ]; then
        source "$agent_env_file"
    elif [ "$1" != "advanced" ]; then
        touch "$agent_env_file"
    fi

    if [ -f "$bsns_s_env_file" ]; then
        source "$bsns_s_env_file"
    elif [ "$1" != "advanced" ]; then
        touch "$bsns_s_env_file"
    fi

    if [ -f "$orchestrator_env_file" ]; then
        source "$orchestrator_env_file"
    elif [ "$1" != "advanced" ]; then
        touch "$orchestrator_env_file"
    fi

    if [ -f "$base_env_file" ]; then
        source "$base_env_file"
    elif [ "$1" != "advanced" ]; then
        touch "$base_env_file"
    fi
}




load_from_env_file "wizard"
PRIV_KEY=${PRIV_KEY:-""}
HUGGINGFACE_API_KEY=${HUGGINGFACE_API_KEY:-""}
MODEL_NAME=${MODEL_NAME:-""}


# don't use cached/saved values for these 
PUBLIC_IP=$(curl -s ifconfig.me)

#
# bootstrap core logic
#

# deps
check_gum_installed
check_docker_installed
check_jq_installed

clear
update_header


echo -e "Select a $(gum style --foreground "$main_color" "mode")"
wizard_mode="Wizardy"
advanced_mode="Advanced Wizardy"

mode=$(gum choose "$wizard_mode" "$advanced_mode")

clear
update_header

if grep -q "$advanced_mode" <<<"$mode"; then
    load_from_env_file "advanced"
    echo -e "Current configuration:"
    cat "$config_env_file" "$agent_env_file" "$bsns_s_env_file" "$orchestrator_env_file" "$base_env_file" | sort | uniq

    confirm=$(gum confirm "Do you want to run this script with this configuration?")
    if [ "$confirm" != "yes" ]; then
        exit 0
    fi
else


    MONIKER=${MONIKER:$(hostname -s)}
    MONIKER=$(gum input --cursor.foreground "${main_color}" \
        --prompt.foreground "${main_color}" \
        --prompt "Choose a moniker for your node: " \
        --placeholder "$MONIKER" \
        --width 80 \
        --value "$MONIKER")

    MONIKER=$(echo "$MONIKER" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    clear
    update_header
    
    NODE_HOSTNAME=${NODE_HOSTNAME:-"$MONIKER.yourdomain.tld"}
    NODE_HOSTNAME=$(gum input --cursor.foreground "${main_color}" \
        --prompt.foreground "${main_color}" \
        --prompt "What will $(gum style --foreground "main_color" "$MONIKER")'s hostname be? " \
        --placeholder "$NODE_HOSTNAME" \
        --width 80 \
        --value "$NODE_HOSTNAME")

    clear
    update_header

    OP_EMAIL=${OP_EMAIL:-"admin@$NODE_HOSTNAME"}
    OP_EMAIL=$(gum input --cursor.foreground "${main_color}" \
        --prompt.foreground "${main_color}" \
        --prompt "What is the email of the node operator? " \
        --placeholder "$OP_EMAIL" \
        --width 80 \
        --value "$OP_EMAIL")

    clear
    update_header

    echo -e "Now, what type(s) of node is $(gum style --foreground "$main_color" "$MONIKER")? (use space to select which type(s)"

    validator_string="Validator"
    miner_string="Miner"

    node_type=$(gum choose --no-limit "$validator_string" "$miner_string")

    grep -q "$validator_string" <<<"$node_type" && is_validator="pending"
    grep -q "$miner_string" <<<"$node_type" && is_miner="pending"

    clear
    update_header

    gum spin -s line --title "Setting up working directory and cloning node repository..." -- setup_work_dir
    setup_work_dir


    if grep -q "$validator_string" <<<"$node_type"; then

        # echo -e "Please apply to be a $(gum style --foreground "$main_color" "validator") node here: https://forms.gle/3fQQHVJbHqTPpmy58"

        download_import_key_expect

        if [ ! -n "$PRIV_KEY" ]; then
            PRIV_KEY=$(gum input --cursor.foreground "${main_color}" \
                --password \
                --prompt.foreground "${main_color}" \
                --prompt "Validator's private key: " \
                --width 80)

            PASSWORD=$(gum input --cursor.foreground "${main_color}" \
                --password \
                --prompt.foreground "${main_color}" \
                --prompt "Password for the private key: " \
                --width 80)

            docker pull ghcr.io/nesaorg/nesachain/nesachain:test
            docker volume create nesachain-data

            docker run --rm -v nesachain-data:/app/.nesachain -e MONIKER="$MONIKER" -e CHAIN_ID="$CHAIN_ID" -p 26656:26656 -p 26657:26657 -p 1317:1317 -p 9090:9090 -p 2345:2345 $chain_container

            "$WORKING_DIRECTORY/import_key.expect" "$MONIKER" "$PRIV_KEY" "$chain_container" "$PASSWORD"

        fi

        docker run --rm --entrypoint sh -v nesachain-data:/app/.nesachain -p 26656:26656 -p 26657:26657 -p 1317:1317 -p 9090:9090 -p 2345:2345 $chain_container -c '
            VAL_PUB_KEY=$(nesad tendermint show-validator | jq -r ".key") && \
            echo "VAL_PUB_KEY: $VAL_PUB_KEY" && \
            jq -n \
                --arg pubkey "$VAL_PUB_KEY" \
                --arg amount "100000000000unes" \
                --arg moniker "'"$MONIKER"'" \
                --arg chain_id "'"$CHAIN_ID"'" \
                --arg commission_rate "0.10" \
                --arg commission_max_rate "0.20" \
                --arg commission_max_change_rate "0.01" \
                --arg min_self_delegation "1" \
                '"'"'{
                    pubkey: {"@type":"/cosmos.crypto.ed25519.PubKey", "key": $pubkey},
                    amount: $amount,
                    moniker: $moniker,
                    "commission-rate": $commission_rate,
                    "commission-max-rate": $commission_max_rate,
                    "commission-max-change-rate": $commission_max_change_rate,
                    "min-self-delegation": $min_self_delegation
                }'"'"' > /app/.nesachain/validator.json && \
            cat /app/.nesachain/validator.json
        '

        ehco "sending tx from $MONIKER"
        docker run --rm --entrypoint nesad -v nesachain-data:/app/.nesachain $chain_container tx staking create-validator /app/.nesachain/validator.json --from "$MONIKER" --chain-id "$CHAIN_ID" --gas auto --gas-adjustment 1.5 --node https://rpc.test.nesa.ai
  
    fi

    if grep -q "$miner_string" <<<"$node_type"; then        
        clear
        update_header 
        
        prompt_for_node_pk=0

        if [ -n "$NODE_PRIV_KEY" ]; then
            pk_confirm=$(gum confirm "Do you want to use the existing private key? ")
            if [ "$pk_confirm" != "yes" ]; then
                prompt_for_node_pk=1

            fi
        else
            prompt_for_node_pk=1
        fi
        
        if [ "$prompt_for_node_pk" -eq 1 ]; then
            NODE_PRIV_KEY=$(gum input --cursor.foreground "${main_color}" \
                --password \
                --prompt.foreground "${main_color}" \
                --prompt "Node's wallet private key: " \
                --width 80)
        fi

        clear
        update_header

        echo -e "Now, what type of miner will $(gum style --foreground "$main_color" "$MONIKER") be?"
        distributed_string="Distributed Miner"
        non_distributed_string="Non-Distributed Miner"

        miner_type=$(gum choose "$distributed_string" "$non_distributed_string")


        clear
        update_header

        if grep -q "$miner_type" <<<"$distributed_string"; then
            IS_DIST=True

            
            echo -e "Would you like to join an existing $(gum style --foreground "$main_color" "swarm") or start a new one?"
            existing_swarm="Join existing swarm"
            new_swarm="Start a new swarm"

            distributed_type=$(gum choose "$existing_swarm" "$new_swarm")

            if grep -q "$distributed_type" <<<"$new_swarm"; then
                MODEL_NAME=$(
                    gum input --cursor.foreground "${main_color}" \
                        --prompt.foreground "${main_color}" \
                        --prompt "Which model would you like to run? " \
                        --placeholder "$MODEL_NAME" \
                        --width 80 \
                        --value "$MODEL_NAME"
                )

                HUGGINGFACE_API_KEY=$(
                    gum input --cursor.foreground "${main_color}" \
                        --prompt.foreground "${main_color}" \
                        --prompt "Please provide your Huggingface API key: " \
                        --placeholder "$HUGGINGFACE_API_KEY" \
                        --width 80 \
                        --value "$HUGGINGFACE_API_KEY
                        "
                )

            else 
                swarms_map=$(get_swarms_map)
                model_names=$(get_model_names "$swarms_map")
                echo -e "Which existing $(gum style --foreground "$main_color" "swarm") would you like to join?"
                MODEL_NAME=$(echo "$model_names" | gum choose --no-limit)
                INITIAL_PEER_ID=$(recreate_node_id "$swarms_map" "$MODEL_NAME")
                INITIAL_PEER_ADDRESS=$(fetch_network_address "$INITIAL_PEER_ID") 

                INITIAL_PEER="ip4/$INITIAL_PEER_ADDRESS/tcp/31330/p2p/$INITIAL_PEER_ID"
                
                echo "Initial peer address: $INITIAL_PEER_ADDRESS" 

            fi

        else # non-distributed setup

            MODEL_NAME=$(
                gum input --cursor.foreground "${main_color}" \
                    --prompt.foreground "${main_color}" \
                    --prompt "Which model would you like to run?" \
                    --placeholder "nlptown/bert-base-multilingual-uncased-sentiment" \
                    --width 80 \
                    --value "$MODEL_NAME"
            )
            
            clear
            update_header
            HUGGINGFACE_API_KEY=$(
                gum input --cursor.foreground "${main_color}" \
                    --prompt.foreground "${main_color}" \
                    --prompt "Please provide your Huggingface API key:" \
                    --placeholder "$MODEL_NAME" \
                    --width 80 \
                    --value "$MODEL_NAME"
            )
        fi
    fi
    save_to_env_file
fi

cd "$WORKING_DIRECTORY/docker" || {
    echo -e "Error changing to working directory: $WORKING_DIRECTORY/docker"
    exit 1
}

compose_up
cd "$init_pwd" || return

echo -e "Congratulations! Your $(gum style --foreground "$main_color" "nesa") node was successfully bootstrapped!"
# set +x