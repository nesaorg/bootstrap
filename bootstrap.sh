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
#
#
#   noteworthy conventions: variables that are exported to the config file or the container environment files are in all caps

#
# vars
#

trap 'trap " " SIGINT SIGTERM SIGHUP; kill 0; wait; sigterm_handler' SIGINT SIGTERM SIGHUP

# Store the real script path for restarts
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# Detect OS early for platform-specific code
OS_TYPE="$(uname -s)"

# ---- global bootstrap logging (captures ALL stdout/err while keeping the screen interactive) ----
DEFAULT_WORKDIR="${HOME}/.nesa"
LOG_DIR="${DEFAULT_WORKDIR}/logs"
ENV_DIR="${DEFAULT_WORKDIR}/env"

# Create directories with error handling
if ! mkdir -p "${DEFAULT_WORKDIR}" "${LOG_DIR}" "${ENV_DIR}" 2>/dev/null; then
  echo "ERROR: Cannot create directory ${DEFAULT_WORKDIR}"
  echo "Please check permissions on your home directory."
  exit 1
fi

# Mirror STDOUT and STDERR to file; only the copy to file is timestamped.
# This preserves gum's interactive UI on the terminal.
# exec > >(tee >(awk '{ printf "[%s] %s\n", strftime("%Y-%m-%dT%H:%M:%SZ"), $0; fflush() }' >> "${LOG_DIR}/bootstrap.log"))
# exec 2> >(tee >(awk '{ printf "[%s] %s\n", strftime("%Y-%m-%dT%H:%M:%SZ"), $0; fflush() }' >> "${LOG_DIR}/bootstrap.log") >&2)
# -----------------------------------------------------------------------------------------------
LOG_FILE="${LOG_DIR}/bootstrap.log"
_ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log_line() { printf "[%s] %s\n" "$(_ts)" "$*" >>"$LOG_FILE" 2>/dev/null || true; }
log_stream() { while IFS= read -r line; do printf "[%s] %s\n" "$(_ts)" "$line" >>"$LOG_FILE"; done; }
run_and_log() {
  local title="$1"
  shift
  log_line "BEGIN: $title — $*"
  if gum spin -s line --title "$title" -- "$@" 2> >(log_stream) | log_stream; then
    log_line "END: $title (ok)"
    return 0
  else
    log_line "END: $title (fail)"
    return 1
  fi
}

# Safe math helper - works on both GNU and BSD (Mac) awk
# Usage: safe_divide <numerator> <divisor> <decimals>
safe_divide() {
  local num="${1:-0}"
  local div="${2:-1}"
  local dec="${3:-6}"
  # Handle empty or non-numeric input
  [ -z "$num" ] || [ "$num" = "" ] && num=0
  [ -z "$div" ] || [ "$div" = "" ] || [ "$div" = "0" ] && div=1
  awk -v n="$num" -v d="$div" -v p="$dec" 'BEGIN { printf "%.*f", p, n/d }'
}

# Safe multiply helper
# Usage: safe_multiply <num1> <num2> <decimals>
safe_multiply() {
  local num1="${1:-0}"
  local num2="${2:-1}"
  local dec="${3:-0}"
  [ -z "$num1" ] || [ "$num1" = "" ] && num1=0
  [ -z "$num2" ] || [ "$num2" = "" ] && num2=1
  awk -v a="$num1" -v b="$num2" -v p="$dec" 'BEGIN { printf "%.*f", p, a*b }'
}

# Safe JSON parsing helper
# Usage: safe_jq <json_string> <jq_filter> [default_value]
# Returns the jq result or default_value if parsing fails
safe_jq() {
  local json="$1"
  local filter="$2"
  local default="${3:-}"

  # Check if input looks like JSON (starts with { or [)
  if [[ -z "$json" ]] || [[ ! "$json" =~ ^[[:space:]]*[\{\[] ]]; then
    log_line "safe_jq: Invalid JSON input"
    echo "$default"
    return 1
  fi

  # Try to parse with jq
  local result
  result=$(echo "$json" | jq -r "$filter" 2>/dev/null)
  local jq_exit=$?

  # Check if jq failed or returned null/empty
  if [[ $jq_exit -ne 0 ]] || [[ -z "$result" ]] || [[ "$result" == "null" ]]; then
    log_line "safe_jq: jq filter '$filter' returned empty/null"
    echo "$default"
    return 1
  fi

  echo "$result"
  return 0
}

# Fetch JSON from URL with error handling
# Usage: fetch_json <url> [timeout_seconds]
# Returns JSON string or empty on failure
fetch_json() {
  local url="$1"
  local timeout="${2:-10}"
  local response

  response=$(curl -sfS --connect-timeout "$timeout" --max-time "$((timeout * 3))" "$url" 2>/dev/null)
  local curl_exit=$?

  if [[ $curl_exit -ne 0 ]] || [[ -z "$response" ]]; then
    log_line "fetch_json: Failed to fetch $url (curl exit: $curl_exit)"
    echo ""
    return 1
  fi

  # Validate it's JSON
  if ! echo "$response" | jq empty 2>/dev/null; then
    log_line "fetch_json: Response from $url is not valid JSON"
    echo ""
    return 1
  fi

  echo "$response"
  return 0
}

# Append to log file (don't truncate on restart)
touch "${LOG_FILE}" 2>/dev/null || true
log_line "=== Bootstrap session started ==="

# Create env files if they don't exist
touch "${ENV_DIR}/base.env" "${ENV_DIR}/orchestrator.env" "${DEFAULT_WORKDIR}/.env" 2>/dev/null || {
  echo "ERROR: Cannot create config files in ${ENV_DIR}"
  echo "Please check permissions."
  exit 1
}

sigterm_handler() {
  printf "\n Aborting node setup. Cleaning up...\n"
  # Add any additional cleanup tasks here
  echo
  exit 1
}

# Get terminal size with fallback for non-interactive terminals (SSH, tmux, etc.)
terminal_size=$(stty size 2>/dev/null || echo "24 80")
terminal_height="${terminal_size% *}"
terminal_width="${terminal_size#* }"
# Validate we got numbers, fallback if not
[[ "$terminal_height" =~ ^[0-9]+$ ]] || terminal_height=24
[[ "$terminal_width" =~ ^[0-9]+$ ]] || terminal_width=80
prompt_height=${PROMPT_HEIGHT:-1}
main_color=43
link_color=69

#
# EARLY DEPENDENCY CHECKS - must run before any gum usage
#

# check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check if sudo is available and user can use it
# Returns 0 if sudo works, 1 otherwise
can_sudo() {
  # Check if sudo exists
  if ! command_exists sudo; then
    return 1
  fi
  # Check if we can actually use sudo (might prompt for password)
  # Use -n to avoid prompting - if it fails, sudo needs password
  if sudo -n true 2>/dev/null; then
    return 0
  fi
  # sudo exists but needs password - still return success but warn user
  return 0
}

# Run a command with sudo if available, otherwise warn and try without
# Usage: run_with_sudo command [args...]
run_with_sudo() {
  if can_sudo; then
    sudo "$@"
  else
    echo "WARNING: sudo not available. Trying without elevated privileges..."
    "$@"
  fi
}

# Get system architecture for binary downloads
get_arch() {
  local arch
  arch=$(uname -m)
  case "$arch" in
    x86_64|amd64) echo "x86_64" ;;
    arm64|aarch64) echo "arm64" ;;
    armv7l) echo "armv7" ;;
    *) echo "$arch" ;;
  esac
}

# Get OS name for binary downloads
get_os() {
  case "$(uname -s)" in
    Darwin) echo "Darwin" ;;
    Linux) echo "Linux" ;;
    MINGW*|MSYS*|CYGWIN*) echo "Windows" ;;
    *) echo "$(uname -s)" ;;
  esac
}

# Download gum binary directly from GitHub releases (no package manager needed)
install_gum_binary() {
  local version="0.14.5"
  local os arch url tmpdir
  os=$(get_os)
  arch=$(get_arch)

  echo "Downloading gum v${version} for ${os}/${arch}..."

  # Determine download URL
  local ext="tar.gz"
  [[ "$os" == "Windows" ]] && ext="zip"
  url="https://github.com/charmbracelet/gum/releases/download/v${version}/gum_${version}_${os}_${arch}.${ext}"

  tmpdir=$(mktemp -d)
  cd "$tmpdir" || return 1

  if ! curl -fsSL -o "gum.${ext}" "$url"; then
    echo "Failed to download gum from $url"
    rm -rf "$tmpdir"
    return 1
  fi

  # Extract
  if [[ "$ext" == "zip" ]]; then
    unzip -q "gum.${ext}"
  else
    tar -xzf "gum.${ext}"
  fi

  # Install to user bin directory
  local install_dir="$HOME/.local/bin"
  mkdir -p "$install_dir"

  # Find and copy the binary
  if [[ -f "gum" ]]; then
    cp gum "$install_dir/"
  elif [[ -f "gum_${version}_${os}_${arch}/gum" ]]; then
    cp "gum_${version}_${os}_${arch}/gum" "$install_dir/"
  else
    # Try to find it
    local gum_bin
    gum_bin=$(find . -name "gum" -type f | head -1)
    if [[ -n "$gum_bin" ]]; then
      cp "$gum_bin" "$install_dir/"
    else
      echo "Could not find gum binary in downloaded archive"
      rm -rf "$tmpdir"
      return 1
    fi
  fi

  chmod +x "$install_dir/gum"
  rm -rf "$tmpdir"

  # Add to PATH for this session if not already there
  if [[ ":$PATH:" != *":$install_dir:"* ]]; then
    export PATH="$install_dir:$PATH"
  fi

  echo "gum installed to $install_dir/gum"
  echo "NOTE: Add $install_dir to your PATH permanently by adding this to your ~/.bashrc or ~/.zshrc:"
  echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
  return 0
}

# Install gum using Go
install_gum_go() {
  echo "Installing gum using Go..."
  go install github.com/charmbracelet/gum@latest
}

# Install gum based on OS and available tools
install_gum() {
  # Try direct binary download first (most reliable, no dependencies)
  if install_gum_binary; then
    return 0
  fi

  # Fallback: Try Go if available
  if command_exists go; then
    if install_gum_go; then
      return 0
    fi
  fi

  # Fallback: Try package managers
  case "$(uname -s)" in
  Darwin)
    if command_exists brew; then
      echo "Installing gum using Homebrew..."
      brew install gum && return 0
    fi
    ;;
  Linux)
    if command_exists apt-get; then
      echo "Installing gum on Ubuntu/Debian..."
      sudo mkdir -p /etc/apt/keyrings
      curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
      echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
      sudo apt update && sudo apt install -y gum && return 0
    elif command_exists pacman; then
      echo "Installing gum using pacman..."
      sudo pacman -S --noconfirm gum && return 0
    fi
    ;;
  esac

  echo "=========================================="
  echo "ERROR: Failed to install gum automatically"
  echo "=========================================="
  echo "Please install gum manually:"
  echo "  https://github.com/charmbracelet/gum#installation"
  echo ""
  echo "Quick options:"
  echo "  Mac:   brew install gum"
  echo "  Linux: See https://github.com/charmbracelet/gum#linux"
  echo "=========================================="
  exit 1
}

# Download jq binary directly
install_jq_binary() {
  local version="1.7.1"
  local os arch url
  os=$(get_os)
  arch=$(get_arch)

  echo "Downloading jq v${version} for ${os}/${arch}..."

  # jq uses different naming convention
  local jq_os jq_arch
  case "$os" in
    Darwin) jq_os="macos" ;;
    Linux) jq_os="linux" ;;
    Windows) jq_os="windows" ;;
    *) jq_os="$os" ;;
  esac

  case "$arch" in
    x86_64) jq_arch="amd64" ;;
    arm64) jq_arch="arm64" ;;
    *) jq_arch="$arch" ;;
  esac

  local ext=""
  [[ "$os" == "Windows" ]] && ext=".exe"

  url="https://github.com/jqlang/jq/releases/download/jq-${version}/jq-${jq_os}-${jq_arch}${ext}"

  local install_dir="$HOME/.local/bin"
  mkdir -p "$install_dir"

  if curl -fsSL -o "$install_dir/jq" "$url"; then
    chmod +x "$install_dir/jq"
    if [[ ":$PATH:" != *":$install_dir:"* ]]; then
      export PATH="$install_dir:$PATH"
    fi
    echo "jq installed to $install_dir/jq"
    return 0
  else
    echo "Failed to download jq"
    return 1
  fi
}

# Install jq
install_jq() {
  # Try direct binary download first
  if install_jq_binary; then
    return 0
  fi

  # Fallback to package managers
  case "$(uname -s)" in
  Linux)
    if command_exists apt-get; then
      echo "Installing jq with apt-get..."
      sudo apt-get update && sudo apt-get install -y jq && return 0
    elif command_exists yum; then
      sudo yum install -y jq && return 0
    elif command_exists dnf; then
      sudo dnf install -y jq && return 0
    elif command_exists pacman; then
      sudo pacman -S --noconfirm jq && return 0
    fi
    ;;
  Darwin)
    if command_exists brew; then
      brew install jq && return 0
    fi
    ;;
  esac

  echo "Failed to install jq. Please install manually: https://jqlang.github.io/jq/download/"
  exit 1
}

# Install Docker
install_docker() {
  case "$(uname -s)" in
  Linux)
    echo "Installing Docker using official convenience script..."
    echo "(This requires sudo access)"
    if curl -fsSL https://get.docker.com | sh; then
      # Add current user to docker group
      sudo usermod -aG docker "$USER" 2>/dev/null || true
      echo ""
      echo "Docker installed successfully!"
      echo "NOTE: You may need to log out and back in for docker group permissions to take effect."
      echo "      Or run: newgrp docker"
      return 0
    else
      echo "Docker installation failed"
      return 1
    fi
    ;;
  Darwin)
    echo "=========================================="
    echo "Docker Desktop Required (Mac)"
    echo "=========================================="
    echo "Docker Desktop must be installed manually on Mac."
    echo ""
    echo "Download from: https://www.docker.com/products/docker-desktop/"
    echo ""
    echo "After installing, make sure Docker Desktop is running,"
    echo "then run this script again."
    echo "=========================================="
    exit 1
    ;;
  MINGW*|MSYS*|CYGWIN*)
    echo "=========================================="
    echo "Docker Desktop Required (Windows)"
    echo "=========================================="
    echo "For Windows, please install Docker Desktop:"
    echo "  https://www.docker.com/products/docker-desktop/"
    echo ""
    echo "Or if using WSL2, ensure Docker Desktop is configured"
    echo "to integrate with your WSL distribution."
    echo "=========================================="
    exit 1
    ;;
  *)
    echo "Unsupported OS for automatic Docker installation."
    echo "Please install Docker manually: https://docs.docker.com/engine/install/"
    exit 1
    ;;
  esac
}

# Check for NVIDIA GPU and container toolkit
# Shows instructions if toolkit is missing - user installs manually and re-runs bootstrap
check_nvidia_toolkit() {
  # Only relevant on Linux
  [[ "$OS_TYPE" != "Linux" ]] && return 0

  # Check if nvidia-smi exists (NVIDIA drivers installed)
  if ! command_exists nvidia-smi; then
    # No NVIDIA GPU or drivers - continue silently in CPU-only mode
    log_line "No NVIDIA GPU detected, continuing in CPU-only mode"
    return 0
  fi

  # GPU detected - check if container toolkit is installed
  local toolkit_installed=false
  if command_exists nvidia-container-runtime; then
    toolkit_installed=true
  elif docker info 2>/dev/null | grep -qi "nvidia"; then
    toolkit_installed=true
  fi

  if [ "$toolkit_installed" = true ]; then
    log_line "NVIDIA GPU and container toolkit detected"
    echo "NVIDIA GPU detected with container toolkit installed"
    return 0
  fi

  # GPU detected but toolkit missing - show instructions
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "  NVIDIA GPU Detected - Container Toolkit Required"
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  echo "Your system has an NVIDIA GPU, but the NVIDIA Container Toolkit"
  echo "is not installed. This toolkit is required for GPU acceleration."
  echo ""
  echo "To install the NVIDIA Container Toolkit:"
  echo ""
  if command_exists apt-get; then
    echo "  # Add the NVIDIA repository"
    echo "  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \\"
    echo "    | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg"
    echo ""
    echo "  curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \\"
    echo "    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \\"
    echo "    | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list"
    echo ""
    echo "  # Install the toolkit"
    echo "  sudo apt-get update"
    echo "  sudo apt-get install -y nvidia-container-toolkit"
    echo ""
    echo "  # Configure Docker and restart"
    echo "  sudo nvidia-ctk runtime configure --runtime=docker"
    echo "  sudo systemctl restart docker"
  elif command_exists dnf; then
    echo "  # Add the NVIDIA repository"
    echo "  curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo \\"
    echo "    | sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo"
    echo ""
    echo "  # Install the toolkit"
    echo "  sudo dnf install -y nvidia-container-toolkit"
    echo ""
    echo "  # Configure Docker and restart"
    echo "  sudo nvidia-ctk runtime configure --runtime=docker"
    echo "  sudo systemctl restart docker"
  elif command_exists yum; then
    echo "  # Add the NVIDIA repository"
    echo "  curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo \\"
    echo "    | sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo"
    echo ""
    echo "  # Install the toolkit"
    echo "  sudo yum install -y nvidia-container-toolkit"
    echo ""
    echo "  # Configure Docker and restart"
    echo "  sudo nvidia-ctk runtime configure --runtime=docker"
    echo "  sudo systemctl restart docker"
  else
    echo "  See: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html"
  fi
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  echo "Options:"
  echo "  1) Exit now, install the toolkit, then re-run bootstrap"
  echo "  2) Continue without GPU (CPU-only mode)"
  echo ""
  read -p "Continue without GPU? [y/N] " -n 1 -r
  echo

  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "Continuing in CPU-only mode..."
    echo "You can install the toolkit later and re-run bootstrap for GPU support."
    log_line "User chose to continue without GPU support"
    return 0
  else
    echo ""
    echo "Exiting. Please install the NVIDIA Container Toolkit and run bootstrap again."
    log_line "User exited to install NVIDIA toolkit"
    exit 0
  fi
}

# Check if gum is installed, install if not
check_gum_installed() {
  if ! command_exists gum; then
    echo "gum not found. Installing..."
    install_gum
  fi
}

# Check if jq is installed, install if not
check_jq_installed() {
  if ! command_exists jq; then
    echo "jq not found. Installing..."
    install_jq
  fi
}

# Check if Docker is installed, install if not
check_docker_installed() {
  if ! command_exists docker; then
    echo "Docker not found."
    install_docker
  fi

  # Verify Docker is running
  if ! docker info >/dev/null 2>&1; then
    echo ""
    echo "WARNING: Docker is installed but not running or accessible."
    echo ""
    case "$(uname -s)" in
    Darwin)
      echo "Please start Docker Desktop and try again."
      ;;
    Linux)
      echo "Try one of these:"
      echo "  1. Start Docker: sudo systemctl start docker"
      echo "  2. Add yourself to docker group: sudo usermod -aG docker $USER"
      echo "     Then log out and back in."
      ;;
    esac
    exit 1
  fi
}

# Check if curl is available (required for downloads)
check_curl_installed() {
  if ! command_exists curl; then
    echo "=========================================="
    echo "curl Required"
    echo "=========================================="
    echo "curl is required for downloading dependencies."
    echo "Please install curl:"
    case "$OS_TYPE" in
    Darwin)
      echo "  curl should be pre-installed on Mac"
      echo "  If missing: brew install curl"
      ;;
    Linux)
      echo "  Ubuntu/Debian: sudo apt install curl"
      echo "  Fedora/RHEL:   sudo dnf install curl"
      ;;
    esac
    echo "=========================================="
    exit 1
  fi
}

# Check Python and required libraries
check_python_and_ecdsa() {
  if ! command_exists python3; then
    echo "=========================================="
    echo "Python 3 Required"
    echo "=========================================="
    echo "Please install Python 3:"
    case "$OS_TYPE" in
    Darwin)
      echo "  brew install python3"
      echo "  or download from: https://www.python.org/downloads/"
      ;;
    Linux)
      echo "  Ubuntu/Debian: sudo apt install python3 python3-pip"
      echo "  Fedora/RHEL:   sudo dnf install python3 python3-pip"
      ;;
    esac
    echo "=========================================="
    exit 1
  fi

  # Virtual environment path for isolated Python packages
  local NESA_VENV="${DEFAULT_WORKDIR}/venv"
  local PYTHON_CMD="python3"
  local PIP_CMD=""

  # Check if we have an existing venv, activate it
  if [ -f "${NESA_VENV}/bin/activate" ]; then
    # shellcheck disable=SC1091
    source "${NESA_VENV}/bin/activate" 2>/dev/null || true
    PYTHON_CMD="${NESA_VENV}/bin/python3"
    PIP_CMD="${NESA_VENV}/bin/pip"
  fi

  # Check and install required Python libraries
  local missing_libs=()

  $PYTHON_CMD -c "import ecdsa" 2>/dev/null || missing_libs+=("ecdsa")
  $PYTHON_CMD -c "import base58" 2>/dev/null || missing_libs+=("base58")
  $PYTHON_CMD -c "from cryptography.hazmat.primitives.asymmetric import ed25519" 2>/dev/null || missing_libs+=("cryptography")
  $PYTHON_CMD -c "import mospy" 2>/dev/null || missing_libs+=("mospy-wallet")
  $PYTHON_CMD -c "import httpx" 2>/dev/null || missing_libs+=("httpx")
  $PYTHON_CMD -c "import betterproto" 2>/dev/null || missing_libs+=("betterproto")

  if [ ${#missing_libs[@]} -gt 0 ]; then
    echo "Installing required Python libraries: ${missing_libs[*]}..."

    local install_success=false

    # Method 1: Try standard pip install with various flags (works on most Linux)
    if [ "$install_success" = false ]; then
      if pip3 install --user --break-system-packages "${missing_libs[@]}" 2>/dev/null; then
        install_success=true
      elif pip3 install --user "${missing_libs[@]}" 2>/dev/null; then
        install_success=true
      elif python3 -m pip install --user --break-system-packages "${missing_libs[@]}" 2>/dev/null; then
        install_success=true
      elif python3 -m pip install --user "${missing_libs[@]}" 2>/dev/null; then
        install_success=true
      fi
    fi

    # Method 2: Create a virtual environment (required for macOS Homebrew Python)
    if [ "$install_success" = false ]; then
      echo "Creating Python virtual environment at ${NESA_VENV}..."

      if python3 -m venv "${NESA_VENV}" 2>/dev/null; then
        # shellcheck disable=SC1091
        source "${NESA_VENV}/bin/activate"
        PYTHON_CMD="${NESA_VENV}/bin/python3"
        PIP_CMD="${NESA_VENV}/bin/pip"

        if $PIP_CMD install "${missing_libs[@]}" 2>/dev/null; then
          install_success=true
          echo "Python libraries installed in virtual environment."
          echo ""
          echo "NOTE: The virtual environment is at: ${NESA_VENV}"
          echo "      Python commands in this script will use it automatically."
        fi
      fi
    fi

    # Method 3: Final fallback - show manual instructions
    if [ "$install_success" = false ]; then
      echo ""
      echo "=========================================="
      echo "ERROR: Failed to install Python libraries"
      echo "=========================================="
      echo ""
      echo "Please install manually using one of these methods:"
      echo ""
      echo "Option 1 - Use a virtual environment (recommended):"
      echo "  python3 -m venv ~/.nesa/venv"
      echo "  source ~/.nesa/venv/bin/activate"
      echo "  pip install ${missing_libs[*]}"
      echo ""
      echo "Option 2 - Force system install (if you understand the risks):"
      echo "  pip3 install --user --break-system-packages ${missing_libs[*]}"
      echo ""
      echo "Then run this script again."
      echo "=========================================="
      exit 1
    fi
  fi

  # Export the Python command for use in the rest of the script
  export NESA_PYTHON_CMD="${PYTHON_CMD}"
  export NESA_VENV="${NESA_VENV}"
}

# --- RUN DEPENDENCY CHECKS NOW (before any gum usage) ---
log_line "[STAGE 0]: Early dependency checks"
check_curl_installed   # curl needed for downloads
check_gum_installed
check_jq_installed
check_docker_installed
check_python_and_ecdsa
check_nvidia_toolkit   # shows instructions if GPU detected but toolkit missing

# Now gum is guaranteed to be installed, create the logo
logo=$(gum style --foreground 43 '
 _  _ ___ ___   _
| \| | __/ __| /_\
| .` | _|\__ \/ _ \
|_|\_|___|___/_/ \_\')

# Chain configuration - can be overridden via environment variables
CHAIN_ID="${CHAIN_ID:-nesa-testnet-3}"
LCD_URL="${LCD_URL:-https://lcd.dev.nesa.ai}"
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

WORKING_DIRECTORY=${WORKING_DIRECTORY:-"$DEFAULT_WORKDIR"}
env_dir="$WORKING_DIRECTORY/env"

orchestrator_env_file="$env_dir/orchestrator.env"
base_env_file="$env_dir/base.env"
config_env_file="$env_dir/.env"
init_pwd=$PWD    # so they can get back to where they started!
# Get dynamic node status based on container state
get_node_status() {
  # Check if docker is available
  if ! command -v docker &>/dev/null; then
    echo "no docker"
    return
  fi

  # Try to find orchestrator container
  local container
  container=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -E "^orchestrator$" | head -1)

  if [ -z "$container" ]; then
    echo "not started"
    return
  fi

  local state
  state=$(docker inspect --format '{{.State.Status}}' "$container" 2>/dev/null)

  case "$state" in
    "running")
      echo "running"
      ;;
    "restarting")
      echo "restarting"
      ;;
    "paused")
      echo "paused"
      ;;
    "exited")
      echo "stopped"
      ;;
    "dead")
      echo "error"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

status="booting" # will be updated dynamically
ORC_PORT=31333

MONIKER=${MONIKER:-$(hostname -s)}
#
# basic helper functions
#

# Show wizard step header with context/help information
show_step_header() {
  local step_num="$1"
  local total_steps="$2"
  local title="$3"
  local description="$4"
  local format_info="$5"
  local example="$6"
  local required="$7"  # "required" or "optional"
  local help_link="$8" # optional URL

  local req_text
  if [ "$required" = "required" ]; then
    req_text=$(gum style --foreground 214 "This field is REQUIRED")
  else
    req_text=$(gum style --foreground 245 "This field is OPTIONAL")
  fi

  local help_text=""
  if [ -n "$help_link" ]; then
    help_text="
$(gum style --foreground 250 "Get it at:") $(gum style --foreground "$link_color" "$help_link")"
  fi

  echo ""
  gum style --border rounded --padding "1 2" --border-foreground "$main_color" \
    "$(gum style --foreground "$main_color" --bold "STEP $step_num OF $total_steps: $title")

$(gum style --foreground 255 "$description")

$(gum style --foreground 250 "Format:") $(gum style --foreground "$link_color" "$format_info")
$(gum style --foreground 250 "Example:") $(gum style --foreground 245 "$example")$help_text

$req_text"
  echo ""
}

# Show summary of what user entered after input
# Usage: show_input_summary "field_label" "value" "required|optional"
show_input_summary() {
  local label="$1"
  local value="$2"
  local required="$3"

  echo ""
  if [ -n "$value" ]; then
    # Has value - show what they entered
    gum style --foreground 245 "$label: $(gum style --foreground 255 --bold "$value")"
  elif [ "$required" = "required" ]; then
    # Empty but required
    gum style --foreground 214 "No value entered (required)"
  else
    # Empty but optional - that's fine
    gum style --foreground 245 "$label: (skipped)"
  fi
  echo ""
}

# Show wizard navigation buttons
wizard_nav() {
  local show_back="$1"  # "yes" or "no"

  echo ""
  if [ "$show_back" = "yes" ]; then
    gum choose --cursor.foreground "$main_color" \
      "Continue" \
      "← Back" \
      "Cancel Setup"
  else
    gum choose --cursor.foreground "$main_color" \
      "Continue" \
      "Cancel Setup"
  fi
}

# Return to main menu (restarts script)
# Script will show main menu if config exists, or wizard if not
return_to_main_menu() {
  exec "$SCRIPT_PATH"
}

# Validate wizard input - returns "ok" or "error|message"
validate_input() {
  local type="$1"
  local value="$2"

  case "$type" in
    "moniker")
      # 3-32 chars, alphanumeric and hyphens
      if [ ${#value} -lt 3 ] || [ ${#value} -gt 32 ]; then
        echo "error|Node name must be 3-32 characters (got ${#value})"
        return 1
      fi
      # Use grep for portability (no [[ =~ ]] which varies across bash versions)
      if ! echo "$value" | grep -qE '^[a-zA-Z0-9-]+$'; then
        echo "error|Node name can only contain letters, numbers, and hyphens"
        return 1
      fi
      echo "ok"
      ;;
    "referral")
      # Optional - empty is ok
      if [ -z "$value" ]; then
        echo "ok"
        return 0
      fi
      # If provided, must be nesa1... format (~44 chars)
      if ! echo "$value" | grep -qE '^nesa1[a-z0-9]{38,40}$'; then
        echo "error|Referral code must start with 'nesa1' and be about 44 characters"
        return 1
      fi
      echo "ok"
      ;;
    "hf_token")
      # Optional - empty triggers warning but is allowed
      if [ -z "$value" ]; then
        echo "warn|No API key provided. Some gated models may not be available."
        return 0
      fi
      # If provided, validate format
      if ! echo "$value" | grep -qE '^hf_[a-zA-Z0-9]{20,50}$'; then
        echo "error|API key should start with 'hf_' and be about 40 characters"
        return 1
      fi
      echo "ok"
      ;;
    "private_key")
      local key="$value"
      # Remove 0x prefix if present
      key="${key#0x}"
      key="${key#0X}"
      if [ -z "$key" ]; then
        echo "error|Private key is required"
        return 1
      fi
      if [ ${#key} -ne 64 ]; then
        echo "error|Private key must be 64 hex characters (got ${#key})"
        return 1
      fi
      if ! echo "$key" | grep -qE '^[a-fA-F0-9]{64}$'; then
        echo "error|Private key must contain only hexadecimal characters (0-9, a-f)"
        return 1
      fi
      echo "ok"
      ;;
    *)
      echo "ok"
      ;;
  esac
}

# print if the output fits on screen
print_test() {
  local no_color
  local max_length
  no_color=$(printf '%b' "${1}" | sed -e 's/\x1B\[[0-9;]*[JKmsu]//g')
  max_length=$(max_line_length "$no_color")

  [ "$(printf '%s' "${no_color}" | wc -l)" -gt $((terminal_height - prompt_height)) ] && return 1
  [ "$max_length" -gt "$terminal_width" ] && return 1

  gum style --align center --width="${terminal_width}" "${1}" ''
  printf '%b' "\033[A"
}

update_header() {
  local dashboard_url
  local op_dashboard_url
  local public_key
  local header

  # Get dynamic status from container state
  status=$(get_node_status)

  # Re-read terminal size in case it changed
  terminal_size=$(stty size 2>/dev/null || echo "24 80")
  terminal_height=${terminal_size% *}
  terminal_width=${terminal_size#* }

  if [[ "$NODE_ID" == "pending..." ]]; then
    dashboard_url="https://node.nesa.ai"
  else
    dashboard_url="https://node.nesa.ai/nodes/$NODE_ID"
  fi

  if [[ -n "$NODE_PRIV_KEY" ]]; then
    public_key=$(generate_public_key "$NODE_PRIV_KEY")
    op_dashboard_url="https://node.nesa.ai/$public_key/list"
  else
    public_key="pending..."
    op_dashboard_url="pending..."
  fi

  # Layout thresholds (increased for better fit)
  local min_horizontal_width=130  # Wide: logo + info side by side
  local min_vertical_width=70     # Medium: logo on top, info below
  # Below 70: compact mode, no logo

  # Helper to truncate strings
  truncate_str() {
    local str="$1"
    local max_len="$2"
    if [[ ${#str} -gt $max_len && $max_len -gt 3 ]]; then
      echo "${str:0:$((max_len-3))}..."
    else
      echo "$str"
    fi
  }

  # Use simpler ASCII logo as fallback (works in all terminals)
  local simple_logo
  simple_logo=$(gum style --foreground "$main_color" '
 _  _ ___ ___   _
| \| | __/ __| /_\
| .` | _|\__ \/ _ \
|_|\_|___|___/_/ \_\')

  if [[ "$terminal_width" -ge "$min_horizontal_width" ]]; then
    # Wide terminal: horizontal layout (logo on left, info on right)
    # Still truncate long URLs
    local max_url_width=$((terminal_width - 50))
    local trunc_dashboard=$(truncate_str "$dashboard_url" "$max_url_width")
    local trunc_op_dash=$(truncate_str "$op_dashboard_url" "$max_url_width")

    info=$(gum style "[1;38;5;${main_color}m  ${MONIKER}[0m.${domain}
  ----------------
  [1;38;5;${main_color}mnode id:       [0m${NODE_ID}
  [1;38;5;${main_color}mpublic key:    [0m${public_key}
  [1;38;5;${main_color}mdashboard:     [0;38;5;${link_color}m${trunc_dashboard}[0m
  [1;38;5;${main_color}mop dash:       [0;38;5;${link_color}m${trunc_op_dash}[0m
  [1;38;5;${main_color}mstatus:        [0m${status}")
    header=$(gum join --horizontal --align top "${logo}" '  ' "${info}")

  elif [[ "$terminal_width" -ge "$min_vertical_width" ]]; then
    # Medium terminal: vertical layout with simple logo
    local max_val_width=$((terminal_width - 16))
    local trunc_node_id=$(truncate_str "$NODE_ID" "$max_val_width")
    local trunc_pubkey=$(truncate_str "$public_key" "$max_val_width")
    local trunc_dashboard=$(truncate_str "$dashboard_url" "$max_val_width")
    local trunc_op_dash=$(truncate_str "$op_dashboard_url" "$max_val_width")
    local trunc_moniker=$(truncate_str "${MONIKER}.${domain}" "$((terminal_width - 4))")

    info=$(gum style "[1;38;5;${main_color}m${trunc_moniker}[0m
----------------
[1;38;5;${main_color}mnode id:    [0m${trunc_node_id}
[1;38;5;${main_color}mpublic key: [0m${trunc_pubkey}
[1;38;5;${main_color}mdashboard:  [0;38;5;${link_color}m${trunc_dashboard}[0m
[1;38;5;${main_color}mop dash:    [0;38;5;${link_color}m${trunc_op_dash}[0m
[1;38;5;${main_color}mstatus:     [0m${status}")
    header=$(gum join --vertical --align center "${simple_logo}" "${info}")

  else
    # Narrow terminal: compact mode, no logo
    local max_val_width=$((terminal_width - 8))
    [[ $max_val_width -lt 10 ]] && max_val_width=10

    local trunc_node_id=$(truncate_str "$NODE_ID" "$max_val_width")
    local trunc_pubkey=$(truncate_str "$public_key" "$max_val_width")
    local trunc_moniker=$(truncate_str "${MONIKER}" "$((terminal_width - 6))")

    # Minimal compact header for narrow terminals
    header=$(gum style --border rounded --padding "0 1" --border-foreground "$main_color" \
      "[1;38;5;${main_color}m${trunc_moniker}[0m
[1;38;5;${main_color}mid:[0m ${trunc_node_id}
[1;38;5;${main_color}mpk:[0m ${trunc_pubkey}
[1;38;5;${main_color}m→[0m  ${status}")
  fi

  echo ""
  # Print header - if it doesn't fit, print without centering
  if ! print_test "${header}"; then
    echo "${header}"
  fi
  echo ""
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

get_linux_info() {
  local name version kernel architecture cpu cores ram disk_avail gpu gpu_count gpu_memory
  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release 2>/dev/null || true
    name="${NAME:-Unknown}"
    version="${VERSION:-Unknown}"
  else
    name="Linux"
    version="Unknown"
  fi
  kernel=$(uname -r 2>/dev/null || echo "Unknown")
  architecture=$(uname -m 2>/dev/null || echo "Unknown")

  # CPU info with fallback
  if command -v lscpu >/dev/null 2>&1; then
    cpu=$(lscpu 2>/dev/null | grep -i 'Model name' | awk -F: '{print $2}' | sed 's/^ *//' | head -1)
    cores=$(lscpu 2>/dev/null | grep -i '^CPU(s):' | awk '{print $2}' | head -1)
  fi
  # Fallback to /proc/cpuinfo
  if [ -z "$cpu" ] && [ -f /proc/cpuinfo ]; then
    cpu=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | awk -F: '{print $2}' | sed 's/^ *//')
    cores=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)
  fi
  cpu="${cpu:-Unknown}"
  cores="${cores:-1}"

  # RAM info with fallback
  if command -v free >/dev/null 2>&1; then
    ram=$(free -h 2>/dev/null | grep -i Mem | awk '{print $2}')
  fi
  if [ -z "$ram" ] && [ -f /proc/meminfo ]; then
    ram=$(awk '/MemTotal/ {printf "%.1f GB", $2/1024/1024}' /proc/meminfo 2>/dev/null)
  fi
  ram="${ram:-Unknown}"

  # Disk space - df --total may not work on all systems
  disk_avail=$(df -h --total 2>/dev/null | grep -i total | awk '{print $4}')
  if [ -z "$disk_avail" ]; then
    # Fallback: show root partition free space
    disk_avail=$(df -h / 2>/dev/null | tail -1 | awk '{print $4}')
  fi
  disk_avail="${disk_avail:-Unknown}"

  # GPU detection
  if command -v lspci >/dev/null 2>&1; then
    gpu=$(lspci 2>/dev/null | grep -i -e '3D controller' -e 'VGA compatible controller' | grep -i -e nvidia -e amd | awk -F: '{print $3}' | sed 's/^ *//' | head -1)
    gpu_count=$(lspci 2>/dev/null | grep -i -e '3D controller' -e 'VGA compatible controller' | grep -i -e nvidia -e amd | wc -l | tr -d ' ')
  fi

  # NVIDIA GPU memory
  if command -v nvidia-smi >/dev/null 2>&1; then
    gpu_memory=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | awk '{total += $1} END {if(total>0) print total " MB"}')
  fi

  # Fallback GPU memory detection
  if [ -z "$gpu_memory" ] && command -v lshw >/dev/null 2>&1; then
    gpu_memory=$(sudo lshw -C display 2>/dev/null | grep -i size | awk '{print $2 " " $3}' | head -n 1)
  fi

  NODE_OS="Linux ${version}"
  NODE_ARCH="${architecture}"
  NODE_CPU="${cpu}"
  NODE_CORES="${cores}"
  NODE_GPU="${gpu:-NA}"
  NODE_GPU_COUNT="${gpu_count:-0}"
  NODE_RAM="${ram}"
  NODE_VRAM="${gpu_memory:-NA}"
  NODE_DISK_AVAIL="${disk_avail}"
}

get_macos_info() {
  local product_version build_version architecture cpu cores ram disk_avail gpu gpu_count gpu_memory

  # Basic system info
  product_version=$(sw_vers -productVersion 2>/dev/null || echo "Unknown")
  build_version=$(sw_vers -buildVersion 2>/dev/null || echo "Unknown")
  architecture=$(uname -m 2>/dev/null || echo "Unknown")

  # CPU info
  cpu=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Apple Silicon")
  cores=$(sysctl -n hw.ncpu 2>/dev/null || echo "1")

  # RAM - convert bytes to GB
  local memsize
  memsize=$(sysctl -n hw.memsize 2>/dev/null)
  if [ -n "$memsize" ]; then
    ram=$(awk -v mem="$memsize" 'BEGIN {printf "%.0f GB", mem/1024/1024/1024}')
  else
    ram="Unknown"
  fi

  # Disk space - Mac df doesn't support --total, use root partition
  # Mac df -h output columns: Filesystem Size Used Avail Capacity Mounted
  disk_avail=$(df -h / 2>/dev/null | tail -1 | awk '{print $4}')
  disk_avail="${disk_avail:-Unknown}"

  # GPU detection via system_profiler (may be slow, redirect stderr)
  gpu=$(system_profiler SPDisplaysDataType 2>/dev/null | grep 'Chipset Model' | awk -F: '{print $2}' | sed 's/^ *//' | head -1)
  gpu_count=$(system_profiler SPDisplaysDataType 2>/dev/null | grep -c 'Chipset Model' | tr -d ' ')

  # GPU memory - Apple Silicon uses unified memory, VRAM field may not exist
  gpu_memory=$(system_profiler SPDisplaysDataType 2>/dev/null | grep -i 'VRAM\|Total Number of Cores' | head -1 | awk -F: '{print $2}' | sed 's/^ *//')
  if [ -z "$gpu_memory" ] || [ "$gpu_memory" = "0 MB" ]; then
    # Apple Silicon shares system RAM
    gpu_memory="Unified Memory"
  fi

  NODE_OS="macOS ${product_version} (${build_version})"
  NODE_ARCH="${architecture}"
  NODE_CPU="${cpu}"
  NODE_CORES="${cores}"
  NODE_GPU="${gpu:-Apple GPU}"
  NODE_GPU_COUNT="${gpu_count:-1}"
  NODE_RAM="${ram}"
  NODE_VRAM="${gpu_memory:-NA}"
  NODE_DISK_AVAIL="${disk_avail}"
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
    # shellcheck disable=SC1091
    . /etc/os-release 2>/dev/null || true
    name="${NAME:-Unknown}"
    version="${VERSION:-Unknown}"
  else
    name="WSL"
    version="Unknown"
  fi
  kernel=$(uname -r 2>/dev/null || echo "Unknown")
  architecture=$(uname -m 2>/dev/null || echo "Unknown")

  # CPU info from /proc/cpuinfo (always available in WSL)
  cpu=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | awk -F: '{print $2}' | sed 's/^ *//')
  cores=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)
  cpu="${cpu:-Unknown}"
  cores="${cores:-1}"

  # RAM
  if command -v free >/dev/null 2>&1; then
    ram=$(free -h 2>/dev/null | grep -i Mem | awk '{print $2}')
  fi
  ram="${ram:-Unknown}"

  # Disk - df --total should work in WSL
  disk_avail=$(df -h --total 2>/dev/null | grep -i total | awk '{print $4}')
  if [ -z "$disk_avail" ]; then
    disk_avail=$(df -h / 2>/dev/null | tail -1 | awk '{print $4}')
  fi
  disk_avail="${disk_avail:-Unknown}"

  # GPU - WSL2 can access Windows GPU via nvidia-smi
  if command -v nvidia-smi >/dev/null 2>&1; then
    gpu=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    gpu_count=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l | tr -d ' ')
    gpu_memory=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | awk '{total += $1} END {if(total>0) print total " MB"}')
  else
    gpu="NA"
    gpu_count=0
    gpu_memory="NA"
  fi

  NODE_OS="WSL ${version} (${kernel})"
  NODE_ARCH="${architecture}"
  NODE_CPU="${cpu}"
  NODE_CORES="${cores}"
  NODE_GPU="${gpu:-NA}"
  NODE_GPU_COUNT="${gpu_count:-0}"
  NODE_RAM="${ram}"
  NODE_VRAM="${gpu_memory:-NA}"
  NODE_DISK_AVAIL="${disk_avail}"
}
log_line "[STAGE 2]: detecting hardware capabilities"

detect_hardware_capabilities() {
  case "$OS_TYPE" in
  Linux)
    # Check for WSL - /proc/version contains "Microsoft" or "WSL"
    if [ -f /proc/version ] && grep -qi -e Microsoft -e WSL /proc/version 2>/dev/null; then
      get_wsl_info
    else
      get_linux_info
    fi
    ;;
  Darwin)
    get_macos_info
    ;;
  CYGWIN* | MINGW* | MSYS*)
    get_windows_info
    ;;
  *)
    echo "WARNING: Unsupported platform: $OS_TYPE"
    echo "Hardware detection may be incomplete."
    # Set defaults
    NODE_OS="$OS_TYPE"
    NODE_ARCH=$(uname -m 2>/dev/null || echo "Unknown")
    NODE_CPU="Unknown"
    NODE_CORES="1"
    NODE_GPU="NA"
    NODE_GPU_COUNT="0"
    NODE_RAM="Unknown"
    NODE_VRAM="NA"
    NODE_DISK_AVAIL="Unknown"
    ;;
  esac
}

log_line "[STAGE 3]: setup work dir"
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
  local url="${LCD_URL}/nesachain/dht/get_orchestrators"
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
  local url="${LCD_URL}/nesachain/dht/get_node/$recreated_node_id"
  local json_data
  local network_address

  json_data=$(curl -s "$url")
  network_address=$(echo "$json_data" | jq -r '.node.network_address')

  echo "$network_address"
}

generate_public_key() {
  local private_key="$1"
  ${NESA_PYTHON_CMD:-python3} -c "
import ecdsa

def strip_0x_prefix(key_hex):
    return key_hex[2:] if key_hex.startswith('0x') else key_hex

def private_key_to_public_key(private_key_hex):
    private_key_hex = strip_0x_prefix(private_key_hex)
    private_key_bytes = bytes.fromhex(private_key_hex)
    sk = ecdsa.SigningKey.from_string(private_key_bytes, curve=ecdsa.SECP256k1)
    vk = sk.get_verifying_key()
    public_key_compressed = b'\x02' + vk.to_string()[:32] if vk.to_string()[-1] % 2 == 0 else b'\x03' + vk.to_string()[:32]
    return public_key_compressed.hex()

print(private_key_to_public_key('$private_key'))
"
}

# Derive wallet address from private key (bech32 format)
derive_wallet_address() {
  local private_key="$1"
  local prefix="${2:-nesa}"

  ${NESA_PYTHON_CMD:-python3} -c "
import hashlib
import ecdsa

def bech32_polymod(values):
    GEN = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
    chk = 1
    for v in values:
        b = chk >> 25
        chk = (chk & 0x1ffffff) << 5 ^ v
        for i in range(5):
            chk ^= GEN[i] if ((b >> i) & 1) else 0
    return chk

def bech32_hrp_expand(hrp):
    return [ord(x) >> 5 for x in hrp] + [0] + [ord(x) & 31 for x in hrp]

def bech32_create_checksum(hrp, data):
    values = bech32_hrp_expand(hrp) + data
    polymod = bech32_polymod(values + [0, 0, 0, 0, 0, 0]) ^ 1
    return [(polymod >> 5 * (5 - i)) & 31 for i in range(6)]

def bech32_encode(hrp, data):
    combined = data + bech32_create_checksum(hrp, data)
    return hrp + '1' + ''.join([\"qpzry9x8gf2tvdw0s3jn54khce6mua7l\"[d] for d in combined])

def convertbits(data, frombits, tobits, pad=True):
    acc = 0
    bits = 0
    ret = []
    maxv = (1 << tobits) - 1
    for value in data:
        acc = (acc << frombits) | value
        bits += frombits
        while bits >= tobits:
            bits -= tobits
            ret.append((acc >> bits) & maxv)
    if pad:
        if bits:
            ret.append((acc << (tobits - bits)) & maxv)
    return ret

def strip_0x_prefix(key_hex):
    return key_hex[2:] if key_hex.startswith('0x') else key_hex

def private_key_to_address(private_key_hex, prefix='$prefix'):
    private_key_hex = strip_0x_prefix(private_key_hex)
    private_key_bytes = bytes.fromhex(private_key_hex)
    sk = ecdsa.SigningKey.from_string(private_key_bytes, curve=ecdsa.SECP256k1)
    vk = sk.get_verifying_key()
    public_key_compressed = b'\x02' + vk.to_string()[:32] if vk.to_string()[-1] % 2 == 0 else b'\x03' + vk.to_string()[:32]

    sha256_hash = hashlib.sha256(public_key_compressed).digest()
    ripemd160_hash = hashlib.new('ripemd160', sha256_hash).digest()

    five_bit_data = convertbits(ripemd160_hash, 8, 5)
    return bech32_encode(prefix, five_bit_data)

print(private_key_to_address('$private_key'))
"
}

# Generate NODE_ID from private key (deterministic derivation)
# Algorithm: SHA256(priv_key) -> Ed25519 seed -> Ed25519 pubkey -> SHA256 -> Base58
generate_node_id() {
  local private_key="$1"
  ${NESA_PYTHON_CMD:-python3} -c "
import hashlib
import base58
from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.hazmat.primitives import serialization

def strip_0x_prefix(key_hex):
    return key_hex[2:] if key_hex.startswith('0x') else key_hex

def derive_node_id(private_key_hex):
    private_key_hex = strip_0x_prefix(private_key_hex)
    private_key_bytes = bytes.fromhex(private_key_hex)

    # Derive Ed25519 seed from secp256k1 private key
    seed = hashlib.sha256(private_key_bytes).digest()

    # Create Ed25519 key from seed
    ed_private_key = ed25519.Ed25519PrivateKey.from_private_bytes(seed)
    ed_public_key = ed_private_key.public_key()

    # Get raw public key bytes
    public_bytes = ed_public_key.public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw
    )

    # Hash and encode
    public_key_hash = hashlib.sha256(public_bytes).digest()
    return base58.b58encode(public_key_hash).decode('utf-8')

print(derive_node_id('$private_key'))
"
}

# Check wallet balance (unes)
check_wallet_balance() {
  local wallet_address="$1"
  local lcd_url="${LCD_URL}"

  log_line "Checking wallet balance for ${wallet_address}"

  # Query balance via LCD REST API
  local balance_endpoint="${lcd_url}/cosmos/bank/v1beta1/balances/${wallet_address}"

  local json_data
  local http_code
  json_data=$(curl -s -w "\n%{http_code}" "$balance_endpoint" 2>&1)
  http_code=$(echo "$json_data" | tail -1)
  json_data=$(echo "$json_data" | sed '$d')

  if [ "$http_code" != "200" ]; then
    local err_msg="HTTP $http_code"
    if [ -n "$json_data" ]; then
      local api_err=$(echo "$json_data" | jq -r '.message // .error // empty' 2>/dev/null)
      [ -n "$api_err" ] && err_msg="$err_msg: $api_err"
    fi
    echo "error|0|0|${err_msg}"
    log_line "Error querying balance: $err_msg"
    return 1
  fi

  # Extract unes balance
  local unes_balance
  unes_balance=$(echo "$json_data" | jq -r '.balances[] | select(.denom == "unes") | .amount' 2>/dev/null)

  if [ -z "$unes_balance" ] || [ "$unes_balance" = "null" ]; then
    unes_balance="0"
  fi

  # Convert unes to NES for display (1 NES = 1,000,000 unes)
  local nes_display
  nes_display=$(safe_divide "$unes_balance" 1000000 6)

  echo "ok|$unes_balance|$nes_display"
}

# Check miner deposit status
check_miner_deposit() {
  local node_id="$1"
  local lcd_url="${LCD_URL}"

  log_line "Checking miner deposit for node ${node_id}"

  # Query miner via LCD REST API
  local miner_endpoint="${lcd_url}/nesachain/dht/get_miner/${node_id}"

  local json_data
  local http_code
  json_data=$(curl -s -w "\n%{http_code}" "$miner_endpoint" 2>&1)
  http_code=$(echo "$json_data" | tail -1)
  json_data=$(echo "$json_data" | sed '$d')

  # Check for API-level errors (returned in JSON even with HTTP 200)
  local api_code
  api_code=$(echo "$json_data" | jq -r '.code // 0' 2>/dev/null)

  if [ "$http_code" != "200" ] || [ "$api_code" != "0" ]; then
    local err_msg="HTTP $http_code"
    if [ -n "$json_data" ]; then
      local api_err=$(echo "$json_data" | jq -r '.message // .error // empty' 2>/dev/null)
      [ -n "$api_err" ] && err_msg="$api_err"
    fi

    # If error is "miner not found", treat it as not registered (not an error)
    if [[ "$err_msg" == *"miner not found"* ]]; then
      echo "ok|0|0|not_registered|unes"
      return 0
    fi

    echo "error|0|0|not_registered|unes|${err_msg}"
    log_line "Error querying miner: $err_msg"
    return 1
  fi

  # Check if miner exists
  local miner_exists
  miner_exists=$(echo "$json_data" | jq -r '.miner' 2>/dev/null)

  if [ "$miner_exists" = "null" ] || [ -z "$miner_exists" ]; then
    echo "ok|0|0|not_registered|unes"
    return 0
  fi

  # Extract deposit information
  local deposit_amount
  local deposit_denom
  local bond_status

  deposit_amount=$(echo "$json_data" | jq -r '.miner.deposit.amount // "0"')
  deposit_denom=$(echo "$json_data" | jq -r '.miner.deposit.denom // "unes"')
  bond_status=$(echo "$json_data" | jq -r '.miner.bond_status // 0')

  # Convert bond status to readable format (handles both numeric and string enum)
  case "$bond_status" in
    0|"BOND_STATUS_UNBONDED") bond_status="unbonded" ;;
    1|"BOND_STATUS_UNBONDING") bond_status="unbonding" ;;
    2|"BOND_STATUS_BONDED") bond_status="bonded" ;;
    *) bond_status="unknown" ;;
  esac

  # Convert unes to NES for display (1 NES = 1,000,000 unes)
  local deposit_display
  deposit_display=$(safe_divide "$deposit_amount" 1000000 6)

  echo "ok|$deposit_amount|$deposit_display|$bond_status|$deposit_denom"
}

# Check if node is registered on chain
# Returns: ok|registered or ok|not_registered or error|message
check_node_registered() {
  local node_id="$1"
  local lcd_url="${LCD_URL}"

  log_line "Checking node registration for ${node_id}"

  local node_endpoint="${lcd_url}/nesachain/dht/get_node/${node_id}"

  local json_data
  local http_code
  json_data=$(curl -s -w "\n%{http_code}" "$node_endpoint" 2>&1)
  http_code=$(echo "$json_data" | tail -1)
  json_data=$(echo "$json_data" | sed '$d')

  local api_code
  api_code=$(echo "$json_data" | jq -r '.code // 0' 2>/dev/null)

  if [ "$http_code" != "200" ] || [ "$api_code" != "0" ]; then
    local err_msg="HTTP $http_code"
    if [ -n "$json_data" ]; then
      local api_err=$(echo "$json_data" | jq -r '.message // .error // empty' 2>/dev/null)
      [ -n "$api_err" ] && err_msg="$api_err"
    fi

    # "node not found" means not registered
    if [[ "$err_msg" == *"node not found"* ]] || [[ "$err_msg" == *"not found"* ]]; then
      echo "ok|not_registered"
      return 0
    fi

    echo "error|${err_msg}"
    return 1
  fi

  local node_exists
  node_exists=$(echo "$json_data" | jq -r '.node.node_id // empty' 2>/dev/null)

  if [ -z "$node_exists" ]; then
    echo "ok|not_registered"
  else
    echo "ok|registered"
  fi
}

# Register node on chain (MsgRegisterNode)
# Returns: success|tx_hash or error|message
# Includes retry logic for sequence mismatch errors
register_node() {
  local node_id="$1"
  local private_key="$2"
  local public_name="${3:-nesa-miner}"
  local version="${4:-v1.0.0}"
  local network_address="${5:-127.0.0.1:8080}"
  local vram="${6:-8000000000}"
  local network_rps="${7:-100.0}"
  local max_retries="${8:-5}"

  log_line "Registering node: node_id=$node_id (max_retries=$max_retries)"

  ${NESA_PYTHON_CMD:-python3} << PYEOF
import sys
import json
import time
import re
from dataclasses import dataclass
import betterproto
from mospy import Account, Transaction
from mospy.clients import HTTPClient
from google.protobuf import any_pb2 as any_pb
import httpx

# Define MsgRegisterNode
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

def build_and_broadcast_tx(account, msg, lcd_url):
    """Build and broadcast transaction, returns (success, result_msg)"""
    # Refresh account data to get latest sequence
    client = HTTPClient(api=lcd_url)
    client.load_account_data(account=account)

    # Build transaction
    tx = Transaction(account=account, gas=200000, chain_id="nesa")
    tx.set_fee(amount=1000, denom="unes")

    # Pack message into Any and add to transaction
    msg_any = any_pb.Any()
    msg_any.value = bytes(msg)
    msg_any.type_url = "/dht.v1.MsgRegisterNode"
    tx._tx_body.messages.append(msg_any)

    # Get signed transaction bytes
    tx_bytes = tx.get_tx_bytes_as_string()

    # Broadcast
    broadcast_url = f"{lcd_url}/cosmos/tx/v1beta1/txs"
    payload = {"tx_bytes": tx_bytes, "mode": "BROADCAST_MODE_SYNC"}

    response = httpx.post(broadcast_url, json=payload, timeout=30)
    result = response.json()

    if "tx_response" in result:
        tx_response = result["tx_response"]
        code = tx_response.get("code", 0)
        if code == 0:
            txhash = tx_response.get("txhash", "unknown")
            return True, txhash
        else:
            raw_log = tx_response.get("raw_log", "Unknown error")
            return False, f"code {code}: {raw_log}"
    else:
        error_msg = result.get("message", str(result))
        return False, f"Broadcast failed: {error_msg}"

try:
    private_key = "${private_key}"
    node_id = "${node_id}"
    public_name = "${public_name}"
    version = "${version}"
    network_address = "${network_address}"
    vram = int(${vram})
    network_rps = float(${network_rps})
    max_retries = int(${max_retries})
    lcd_url = "${LCD_URL}"

    # Create account
    account = Account(private_key=private_key, hrp="nesa")
    wallet_address = account.address

    # Create message
    msg = MsgRegisterNode(
        creator=wallet_address,
        node_id=node_id,
        public_name=public_name,
        version=version,
        network_address=network_address,
        wallet_address=wallet_address,
        vram=vram,
        network_rps=network_rps,
        using_relay=False
    )

    # Initial load to verify account exists
    client = HTTPClient(api=lcd_url)
    try:
        client.load_account_data(account=account)
    except Exception as load_err:
        print(f"error|Account not found on chain. Please fund your wallet first: {wallet_address}")
        sys.exit(0)

    # Retry loop for sequence mismatch
    last_error = ""
    for attempt in range(max_retries):
        success, result = build_and_broadcast_tx(account, msg, lcd_url)

        if success:
            print(f"success|{result}")
            sys.exit(0)

        last_error = result

        # Check if it's a sequence mismatch error
        if "sequence mismatch" in result.lower() or "incorrect account sequence" in result.lower():
            match = re.search(r'expected (\d+)', result)
            if match:
                account.next_sequence = int(match.group(1))
            wait_time = 0.5 * (attempt + 1)
            time.sleep(wait_time)
            continue
        else:
            break

    print(f"error|Transaction failed after {max_retries} attempts: {last_error}")

except Exception as e:
    print(f"error|{str(e)}")
PYEOF
}

# Register miner on chain (MsgRegisterMiner)
# Returns: success|tx_hash or error|message
# Includes retry logic for sequence mismatch errors
register_miner() {
  local node_id="$1"
  local private_key="$2"
  local model_name="${3:-nesaorg/llama-3.2-1b-instruct-ee}"
  local max_retries="${4:-5}"

  log_line "Registering miner: node_id=$node_id model=$model_name (max_retries=$max_retries)"

  ${NESA_PYTHON_CMD:-python3} << PYEOF
import sys
import json
import time
import re
from dataclasses import dataclass
from typing import List
import betterproto
from mospy import Account, Transaction
from mospy.clients import HTTPClient
from google.protobuf import any_pb2 as any_pb
import httpx

# Define MsgRegisterMiner
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

def build_and_broadcast_tx(account, msg, lcd_url):
    """Build and broadcast transaction, returns (success, result_msg)"""
    # Refresh account data to get latest sequence
    client = HTTPClient(api=lcd_url)
    client.load_account_data(account=account)

    # Build transaction
    tx = Transaction(account=account, gas=200000, chain_id="nesa")
    tx.set_fee(amount=1000, denom="unes")

    # Pack message into Any and add to transaction
    msg_any = any_pb.Any()
    msg_any.value = bytes(msg)
    msg_any.type_url = "/dht.v1.MsgRegisterMiner"
    tx._tx_body.messages.append(msg_any)

    # Get signed transaction bytes
    tx_bytes = tx.get_tx_bytes_as_string()

    # Broadcast
    broadcast_url = f"{lcd_url}/cosmos/tx/v1beta1/txs"
    payload = {"tx_bytes": tx_bytes, "mode": "BROADCAST_MODE_SYNC"}

    response = httpx.post(broadcast_url, json=payload, timeout=30)
    result = response.json()

    if "tx_response" in result:
        tx_response = result["tx_response"]
        code = tx_response.get("code", 0)
        if code == 0:
            txhash = tx_response.get("txhash", "unknown")
            return True, txhash
        else:
            raw_log = tx_response.get("raw_log", "Unknown error")
            return False, f"code {code}: {raw_log}"
    else:
        error_msg = result.get("message", str(result))
        return False, f"Broadcast failed: {error_msg}"

try:
    private_key = "${private_key}"
    node_id = "${node_id}"
    model_name = "${model_name}"
    max_retries = int(${max_retries})
    lcd_url = "${LCD_URL}"

    # Create account
    account = Account(private_key=private_key, hrp="nesa")
    wallet_address = account.address

    # Create message
    msg = MsgRegisterMiner(
        creator=wallet_address,
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

    # Initial load to verify account exists
    client = HTTPClient(api=lcd_url)
    try:
        client.load_account_data(account=account)
    except Exception as load_err:
        print(f"error|Account not found on chain. Please fund your wallet first: {wallet_address}")
        sys.exit(0)

    # Retry loop for sequence mismatch
    last_error = ""
    for attempt in range(max_retries):
        success, result = build_and_broadcast_tx(account, msg, lcd_url)

        if success:
            print(f"success|{result}")
            sys.exit(0)

        last_error = result

        # Check if it's a sequence mismatch error
        if "sequence mismatch" in result.lower() or "incorrect account sequence" in result.lower():
            match = re.search(r'expected (\d+)', result)
            if match:
                account.next_sequence = int(match.group(1))
            wait_time = 0.5 * (attempt + 1)
            time.sleep(wait_time)
            continue
        else:
            break

    print(f"error|Transaction failed after {max_retries} attempts: {last_error}")

except Exception as e:
    print(f"error|{str(e)}")
PYEOF
}

# Submit miner deposit transaction
# Returns: success|tx_hash or error|message
# Includes retry logic for sequence mismatch errors
submit_miner_deposit() {
  local node_id="$1"
  local amount_unes="$2"
  local private_key="$3"
  local max_retries="${4:-5}"

  local amount_nes_log=$(safe_divide "$amount_unes" 1000000 6)
  log_line "Submitting miner deposit: node_id=$node_id, amount=${amount_nes_log} NES (max_retries=$max_retries)"

  ${NESA_PYTHON_CMD:-python3} << PYEOF
import sys
import json
import time
import re
from dataclasses import dataclass
import betterproto
from mospy import Account, Transaction
from mospy.clients import HTTPClient
from google.protobuf import any_pb2 as any_pb
import httpx

# Define the Cosmos SDK Coin message
@dataclass(eq=False, repr=False)
class Coin(betterproto.Message):
    denom: str = betterproto.string_field(1)
    amount: str = betterproto.string_field(2)

# Define MsgAddMinerDeposit
@dataclass(eq=False, repr=False)
class MsgAddMinerDeposit(betterproto.Message):
    depositor: str = betterproto.string_field(1)
    node_id: str = betterproto.string_field(2)
    amount: Coin = betterproto.message_field(3)

def build_and_broadcast_tx(account, node_id, amount_unes, lcd_url):
    """Build and broadcast transaction, returns (success, result_msg)"""
    # Refresh account data to get latest sequence
    client = HTTPClient(api=lcd_url)
    client.load_account_data(account=account)

    # Create transaction
    tx = Transaction(
        account=account,
        gas=150000,
        chain_id="nesa",
    )
    tx.set_fee(amount=1000, denom="unes")

    # Create deposit message
    msg = MsgAddMinerDeposit(
        depositor=account.address,
        node_id=node_id,
        amount=Coin(denom="unes", amount=amount_unes)
    )

    # Pack message into Any and add to transaction
    msg_any = any_pb.Any()
    msg_any.value = bytes(msg)
    msg_any.type_url = "/dht.v1.MsgAddMinerDeposit"
    tx._tx_body.messages.append(msg_any)

    # Get signed transaction bytes
    tx_bytes = tx.get_tx_bytes_as_string()

    # Broadcast transaction
    broadcast_url = f"{lcd_url}/cosmos/tx/v1beta1/txs"
    broadcast_payload = {
        "tx_bytes": tx_bytes,
        "mode": "BROADCAST_MODE_SYNC"
    }

    response = httpx.post(broadcast_url, json=broadcast_payload, timeout=30)
    result = response.json()

    # Check for errors
    if "tx_response" in result:
        tx_response = result["tx_response"]
        code = tx_response.get("code", 0)
        if code == 0:
            tx_hash = tx_response.get("txhash", "")
            return True, tx_hash
        else:
            raw_log = tx_response.get("raw_log", "Unknown error")
            return False, f"code {code}: {raw_log}"
    else:
        error_msg = result.get("message", str(result))
        return False, f"Broadcast failed: {error_msg}"

try:
    private_key = "${private_key}"
    node_id = "${node_id}"
    amount_unes = "${amount_unes}"
    max_retries = int(${max_retries})
    lcd_url = "${LCD_URL}"

    # Create account from private key
    account = Account(
        private_key=private_key,
        hrp="nesa",
    )

    # Initial load to verify account exists
    client = HTTPClient(api=lcd_url)
    try:
        client.load_account_data(account=account)
    except Exception as load_err:
        print(f"error|Account not found on chain. Please fund your wallet first: {account.address}")
        sys.exit(0)

    if account.next_sequence is None:
        print(f"error|Account not initialized on chain. Send funds to {account.address} first.")
        sys.exit(0)

    # Retry loop for sequence mismatch
    last_error = ""
    for attempt in range(max_retries):
        success, result = build_and_broadcast_tx(account, node_id, amount_unes, lcd_url)

        if success:
            print(f"success|{result}")
            sys.exit(0)

        last_error = result

        # Check if it's a sequence mismatch error
        if "sequence mismatch" in result.lower() or "incorrect account sequence" in result.lower():
            # Extract expected sequence if possible
            match = re.search(r'expected (\d+)', result)
            if match:
                expected_seq = int(match.group(1))
                account.next_sequence = expected_seq

            # Wait a bit before retry (increasing delay)
            wait_time = 0.5 * (attempt + 1)
            time.sleep(wait_time)
            continue
        else:
            # Non-retryable error
            break

    print(f"error|Transaction failed after {max_retries} attempts: {last_error}")

except Exception as e:
    print(f"error|{str(e)}")
PYEOF
}

# Add miner deposit - wrapper with UI
add_miner_deposit() {
  local node_id="$1"
  local amount_unes="$2"

  local amount_nes_log=$(safe_divide "$amount_unes" 1000000 6)
  log_line "Add miner deposit: node_id=$node_id, amount=${amount_nes_log} NES"

  # Load private key from config
  if [ -z "$NODE_PRIV_HEX" ]; then
    local orchestrator_env_file="${env_dir}/orchestrator.env"
    if [ -f "$orchestrator_env_file" ]; then
      source "$orchestrator_env_file" 2>/dev/null || true
    fi
  fi

  if [ -z "$NODE_PRIV_HEX" ]; then
    echo "error|Private key not found"
    return 1
  fi

  # Submit the transaction (unes is the base denomination, no conversion needed)
  local result
  result=$(submit_miner_deposit "$node_id" "$amount_unes" "$NODE_PRIV_HEX")

  echo "$result"
}

# Interactive deposit flow with nice UI
# Returns: 0 if deposit successful or skipped, 1 if failed, 2 if user chose to defer
# $4: skip_if_meets_minimum - if "true", return immediately when deposit already meets minimum
show_deposit_flow() {
  local wallet_address="$1"
  local node_id="$2"
  local private_key="$3"
  local skip_if_meets_minimum="${4:-false}"

  log_line "Starting deposit flow for wallet=$wallet_address node=$node_id skip_if_meets_minimum=$skip_if_meets_minimum"

  # Fetch all required data
  echo ""
  gum spin -s line --title "Fetching wallet and deposit info..." -- sleep 1

  # Get wallet balance
  local balance_result
  balance_result=$(check_wallet_balance "$wallet_address")
  local balance_status=$(echo "$balance_result" | cut -d'|' -f1)
  local balance_unes=$(echo "$balance_result" | cut -d'|' -f2)
  local balance_display=$(echo "$balance_result" | cut -d'|' -f3)

  if [ "$balance_status" != "ok" ]; then
    gum style --foreground 196 "Failed to fetch wallet balance"
    return 1
  fi

  # Get minimum deposit requirements
  local params_result
  params_result=$(check_min_deposit)
  local params_status=$(echo "$params_result" | cut -d'|' -f1)
  local min_deposit_unes=$(echo "$params_result" | cut -d'|' -f2)
  local min_deposit_display=$(echo "$params_result" | cut -d'|' -f3)

  if [ "$params_status" != "ok" ]; then
    gum style --foreground 196 "Failed to fetch deposit requirements"
    return 1
  fi

  # Get current miner deposit
  local deposit_result
  deposit_result=$(check_miner_deposit "$node_id")
  local deposit_status=$(echo "$deposit_result" | cut -d'|' -f1)
  local current_deposit_unes=$(echo "$deposit_result" | cut -d'|' -f2)
  local current_deposit_display=$(echo "$deposit_result" | cut -d'|' -f3)
  local bond_status=$(echo "$deposit_result" | cut -d'|' -f4)

  if [ "$deposit_status" != "ok" ]; then
    current_deposit_unes="0"
    current_deposit_display="0"
    bond_status="not_registered"
  fi

  # Calculate shortfall
  local shortfall_unes=$((min_deposit_unes - current_deposit_unes))
  if [ "$shortfall_unes" -lt 0 ]; then
    shortfall_unes=0
  fi

  # Convert shortfall to NES for display
  local shortfall_display
  shortfall_display=$(safe_divide "$shortfall_unes" 1000000 6)

  # Check if miner is not registered - auto-register node and miner
  if [ "$bond_status" = "not_registered" ]; then
    # First check if wallet is funded - can't register without funds
    if [ "$balance_unes" -eq 0 ]; then
      echo ""
      gum style --border rounded --padding "1 2" --border-foreground 196 \
        "$(gum style --foreground 196 --bold "WALLET NOT FUNDED")

Your wallet needs funds before you can register your node.

$(gum style --foreground 43 "Wallet Address:")
$(gum style --foreground 69 "$wallet_address")

Please send at least $(gum style --foreground 214 "$min_deposit_display NES") to this address.
This will cover your minimum deposit plus transaction fees.

$(gum style --foreground 245 "Get testnet tokens from the Nesa Playground faucet:")
$(gum style --foreground "$link_color" "https://beta.nesa.ai/faucet")"
      echo ""

      # Loop until wallet is funded
      while true; do
        local action
        action=$(gum choose --cursor.foreground 42 \
          "Check balance again" \
          "← Back")

        if [ -z "$action" ] || [ "$action" = "← Back" ]; then
          return 2  # User chose to go back, not an error
        fi

        echo ""
        gum spin -s line --title "Checking wallet balance..." -- sleep 1
        balance_result=$(check_wallet_balance "$wallet_address")
        balance_status=$(echo "$balance_result" | cut -d'|' -f1)
        balance_unes=$(echo "$balance_result" | cut -d'|' -f2)
        balance_display=$(echo "$balance_result" | cut -d'|' -f3)

        if [ "$balance_status" = "ok" ] && [ "$balance_unes" -gt 0 ]; then
          echo ""
          gum style --foreground 42 "Wallet funded. Balance: ${balance_display} NES"
          echo ""
          sleep 1
          break
        else
          gum style --foreground 214 "Wallet still has no balance. Please fund it first."
          echo ""
        fi
      done
    fi

    echo ""
    gum style --border rounded --padding "1 2" --border-foreground 214 \
      "$(gum style --foreground 214 --bold "REGISTRATION REQUIRED")

  Your node and miner are not yet registered on the blockchain.
  Registering them now..."

    # Step 1: Check and register node
    echo ""
    gum spin -s line --title "Checking node registration..." -- sleep 1

    local node_check
    node_check=$(check_node_registered "$node_id")
    local node_status=$(echo "$node_check" | cut -d'|' -f2)

    if [ "$node_status" = "not_registered" ]; then
      echo ""
      gum style --foreground 43 "Registering node on blockchain..."

      # Retry loop for sequence mismatch errors
      local node_result node_tx_status node_tx_data
      local max_retries=5
      local retry_count=0

      while [ $retry_count -lt $max_retries ]; do
        node_result=$(register_node "$node_id" "$private_key")
        node_tx_status=$(echo "$node_result" | cut -d'|' -f1)
        node_tx_data=$(echo "$node_result" | cut -d'|' -f2-)

        if [ "$node_tx_status" = "success" ]; then
          break
        elif [[ "$node_tx_data" == *"sequence"* ]] || [[ "$node_tx_data" == *"account sequence mismatch"* ]]; then
          retry_count=$((retry_count + 1))
          if [ $retry_count -lt $max_retries ]; then
            gum style --foreground 214 "    Sequence mismatch, retrying ($retry_count/$max_retries)..."
            sleep 2
          fi
        else
          # Non-retryable error
          break
        fi
      done

      if [ "$node_tx_status" = "success" ]; then
        gum style --foreground 42 "[OK] Node registered"
        gum style --foreground 245 "    TX: ${node_tx_data}"
        gum spin -s line --title "Waiting for confirmation..." -- sleep 5
      else
        echo ""
        gum style --border rounded --padding "1 2" --border-foreground 196 \
          "$(gum style --foreground 196 --bold "NODE REGISTRATION FAILED")

  $(gum style --foreground 250 "Error:") $node_tx_data"
        echo ""
        read -p "> Press Enter to continue..."
        return 1
      fi
    else
      gum style --foreground 42 "[OK] Node already registered"
    fi

    # Step 2: Register miner
    echo ""
    gum spin -s line --title "Registering miner..." -- sleep 1

    # Retry loop for sequence mismatch errors
    local miner_result miner_tx_status miner_tx_data
    local max_retries=5
    local retry_count=0

    while [ $retry_count -lt $max_retries ]; do
      miner_result=$(register_miner "$node_id" "$private_key" "nesaorg/llama-3.2-1b-instruct-ee")
      miner_tx_status=$(echo "$miner_result" | cut -d'|' -f1)
      miner_tx_data=$(echo "$miner_result" | cut -d'|' -f2-)

      if [ "$miner_tx_status" = "success" ]; then
        break
      elif [[ "$miner_tx_data" == *"sequence"* ]] || [[ "$miner_tx_data" == *"account sequence mismatch"* ]]; then
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
          gum style --foreground 214 "    Sequence mismatch, retrying ($retry_count/$max_retries)..."
          sleep 2
        fi
      else
        # Non-retryable error (including "already registered")
        break
      fi
    done

    if [ "$miner_tx_status" = "success" ]; then
      gum style --foreground 42 "[OK] Miner registered"
      gum style --foreground 245 "    TX: ${miner_tx_data}"
      gum spin -s line --title "Waiting for confirmation..." -- sleep 5
    else
      # Check if error is "miner already registered"
      if [[ "$miner_tx_data" == *"already"* ]] || [[ "$miner_tx_data" == *"exists"* ]]; then
        gum style --foreground 42 "[OK] Miner already registered"
      else
        echo ""
        gum style --border rounded --padding "1 2" --border-foreground 196 \
          "$(gum style --foreground 196 --bold "MINER REGISTRATION FAILED")

  $(gum style --foreground 250 "Error:") $miner_tx_data"
        echo ""
        read -p "> Press Enter to continue..."
        return 1
      fi
    fi

    echo ""
    gum style --foreground 42 --bold "Registration complete. Now let's add your deposit."
    echo ""
    read -p "> Press Enter to continue..."

    # Refresh deposit info after registration
    deposit_result=$(check_miner_deposit "$node_id")
    deposit_status=$(echo "$deposit_result" | cut -d'|' -f1)
    current_deposit_unes=$(echo "$deposit_result" | cut -d'|' -f2)
    current_deposit_display=$(echo "$deposit_result" | cut -d'|' -f3)
    bond_status=$(echo "$deposit_result" | cut -d'|' -f4)
  fi

  # Check if deposit meets minimum
  local deposit_meets_minimum=false
  if [ "$current_deposit_unes" -ge "$min_deposit_unes" ]; then
    deposit_meets_minimum=true
    # If skip_if_meets_minimum is true, skip deposit screen entirely
    if [ "$skip_if_meets_minimum" = "true" ]; then
      echo ""
      gum style --foreground 42 "Deposit status: ${current_deposit_display} NES (meets minimum of ${min_deposit_display} NES)"
      sleep 1
      return 0
    fi
  fi

  # Calculate gas fee estimate (fixed at 1000 unes = 0.001 NES)
  local gas_fee_unes=1000
  local gas_fee_display
  gas_fee_display=$(safe_divide "$gas_fee_unes" 1000000 6)

  # Show deposit screen (only if deposit doesn't meet minimum)
  while true; do
    clear
    update_header

    echo ""

    # Different header based on whether deposit meets minimum
    if [ "$deposit_meets_minimum" = true ]; then
      local status_color=42
      local status_text="DEPOSIT STATUS"
      local status_desc="Your deposit meets the minimum requirement. You can add more if you wish."
      local amount_needed_line=""
    else
      local status_color=214
      local status_text="MINER DEPOSIT"
      local status_desc="Your node requires a deposit to participate in the network."
      local amount_needed_line="
  $(gum style --foreground 214 "Shortfall:")          ${shortfall_display} NES"
    fi

    gum style --border rounded --padding "1 2" --border-foreground "$status_color" \
      "$(gum style --foreground "$status_color" --bold "$status_text")

$(gum style --foreground 250 "$status_desc")

  $(gum style --foreground 245 "─────────────────────────────────────────────────────────────────")

  $(gum style --foreground 43 "Wallet:")             ${wallet_address}
  $(gum style --foreground 43 "Balance:")            $(gum style --bold "${balance_display} NES")

  $(gum style --foreground 245 "─────────────────────────────────────────────────────────────────")

  $(gum style --foreground 43 "Minimum Required:")   ${min_deposit_display} NES
  $(gum style --foreground 43 "Current Deposit:")    $(gum style --foreground $status_color "${current_deposit_display} NES")
  $(gum style --foreground 43 "Bond Status:")        $(gum style --foreground $status_color "${bond_status}")${amount_needed_line}

  $(gum style --foreground 245 "─────────────────────────────────────────────────────────────────")

  $(gum style --foreground 250 "Gas Fee:")            ~${gas_fee_display} NES

$(gum style --foreground 245 --italic "Deposits are held in escrow and can be withdrawn after
a 7-day unbonding period.")"

    echo ""

    # Determine default amount (in NES)
    local default_amount
    if [ "$deposit_meets_minimum" = true ]; then
      default_amount="0.001"  # 0.001 NES = 1000 unes
    elif [ "$shortfall_unes" -gt 0 ]; then
      default_amount="$shortfall_display"
    else
      default_amount="$min_deposit_display"
    fi

    # If deposit already meets minimum, offer choice first
    if [ "$deposit_meets_minimum" = true ]; then
      local action_choice
      action_choice=$(gum choose --cursor.foreground 42 \
        "Add more deposit" \
        "← Back")

      if [ -z "$action_choice" ] || [ "$action_choice" = "← Back" ]; then
        return 0
      fi
    fi

    local deposit_amount
    deposit_amount=$(gum input \
      --placeholder "Enter deposit amount in NES" \
      --value "$default_amount" \
      --prompt "Deposit amount: " \
      --prompt.foreground "$main_color")

    echo ""
    local nav
    nav=$(gum choose --cursor.foreground "$main_color" "Next →" "← Back")
    if [ "$nav" = "← Back" ]; then
      continue  # Re-show deposit screen
    fi

    # Handle empty input or cancel
    if [ -z "$deposit_amount" ]; then
      echo ""
      if [ "$deposit_meets_minimum" = true ]; then
        continue
      fi
      # Deposit is required - cannot skip
      gum style --foreground 196 "Deposit is required to run a node. Please enter an amount."
      sleep 2
      continue
    fi

    # Convert user input from NES to unes (1 NES = 1,000,000 unes)
    local deposit_unes
    if command -v bc >/dev/null 2>&1; then
      deposit_unes=$(echo "$deposit_amount * 1000000" | bc | cut -d. -f1)
    else
      deposit_unes=$(safe_multiply "$deposit_amount" 1000000 0)
    fi

    # Validate amount
    local total_needed=$((deposit_unes + gas_fee_unes))

    if [ -z "$deposit_unes" ] || [ "$deposit_unes" -le 0 ]; then
      gum style --foreground 196 "Amount must be greater than 0"
      sleep 2
      continue
    fi

    if [ "$total_needed" -gt "$balance_unes" ]; then
      gum style --foreground 196 "Insufficient balance. You need ${deposit_amount} NES + ~${gas_fee_display} NES for gas."
      gum style --foreground 196 "Your balance: ${balance_display} NES"
      sleep 3
      continue
    fi

    # Calculate final deposit
    local final_deposit_unes=$((current_deposit_unes + deposit_unes))
    local final_deposit_display
    final_deposit_display=$(safe_divide "$final_deposit_unes" 1000000 6)

    local remaining_balance_unes=$((balance_unes - total_needed))
    local remaining_balance_display
    remaining_balance_display=$(safe_divide "$remaining_balance_unes" 1000000 6)

    local meets_minimum="Below minimum"
    local meets_color=196
    if [ "$final_deposit_unes" -ge "$min_deposit_unes" ]; then
      meets_minimum="OK"
      meets_color=42
    fi

    # Calculate total cost for display
    local total_cost_unes=$((deposit_unes + gas_fee_unes))
    local total_cost_display
    total_cost_display=$(safe_divide "$total_cost_unes" 1000000 6)

    # Show confirmation
    echo ""
    gum style --border rounded --padding "1 2" --border-foreground 43 \
      "$(gum style --foreground 43 --bold "CONFIRM TRANSACTION")

  $(gum style --foreground 245 "─────────────────────────────────────────────────────────────────")

  $(gum style --foreground 250 "Deposit Amount:")     ${deposit_amount} NES
  $(gum style --foreground 250 "Gas Fee:")            ~${gas_fee_display} NES
  $(gum style --foreground 245 "─────────────────────────────────────────────────────────────────")
  $(gum style --foreground 43 "Total Cost:")          $(gum style --bold "${total_cost_display} NES")

  $(gum style --foreground 245 "─────────────────────────────────────────────────────────────────")

  $(gum style --foreground 250 "After Transaction:")
  $(gum style --foreground 250 "Your Deposit:")       ${final_deposit_display} NES  $(gum style --foreground $meets_color "[$meets_minimum]")
  $(gum style --foreground 250 "Remaining Balance:")  ${remaining_balance_display} NES"

    echo ""

    # Confirm - different options if already meets minimum
    local confirm
    if [ "$deposit_meets_minimum" = true ]; then
      confirm=$(gum choose --cursor.foreground 42 "Submit Deposit" "Change Amount" "← Back")
    else
      # Deposit is required, but allow back to menu to fund wallet first
      confirm=$(gum choose --cursor.foreground 42 "Submit Deposit" "Change Amount" "← Back")
    fi

    case "$confirm" in
      "Submit Deposit")
        echo ""
        gum spin -s line --title "Submitting deposit transaction..." -- sleep 1

        # Actually submit the transaction (pass unes value to chain)
        local tx_result
        tx_result=$(add_miner_deposit "$node_id" "$deposit_unes")

        local tx_status=$(echo "$tx_result" | cut -d'|' -f1)
        local tx_data=$(echo "$tx_result" | cut -d'|' -f2-)

        if [ "$tx_status" = "success" ]; then
          echo ""
          gum style --border rounded --padding "1 2" --border-foreground 42 \
            "$(gum style --foreground 42 --bold "DEPOSIT SUCCESSFUL")

  $(gum style --foreground 250 "Transaction Hash:")
  $(gum style --foreground 69 "$tx_data")

  Your deposit of ${deposit_amount} NES has been submitted.
  It may take a few seconds to confirm on-chain."
          echo ""

          # Update the deposit status for next iteration
          deposit_meets_minimum=true
          current_deposit_unes=$final_deposit_unes
          current_deposit_display=$final_deposit_display

          sleep 2
          # Ask if they want to add more
          local more_choice
          more_choice=$(gum choose --cursor.foreground 42 "Add more deposit" "← Back")
          if [ -z "$more_choice" ] || [ "$more_choice" = "← Back" ]; then
            return 0
          fi
          continue
        else
          echo ""
          gum style --border rounded --padding "1 2" --border-foreground 196 \
            "$(gum style --foreground 196 --bold "DEPOSIT FAILED")

  $(gum style --foreground 250 "Error:") $tx_data

  Please try again or check your wallet balance."
          echo ""

          # Offer menu after failure
          local fail_choice
          fail_choice=$(gum choose --cursor.foreground 42 \
            "Try again" \
            "Change amount" \
            "← Back")

          case "$fail_choice" in
            "Try again")
              continue
              ;;
            "Change amount")
              continue
              ;;
            "← Back")
              return 0
              ;;
            *)
              continue
              ;;
          esac
        fi
        ;;
      "Change Amount")
        continue
        ;;
      "← Back")
        # Go back to previous screen
        return 0
        ;;
      *)
        # Empty selection or escape - loop back
        continue
        ;;
    esac
  done
}

# Check minimum deposit requirements
check_min_deposit() {
  local lcd_url="${LCD_URL}"
  local params_endpoint="${lcd_url}/nesachain/dht/params"

  log_line "Checking minimum deposit requirements"

  local json_data
  local http_code
  json_data=$(curl -s -w "\n%{http_code}" "$params_endpoint" 2>&1)
  http_code=$(echo "$json_data" | tail -1)
  json_data=$(echo "$json_data" | sed '$d')

  if [ "$http_code" != "200" ]; then
    echo "error|Failed to fetch params"
    return 1
  fi

  # Extract miner and orchestrator minimum deposits
  local miner_min_amount=$(echo "$json_data" | jq -r '.params.miner_min_deposit.amount // "0"')
  local miner_min_denom=$(echo "$json_data" | jq -r '.params.miner_min_deposit.denom // "unes"')
  local orch_min_amount=$(echo "$json_data" | jq -r '.params.orchestrator_min_deposit.amount // "0"')
  local orch_min_denom=$(echo "$json_data" | jq -r '.params.orchestrator_min_deposit.denom // "unes"')

  # Extract unbonding periods
  local miner_unbond=$(echo "$json_data" | jq -r '.params.miner_unbonding_period // "0s"')
  local orch_unbond=$(echo "$json_data" | jq -r '.params.orchestrator_unbonding_period // "0s"')

  # Convert unes to NES for display (1 NES = 1,000,000 unes)
  local miner_min_display
  local orch_min_display
  miner_min_display=$(safe_divide "$miner_min_amount" 1000000 6)
  orch_min_display=$(safe_divide "$orch_min_amount" 1000000 6)

  # Display as NES
  local miner_denom_display="NES"
  local orch_denom_display="NES"

  echo "ok|$miner_min_amount|$miner_min_display|$miner_denom_display|$orch_min_amount|$orch_min_display|$orch_denom_display|$miner_unbond|$orch_unbond"
}

# Management menu for balance and deposit operations
show_management_menu() {
  while true; do
    clear
    update_header

    # Load configuration
    local config_env_file="${env_dir}/.env"
    local orchestrator_env_file="${env_dir}/orchestrator.env"

    if [ ! -f "$orchestrator_env_file" ]; then
      echo "Error: Configuration not found. Please run the bootstrap wizard first."
      return 1
    fi

    # Source the config to get NODE_PRIV_HEX
    source "$orchestrator_env_file" 2>/dev/null || true

    if [ -z "$NODE_PRIV_HEX" ]; then
      echo "Error: Private key not found in configuration."
      return 1
    fi

    # Derive wallet address
    local wallet_address
    wallet_address=$(derive_wallet_address "$NODE_PRIV_HEX" "nesa")

    # Get node ID if available
    local node_id=""
    if [ -f "$node_id_file" ]; then
      node_id=$(cat "$node_id_file" 2>/dev/null | tr -d '\n\r')
    fi

    # Show current status
    echo ""
    gum style --border normal --padding "1 2" --border-foreground "$main_color" \
      "$(gum style --foreground "$main_color" --bold "Miner Management")

Wallet Address: $wallet_address
Node ID: ${node_id:-"(not available - start your node first)"}"

    echo ""

    # Menu options
    local choice
    choice=$(gum choose \
      --cursor.foreground "$main_color" \
      --item.foreground "$link_color" \
      "Check Wallet Balance" \
      "Check Miner Deposit Status" \
      "Check Minimum Deposit Requirements" \
      "Add Miner Deposit" \
      "Return to Main Menu" \
      "Exit")

    case "$choice" in
      "Check Wallet Balance")
        echo ""
        gum spin -s line --title "Fetching wallet balance..." -- sleep 1

        local balance_result
        balance_result=$(check_wallet_balance "$wallet_address")
        local status=$(echo "$balance_result" | cut -d'|' -f1)
        local balance_micro=$(echo "$balance_result" | cut -d'|' -f2)
        local balance_display=$(echo "$balance_result" | cut -d'|' -f3)
        local error_msg=$(echo "$balance_result" | cut -d'|' -f4-)

        echo ""
        if [ "$status" = "ok" ]; then
          gum style --border double --padding "1 2" --border-foreground "$main_color" \
            "$(gum style --foreground "$main_color" --bold "Wallet Balance")

Balance: $(gum style --foreground "$main_color" --bold "$balance_display NES")"
        else
          echo "Error: Failed to fetch wallet balance."
          if [ -n "$error_msg" ]; then
            echo ""
            echo "Details: $error_msg"
          fi
          echo ""
          echo "Check logs at: ~/.nesa/logs/bootstrap.log"
        fi
        echo ""
        read -r -s -p "Press Enter to continue..." && echo
        ;;

      "Check Miner Deposit Status")
        if [ -z "$node_id" ]; then
          echo ""
          echo "Error: Node ID not found. Please start your node first to generate a Node ID."
          echo ""
          read -r -s -p "Press Enter to continue..." && echo
          continue
        fi

        echo ""
        gum spin -s line --title "Fetching miner deposit status..." -- sleep 1

        local deposit_result
        deposit_result=$(check_miner_deposit "$node_id")
        local status=$(echo "$deposit_result" | cut -d'|' -f1)
        local deposit_micro=$(echo "$deposit_result" | cut -d'|' -f2)
        local deposit_display=$(echo "$deposit_result" | cut -d'|' -f3)
        local bond_status=$(echo "$deposit_result" | cut -d'|' -f4)
        local error_msg=$(echo "$deposit_result" | cut -d'|' -f5-)

        echo ""
        if [ "$status" = "ok" ]; then
          local status_color="$main_color"
          case "$bond_status" in
            "bonded") status_color="2" ;;  # green
            "unbonding") status_color="3" ;;  # yellow
            "unbonded") status_color="1" ;;  # red
            "not_registered") status_color="8" ;;  # gray
          esac

          gum style --border double --padding "1 2" --border-foreground "$main_color" \
            "$(gum style --foreground "$main_color" --bold "Miner Deposit Status")

Node ID: $node_id
Deposit: $(gum style --foreground "$main_color" --bold "$deposit_display NES")
Status:  $(gum style --foreground "$status_color" --bold "$bond_status")"
        else
          echo "Error: Failed to fetch miner deposit status."
          if [ -n "$error_msg" ]; then
            echo ""
            echo "Details: $error_msg"
          fi
          echo ""
          echo "Check logs at: ~/.nesa/logs/bootstrap.log"
        fi
        echo ""
        read -r -s -p "Press Enter to continue..." && echo
        ;;

      "Check Minimum Deposit Requirements")
        echo ""
        gum spin -s line --title "Fetching chain parameters..." -- sleep 1

        local params_result
        params_result=$(check_min_deposit)
        local status=$(echo "$params_result" | cut -d'|' -f1)

        echo ""
        if [ "$status" = "ok" ]; then
          local miner_min_micro=$(echo "$params_result" | cut -d'|' -f2)
          local miner_min_display=$(echo "$params_result" | cut -d'|' -f3)
          local miner_denom=$(echo "$params_result" | cut -d'|' -f4)
          local orch_min_micro=$(echo "$params_result" | cut -d'|' -f5)
          local orch_min_display=$(echo "$params_result" | cut -d'|' -f6)
          local orch_denom=$(echo "$params_result" | cut -d'|' -f7)
          local miner_unbond=$(echo "$params_result" | cut -d'|' -f8)
          local orch_unbond=$(echo "$params_result" | cut -d'|' -f9)

          gum style --border double --padding "1 2" --border-foreground "$main_color" \
            "$(gum style --foreground "$main_color" --bold "Miner Deposit Requirements")

Minimum Deposit:    $(gum style --foreground "$main_color" --bold "$miner_min_display $miner_denom")
Unbonding Period:   $miner_unbond

$(gum style --foreground "8" "Note: You can add deposits anytime. Withdrawals require the unbonding period.")"
        else
          local error_msg=$(echo "$params_result" | cut -d'|' -f2-)
          echo "Error: $error_msg"
        fi
        echo ""
        read -r -s -p "Press Enter to continue..." && echo
        ;;

      "Add Miner Deposit")
        if [ -z "$node_id" ]; then
          echo ""
          echo "Error: Node ID not found. Please start your node first to generate a Node ID."
          echo ""
          read -r -s -p "Press Enter to continue..." && echo
          continue
        fi

        # Use the full deposit flow which includes registration check
        show_deposit_flow "$wallet_address" "$node_id" "$NODE_PRIV_HEX"
        continue
        ;;

      "Return to Main Menu")
        return 0
        ;;

      "Exit")
        echo "Goodbye!"
        exit 0
        ;;

      *)
        return 0
        ;;
    esac
  done
}

log_line "[STAGE 4]: collect config (${mode})"

update_config_var() {
  local file=$1
  local var=$2
  local value=$3
  local temp_file

  temp_file=$(mktemp)

  if grep -q "^$var=" "$file"; then
    # Use a temporary file to handle sed differences
    sed "s|^$var=.*|$var=\"$value\"|" "$file" >"$temp_file" && mv "$temp_file" "$file"
  else
    echo "$var=\"$value\"" >>"$file"
  fi

  # Clean up the temporary file if it still exists
  [ -f "$temp_file" ] && rm "$temp_file"
}

strip_0x_prefix() {
  local key="$1"
  # Remove 0x prefix if present
  echo "${key#0x}"
}
log_line "[STAGE 5]: saving env variables"

save_to_env_file() {
  # Config environment variables
  update_config_var "$config_env_file" "IS_CHAIN" "$IS_CHAIN"
  update_config_var "$config_env_file" "IS_VALIDATOR" "$IS_VALIDATOR"
  update_config_var "$config_env_file" "IS_MINER" "$IS_MINER"
  update_config_var "$config_env_file" "MINER_TYPE" "$MINER_TYPE"
  update_config_var "$config_env_file" "DISTRIBUTED_TYPE" "$DISTRIBUTED_TYPE"

  # Orchestrator environment variables
  update_config_var "$orchestrator_env_file" "IS_DIST" "$IS_DIST"
  update_config_var "$orchestrator_env_file" "HUGGINGFACE_API_KEY" "$HUGGINGFACE_API_KEY"
  update_config_var "$orchestrator_env_file" "MONIKER" "$MONIKER"
  update_config_var "$orchestrator_env_file" "NESA_NODE_TYPE" "$NESA_NODE_TYPE"
  update_config_var "$orchestrator_env_file" "NODE_PRIV_KEY" "$NODE_PRIV_KEY"
  update_config_var "$orchestrator_env_file" "NODE_PRIV_HEX" "$NODE_PRIV_KEY"

  # Save NODE_ID if available (so orchestrator doesn't regenerate)
  if [[ -n "$NODE_ID" && "$NODE_ID" != "pending..." ]]; then
    update_config_var "$orchestrator_env_file" "NODE_ID" "$NODE_ID"
  fi

  # Base environment variables
  # update_config_var "$base_env_file" "MODEL_NAME" "$MODEL_NAME"
  update_config_var "$base_env_file" "MONIKER" "$MONIKER"
  # update_config_var "$base_env_file" "OP_EMAIL" "$OP_EMAIL"
  update_config_var "$base_env_file" "REF_CODE" "$REF_CODE"
  update_config_var "$base_env_file" "PUBLIC_IP" "$PUBLIC_IP"
  update_config_var "$base_env_file" "CHAIN_ID" "$CHAIN_ID"

  # update_config_var "$base_env_file" "ORC_PORT" "$ORC_PORT"
  # update_config_var "$base_env_file" "NODE_OS" "$NODE_OS"
  # update_config_var "$base_env_file" "NODE_ARCH" "$NODE_ARCH"
  # update_config_var "$base_env_file" "NODE_CPU" "$NODE_CPU"
  # update_config_var "$base_env_file" "NODE_CORES" "$NODE_CORES"
  # update_config_var "$base_env_file" "NODE_RAM" "$NODE_RAM"
  # update_config_var "$base_env_file" "NODE_GPU" "$NODE_GPU"
  # update_config_var "$base_env_file" "NODE_GPU_COUNT" "$NODE_GPU_COUNT"
  # update_config_var "$base_env_file" "NODE_VRAM" "$NODE_VRAM"
}

display_config() {
  local exclude_keys=("HUGGINGFACE_API_KEY" "NODE_PRIV_KEY" "IS_DIST" "IS_CHAIN" "IS_VALIDATOR" "IS_MINER" "MINER_TYPE" "DISTRIBUTED_TYPE" "NESA_NODE_TYPE")
  local config_content
  local priv_key_display

  config_content=$(cat "$config_env_file" "$orchestrator_env_file" "$base_env_file" | sort | uniq)

  for key in "${exclude_keys[@]}"; do
    config_content=$(echo "$config_content" | grep -v "^$key=")
  done

  config_content=$(echo "$config_content" | grep -v "=$")

  if [[ -n "$NODE_ID" && "$NODE_ID" != "pending..." ]]; then
    config_content="$config_content"$'\n'"NODE_ID=$NODE_ID"
  fi

  if [[ -n "$NODE_PRIV_KEY" ]]; then
    local pub_key=$(generate_public_key "$NODE_PRIV_KEY")
    local length=${#NODE_PRIV_KEY}
    priv_key_display="$(printf '%*s' "$((length - 4))" '' | tr ' ' '*')${NODE_PRIV_KEY: -4}"
    config_content="$config_content"$'\n'"PRIVATE_KEY=$priv_key_display"$'\n'"PUBLIC_KEY=$pub_key"
  fi

  config_content=$(echo "$config_content" | sed 's/"//g')

  # Display config with explicit colors that work on both light and dark terminals
  echo ""
  echo "$config_content" | while IFS='=' read -r key value; do
    [ -z "$key" ] && continue
    gum style --foreground 6 "$key=$(gum style --foreground 10 "$value")"
  done
  echo ""
}

# Log ingestion endpoint - logs are signed locally and sent to central Nesa server
CONTAINER_INGEST_URL="${CONTAINER_INGEST_URL:-http://38.80.122.133:11444/ingest}"
export INGEST_URL="$CONTAINER_INGEST_URL"
export NODE_ID MONIKER PUBLIC_IP
export NODE_PRIV_HEX="$NODE_PRIV_KEY"

compose_up() {
  local compose_files="compose.yml"
  local gpu_mode="CPU-only"

  cd "$WORKING_DIRECTORY/docker" || {
    echo "Error: Docker directory does not exist."
    exit 1
  }

  # Detect CPU architecture
  local arch
  arch=$(uname -m)

  # Check for ARM64 (Apple Silicon Macs, etc.)
  if [[ "$arch" == "arm64" || "$arch" == "aarch64" ]]; then
    echo ""
    echo "Note: ARM64 architecture detected (Apple Silicon)."
    echo "Running via Rosetta 2 emulation - this is normal and fully supported."
    echo ""
    gpu_mode="CPU-only (ARM64 via Rosetta)"
  # Check for GPU support on x86_64 (use tr for portable lowercase conversion)
  else
    local nogpu_lower
    nogpu_lower=$(echo "$NOGPU" | tr '[:upper:]' '[:lower:]')
    if [[ "$nogpu_lower" == "true" || "$nogpu_lower" == "1" ]]; then
      # User explicitly disabled GPU
      gpu_mode="CPU-only (GPU disabled via NOGPU)"
    elif command -v nvidia-smi >/dev/null 2>&1; then
      # NVIDIA drivers present, check if container toolkit works
      if docker info 2>/dev/null | grep -q "nvidia" || command -v nvidia-container-runtime >/dev/null 2>&1; then
        compose_files="compose.nvidia.yml"
        gpu_mode="GPU-accelerated (NVIDIA)"
      else
        echo ""
        echo "WARNING: NVIDIA GPU detected but container toolkit not configured."
        echo "Running in CPU-only mode. To enable GPU support, run:"
        echo "  sudo nvidia-ctk runtime configure --runtime=docker"
        echo "  sudo systemctl restart docker"
        echo ""
        gpu_mode="CPU-only (toolkit not configured)"
      fi
    else
      # No NVIDIA GPU detected
      gpu_mode="CPU-only (no GPU detected)"
    fi
  fi

  echo ""
  echo "Starting containers in ${gpu_mode} mode..."
  echo "Using compose file: ${compose_files}"
  echo ""

  local files="-f ${compose_files}"
  if [ -f "compose.logs.yml" ]; then
    files="${files} -f compose.logs.yml"
  fi

  # Clean up any orphaned containers that might conflict
  echo "Cleaning up any existing containers..."
  docker compose ${files} \
    --env-file "$base_env_file" \
    --env-file "$orchestrator_env_file" \
    down --remove-orphans 2>/dev/null || true

  # Also remove any containers with conflicting names (from previous runs)
  docker rm -f orchestrator log-signer 2>/dev/null || true

  docker compose ${files} \
    --env-file "$base_env_file" \
    --env-file "$orchestrator_env_file" \
    up --pull always -d --wait || {
      echo "Error: Docker Compose failed to start."
      exit 1
    }

  echo ""
  echo "Docker Compose started successfully! (${gpu_mode})"
}

# Helper to detect compose files from container labels
get_compose_files() {
  local compose_dir="$1"
  local config_files
  config_files=$(docker inspect orchestrator --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}' 2>/dev/null)

  local files=""
  if [ -n "$config_files" ]; then
    # Parse comma-separated list (portable - works on bash 3.x and zsh)
    local OLD_IFS="$IFS"
    IFS=','
    for f in $config_files; do
      local basename_f
      basename_f=$(basename "$f")
      if [ -f "${compose_dir}/${basename_f}" ]; then
        files="${files} -f ${basename_f}"
      fi
    done
    IFS="$OLD_IFS"
  fi

  # Fallback if no labels found or empty result
  if [ -z "$files" ]; then
    if [ -f "${compose_dir}/compose.nvidia.yml" ]; then
      files="-f compose.nvidia.yml"
    else
      files="-f compose.yml"
    fi
    if [ -f "${compose_dir}/compose.logs.yml" ]; then
      files="${files} -f compose.logs.yml"
    fi
  fi

  echo "$files"
}

# Stop node containers
stop_node() {
  local compose_dir="${WORKING_DIRECTORY:-$HOME/.nesa}/docker"
  if [ ! -d "$compose_dir" ]; then
    gum style --foreground 196 "Docker directory not found. Is the node installed?"
    sleep 2
    return 1
  fi

  cd "$compose_dir" || return 1
  local files
  files=$(get_compose_files "$compose_dir")

  gum spin -s line --title "Stopping node containers..." -- \
    docker compose ${files} stop

  echo ""
  gum style --foreground 42 "Node stopped."
  sleep 1
}

# Pause node containers
pause_node() {
  local compose_dir="${WORKING_DIRECTORY:-$HOME/.nesa}/docker"
  if [ ! -d "$compose_dir" ]; then
    gum style --foreground 196 "Docker directory not found. Is the node installed?"
    sleep 2
    return 1
  fi

  cd "$compose_dir" || return 1
  local files
  files=$(get_compose_files "$compose_dir")

  gum spin -s line --title "Pausing node containers..." -- \
    docker compose ${files} pause

  echo ""
  gum style --foreground 42 "Node paused."
  sleep 1
}

# Resume paused node containers
resume_node() {
  local compose_dir="${WORKING_DIRECTORY:-$HOME/.nesa}/docker"
  if [ ! -d "$compose_dir" ]; then
    gum style --foreground 196 "Docker directory not found. Is the node installed?"
    sleep 2
    return 1
  fi

  cd "$compose_dir" || return 1
  local files
  files=$(get_compose_files "$compose_dir")

  gum spin -s line --title "Resuming node containers..." -- \
    docker compose ${files} unpause

  echo ""
  gum style --foreground 42 "Node resumed."
  sleep 1
}

# Delete node - removes all containers and data
delete_node() {
  clear
  update_header

  echo ""
  gum style --border rounded --padding "1 2" --border-foreground 196 \
    "$(gum style --foreground 196 --bold "PERMANENT NODE DELETION")

$(gum style --foreground 250 "This action is") $(gum style --foreground 196 --bold "IRREVERSIBLE")$(gum style --foreground 250 ". All data will be permanently deleted:")

  $(gum style --foreground 250 "•") Docker containers (orchestrator, watchtower, log-signer)
  $(gum style --foreground 250 "•") Configuration files (~/.nesa/env/)
  $(gum style --foreground 250 "•") Bootstrap logs (~/.nesa/logs/)
  $(gum style --foreground 250 "•") Model cache (~/.nesa/cache/)
  $(gum style --foreground 250 "•") Node identity files (~/.nesa/identity/)

$(gum style --foreground 196 --bold "WARNING: Your wallet private key will NOT be recoverable")
$(gum style --foreground 196 "if you have not backed it up elsewhere.")"

  echo ""
  echo ""

  # Require typing DELETE to confirm
  local confirm_text
  confirm_text=$(gum input \
    --prompt "Type DELETE to confirm permanent deletion: " \
    --placeholder "" \
    --prompt.foreground 196)

  if [ "$confirm_text" != "DELETE" ]; then
    echo ""
    gum style --foreground 214 "Deletion cancelled. Returning to menu."
    sleep 2
    return 0
  fi

  echo ""

  # Final confirmation
  if ! gum confirm --prompt.foreground 196 \
    --affirmative "Yes, delete everything" \
    --negative "No, cancel" \
    "Are you absolutely sure?"; then
    echo ""
    gum style --foreground 214 "Deletion cancelled."
    sleep 2
    return 0
  fi

  echo ""

  # Execute deletion
  local compose_dir="${WORKING_DIRECTORY:-$HOME/.nesa}/docker"
  if [ -d "$compose_dir" ]; then
    cd "$compose_dir" 2>/dev/null
    gum spin -s line --title "Stopping and removing containers..." -- \
      docker compose -f compose.yml down --remove-orphans --volumes 2>/dev/null
  fi

  # Force remove any remaining containers
  docker rm -f orchestrator watchtower log-signer 2>/dev/null

  # Remove all nesa directories
  gum spin -s line --title "Removing node data..." -- sleep 1
  rm -rf "${HOME}/.nesa" 2>/dev/null
  rm -rf "${HOME}/nesa/docker" 2>/dev/null
  rmdir "${HOME}/nesa" 2>/dev/null  # Only removes if empty

  echo ""
  gum style --foreground 42 --bold "Node deleted successfully."
  echo ""
  gum style --foreground 250 "You can run the bootstrap script again to set up a new node."
  sleep 3

  exit 0
}

# Find actual container name (handles both explicit names and compose-generated names)
find_container() {
  local container_name="$1"

  # Try exact name first
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${container_name}$"; then
    echo "$container_name"
    return 0
  fi

  # Try to find compose-generated name (e.g., docker-watchtower-1, docker_watchtower_1)
  local found
  found=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -E "(^|[-_])${container_name}([-_]|$)" | head -1)
  if [ -n "$found" ]; then
    echo "$found"
    return 0
  fi

  return 1
}

# Get container status with color coding
get_container_status() {
  local container_name="$1"
  local status health uptime
  local actual_container

  actual_container=$(find_container "$container_name")
  if [ -z "$actual_container" ]; then
    echo "not_found|—|—"
    return
  fi

  # Get status
  status=$(docker inspect --format '{{.State.Status}}' "$actual_container" 2>/dev/null || echo "unknown")

  # Get health if available - show "ok" for running containers without healthcheck
  local raw_health
  raw_health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$actual_container" 2>/dev/null || echo "unknown")

  if [ "$raw_health" = "none" ]; then
    # No healthcheck defined - show status based on container state
    if [ "$status" = "running" ]; then
      health="ok"
    else
      health="—"
    fi
  else
    health="$raw_health"
  fi

  # Get uptime
  if [ "$status" = "running" ]; then
    local started_at
    started_at=$(docker inspect --format '{{.State.StartedAt}}' "$actual_container" 2>/dev/null)
    if [ -n "$started_at" ]; then
      # Calculate uptime in human-readable format
      local start_epoch now_epoch diff_seconds
      if [ "$OS_TYPE" = "Darwin" ]; then
        # -u flag ensures UTC interpretation (Docker timestamps are UTC)
        start_epoch=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "${started_at%%.*}" "+%s" 2>/dev/null || echo "0")
      else
        start_epoch=$(date -d "${started_at}" "+%s" 2>/dev/null || echo "0")
      fi
      now_epoch=$(date "+%s")
      diff_seconds=$((now_epoch - start_epoch))

      if [ "$diff_seconds" -lt 60 ]; then
        uptime="${diff_seconds}s"
      elif [ "$diff_seconds" -lt 3600 ]; then
        uptime="$((diff_seconds / 60))m $((diff_seconds % 60))s"
      elif [ "$diff_seconds" -lt 86400 ]; then
        uptime="$((diff_seconds / 3600))h $((diff_seconds % 3600 / 60))m"
      else
        uptime="$((diff_seconds / 86400))d $((diff_seconds % 86400 / 3600))h"
      fi
    else
      uptime="—"
    fi
  else
    uptime="—"
  fi

  echo "${status}|${health}|${uptime}"
}

# Show node status dashboard
show_node_status() {
  clear
  update_header

  echo ""
  gum style --bold --foreground "$main_color" "NODE STATUS"
  echo ""

  # Get status for each container
  local orch_status orch_health orch_uptime
  local wt_status wt_health wt_uptime

  IFS='|' read -r orch_status orch_health orch_uptime <<< "$(get_container_status "orchestrator")"
  IFS='|' read -r wt_status wt_health wt_uptime <<< "$(get_container_status "watchtower")"

  # Color coding for status
  local orch_status_color wt_status_color
  case "$orch_status" in
    "running") orch_status_color=42 ;;  # green
    "exited"|"dead") orch_status_color=196 ;;  # red
    "restarting") orch_status_color=214 ;;  # yellow
    *) orch_status_color=245 ;;  # gray
  esac

  case "$wt_status" in
    "running") wt_status_color=42 ;;
    "exited"|"dead") wt_status_color=196 ;;
    "restarting") wt_status_color=214 ;;
    *) wt_status_color=245 ;;
  esac

  # Overall status - check both running state AND health check result
  local overall_status overall_color overall_msg
  if [ "$orch_status" = "running" ] && [ "$orch_health" = "healthy" -o "$orch_health" = "ok" ]; then
    overall_status="HEALTHY"
    overall_color=42
    overall_msg="Your node is running properly"
  elif [ "$orch_status" = "running" ] && [ "$orch_health" = "unhealthy" ]; then
    overall_status="UNHEALTHY"
    overall_color=196
    overall_msg="Orchestrator health check failing - check logs for errors"
  elif [ "$orch_status" = "running" ] && [ "$orch_health" = "starting" ]; then
    overall_status="STARTING"
    overall_color=214
    overall_msg="Orchestrator is starting up, health check in progress..."
  elif [ "$orch_status" = "restarting" ]; then
    overall_status="RESTARTING"
    overall_color=214
    overall_msg="Orchestrator is restarting, please wait..."
  elif [ "$orch_status" = "not_found" ]; then
    overall_status="NOT STARTED"
    overall_color=245
    overall_msg="Node containers have not been started yet"
  else
    overall_status="UNHEALTHY"
    overall_color=196
    overall_msg="Orchestrator is not running - check logs for errors"
  fi

  # Display status box
  gum style --border rounded --padding "1 2" --border-foreground "$overall_color" \
    "$(gum style --foreground "$overall_color" --bold "$overall_status")

$overall_msg"

  echo ""

  # Container table using ANSI colors (gum style --inline not available in all versions)
  # Color codes: 32=green, 31=red, 33=yellow, 90=gray
  local color_reset="\033[0m"
  local color_green="\033[32m"
  local color_red="\033[31m"
  local color_yellow="\033[33m"
  local color_gray="\033[90m"

  # Map status colors to ANSI
  local orch_ansi wt_ansi
  case "$orch_status_color" in
    42) orch_ansi="$color_green" ;;
    196) orch_ansi="$color_red" ;;
    214) orch_ansi="$color_yellow" ;;
    *) orch_ansi="$color_gray" ;;
  esac
  case "$wt_status_color" in
    42) wt_ansi="$color_green" ;;
    196) wt_ansi="$color_red" ;;
    214) wt_ansi="$color_yellow" ;;
    *) wt_ansi="$color_gray" ;;
  esac

  echo -e "${color_gray}─────────────────────────────────────────────────────────────────${color_reset}"
  printf "  %-20s %-12s %-15s %-12s\n" "CONTAINER" "STATUS" "HEALTH" "UPTIME"
  echo -e "${color_gray}─────────────────────────────────────────────────────────────────${color_reset}"

  # Orchestrator row
  printf "  %-20s ${orch_ansi}%-12s${color_reset} %-15s %-12s\n" "orchestrator" "$orch_status" "$orch_health" "$orch_uptime"

  # Watchtower row
  printf "  %-20s ${wt_ansi}%-12s${color_reset} %-15s %-12s\n" "watchtower" "$wt_status" "$wt_health" "$wt_uptime"

  echo -e "${color_gray}─────────────────────────────────────────────────────────────────${color_reset}"

  # Show recent errors if orchestrator is not healthy
  if [ "$orch_health" = "unhealthy" ] || { [ "$orch_status" != "running" ] && [ "$orch_status" != "not_found" ]; }; then
    echo ""
    gum style --foreground 196 --bold "Recent Logs:"
    local err_container
    err_container=$(find_container "orchestrator")
    if [ -n "$err_container" ]; then
      docker logs "$err_container" --tail 10 2>&1 | while read -r line; do
        echo "  $line"
      done
    fi
  fi

  echo ""
}

# Stream orchestrator logs with ability to exit
stream_logs() {
  local container="${1:-orchestrator}"
  local tail_lines="${2:-50}"

  clear
  update_header

  echo ""
  gum style --bold --foreground "$main_color" "LIVE LOGS: $container"
  gum style --foreground 245 "Press Ctrl+C to stop and return to menu"
  echo ""
  gum style --foreground 245 "─────────────────────────────────────────────────────────────────"
  echo ""

  # Find actual container name
  local actual_container
  actual_container=$(find_container "$container")
  if [ -z "$actual_container" ]; then
    gum style --foreground 196 "Container '$container' not found. Start your node first."
    echo ""
    read -r -s -p "Press Enter to continue..." && echo
    return
  fi

  # Stream logs with trap to handle Ctrl+C gracefully
  trap 'echo ""; gum style --foreground 245 "Stopped log streaming."; sleep 1; return 0' INT

  docker logs -f --tail "$tail_lines" "$actual_container" 2>&1

  trap - INT
}

# Show status and logs menu
show_status_and_logs_menu() {
  while true; do
    show_node_status

    local choice
    choice=$(gum choose \
      --cursor.foreground "$main_color" \
      --item.foreground "$link_color" \
      "Refresh Status" \
      "View Live Logs (orchestrator)" \
      "View Last 100 Lines" \
      "View Watchtower Logs" \
      "Return to Main Menu")

    case "$choice" in
      "Refresh Status")
        # Just loop to refresh
        continue
        ;;
      "View Live Logs (orchestrator)")
        stream_logs "orchestrator" 50
        ;;
      "View Last 100 Lines")
        clear
        update_header
        echo ""
        gum style --bold --foreground "$main_color" "LAST 100 LOG LINES"
        echo ""
        gum style --foreground 245 "─────────────────────────────────────────────────────────────────"
        echo ""

        local orch_container
        orch_container=$(find_container "orchestrator")
        if [ -n "$orch_container" ]; then
          docker logs "$orch_container" --tail 100 2>&1 | while IFS= read -r line; do
            echo "$line"
          done
        else
          gum style --foreground 196 "Container 'orchestrator' not found."
        fi

        echo ""
        gum style --foreground 245 "─────────────────────────────────────────────────────────────────"
        echo ""
        read -r -s -p "Press Enter to continue..." && echo
        ;;
      "View Watchtower Logs")
        clear
        update_header
        echo ""
        gum style --bold --foreground "$main_color" "WATCHTOWER LOGS (Last 50 lines)"
        echo ""
        gum style --foreground 245 "─────────────────────────────────────────────────────────────────"
        echo ""

        local wt_container
        wt_container=$(find_container "watchtower")
        if [ -n "$wt_container" ]; then
          docker logs "$wt_container" --tail 50 2>&1 | while IFS= read -r line; do
            echo "$line"
          done
        else
          gum style --foreground 196 "Container 'watchtower' not found."
        fi

        echo ""
        gum style --foreground 245 "─────────────────────────────────────────────────────────────────"
        echo ""
        read -r -s -p "Press Enter to continue..." && echo
        ;;
      "Return to Main Menu"|"")
        return 0
        ;;
    esac
  done
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

# Generate and save NODE_ID from private key (if not already exists)
ensure_node_id() {
  local private_key="$1"

  # If node_id.id already exists, use it (backwards compatibility)
  if [[ -f "$node_id_file" ]]; then
    NODE_ID=$(cat "$node_id_file")
    log_line "Using existing NODE_ID: $NODE_ID"
    return 0
  fi

  # Generate NODE_ID from private key
  if [[ -n "$private_key" ]]; then
    local identity_dir
    identity_dir=$(dirname "$node_id_file")
    mkdir -p "$identity_dir"

    NODE_ID=$(generate_node_id "$private_key")

    # Save to file
    echo -n "$NODE_ID" > "$node_id_file"
    log_line "Generated and saved NODE_ID: $NODE_ID"
  else
    NODE_ID="pending..."
    log_line "No private key available, NODE_ID pending"
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
  : ${IS_CHAIN:="no"}
  : ${IS_VALIDATOR:="no"}
  : ${IS_MINER:="no"}
  : ${MINER_TYPE:=$MINER_TYPE_NONE}
  : ${DISTRIBUTED_TYPE:=$DISTRIBUTED_TYPE_NONE}
  : ${NESA_NODE_TYPE:="nesa"}

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

# deps already checked at script start (STAGE 0)
detect_hardware_capabilities
clear
update_header

# Check if node is already configured (files exist AND have actual config)
# Just checking file existence isn't enough since we touch empty files on startup
config_valid=false
chain_status="unknown"
if [ -f "$orchestrator_env_file" ] && [ -s "$orchestrator_env_file" ]; then
  # File exists and is not empty - check if it has a private key configured
  if grep -q "NODE_PRIV" "$orchestrator_env_file" 2>/dev/null; then
    config_valid=true
  fi
fi

if [ "$config_valid" = true ]; then
  # Node has local config, offer options in a loop
  while true; do
    clear
    update_header

    # Check blockchain state each iteration (refreshes after menu actions)
    log_line "Checking blockchain state..."
    chain_status="unknown"

    # Get node_id from config
    config_node_id=$(grep "^NODE_ID=" "$orchestrator_env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'")

    if [ -n "$config_node_id" ]; then
      # Check node registration
      node_check=$(check_node_registered "$config_node_id" 2>/dev/null || echo "error|check_failed")
      node_reg_status=$(echo "$node_check" | cut -d'|' -f2)

      # Check miner deposit
      deposit_check=$(check_miner_deposit "$config_node_id" 2>/dev/null || echo "error|0|0|unknown|unes")
      deposit_status=$(echo "$deposit_check" | cut -d'|' -f1)
      deposit_amount=$(echo "$deposit_check" | cut -d'|' -f2)
      bond_status=$(echo "$deposit_check" | cut -d'|' -f4)

      # Get minimum deposit requirement
      min_check=$(check_min_deposit 2>/dev/null || echo "ok|0|0")
      min_deposit=$(echo "$min_check" | cut -d'|' -f2)

      # Determine overall chain status
      if [ "$node_reg_status" = "registered" ] && [ "$bond_status" != "not_registered" ] && [ "$deposit_amount" -ge "$min_deposit" ] 2>/dev/null; then
        chain_status="ok"
      elif [ "$node_reg_status" = "registered" ] && [ "$bond_status" != "not_registered" ]; then
        chain_status="needs_deposit"
      elif [ "$node_reg_status" = "registered" ]; then
        chain_status="needs_miner"
      else
        chain_status="needs_registration"
      fi

      log_line "Chain status: node=$node_reg_status, bond=$bond_status, deposit=$deposit_amount, min=$min_deposit, overall=$chain_status"
    fi

    echo ""

    # Show different message based on chain status
    if [ "$chain_status" = "ok" ]; then
      gum style --border normal --padding "1 2" --border-foreground "$main_color" \
        "$(gum style --foreground "$main_color" --bold "Existing Configuration Detected")

Your Nesa node is fully configured and ready."
    elif [ "$chain_status" = "needs_deposit" ]; then
      gum style --border normal --padding "1 2" --border-foreground 214 \
        "$(gum style --foreground 214 --bold "Configuration Incomplete")

Your node is registered but $(gum style --foreground 196 "deposit is below minimum").
Please add deposit to activate your miner."
    elif [ "$chain_status" = "needs_miner" ]; then
      gum style --border normal --padding "1 2" --border-foreground 214 \
        "$(gum style --foreground 214 --bold "Configuration Incomplete")

Your node is registered but $(gum style --foreground 196 "miner is not registered").
Please complete registration via Manage Wallet & Deposits."
    elif [ "$chain_status" = "needs_registration" ]; then
      gum style --border normal --padding "1 2" --border-foreground 196 \
        "$(gum style --foreground 196 --bold "Registration Required")

Local config exists but $(gum style --foreground 196 "node is not registered on chain").
Please complete registration via Manage Wallet & Deposits."
    else
      gum style --border normal --padding "1 2" --border-foreground "$main_color" \
        "$(gum style --foreground "$main_color" --bold "Existing Configuration Detected")

Your Nesa node is already configured."
    fi

    echo ""
    echo "What would you like to do?"
    echo ""

    # Check container state for dynamic menu options
    container_state="stopped"
    orch_status=$(docker inspect -f '{{.State.Status}}' orchestrator 2>/dev/null || echo "")
    if [ "$orch_status" = "running" ]; then
      container_state="running"
    elif [ "$orch_status" = "paused" ]; then
      container_state="paused"
    elif [ -n "$orch_status" ]; then
      container_state="stopped"
    fi

    # Build menu options based on container state
    menu_options=("Node Status & Logs" "Manage Wallet & Deposits")

    case "$container_state" in
      "running")
        menu_options+=("Pause Node" "Stop Node")
        ;;
      "paused")
        menu_options+=("Resume Node" "Stop Node")
        ;;
      *)
        menu_options+=("Start Node")
        ;;
    esac

    menu_options+=("Reconfigure Node" "Delete Node" "Exit")

    existing_choice=$(gum choose \
      --cursor.foreground "$main_color" \
      --item.foreground "$link_color" \
      "${menu_options[@]}")

    case "$existing_choice" in
      "Node Status & Logs")
        show_status_and_logs_menu
        # Loop back to main menu
        ;;
      "Manage Wallet & Deposits")
        show_management_menu
        # Loop back to main menu
        ;;
      "Start Node")
        # Check if node meets requirements before starting
        if [ "$chain_status" = "needs_registration" ]; then
          echo ""
          gum style --border rounded --padding "1 2" --border-foreground 196 \
            "$(gum style --foreground 196 --bold "CANNOT START NODE")

Your node is $(gum style --foreground 196 "not registered on the blockchain").

Please go to $(gum style --foreground "$main_color" "Manage Wallet & Deposits") to:
  1. Fund your wallet with NES
  2. Complete node and miner registration"
          echo ""
          read -r -s -p "Press Enter to continue..." && echo
          continue
        elif [ "$chain_status" = "needs_miner" ]; then
          echo ""
          gum style --border rounded --padding "1 2" --border-foreground 196 \
            "$(gum style --foreground 196 --bold "CANNOT START NODE")

Your node is registered but $(gum style --foreground 196 "miner is not registered").

Please go to $(gum style --foreground "$main_color" "Manage Wallet & Deposits") to:
  1. Ensure your wallet is funded
  2. Complete miner registration"
          echo ""
          read -r -s -p "Press Enter to continue..." && echo
          continue
        elif [ "$chain_status" = "needs_deposit" ]; then
          echo ""
          gum style --border rounded --padding "1 2" --border-foreground 196 \
            "$(gum style --foreground 196 --bold "CANNOT START NODE")

Your deposit is $(gum style --foreground 196 "below the minimum requirement").

Please go to $(gum style --foreground "$main_color" "Manage Wallet & Deposits") to:
  1. Check the minimum deposit requirements
  2. Add more deposit to meet the minimum"
          echo ""
          read -r -s -p "Press Enter to continue..." && echo
          continue
        fi

        clear
        update_header
        echo "Checking for updates..."
        cd "$WORKING_DIRECTORY/docker" || {
          echo "Error: Docker directory does not exist."
          exit 1
        }
        git pull --quiet 2>/dev/null || true
        echo "Starting node containers..."
        compose_up
        cd "$init_pwd" || exit
        echo ""
        echo -e "$(gum style --foreground "$main_color" "nesa") node containers started!"
        echo ""
        read -r -s -p "Press Enter to continue..." && echo
        # Loop back to main menu
        ;;
      "Pause Node")
        pause_node
        ;;
      "Resume Node")
        resume_node
        ;;
      "Stop Node")
        stop_node
        ;;
      "Delete Node")
        delete_node
        ;;
      "Reconfigure Node")
        echo "Proceeding to reconfiguration wizard..."
        sleep 1
        break  # Exit loop to continue to wizard
        ;;
      "Exit")
        exit 0
        ;;
      *)
        # Empty selection (escape pressed) or unknown - stay in menu
        continue
        ;;
    esac
  done
fi

clear
update_header

echo "Setting up working directory..."
setup_work_dir

# Setup wizard with Back/Next navigation
wizard_step=1
existing_key_saved="$NODE_PRIV_KEY"  # Save existing key for "use existing" option

while true; do
  clear
  update_header

  case $wizard_step in
    1) # Moniker (first step)
      show_step_header 1 4 "NODE NAME" \
        "Your node's display name on the Nesa network." \
        "Letters, numbers, hyphens (3-32 characters)" \
        "my-mining-node, server-01, nesa-validator" \
        "required"

      MONIKER=$(gum input --cursor.foreground "${main_color}" \
        --prompt.foreground "${main_color}" \
        --prompt "Node name: " \
        --placeholder "${MONIKER:-my-node}" \
        --width 60 \
        --no-show-help \
        --value "$MONIKER")
      MONIKER=$(echo "$MONIKER" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

      # Show what user entered
      show_input_summary "Node name" "$MONIKER" "required"

      # Validate
      validation=$(validate_input "moniker" "$MONIKER")
      if [ "${validation%%|*}" = "error" ]; then
        gum style --foreground 196 "  ${validation#error|}"
        echo ""
        if gum confirm "" --affirmative "Try Again" --negative "Cancel"; then
          continue
        else
          return_to_main_menu
        fi
      fi

      # Navigation (first step - no back)
      if gum confirm "" --affirmative "Continue →" --negative "Cancel"; then
        wizard_step=2
      else
        return_to_main_menu
      fi
      ;;

    2) # Referral code
      show_step_header 2 4 "REFERRAL CODE" \
        "A Nesa wallet address that referred you to the network." \
        "nesa1... (44 characters starting with nesa1)" \
        "nesa1abc123def456ghi789jkl012mno345pqr678st" \
        "optional"

      REF_CODE=$(gum input --cursor.foreground "${main_color}" \
        --prompt.foreground "${main_color}" \
        --prompt "Referral code: " \
        --placeholder "" \
        --width 60 \
        --no-show-help \
        --value "$REF_CODE")

      # Show what user entered
      show_input_summary "Referral code" "$REF_CODE" "optional"

      # Validate (optional field - only validates if non-empty)
      validation=$(validate_input "referral" "$REF_CODE")
      if [ "${validation%%|*}" = "error" ]; then
        gum style --foreground 196 "  ${validation#error|}"
        echo ""
        err_choice=$(gum choose --header="" --no-show-help --cursor.foreground "$main_color" \
          "Try Again" \
          "← Back" \
          "Return to Main Menu")
        case "$err_choice" in
          "Try Again") continue ;;
          "← Back") wizard_step=1; continue ;;
          "Return to Main Menu"|"") return_to_main_menu ;;
        esac
      fi

      # Navigation
      nav_choice=$(gum choose --header="" --no-show-help --cursor.foreground "$main_color" \
        "Continue →" \
        "← Back" \
        "Return to Main Menu")
      case "$nav_choice" in
        "Continue →") wizard_step=3 ;;
        "← Back") wizard_step=1 ;;
        "Return to Main Menu"|"") return_to_main_menu ;;
      esac
      ;;

    3) # Huggingface API key
      show_step_header 3 4 "HUGGINGFACE API KEY" \
        "Used for downloading AI models from Huggingface Hub." \
        "hf_xxxxxxxxxxxxxxxxxxxx (starts with hf_, ~40 chars)" \
        "hf_aBcDeFgHiJkLmNoPqRsTuVwXyZ123456" \
        "optional" \
        "https://huggingface.co/settings/tokens"

      HUGGINGFACE_API_KEY=$(gum input --cursor.foreground "${main_color}" \
        --prompt.foreground "${main_color}" \
        --prompt "API key: " \
        --placeholder "" \
        --password \
        --width 60 \
        --no-show-help \
        --value "$HUGGINGFACE_API_KEY")

      # Show what user entered (masked for security)
      if [ -n "$HUGGINGFACE_API_KEY" ]; then
        masked_key="${HUGGINGFACE_API_KEY:0:6}$( printf '*%.0s' {1..20} )${HUGGINGFACE_API_KEY: -4}"
        show_input_summary "API key" "$masked_key" "optional"
      else
        show_input_summary "API key" "" "optional"
      fi

      # Validate
      validation=$(validate_input "hf_token" "$HUGGINGFACE_API_KEY")
      if [ "${validation%%|*}" = "error" ]; then
        gum style --foreground 196 "  ${validation#error|}"
        echo ""
        err_choice=$(gum choose --header="" --no-show-help --cursor.foreground "$main_color" \
          "Try Again" \
          "← Back" \
          "Return to Main Menu")
        case "$err_choice" in
          "Try Again") continue ;;
          "← Back") wizard_step=2; continue ;;
          "Return to Main Menu"|"") return_to_main_menu ;;
        esac
      fi

      # Show warning if skipped
      if [ "${validation%%|*}" = "warn" ]; then
        gum style --foreground 214 "  ${validation#warn|}"
        echo ""
      fi

      # Navigation
      nav_choice=$(gum choose --header="" --no-show-help --cursor.foreground "$main_color" \
        "Continue →" \
        "← Back" \
        "Return to Main Menu")
      case "$nav_choice" in
        "Continue →") wizard_step=4 ;;
        "← Back") wizard_step=2 ;;
        "Return to Main Menu"|"") return_to_main_menu ;;
      esac
      ;;

    4) # Wallet setup choice
      echo ""
      gum style --border rounded --padding "1 2" --border-foreground "$main_color" \
        "$(gum style --foreground "$main_color" --bold "STEP 4 OF 4: WALLET SETUP")

$(gum style --foreground 255 "Your wallet holds NES for staking and rewards.")
$(gum style --foreground 255 "You need a secp256k1 private key (same as Ethereum).")

$(gum style --foreground 245 "Select an option below")"
      echo ""

      # Different options based on whether key already exists
      if [ -n "$existing_key_saved" ]; then
        wallet_choice=$(gum choose --header="" --no-show-help --cursor.foreground "$main_color" \
          "Use existing private key" \
          "Enter different private key" \
          "Generate new wallet" \
          "← Back" \
          "Return to Main Menu")

        case "$wallet_choice" in
          "Use existing private key")
            NODE_PRIV_KEY="$existing_key_saved"
            break  # Exit wizard
            ;;
          "Enter different private key")
            wizard_step=5
            ;;
          "Generate new wallet")
            wizard_step=6
            ;;
          "← Back")
            wizard_step=3
            ;;
          "Return to Main Menu"|"")
            return_to_main_menu
            ;;
        esac
      else
        wallet_choice=$(gum choose --header="" --no-show-help --cursor.foreground "$main_color" \
          "Enter existing private key" \
          "Generate new wallet" \
          "← Back" \
          "Return to Main Menu")

        case "$wallet_choice" in
          "Enter existing private key")
            wizard_step=5
            ;;
          "Generate new wallet")
            wizard_step=6
            ;;
          "← Back")
            wizard_step=3
            ;;
          "Return to Main Menu"|"")
            return_to_main_menu
            ;;
        esac
      fi
      ;;

    5) # Enter private key
      echo ""
      gum style --border rounded --padding "1 2" --border-foreground "$main_color" \
        "$(gum style --foreground "$main_color" --bold "ENTER PRIVATE KEY")

$(gum style --foreground 255 "Your wallet's private key (secp256k1, same as Ethereum).")

$(gum style --foreground 250 "Format:") $(gum style --foreground "$link_color" "64 hexadecimal characters (with or without 0x prefix)")
$(gum style --foreground 250 "Example:") $(gum style --foreground 245 "0x1a2b3c4d5e6f... or 1a2b3c4d5e6f...")

$(gum style --foreground 196 "WARNING: Never share your private key with anyone!")"
      echo ""

      NODE_PRIV_KEY=$(gum input --cursor.foreground "${main_color}" \
        --password \
        --prompt.foreground "${main_color}" \
        --prompt "Private key: " \
        --width 70 \
        --no-show-help)

      # Show what user entered (masked)
      if [ -n "$NODE_PRIV_KEY" ]; then
        masked_pk="${NODE_PRIV_KEY:0:4}$( printf '*%.0s' {1..20} )${NODE_PRIV_KEY: -4}"
        show_input_summary "Private key" "$masked_pk" "required"
      else
        show_input_summary "Private key" "" "required"
      fi

      # Validate format
      validation=$(validate_input "private_key" "$NODE_PRIV_KEY")
      if [ "${validation%%|*}" = "error" ]; then
        gum style --foreground 196 "  ${validation#error|}"
        echo ""
        err_choice=$(gum choose --header="" --no-show-help --cursor.foreground "$main_color" \
          "Try Again" \
          "← Back" \
          "Return to Main Menu")
        case "$err_choice" in
          "Try Again") continue ;;
          "← Back") wizard_step=4; continue ;;
          "Return to Main Menu"|"") return_to_main_menu ;;
        esac
      fi

      # Strip 0x prefix for storage
      NODE_PRIV_KEY="${NODE_PRIV_KEY#0x}"
      NODE_PRIV_KEY="${NODE_PRIV_KEY#0X}"

      # Derive wallet address for confirmation
      echo ""
      gum spin -s line --title "Deriving wallet address..." -- sleep 1
      derived_address=$(derive_wallet_address "$NODE_PRIV_KEY" "nesa" 2>/dev/null || echo "error")

      if [ "$derived_address" = "error" ]; then
        echo ""
        gum style --foreground 196 "Failed to derive wallet address. Please check your private key."
        sleep 2
        NODE_PRIV_KEY=""
        continue
      fi

      # Show verification
      echo ""
      gum style --border rounded --padding "1 2" --border-foreground 214 \
        "$(gum style --foreground 214 --bold "VERIFY YOUR WALLET")

$(gum style --foreground 255 "Derived wallet address:")
$(gum style --foreground "$link_color" --bold "$derived_address")

$(gum style --foreground 250 "Does this match your expected wallet address?")"
      echo ""

      verify_choice=$(gum choose --header="" --no-show-help --cursor.foreground "$main_color" \
        "Yes, correct" \
        "Re-enter" \
        "← Back" \
        "Return to Main Menu")
      case "$verify_choice" in
        "Yes, correct") break ;;  # Exit wizard with key
        "Re-enter") NODE_PRIV_KEY="" ;;  # Stay on step 5
        "← Back") wizard_step=4 ;;
        "Return to Main Menu"|"") return_to_main_menu ;;
      esac
      ;;

    6) # Generate new wallet
      echo ""
      gum spin -s line --title "Generating new wallet..." -- sleep 1

      # Generate 32 random bytes = 64 hex characters
      NODE_PRIV_KEY=$(openssl rand -hex 32)

      # Derive address and public key
      new_wallet_address=$(derive_wallet_address "$NODE_PRIV_KEY" "nesa")
      new_public_key=$(generate_public_key "$NODE_PRIV_KEY")

      clear
      update_header

      echo ""
      gum style --border double --padding "1 2" --border-foreground 214 \
        "$(gum style --foreground 214 --bold "NEW WALLET GENERATED")

$(gum style --foreground 196 --bold "IMPORTANT: SAVE THIS PRIVATE KEY NOW!")
$(gum style --foreground 196 "This is the ONLY time it will be displayed.")

$(gum style --foreground 245 "─────────────────────────────────────────────────────────────")

$(gum style --foreground "$main_color" "Private Key:")
$(gum style --foreground 255 --bold "$NODE_PRIV_KEY")

$(gum style --foreground "$main_color" "Wallet Address:")
$(gum style --foreground 255 "$new_wallet_address")

$(gum style --foreground "$main_color" "Public Key:")
$(gum style --foreground 255 "$new_public_key")

$(gum style --foreground 245 "─────────────────────────────────────────────────────────────")

$(gum style --foreground 250 "Store your private key securely. Anyone with this key")
$(gum style --foreground 250 "can access your wallet and funds.")"

      echo ""

      # Make them confirm they saved it
      if ! gum confirm --prompt.foreground 214 "I have saved my private key securely"; then
        echo ""
        gum style --foreground 214 "Please save your private key before continuing!"
        echo ""
        gum style --foreground 255 "Private Key: $NODE_PRIV_KEY"
        echo ""
        read -r -s -p "Press Enter once you have saved it..." && echo
      fi

      echo ""
      gum style --border rounded --padding "1 2" --border-foreground "$main_color" \
        "$(gum style --foreground "$main_color" --bold "FUND YOUR WALLET")

Before your node can register and start mining, you need
to fund your wallet with NES.

$(gum style --foreground "$main_color" "Send tokens to:")
$(gum style --foreground 255 --bold "$new_wallet_address")

$(gum style --foreground 245 "Get testnet tokens from the Nesa Playground faucet:")
$(gum style --foreground "$link_color" "https://beta.nesa.ai/faucet")"

      echo ""

      # Check balance loop
      go_back=false
      while true; do
        fund_choice=$(gum choose --header="" --no-show-help \
          --cursor.foreground "$main_color" \
          "Check Balance" \
          "Continue (I'll fund it later)" \
          "← Back")

        if [ "$fund_choice" = "Check Balance" ]; then
          gum spin -s line --title "Checking wallet balance..." -- sleep 1
          balance_result=$(check_wallet_balance "$new_wallet_address")
          balance_status=$(echo "$balance_result" | cut -d'|' -f1)
          balance_display=$(echo "$balance_result" | cut -d'|' -f3)

          if [ "$balance_status" = "ok" ] && [ "$balance_display" != "0" ]; then
            echo ""
            gum style --foreground 42 "Balance: $balance_display NES"
            echo ""
            break
          else
            echo ""
            gum style --foreground 214 "Balance: 0 NES - Wallet not funded yet"
            echo ""
          fi
        elif [ -z "$fund_choice" ] || [ "$fund_choice" = "← Back" ]; then
          go_back=true
          break
        else
          echo ""
          gum style --foreground 214 "Note: You'll need to fund your wallet before registration can complete."
          break
        fi
      done

      if [ "$go_back" = true ]; then
        wizard_step=4
        continue
      fi
      break  # Exit wizard after wallet generation
      ;;
  esac
done

NODE_PRIV_KEY=$(strip_0x_prefix "$NODE_PRIV_KEY")

clear
update_header

NESA_NODE_TYPE="nesa"
MINER_TYPE=$miner_type_agnostic
DISTRIBUTED_TYPE=$distributed_type_agnostic
IS_MINER="yes"
IS_DIST=False

# Generate NODE_ID from private key (if not already exists)
# This ensures NODE_ID is available before orchestrator starts
ensure_node_id "$NODE_PRIV_KEY"

save_to_env_file

clear
update_header

display_config

echo ""
echo "What would you like to do?"
echo ""

post_config_choice=$(gum choose \
  --cursor.foreground "$main_color" \
  --item.foreground "$link_color" \
  "Start Node Now" \
  "Return to Main Menu")

if [ "$post_config_choice" != "Start Node Now" ]; then
  echo ""
  gum style --foreground "$main_color" "Configuration saved. Returning to main menu..."
  sleep 1
  exec "$SCRIPT_PATH"  # Restart script to show main menu
fi

# Check and handle deposit before starting containers
log_line "[STAGE 5.5]: checking miner deposit"
echo ""
gum style --foreground "$main_color" --bold "Checking deposit status..."

# Get wallet address
WALLET_ADDRESS=$(derive_wallet_address "$NODE_PRIV_KEY" "nesa")

# Show deposit flow (handles checking and prompting if needed)
# Returns: 0 = success, 1 = error, 2 = user chose to defer
# Pass "true" to skip deposit screen if already meets minimum (user just wants to start node)
show_deposit_flow "$WALLET_ADDRESS" "$NODE_ID" "$NODE_PRIV_KEY" "true"
deposit_result=$?

if [ "$deposit_result" -eq 2 ]; then
  # User chose to fund later - go back to main menu without error
  echo ""
  gum style --foreground "$main_color" "Returning to main menu. You can fund your wallet and try again later."
  sleep 2
  exec "$SCRIPT_PATH"
elif [ "$deposit_result" -eq 1 ]; then
  # Actual error
  echo ""
  gum style --border rounded --padding "1 2" --border-foreground 196 \
    "$(gum style --foreground 196 --bold "DEPOSIT CHECK FAILED")

Could not verify deposit status. This may be due to:
- Network connectivity issues
- Wallet not funded

Please fund your wallet and try again."
  echo ""
  read -r -s -p "Press Enter to return to main menu..." && echo
  exec "$SCRIPT_PATH"
fi

cd "$WORKING_DIRECTORY/docker" || {
  echo "Error: Docker directory does not exist."
  exit 1
}
log_line "[STAGE 6]: starting docker containers"

compose_up

cd "$init_pwd" || return
echo -e "Congratulations! Your $(gum style --foreground "$main_color" "nesa") node was successfully bootstrapped!"

# Offer post-setup options in a loop
while true; do
  echo ""
  echo "What would you like to do next?"
  echo ""

  post_setup_choice=$(gum choose \
    --cursor.foreground "$main_color" \
    --item.foreground "$link_color" \
    "View Node Status & Logs" \
    "Manage Wallet & Deposits" \
    "Return to Main Menu" \
    "Exit")

  case "$post_setup_choice" in
    "View Node Status & Logs")
      show_status_and_logs_menu
      # Loop back to post-setup menu
      ;;
    "Manage Wallet & Deposits")
      show_management_menu
      # Loop back to post-setup menu
      ;;
    "Return to Main Menu")
      exec "$SCRIPT_PATH"
      ;;
    "Exit"|"")
      echo ""
      echo "You can run this script again anytime to manage your node, check status, and view logs."
      echo ""
      exit 0
      ;;
  esac
done
