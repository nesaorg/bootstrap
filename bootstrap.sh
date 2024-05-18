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

MONIKER=$(hostname)
WORKING_DIRECTORY="$HOME/nesa"
MNEMONIC=${PRIV_KEY:}
chain_id="nesa-testnet-3"
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

address="pending"
is_validator="no"
is_orchestrator="no"
is_miner="no"
online="booting"
domain=".nesa.sh"

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
  [1;38;5;${main_color}morchestrator:  [0m${is_orchestrator}
  [1;38;5;${main_color}mminer:         [0m${is_miner}
  [1;38;5;${main_color}monline:        [0m${online}")
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
        if command_exists pacman; then
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
        gum spin -s line --title "Installing jq..." -- install_jq
    fi
}

install_jq() {
    case "$(uname -s)" in
    Linux)
        if command -v apt-get &>/dev/null; then
            sudo apt-get update && sudo apt-get install -y jq
        elif command -v yum &>/dev/null; then
            sudo yum install -y jq
        elif command -v pacman &>/dev/null; then
            sudo pacman -Sy jq
        elif command -v zypper &>/dev/null; then
            sudo zypper install -y jq
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y jq
        else
            echo "Package manager not found. Please install jq manually."
            exit 1
        fi
        ;;
    Darwin)
        if command -v brew &>/dev/null; then
            brew install jq
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

setup_work_dir() {
    if [ ! -d "$WORKING_DIRECTORY" ]; then
        mkdir -p "$WORKING_DIRECTORY"
        echo -e "Working directory created at $WORKING_DIRECTORY"
    fi

    cd "$WORKING_DIRECTORY" || {
        echo -e "Error changing to working directory: $WORKING_DIRECTORY"
        exit 1
    }

    # Clone or pull the latest changes if the repo already exists
    if [ ! -d "docker" ]; then
        echo "Cloning the nesaorg/docker repository..."
        git clone https://github.com/nesaorg/docker.git
    else
        echo "Repository already exists. Pulling latest updates..."
        cd docker && git pull && cd ..
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


#
# bootstrap core logic
#

# deps
check_gum_installed
# check_jq_installed

clear
update_header

MONIKER=$(gum input --cursor.foreground "${main_color}" \
    --prompt.foreground "${main_color}" \
    --prompt "Choose a moniker for your node: " \
    --placeholder "$MONIKER" \
    --width 80 \
    --value "$MONIKER")

WORKING_DIRECTORY=$(gum input --cursor.foreground "${main_color}" \
    --prompt.foreground "${main_color}" \
    --prompt "Choose a working directory: " \
    --placeholder "$WORKING_DIRECTORY" \
    --width 80 \
    --value "$WORKING_DIRECTORY")

echo -e "Now, what type(s) of node is $(gum style --foreground "$main_color" "$MONIKER")?"

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

if grep -q "$validator_string" <<<"$node_type"; then

    if true; then
        echo -e "Please apply to be a $(gum style --foreground "$main_color" "validator") node here: https://forms.gle/3fQQHVJbHqTPpmy58"
    else
        # keeping this here for now
        if [ ! -n "$PRIV_KEY" ]; then
            PRIV_KEY=$(gum input --cursor.foreground "${main_color}" \ 
                --password \
                --prompt.foreground "${main_color}" \
                --prompt "Validator's Private Key: " \
                --width 80)


            # currently we aren't generating the keys for the validator
            # will revisit this after initial launch

            # export MNEMONIC=$(gum spin -s line --title "Generating your validator key and mnemonic..." -- bash -c '
            #     docker run --rm --entrypoint nesad \
            #         -e MONIKER="$MONIKER" \
            #         docker pull ghcr.io/nesaorg/nesachain/nesachain:2024.05.13-02.30-ca95b04 \
            #         keys add "$MONIKER" --output json | jq -r ".mnemonic"
            # ')

            # echo -e "Your validator mnemonic is: $MNEMONIC"
        fi

        nesad keys import-hex "$MONIKER" "$PRIV_KEY"

        # debug this below
        nesad tendermint show-validator | jq -n \
            --arg moniker "$MONIKER" \
            '{
                pubkey: {
                    "@type": .["@type"],
                    key: .key
                },
                amount: "100000000000unes",
                moniker: "epin",
                "commission-rate": "0.10",
                "commission-max-rate": "0.20",
                "commission-max-change-rate": "0.01",
                "min-self-delegation": "1"
            }' > validator.json && nesad tx staking create-validator validator.json --from "$MONIKER" --chain-id "$chain_id"
    fi

fi

# if grep -q "$orchestrator_string" <<<"$NODE_TYPE"; then
    
#     sleep 2
# fi

if grep -q "$miner_string" <<<"$node_type"; then

    echo -e "Now, what type of miner will $(gum style --foreground "$main_color" "$MONIKER") be?"
    distributed_string="Distributed Miner"
    non_distributed_string="Non-Distributed Miner"

    miner_type=$(gum choose "$distributed_string" "$non_distributed_string")


    if grep -q "$distributed_string" <<<"$miner_type"; then

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
                --prompt "Which model would you like to run? (meta-llama/Llama-2-13b-Chat-Hf)" \
                --placeholder "$MODEL_NAME" \
                --width 80 \
                --value "$MODEL_NAME"
        )
    fi
fi


# when the configuration is all said and done we need to make sure to expore the variables that need to be passed down and/or saved
# for any future runs

# finally we spin up the docker compose for all of the containers that are needed based on the config

cd "$WORKING_DIRECTORY/docker"

gum spin -s line --title "Booting $(gum style --foreground "$main_color" "$MONIKER")..." -- docker-compose up -d
cd -
echo -e "Congratulations! Your $(gum style --foreground "$main_color" "nesa") node was successfully bootstrapped!?"



