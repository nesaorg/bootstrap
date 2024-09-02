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

trap 'trap " " SIGINT SIGTERM SIGHUP; kill 0; wait; sigterm_handler' SIGINT SIGTERM SIGHUP


sigterm_handler() {
    printf "\n Aborting node setup. Cleaning up...\n"
    # Add any additional cleanup tasks here
    echo; exit 1
}

# set -x
terminal_size=$(stty size)
terminal_height=${terminal_size% *}
terminal_width=${terminal_size#* }
prompt_height=${PROMPT_HEIGHT:-1}
main_color=43
link_color=69
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
node_id_file="$HOME/.nesa/identity/node_id.id"


miner_type_none=0
miner_type_non_distributed=1
miner_type_distributed=2
miner_type_agnostic=3

distributed_type_none=0
distributed_type_new_swarm=1
distributed_type_existing_swarm=2
distributed_type_agnostic=3

# this will never load from the env file, but if they know to override it via ENV vars then they can
WORKING_DIRECTORY=${WORKING_DIRECTORY:-"$HOME/.nesa"}
env_dir="$WORKING_DIRECTORY/env"

agent_env_file="$env_dir/agent.env"
bsns_s_env_file="$env_dir/bsns-s.env"
bsns_c_env_file="$env_dir/bsns-c.env"
orchestrator_env_file="$env_dir/orchestrator.env"
fluentbit_env_file="$env_dir/fluentbit.env"
base_env_file="$env_dir/base.env"
config_env_file="$env_dir/.env"
init_pwd=$PWD # so they can get back to where they started!
status="booting" # lol not really doing anything with this currently
ORC_PORT=31333

MONIKER=${MONIKER:-$(hostname -s)}
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
    local dashboard_url

    if [[ "$NODE_ID" == "pending..." ]]; then
        dashboard_url="https://node.nesa.ai"
    else
        dashboard_url="https://node.nesa.ai/nodes/$NODE_ID"
    fi
    
    info=$(gum style "[1;38;5;${main_color}m  ${MONIKER}[0m.${domain}
  ---------------- 
  [1;38;5;${main_color}mnode id:       [0m${NODE_ID}
  [1;38;5;${main_color}mdashboard:     [0;38;5;${link_color}m$dashboard_url[0m
  [1;38;5;${main_color}mvalidator:     [0m${IS_VALIDATOR}
  [1;38;5;${main_color}mminer:         [0m${IS_MINER}
  [1;38;5;${main_color}mstatus:        [0m${status}") 
    header=$(gum join --horizontal --align top "${logo}" '  ' "${info}")

    echo -e "\n"
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

# TODO: handle the need for sudo here -.-
# check_nvidia_installed() {
#     if ! command_exists nvidia-smi; then
#         echo "NVIDIA drivers are not installed. Please install NVIDIA drivers and try again."
#         exit 1
#     fi

#     if ! command_exists nvidia-container-runtime; then
#         sudo curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
#             && sudo curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
#             sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
#             sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

#         sudo apt-get update
#         sudo apt-get install -y nvidia-container-toolkit

#         sudo nvidia-ctk runtime configure --runtime=docker
#         sudo systemctl restart docker
#     fi
# }

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

get_linux_info() {
    local name version kernel architecture cpu cores ram disk_avail gpu gpu_count gpu_memory
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        name=$NAME
        version=$VERSION
    else
        name="Not Available"
        version="Not Available"
    fi
    kernel=$(uname -r)
    architecture=$(uname -m)
    cpu=$(lscpu | grep 'Model name' | awk -F: '{print $2}' | sed 's/^ *//')
    cores=$(lscpu | grep '^CPU(s):' | awk '{print $2}')
    ram=$(free -h | grep Mem | awk '{print $2}')
    disk_avail=$(df -h --total | grep total | awk '{print $4}')
    
    gpu=$(lspci | grep -i -e '3D controller' -e 'VGA compatible controller' | grep -i -e nvidia -e amd | awk -F: '{print $3}' | sed 's/^ *//')
    gpu_count=$(lspci | grep -i -e '3D controller' -e 'VGA compatible controller' | grep -i -e nvidia -e amd | wc -l | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    gpu_memory=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | awk '{total += $1} END {print total " MB"}')
    
    if [ -z "$gpu_memory" ]; then
        gpu_memory=$(lshw -C display 2>/dev/null | grep -i size | awk '{print $2 " " $3}' | head -n 1)
    fi

    NODE_OS="Linux $version"
    NODE_ARCH="$architecture"
    NODE_CPU="$cpu"
    NODE_CORES="$cores"
    NODE_GPU="${gpu:-NA}"
    NODE_GPU_COUNT="${gpu_count:-0}"
    NODE_RAM="$ram"
    NODE_VRAM="${gpu_memory:-NA}"
    NODE_DISK_AVAIL="$disk_avail"
}

get_macos_info() {
    local product_version build_version architecture cpu cores ram disk_avail gpu gpu_count gpu_memory
    product_version=$(sw_vers -productVersion)
    build_version=$(sw_vers -buildVersion)
    architecture=$(uname -m)
    cpu=$(sysctl -n machdep.cpu.brand_string)
    cores=$(sysctl -n hw.ncpu)
    ram=$(sysctl -n hw.memsize | awk '{print $1/1024/1024/1024 " GB"}')
    disk_avail=$(df -h / | grep / | awk '{print $4}')
    
    gpu=$(system_profiler SPDisplaysDataType | grep 'Chipset Model' | awk -F: '{print $2}' | sed 's/^ *//')
    gpu_count=$(system_profiler SPDisplaysDataType | grep 'Chipset Model' | wc -l | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    gpu_memory=$(system_profiler SPDisplaysDataType | grep 'VRAM' | awk -F: '{total += $2} END {print total " MB"}' | sed 's/^ *//')

    NODE_OS="MacOS $product_version ($build_version)"
    NODE_ARCH="$architecture"
    NODE_CPU="$cpu"
    NODE_CORES="$cores"
    NODE_GPU="${gpu:-NA}"
    NODE_GPU_COUNT="${gpu_count:-0}"
    NODE_RAM="$ram"
    NODE_VRAM="${gpu_memory:-NA}"
    NODE_DISK_AVAIL="$disk_avail"
}

get_windows_info() {
    local caption version architecture cpu cores ram disk_avail gpu gpu_count gpu_memory
    caption=$(wmic os get Caption /value | awk -F= '{print $2}')
    version=$(wmic os get Version /value | awk -F= '{print $2}')
    architecture=$(wmic os get OSArchitecture /value | awk -F= '{print $2}')
    cpu=$(wmic cpu get name /value | awk -F= '{print $2}')
    cores=$(wmic cpu get NumberOfCores /value | awk -F= '{print $2}')
    ram=$(wmic computersystem get totalphysicalmemory /value | awk -F= '{print $2/1024/1024/1024 " GB"}')
    disk_avail=$(wmic logicaldisk get size,freespace,caption | awk '{if ($1 == "C:") print $3/1024/1024/1024 " GB"}')
    
    gpu=$(wmic path win32_videocontroller get name /value | awk -F= '{print $2}')
    gpu_count=$(wmic path win32_videocontroller get name /value | grep -c "Name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    gpu_memory=$(wmic path win32_videocontroller get AdapterRAM /value | awk -F= '{total += $2} END {print total/1024/1024 " MB"}')

    NODE_OS="Windows $caption $version"
    NODE_ARCH="$architecture"
    NODE_CPU="$cpu"
    NODE_CORES="$cores"
    NODE_GPU="${gpu:-NA}"
    NODE_GPU_COUNT="${gpu_count:-0}"
    NODE_RAM="$ram"
    NODE_VRAM="${gpu_memory:-NA}"
    NODE_DISK_AVAIL="$disk_avail"
}

get_wsl_info() {
    local name version kernel architecture cpu cores ram disk_avail gpu gpu_count gpu_memory
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        name=$NAME
        version=$VERSION
    else
        name="Not Available"
        version="Not Available"
    fi
    kernel=$(uname -r)
    architecture=$(uname -m)
    cpu=$(grep -m1 'model name' /proc/cpuinfo | awk -F: '{print $2}' | sed 's/^ *//')
    cores=$(grep -c '^processor' /proc/cpuinfo)
    ram=$(free -h | grep Mem | awk '{print $2}')
    disk_avail=$(df -h --total | grep total | awk '{print $4}')

    if command -v nvidia-smi &> /dev/null; then
        gpu=$(nvidia-smi --query-gpu=name --format=csv,noheader)
        gpu_count=$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)
        gpu_memory=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | awk '{total += $1} END {print total " MB"}')
    else
        gpu="NA"
        gpu_count=0
        gpu_memory="NA"
    fi

    NODE_OS="WSL $version ($kernel)"
    NODE_ARCH="$architecture"
    NODE_CPU="$cpu"
    NODE_CORES="$cores"
    NODE_GPU="${gpu:-NA}"
    NODE_GPU_COUNT="${gpu_count:-0}"
    NODE_RAM="$ram"
    NODE_VRAM="${gpu_memory:-NA}"
    NODE_DISK_AVAIL="$disk_avail"
}


detect_hardware_capabilities() {
    case "$(uname -s)" in
        Linux)
            if grep -q Microsoft /proc/version; then
                get_wsl_info
            else
                get_linux_info
            fi
            ;;
        Darwin)
            get_macos_info
            ;;
        CYGWIN*|MINGW*|MSYS*)
            get_windows_info
            ;;
        *)
            echo "Unsupported platform"
            ;;
    esac
}

setup_work_dir() {
    if [ ! -d "$WORKING_DIRECTORY" ]; then
        mkdir -p "$WORKING_DIRECTORY"
    fi

    cd "$WORKING_DIRECTORY" || {
        echo -e "Error changing to working directory: $WORKING_DIRECTORY"
        exit 1
    }

    setup_docker_repository
}

setup_docker_repository() {
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
        sed "s|^$var=.*|$var=\"$value\"|" "$file" > "$temp_file" && mv "$temp_file" "$file"
    else
        echo "$var=\"$value\"" >> "$file"
    fi

    # Clean up the temporary file if it still exists
    [ -f "$temp_file" ] && rm "$temp_file"
}

strip_0x_prefix() {
    local key="$1"
    # Remove 0x prefix if present
    echo "${key#0x}"
}

save_to_env_file() {
    # Config environment variables
    update_config_var "$config_env_file" "IS_CHAIN" "$IS_CHAIN"
    update_config_var "$config_env_file" "IS_VALIDATOR" "$IS_VALIDATOR"
    update_config_var "$config_env_file" "IS_MINER" "$IS_MINER"
    update_config_var "$config_env_file" "MINER_TYPE" "$MINER_TYPE"
    update_config_var "$config_env_file" "DISTRIBUTED_TYPE" "$DISTRIBUTED_TYPE"

    # Agent environment variables
    update_config_var "$agent_env_file" "VIRTUAL_HOST" "$NODE_HOSTNAME"
    update_config_var "$agent_env_file" "LETSENCRYPT_HOST" "$NODE_HOSTNAME"
    update_config_var "$agent_env_file" "LETSENCRYPT_EMAIL" "$OP_EMAIL"
    update_config_var "$agent_env_file" "CHAIN_ID" "$CHAIN_ID"
    update_config_var "$agent_env_file" "NODE_HOSTNAME" "$NODE_HOSTNAME"
    update_config_var "$agent_env_file" "NODE_PRIV_KEY" "$NODE_PRIV_KEY"

    # bsns-s environment variables
    update_config_var "$bsns_s_env_file" "INITIAL_PEER" "$INITIAL_PEER"
    update_config_var "$bsns_s_env_file" "NODE_PRIV_KEY" "$NODE_PRIV_KEY"
    update_config_var "$bsns_s_env_file" "HUGGINGFACE_API_KEY" "$HUGGINGFACE_API_KEY"


    # bsns-c environment variables
    update_config_var "$bsns_c_env_file" "PUBLIC_IP" "$PUBLIC_IP"
    update_config_var "$bsns_c_env_file" "NODE_PRIV_KEY" "$NODE_PRIV_KEY"

    # Orchestrator environment variables
    update_config_var "$orchestrator_env_file" "IS_DIST" "$IS_DIST"
    update_config_var "$orchestrator_env_file" "HUGGINGFACE_API_KEY" "$HUGGINGFACE_API_KEY"
    update_config_var "$orchestrator_env_file" "MONIKER" "$MONIKER"
    update_config_var "$orchestrator_env_file" "NESA_NODE_TYPE" "$NESA_NODE_TYPE"
    update_config_var "$orchestrator_env_file" "NODE_PRIV_KEY" "$NODE_PRIV_KEY"

    # Base environment variables
    update_config_var "$base_env_file" "MODEL_NAME" "$MODEL_NAME"
    update_config_var "$base_env_file" "MONIKER" "$MONIKER"
    update_config_var "$base_env_file" "OP_EMAIL" "$OP_EMAIL"
    update_config_var "$base_env_file" "REF_CODE" "$REF_CODE"
    update_config_var "$base_env_file" "PUBLIC_IP" "$PUBLIC_IP"
    update_config_var "$base_env_file" "ORC_PORT" "$ORC_PORT"
    update_config_var "$base_env_file" "NODE_OS" "$NODE_OS"
    update_config_var "$base_env_file" "NODE_ARCH" "$NODE_ARCH"
    update_config_var "$base_env_file" "NODE_CPU" "$NODE_CPU"
    update_config_var "$base_env_file" "NODE_CORES" "$NODE_CORES"
    update_config_var "$base_env_file" "NODE_RAM" "$NODE_RAM"
    update_config_var "$base_env_file" "NODE_GPU" "$NODE_GPU"
    update_config_var "$base_env_file" "NODE_GPU_COUNT" "$NODE_GPU_COUNT"
    update_config_var "$base_env_file" "NODE_VRAM" "$NODE_VRAM"
}

display_config() {
    local exclude_keys=("HUGGINGFACE_API_KEY" "NODE_PRIV_KEY")
    local config_content

    config_content=$(cat "$config_env_file" "$agent_env_file" "$bsns_c_env_file" "$bsns_s_env_file" "$orchestrator_env_file" "$base_env_file" | sort | uniq)
     

    for key in "${exclude_keys[@]}"; do
        config_content=$(echo "$config_content" | grep -v "^$key=")
    done

    config_content=$(echo "$config_content" | grep -v "=$")


    if [[ -n "$NODE_ID" && "$NODE_ID" != "pending..." ]]; then
        config_content="$config_content"$'\n'"NODE_ID=$NODE_ID"
    fi

    config_content="\`\`\`Makefile\n$config_content\n\`\`\`"

    echo -e "$config_content" | gum format --type markdown --theme dracula 

}


compose_up() {
    local compose_files="compose.yml"
    local nvidia_present=$(command -v nvidia-smi)
    local compose_ext=".yml"
    
    cd "$WORKING_DIRECTORY/docker" || {
        echo "Error: Docker directory does not exist."
        exit 1
    }

    if [[ -n "$nvidia_present" ]]; then
        compose_ext=".nvidia.yml"
    fi

    if [[ "$NESA_NODE_TYPE" == "community" ]]; then
        compose_files="compose.community${compose_ext}"
    else
        if [[ "$IS_CHAIN" == "yes" ]] || [[ "$IS_VALIDATOR" == "yes" ]]; then
            compose_files+=" -f compose.chain.yml"
        fi 

        if [[ "$IS_MINER" == "yes" ]]; then
            if [[ "$MINER_TYPE" == "$miner_type_non_distributed" ]]; then
                compose_files+=" -f compose.non-dist${compose_ext}"
            elif [[ "$MINER_TYPE" == "$miner_type_distributed" ]]; then
                if [[ "$DISTRIBUTED_TYPE" == "$distributed_type_new_swarm" ]]; then
                    compose_files+=" -f compose.bsns-c${compose_ext}"
                elif [[ "$DISTRIBUTED_TYPE" == "$distributed_type_existing_swarm" ]]; then
                    compose_files+=" -f compose.bsns-s${compose_ext}"
                fi
            fi
        fi 
    fi

    docker--compose -f $compose_files up --pull always -d --wait

    if [[ $? -ne 0 ]]; then
        echo "Error: Docker Compose failed to start."
        exit 1
    else
        echo "Docker Compose started successfully."
    fi
}

load_node_id() {
    if [[ -f "$node_id_file" ]]; then
        # Read the value from the file into an environment variable
        NODE_ID=$(cat "$node_id_file")
    else
        # Set the environment variable to an empty string or default value
        NODE_ID="pending..."
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

    if [ -f "$fluentbit_env_file" ]; then
        source "$fluentbit_env_file"
    elif [ "$1" != "advanced" ]; then
        touch "$fluentbit_env_file"
    fi

    if [ -f "$base_env_file" ]; then
        source "$base_env_file"
    elif [ "$1" != "advanced" ]; then
        touch "$base_env_file"
    fi

    # defaults
    : ${IS_CHAIN:="no"}
    : ${IS_VALIDATOR:="no"}
    : ${IS_MINER:="no"}
    : ${MINER_TYPE:=$MINER_TYPE_NONE}
    : ${DISTRIBUTED_TYPE:=$DISTRIBUTED_TYPE_NONE}
    : ${NESA_NODE_TYPE:="community"}

    # TODO: revisit below
    : ${PRIV_KEY:=""}
    : ${HUGGINGFACE_API_KEY:=""}
    : ${MODEL_NAME:=""}
    : ${REF_CODE:=""}
}

load_from_env_file "wizard"
load_node_id
# don't use cached/saved values for these 
PUBLIC_IP=$(curl -s4 ifconfig.me)

#
# bootstrap core logic
#

# deps
check_gum_installed
check_docker_installed
check_jq_installed
# check_nvidia_installed
detect_hardware_capabilities
clear
update_header


echo -e "Select a $(gum style --foreground "$main_color" "mode")"
wizard_mode="Wizardy"
advanced_mode="Advanced Wizardy"

mode=$(gum choose "$wizard_mode" "$advanced_mode")

clear
update_header

gum spin -s line --title "Setting up working directory and cloning node repository..." -- setup_work_dir
setup_work_dir

if grep -q "$advanced_mode" <<<"$mode"; then
    load_from_env_file "advanced"
else


    MONIKER=$(gum input --cursor.foreground "${main_color}" \
        --prompt.foreground "${main_color}" \
        --prompt "Choose a moniker for your node: " \
        --placeholder "$MONIKER" \
        --width 80 \
        --value "$MONIKER")

    MONIKER=$(echo "$MONIKER" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    clear
    update_header

    if [[ "$NESA_NODE_TYPE" == "nesa" ]]; then 
        NODE_HOSTNAME=${NODE_HOSTNAME:-"$MONIKER.yourdomain.tld"}
        NODE_HOSTNAME=$(gum input --cursor.foreground "${main_color}" \
            --prompt.foreground "${main_color}" \
            --prompt "What will $(gum style --foreground "main_color" "$MONIKER")'s hostname be? " \
            --placeholder "$NODE_HOSTNAME" \
            --width 80 \
            --value "$NODE_HOSTNAME")

        clear
        update_header
    else
        NODE_HOSTNAME=${NODE_HOSTNAME:-"$MONIKER"}
    fi

    OP_EMAIL=${OP_EMAIL:-"admin@$NODE_HOSTNAME"}
    OP_EMAIL=$(gum input --cursor.foreground "${main_color}" \
        --prompt.foreground "${main_color}" \
        --prompt "What is the email of the node operator? " \
        --placeholder "$OP_EMAIL" \
        --width 80 \
        --value "$OP_EMAIL")


    REF_CODE=$(gum input --cursor.foreground "${main_color}" \
        --prompt.foreground "${main_color}" \
        --prompt "if you have a referral code, enter it here to receive bonus points: " \
        --placeholder "nesa1j6y248qnuawdnd7dtc3hg47jlzfj3jzwqv8rkq" \
        --width 160 \
        --value "$REF_CODE")


    HUGGINGFACE_API_KEY=$(
            gum input --cursor.foreground "${main_color}" \
                --prompt.foreground "${main_color}" \
                --prompt "Please provide your Huggingface API key: " \
                --password \
                --placeholder "$HUGGINGFACE_API_KEY" \
            --width 160 \
            --value "$HUGGINGFACE_API_KEY"
        )

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
                --width 160)
        fi

        NODE_PRIV_KEY=$(strip_0x_prefix "$NODE_PRIV_KEY")


    clear
    update_header




    if [[ "$NESA_NODE_TYPE" == "nesa" ]]; then

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

        node_type=$(gum choose "$validator_string" "$miner_string" --selected "$previous_node_type")

        grep -q "$chain_string" <<<"$node_type" && IS_CHAIN="yes" || IS_CHAIN="no"
        grep -q "$validator_string" <<<"$node_type" && IS_VALIDATOR="yes" || IS_VALIDATOR="no"
        grep -q "$miner_string" <<<"$node_type" && IS_MINER="yes" || IS_MINER="no"

        clear
        update_header

        if grep -q "$validator_string" <<<"$node_type"; then
            
            echo -e "We are only bootstrapping miner nodes at the moment."
            echo -e "Please apply to run a $(gum style --foreground "$main_color" "validator") node here: https://forms.gle/3fQQHVJbHqTPpmy58"
            exit 1

            # download_import_key_expect

            # if [ ! -n "$PRIV_KEY" ]; then
            #     PRIV_KEY=$(gum input --cursor.foreground "${main_color}" \
            #         --password \
            #         --prompt.foreground "${main_color}" \
            #         --prompt "Validator's private key: " \
            #         --width 80)

            #     clear
            #     update_header
            #     PASSWORD=$(gum input --cursor.foreground "${main_color}" \
            #         --password \
            #         --prompt.foreground "${main_color}" \
            #         --prompt "Password for the private key: " \
            #         --width 80)

            #     docker pull ghcr.io/nesaorg/nesachain/nesachain:test
            #     docker volume create nesachain-data

            #     docker run --rm -v nesachain-data:/app/.nesachain -e MONIKER="$MONIKER" -e CHAIN_ID="$CHAIN_ID" -p 26656:26656 -p 26657:26657 -p 1317:1317 -p 9090:9090 -p 2345:2345 $chain_container

            #     "$WORKING_DIRECTORY/import_key.expect" "$MONIKER" "$PRIV_KEY" "$chain_container" "$PASSWORD"

            # fi

            # docker run --rm --entrypoint sh -v nesachain-data:/app/.nesachain -p 26656:26656 -p 26657:26657 -p 1317:1317 -p 9090:9090 -p 2345:2345 $chain_container -c '
            #     VAL_PUB_KEY=$(nesad tendermint show-validator | jq -r ".key") && \
            #     echo "VAL_PUB_KEY: $VAL_PUB_KEY" && \
            #     jq -n \
            #         --arg pubkey "$VAL_PUB_KEY" \
            #         --arg amount "100000000000unes" \
            #         --arg moniker "'"$MONIKER"'" \
            #         --arg chain_id "'"$CHAIN_ID"'" \
            #         --arg commission_rate "0.10" \
            #         --arg commission_max_rate "0.20" \
            #         --arg commission_max_change_rate "0.01" \
            #         --arg min_self_delegation "1" \
            #         '"'"'{
            #             pubkey: {"@type":"/cosmos.crypto.ed25519.PubKey", "key": $pubkey},
            #             amount: $amount,
            #             moniker: $moniker,
            #             "commission-rate": $commission_rate,
            #             "commission-max-rate": $commission_max_rate,
            #             "commission-max-change-rate": $commission_max_change_rate,
            #             "min-self-delegation": $min_self_delegation
            #         }'"'"' > /app/.nesachain/validator.json && \
            #     cat /app/.nesachain/validator.json
            # '

            # docker run --rm --entrypoint nesad -v nesachain-data:/app/.nesachain $chain_container tx staking create-validator /app/.nesachain/validator.json --from "$MONIKER" --chain-id "$CHAIN_ID" --gas auto --gas-adjustment 1.5 --node https://rpc.test.nesa.ai
    
        fi

        if grep -q "$miner_string" <<<"$node_type"; then        
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
                IS_DIST=False # deprecrated: update containers to rely on DISTRIBUTED_TYPE instead of IS_DIST
                MODEL_NAME=$(
                    gum input --cursor.foreground "${main_color}" \
                        --prompt.foreground "${main_color}" \
                        --prompt "Which model would you like to run? " \
                        --placeholder "nlptown/bert-base-multilingual-uncased-sentiment" \
                        --width 160 \
                        --value "$MODEL_NAME"
                )
                
        
            fi
            clear
            update_header    
        fi
    else
        MINER_TYPE=$miner_type_agnostic
        DISTRIBUTED_TYPE=$distributed_type_agnostic
        IS_MINER="yes"
        IS_DIST=False
    fi
fi


save_to_env_file

clear
update_header

display_config


if ! gum confirm "Do you want to start the node with the above configuration? "; then
    echo "Configuration saved. You can modify the configuration manually, run the wizard again, or you can simply use advanced wizardry to boot your node."
    exit 0
fi

cd "$WORKING_DIRECTORY/docker" || {
    echo "Error: Docker directory does not exist."
    exit 1
}

compose_up


cd "$init_pwd" || return
echo -e "Congratulations! Your $(gum style --foreground "$main_color" "nesa") node was successfully bootstrapped!"
# set +x
