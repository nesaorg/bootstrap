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
#   noteworthy conventions: variables that are exported to the config file or the container environment files are in all caps

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
miner_type_none=0
miner_type_non_distributed=1
miner_type_distributed=2

distributed_type_none=0
distributed_type_new_swarm=1
distributed_type_existing_swarm=2

# this will never load from the env file, but if they know to override it via ENV vars then they can
WORKING_DIRECTORY=${WORKING_DIRECTORY:-"$HOME/.nesa"}
env_dir="$WORKING_DIRECTORY/env"

agent_env_file="$env_dir/agent.env"
bsns_s_env_file="$env_dir/bsns-s.env"
bsns_c_env_file="$env_dir/bsns-c.env"
orchestrator_env_file="$env_dir/orchestrator.env"
base_env_file="$env_dir/base.env"
config_env_file="$env_dir/.env"

init_pwd=$PWD # so they can get back to where they started!

status="booting" # lol not really doing anything with this currently

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
  [1;38;5;${main_color}mchain:         [0m${IS_CHAIN}
  [1;38;5;${main_color}mvalidator:     [0m${IS_VALIDATOR}
  [1;38;5;${main_color}mminer:         [0m${IS_MINER}

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
    local excluded_node_ids
    local exclude_node_ids_json 
    local map=()

    excluded_node_ids=(
    "QmbtSFavybyKNkP2MAhVftA4S7tAW5HXvbKGiX9hHx9XqF|mistralai|Mixtral-8x7B-Instruct-v0.1" 
    "QmR58ndfebR3LXNxT5qx3FgXMkb4AptjpDM83r1CXfAhAw|mistralai|Mixtral-8x7B-Instruct-v0.1"
    "Qmc6GZVS41EzzU5j13cy1pL3HjhwJfaf1N71cjp2zt18HX|Orenguteng|Llama-3-8B-Lexi-Uncensored" 
    "QmR4Gi37D1cPnihhkvRG9kRGtBtXYxwAYo92x6y1FYxmij|bigscience|bloom-560m"
    "QmeCvBP1N3BqDiQc7hGxNFgrtguVHncqGKChJJeMZtsM8C|randommodel"
    "QmUxwnuEKAEY9CnB4tEPKvmwK6h6pmuSN3V28vQ9A3s8qQ|randommodel22"
    )

    exclude_node_ids_json=$(printf '%s\n' "${excluded_node_ids[@]}" | jq -R . | jq -s .)

    json_data=$(curl -s "$url")

    
    map=$(echo "$json_data" | jq -r --argjson exclude_node_ids "$exclude_node_ids_json" '
        .orchestrators |
        map(select(.node_id | (contains("/") | not))) |
        map(select(.node_id as $id | $exclude_node_ids | index($id) | not)) |
        map(
            {
                "node_id": (.node_id | split("|")[0]),
                "organization": (.node_id | split("|")[1]),
                "model_name": (.node_id | split("|")[2]),
                "model_id": ((.node_id | split("|")[1]) + "/" + (.node_id | split("|")[2]))
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

create_combined_node_id() {
    local map="$1"
    local model_id="$2"

    local node_info
    node_info=$(echo "$map" | jq -r --arg model_id "$model_id" '
        .[] | select(.model_id == $model_id) | "\(.node_id)|\(.organization)|\(.model_name)"
    ')

    echo "$node_info"
}

fetch_network_address() {
    local recreated_node_id="$1"
    local url="https://lcd.test.nesa.ai/nesachain/dht/get_node/$recreated_node_id"
    local json_data
    local network_address

    json_data=$(curl -s "$url")
    network_address=$(echo "$json_data" | jq -r '.node.network_address')

    echo "$network_address"
}


update_config_var() {
    local file=$1
    local var=$2
    local value=$3
    local temp_file

    temp_file=$(mktemp)

    if grep -q "^$var=" "$file"; then
        # Use a temporary file to handle sed differences
        sed "s|^$var=.*|$var=$value|" "$file" > "$temp_file" && mv "$temp_file" "$file"
    else
        echo "$var=$value" >> "$file"
    fi

    # Clean up the temporary file if it still exists
    [ -f "$temp_file" ] && rm "$temp_file"
}


save_to_env_file() {
    # Config environment variables
    update_config_var "$config_env_file" "IS_CHAIN" "$IS_CHAIN"
    update_config_var "$config_env_file" "IS_VALIDATOR" "$IS_VALIDATOR"
    update_config_var "$config_env_file" "IS_MINER" "$IS_MINER"
    update_config_var "$config_env_file" "MINER_TYPE" "$MINER_TYPE"
    update_config_var "$config_env_file" "DISTRIBUTED_TYPE" "$DISTRIBUTED_TYPE"
    update_config_var "$config_env_file" "OP_EMAIL" "$OP_EMAIL"

    # Agent environment variables
    update_config_var "$agent_env_file" "VIRTUAL_HOST" "$NODE_HOSTNAME"
    update_config_var "$agent_env_file" "LETSENCRYPT_HOST" "$NODE_HOSTNAME"
    update_config_var "$agent_env_file" "LETSENCRYPT_EMAIL" "$OP_EMAIL"
    update_config_var "$agent_env_file" "CHAIN_ID" "$CHAIN_ID"
    update_config_var "$agent_env_file" "NODE_HOSTNAME" "$NODE_HOSTNAME"
    update_config_var "$agent_env_file" "MODEL_NAME" "$MODEL_NAME"
    update_config_var "$agent_env_file" "NODE_PRIV_KEY" "$NODE_PRIV_KEY"

    # bsns-s environment variables
    update_config_var "$bsns_s_env_file" "MODEL_NAME" "$MODEL_NAME"
    update_config_var "$bsns_s_env_file" "INITIAL_PEER" "$INITIAL_PEER"
    update_config_var "$bsns_s_env_file" "NODE_PRIV_KEY" "$NODE_PRIV_KEY"
    update_config_var "$bsns_s_env_file" "PUBLIC_IP" "$PUBLIC_IP"
    update_config_var "$bsns_s_env_file" "HUGGINGFACE_API_KEY" "$HUGGINGFACE_API_KEY"

    # bsns-c environment variables
    update_config_var "$bsns_c_env_file" "MODEL_NAME" "$MODEL_NAME"
    update_config_var "$bsns_c_env_file" "PUBLIC_IP" "$PUBLIC_IP"
    update_config_var "$bsns_c_env_file" "NODE_PRIV_KEY" "$NODE_PRIV_KEY"

    # Orchestrator environment variables
    update_config_var "$orchestrator_env_file" "IS_DIST" "$IS_DIST"
    update_config_var "$bsns_c_env_file" "MODEL_NAME" "$MODEL_NAME"
    update_config_var "$orchestrator_env_file" "HUGGINGFACE_API_KEY" "$HUGGINGFACE_API_KEY"
    update_config_var "$orchestrator_env_file" "MONIKER" "$MONIKER"

    # Base environment variables
    update_config_var "$base_env_file" "MONIKER" "$MONIKER"
    update_config_var "$base_env_file" "CHAIN_ID" "$CHAIN_ID"
}

display_config() {
    local exclude_keys=("HUGGINGFACE_API_KEY" "NODE_PRIV_KEY")
    local config_content

    config_content=$(cat "$config_env_file" "$agent_env_file" "$bsns_c_env_file" "$bsns_s_env_file" "$orchestrator_env_file" "$base_env_file" | sort | uniq)
    

    for key in "${exclude_keys[@]}"; do
        config_content=$(echo "$config_content" | grep -v "^$key=")
    done

    config_content=$(echo "$config_content" | grep -v "=$")

    config_content="\`\`\`Makefile\n$config_content\n\`\`\`"

    echo -e "$config_content" | gum format --type markdown --theme dracula 

}

compose_up() {
    local compose_files
    compose_files="compose.yml"

    if [[ "$IS_CHAIN" == "yes" ]] || [[ "$IS_VALIDATOR" == "yes" ]]; then
        compose_files+=" -f compose.chain.yml"
    fi 



    if [[ "$IS_MINER" == "yes" ]]; then
        if [[ "$MINER_TYPE" == "$miner_type_non_distributed" ]]; then
            compose_files+=" -f compose.non-dist.yml"
        elif [[ "$MINER_TYPE" == "$miner_type_distributed" ]]; then
            if [[ "$DISTRIBUTED_TYPE" == "$distributed_type_new_swarm" ]]; then
                compose_files+=" -f compose.bsns-c.yml"
            elif [[ "$DISTRIBUTED_TYPE" == "$distributed_type_existing_swarm" ]]; then
                compose_files+=" -f compose.bsns-s.yml"
            fi
        fi
    fi 

    docker compose -f $compose_files up -d --wait

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

    if [ -f "$bsns_c_env_file" ]; then
        source "$bsns_c_env_file"
    elif [ "$1" != "advanced" ]; then
        touch "$bsns_c_env_file"
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

    # defaults
    : ${IS_CHAIN:="yes"}
    : ${IS_VALIDATOR:="no"}
    : ${IS_MINER:="no"}
    : ${MINER_TYPE:=$MINER_TYPE_NONE}
    : ${DISTRIBUTED_TYPE:=$DISTRIBUTED_TYPE_NONE}

    # TODO: revisit below
    : ${PRIV_KEY:=""}
    : ${HUGGINGFACE_API_KEY:=""}
    : ${MODEL_NAME:=""}
}

load_from_env_file "wizard"

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
else


    MONIKER=${MONIKER:-$(hostname -s)}
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

    chain_string="Base"
    validator_string="Validator"
    miner_string="Miner"

    previous_node_type="$chain_string"

    if [[ "$IS_CHAIN" == "yes" ]]; then
        previous_node_type="$chain_string"
    fi

    if [[ "$IS_VALIDATOR" == "yes" ]]; then
        if [[ -n "$previous_node_type" ]]; then
            previous_node_type+=","
        fi
        previous_node_type+="$validator_string"
    fi

    if [[ "$IS_MINER" == "yes" ]]; then
        if [[ -n "$previous_node_type" ]]; then
            previous_node_type+=","
        fi
        previous_node_type+="$miner_string"
    fi

    node_type=$(gum choose --no-limit "$chain_string" "$validator_string" "$miner_string" --selected "$previous_node_type")

    grep -q "$chain_string" <<<"$node_type" && IS_CHAIN="yes" || IS_CHAIN="no"
    grep -q "$validator_string" <<<"$node_type" && IS_VALIDATOR="yes" || IS_VALIDATOR="no"
    grep -q "$miner_string" <<<"$node_type" && IS_MINER="yes" || IS_MINER="no"

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

            clear
            update_header
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

        docker run --rm --entrypoint nesad -v nesachain-data:/app/.nesachain $chain_container tx staking create-validator /app/.nesachain/validator.json --from "$MONIKER" --chain-id "$CHAIN_ID" --gas auto --gas-adjustment 1.5 --node https://rpc.test.nesa.ai
  
    fi

    if grep -q "$miner_string" <<<"$node_type"; then        
        clear
        update_header 

        prompt_for_node_pk=0

     if [ -n "$NODE_PRIV_KEY" ]; then
            if ! gum confirm "Do you want to use the existing private key? "; then
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

     
        if [[ "$MINER_TYPE" == "$miner_type_distributed" ]]; then
            default_miner_choice="$distributed_string"
        else
            default_miner_choice="$non_distributed_string"
        fi


        selected_miner_type=$(gum choose "$distributed_string" "$non_distributed_string" --selected "$default_miner_choice")


        clear
        update_header

        if grep -q "$selected_miner_type" <<<"$distributed_string"; then
            IS_DIST=True # TODO: update containers to rely on DISTRIBUTED_TYPE instead of IS_DIST
            MINER_TYPE=$miner_type_distributed

            
            echo -e "Would you like to join an existing $(gum style --foreground "$main_color" "swarm") or start a new one?"
            existing_swarm="Join existing swarm"
            new_swarm="Start a new swarm"


            if [[ "$DISTRIBUTED_TYPE" == "$distributed_type_new_swarm" ]]; then
                default_swarm_choice="$new_swarm"
            else
                default_swarm_choice="$existing_swarm"
            fi


            selected_distributed_type=$(gum choose "$existing_swarm" "$new_swarm" --selected "$default_swarm_choice")

            clear
            update_header

            if grep -q "$selected_distributed_type" <<<"$new_swarm"; then
                DISTRIBUTED_TYPE=$distributed_type_new_swarm
                MODEL_NAME=$(
                    gum input --cursor.foreground "${main_color}" \
                        --prompt.foreground "${main_color}" \
                        --prompt "Which model would you like to run? " \
                        --placeholder "$MODEL_NAME" \
                        --width 80 \
                        --value "$MODEL_NAME"
                )


            else 
                DISTRIBUTED_TYPE=$distributed_type_existing_swarm
                swarms_map=$(get_swarms_map)
                model_names=$(get_model_names "$swarms_map")
                echo -e "Which existing $(gum style --foreground "$main_color" "swarm") would you like to join?"
                MODEL_NAME=$(echo "$model_names" | gum choose)

                initial_peer_id=$(get_node_id "$swarms_map" "$MODEL_NAME") 
                node_lookup_id=$(create_combined_node_id "$swarms_map" "$MODEL_NAME")
                initial_peer_ip=$(fetch_network_address "$node_lookup_id") 

                INITIAL_PEER="/ip4/$initial_peer_ip/tcp/31330/p2p/$initial_peer_id"                

            fi

        else
            MINER_TYPE=$miner_type_non_distributed
            DISTRIBUTED_TYPE=$distributed_type_none
            MODEL_NAME=$(
                gum input --cursor.foreground "${main_color}" \
                    --prompt.foreground "${main_color}" \
                    --prompt "Which model would you like to run?" \
                    --placeholder "nlptown/bert-base-multilingual-uncased-sentiment" \
                    --width 80 \
                    --value "$MODEL_NAME"
            )
            
    
        fi
        clear
        update_header
    
        HUGGINGFACE_API_KEY=$(
            gum input --cursor.foreground "${main_color}" \
                --prompt.foreground "${main_color}" \
                --prompt "Please provide your Huggingface API key: " \
                --password \
                --placeholder "$HUGGINGFACE_API_KEY" \
                --width 120 \
                --value "$HUGGINGFACE_API_KEY"
            )
        
    else
        MINER_TYPE=$miner_type_none
        DISTRIBUTED_TYPE=$distributed_type_none
    fi

    save_to_env_file
fi


clear
update_header

display_config

if ! gum confirm "Do you want to start the node with the above configuration? "; then
    echo "Configuration saved. You can modify the configuration manually, run the wizard again, or you can simply use advanced wizardry to boot your node."
    exit 0
fi

cd "$WORKING_DIRECTORY/docker" || {
    echo -e "Error changing to working directory: $WORKING_DIRECTORY/docker"
    exit 1
}

compose_up


cd "$init_pwd" || return
echo -e "Congratulations! Your $(gum style --foreground "$main_color" "nesa") node was successfully bootstrapped!"
# set +x