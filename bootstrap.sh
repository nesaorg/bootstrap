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

chain_id="nesa-testnet-3"
domain=".nesa.sh"
chain_container="9eef1e0f504e"
# chain_container="ghcr.io/nesaorg/nesachain/nesachain:test"

import_key_expect_url="https://raw.githubusercontent.com/nesaorg/bootstrap/master/import_key.expect"

address="pending"
is_validator="no"
is_miner="no"
status="booting"
init_pwd=$PWD


WORKING_DIRECTORY=${WORKING_DIRECTORY:-"$HOME/nesa"}
env_file="$WORKING_DIRECTORY/.env"




#
# basic helper functions
#

# print if the output fi ts on screen
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
    info=$(gum style "[1;38;5;${main_color}m  ${MONIKER}[0m${domain}
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
    # chmod +x "$WORKING_DIRECTORY/import_key.expect"

    cp import_key.expect "$WORKING_DIRECTORY/"
}

setup_work_dir() {
    if [ ! -d "$WORKING_DIRECTORY" ]; then
        mkdir -p "$WORKING_DIRECTORY"
        echo -e "Working directory created at $WORKING_DIRECTORY"
    fi

    cd "$WORKING_DIRECTORY" || {
        echo -e "Error changing to working directory: $WORKING_DIRECTORY"
        exit 1
    }

    download_import_key_expect


    # Clone or pull the latest changes if the repo already exists
    if [ ! -d "docker" ]; then
        gum spin -s line --title "Cloning the nesaorg/docker repository..." -- git clone https://github.com/nesaorg/docker.git
    else
        cd docker
        gum spin -s line --title "Pulling latest updates from nesaorg/docker repository..." -- git pull
        cd ..
    fi
}



get_swarms_map() {
    local url="https://lcd.test.nesa.ai/agent/v1/inference_agent_model"
    local json_data
    local map=()

    # Fetch JSON data
    json_data=$(curl -s "$url")

    # Parse JSON and build the map using jq
    map=$(echo "$json_data" | jq -r '
        .model_agents | 
        map(
            {
                (.model_name): (.inference_agents | map(.url | sub("^wss://"; "")))
            }
        ) | 
        add
    ')

    echo "$map"
}





# Function to get the list of model names from the map
get_model_names() {
    local map="$1"
    local model_names

    model_names=$(echo "$map" | jq -r 'keys | .[]')

    echo "$model_names"
}

save_to_env_file() {
    echo "MONIKER=$MONIKER" > "$env_file"
    echo "WORKING_DIRECTORY=$WORKING_DIRECTORY" >> "$env_file"
    echo "PRIV_KEY=$PRIV_KEY" >> "$env_file"
    echo "CHAIN_ID=$chain_id" >> "$env_file"
    echo "MODEL_NAME=$MODEL_NAME" >> "$env_file"
    echo "HUGGINGFACE_API_KEY=$HUGGINGFACE_API_KEY" >> "$env_file"
    echo "IS_VALIDATOR=$is_validator" >> "$env_file"
    echo "IS_MINER=$is_miner" >> "$env_file"
    echo "ENV variables saved to $env_file"
}



compose_up() {
    local compose_files
    compose_files="compose.yml -f compose.agent.yml"

    if [[ "$node_type" == *"Miner"* ]]; then
        if [[ "$miner_type" == *"Non-Distributed Miner"* ]]; then
            compose_files+=" -f compose.non-dist.yml"
        elif [[ "$miner_type" == *"Distributed Miner"* ]]; then
            if [[ "$distributed_type" == *"Start a new swarm"* ]]; then
                compose_files+=" -f compose.dist-c.yml"
            else
                compose_files+=" -f compose.dist-s.yml"
            fi
        fi
    fi

    echo "Using compose files: $compose_files"
    gum spin -s line --title "Starting Docker Compose..." -- docker compose -f $compose_files up -d --wait

    if [[ $? -ne 0 ]]; then
        echo "Error: Docker Compose failed to start."
        exit 1
    else
        echo "Docker Compose started successfully."
    fi
}

load_from_env_file() {
    if [ -f "$env_file" ]; then
        source "$env_file"
    elif [ "$1" == "advanced" ]; then
        echo "$env_file does not exist. Please run in wizard mode to create the config file."
        exit 1
    fi
}


load_from_env_file "wizard"
MONIKER=${MONIKER:$(hostname)}
PRIV_KEY=${PRIV_KEY:-""}
HUGGINGFACE_API_KEY=${HUGGINGFACE_API_KEY:-""}


#
# bootstrap core logic
#

# deps
check_gum_installed
check_docker_installed
# check_jq_installed

clear
update_header


echo -e "Select a $(gum style --foreground "$main_color" "mode")"
wizard_mode="Wizardy"
advanced_mode="Advanced Wizardy"

mode=$(gum choose "$wizard_mode" "$advanced_mode")

if grep -q "$advanced_mode" <<<"$mode"; then
    load_from_env_file "advanced"
    echo -e "Current configuration:"
    cat $env_file
    confirm=$(gum confirm "Do you want to run this script with this configuration?")
    if [ "$confirm" != "yes" ]; then
        exit 0
    fi
else



    MONIKER=$(gum input --cursor.foreground "${main_color}" \
        --prompt.foreground "${main_color}" \
        --prompt "Choose a moniker for your node: " \
        --placeholder "$MONIKER" \
        --width 80 \
        --value "$MONIKER")

    MONIKER=$(echo "$MONIKER" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')


    WORKING_DIRECTORY=$(gum input --cursor.foreground "${main_color}" \
        --prompt.foreground "${main_color}" \
        --prompt "Choose a working directory: " \
        --placeholder "$WORKING_DIRECTORY" \
        --width 80 \
        --value "$WORKING_DIRECTORY")

    echo -e "Now, what type(s) of node is $(gum style --foreground "$main_color" "$MONIKER")? (use space to select which type(s)"

    validator_string="Validator"
    # orchestrator_string="Orchestrator"
    miner_string="Miner"

    # NODE_TYPE=$(gum choose --no-limit "$validator_string" "$orchestrator_string" "$miner_string")
    node_type=$(gum choose --no-limit "$validator_string" "$miner_string")

    grep -q "$validator_string" <<<"$node_type" && is_validator="pending"
    # grep -q "$orchestrator_string" <<<"$NODE_TYPE" && is_orchestrator="pending"
    grep -q "$miner_string" <<<"$node_type" && is_miner="pending"

    clear
    update_header

    export MONIKER WORKING_DIRECTORY

    gum spin -s line --title "Setting up working directory and cloning node repository..." -- setup_work_dir
    setup_work_dir

    if grep -q "$validator_string" <<<"$node_type"; then

        # echo -e "Please apply to be a $(gum style --foreground "$main_color" "validator") node here: https://forms.gle/3fQQHVJbHqTPpmy58"

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

            docker run --rm -v nesachain-data:/app/.nesachain -e MONIKER="$MONIKER" -e CHAIN_ID="$chain_id" -p 26656:26656 -p 26657:26657 -p 1317:1317 -p 9090:9090 -p 2345:2345 $chain_container

            ./import_key.expect "$MONIKER" "$PRIV_KEY" "$chain_container" "$PASSWORD"


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
  


        # docker run --entrypoint nesad \
        #         -e MONIKER="$MONIKER" \
        #         -e PRIV_KEY="$PRIV_KEY" \
        #         -v nesachain-data:/app/.nesachain/ \
        #         "$chain_container" \
        #         tx poa create-validator validator.json --from="$MONIKER" --chain-id="$chain_id" --keyring-backend="test" --gas auto --gas-adjustment 1.5 
    fi

    if grep -q "$miner_string" <<<"$node_type"; then

        echo -e "Now, what type of miner will $(gum style --foreground "$main_color" "$MONIKER") be?"
        distributed_string="Distributed Miner"
        non_distributed_string="Non-Distributed Miner"

        miner_type=$(gum choose "$distributed_string" "$non_distributed_string")


        if grep -q "$miner_type" <<<"$distributed_string"; then

            echo -e "Would you like to join an existing $(gum style --foreground "$main_color" "swarm") or start a new one?"
            existing_swarm="Join existing swarm"
            new_swarm="Start a new swarm"

            distributed_type=$(gum choose "$existing_swarm" "$new_swarm")

            if grep -q "$distributed_type" <<<"$new_swarm"; then
                MODEL_NAME=$(
                    gum input --cursor.foreground "${main_color}" \
                        --prompt.foreground "${main_color}" \
                        --prompt "Which model would you like to run? (meta-llama/Llama-2-13b-Chat-Hf)" \
                        --placeholder "$MODEL_NAME" \
                        --width 80 \
                        --value "$MODEL_NAME"
                )

                HUGGINGFACE_API_KEY=$(
                    gum input --cursor.foreground "${main_color}" \
                        --prompt.foreground "${main_color}" \
                        --prompt "Please provide your Huggingface API key:" \
                        --placeholder "$MODEL_NAME" \
                        --width 80 \
                        --value "$MODEL_NAME"
                )

                # here I need to save the model name to an environment variable/config, and then spin up the orchestrator
                # which will read the model it wants to load from the env variable.
                # note: it's important that the orchestrator reads the model from the env and then registers itself on chain for that model.
                # otherwise nobody will ever connect to

            else # existing swarm
                # I need to query the blockchain to get the list of models that currently have swarms they can join
                # and then it needs to allow them to select one using gum choose (assuming there aren't too many options)
                # then whichever one they choose I can take the address of that swarm's agent and build the orchestrator address 
                # and set it to an environment variable so the new block miner can connect to the desired swarm
                swarms_map=$(get_swarms_map)
                model_names=$(get_model_names "$swarms_map")
                echo -e "Which existing $(gum style --foreground "$main_color" "swarm") would you like to join?"
                MODEL_NAME=$(echo "$model_names" | gum choose --no-limit)
            fi

        else # non-distributed setup

            MODEL_NAME=$(
                gum input --cursor.foreground "${main_color}" \
                    --prompt.foreground "${main_color}" \
                    --prompt "Which model would you like to run? ()" \
                    --placeholder "$MODEL_NAME" \
                    --width 80 \
                    --value "$MODEL_NAME"
            )

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

# when the configuration is all said and done we need to make sure to expore the variables that need to be passed down and/or saved
# for any future runs

# finally we spin up the docker compose for all of the containers that are needed based on the config

cd "$WORKING_DIRECTORY/docker"

# Temp while testing
# docker run --rm -v nesachain-data:/app/.nesachain -p 26656:26656 -p 26657:26657 -p 1317:1317 -p 9090:9090 -p 2345:2345 -d "$chain_container"

compose_up
cd "$init_pwd"

echo -e "Congratulations! Your $(gum style --foreground "$main_color" "nesa") node was successfully bootstrapped!"
# set +x