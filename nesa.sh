#!/bin/bash

#########
### vars
#########

terminal_size=$(stty size)
terminal_height=${terminal_size% *}
terminal_width=${terminal_size#* }

prompt_height=${PROMPT_HEIGHT:-1}

input_width=80
left_padding=$(( (terminal_width - input_width) / 2 ))


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
moniker=$(hostname)
domain=".nesa.sh"


#########
### basic helper functions
#########

# print if the output fi ts on screen
print_test() {
	local no_color=$(printf '%b' "${1}" | sed -e 's/\x1B\[[0-9;]*[JKmsu]//g')
  local max_length=$(max_line_length "$no_color")

	[ "$(printf '%s' "${no_color}" | wc -l)" -gt $(( terminal_height - prompt_height )) ] && return 1
	# [ "$(printf '%s' "${no_color}" | wc -L)" -gt "${terminal_width}" ] && return 1
  [ "$max_length" -gt "$terminal_width" ] && return 1



	gum style --align center --width="${terminal_width}" "${1}" ''
	printf '%b' "\033[A"
}

update_header() {
  info=$(gum style "[1;38;5;${main_color}m  ${moniker}[0m${domain}
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
        CYGWIN*|MINGW32*|MSYS*|MINGW*)
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

# calculate max line length of the input
max_line_length() {
    local max_len=0
    local line_len
    IFS=$'\n'
    for line in $1; do
        line_len=${#line}
        if (( line_len > max_len )); then
            max_len=$line_len
        fi
    done
    echo $max_len
}



#########
### bootstrap core logic
#########


# Check if gum is installed
if ! command_exists gum; then
    echo "Gum is not installed. Proceeding with installation..."
    install_gum
fi

clear; update_header
moniker=$(gum input --cursor.foreground "${main_color}" \
          --prompt.foreground "${main_color}"\
          --prompt "Choose a moniker for your node: " \
          --placeholder "$moniker" \
          --width 80 \
          --value "$moniker")

echo "Now, what type(s) of node is ${moniker}?"

VALIDATOR="Validator"
ORCHESTRATOR="Orchestrator"
MINER="Miner"

NODE_TYPE=$(gum choose --no-limit "$VALIDATOR" "$ORCHESTRATOR" "$MINER")


grep -q "$VALIDATOR" <<< "$NODE_TYPE" && is_validator="yes"
grep -q "$ORCHESTRATOR" <<< "$NODE_TYPE" && is_orchestrator="yes"
grep -q "$MINER" <<< "$NODE_TYPE" && is_miner="yes"

clear;update_header

grep -q "$VALIDATOR" <<< "$NODE_TYPE" && gum spin -s line --title "Configuring ${moniker} as a validator..." -- sleep 2
grep -q "$ORCHESTRATOR" <<< "$NODE_TYPE" && gum spin -s pulse --title "Configuring ${moniker} as an orchestrator..." -- sleep 2
grep -q "$MINER" <<< "$NODE_TYPE" && gum spin -s monkey --title "Configuring ${moniker} as a inference miner..." -- sleep 2

