#!/usr/bin/env zsh
# DNVM - Docker Node Version Manager Plugin for Zsh
# Compatible with Antígeno
#
# Author: AI Assistant
# Version: 1.0.0

# DNVM Root Directory
export DNVM_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/dnvm"
export DNVM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dnvm"

# Create necessary directories
mkdir -p "$DNVM_ROOT"/{bin,versions}
mkdir -p "$DNVM_CONFIG_DIR"

# Current session variables
export DNVM_CURRENT_VERSION=""
export DNVM_PREVIOUS_VERSION=""

# Initialize DNVM
function _dnvm_init() {
    # Set default version if not set
    if [[ ! -f "$DNVM_CONFIG_DIR/version" ]]; then
        echo "lts" > "$DNVM_CONFIG_DIR/version"
    fi

    # Set default packages file if not exists
    if [[ ! -f "$DNVM_CONFIG_DIR/default-packages" ]]; then
        echo "npm" > "$DNVM_CONFIG_DIR/default-packages"
        echo "pnpm" >> "$DNVM_CONFIG_DIR/default-packages"
        echo "yarn" >> "$DNVM_CONFIG_DIR/default-packages"
    fi

    # Create default npmrc if not exists
    if [[ ! -f "$DNVM_CONFIG_DIR/npmrc" ]]; then
        echo "fund=false" > "$DNVM_CONFIG_DIR/npmrc"
    fi

    # Read global version
    local global_version=$(cat "$DNVM_CONFIG_DIR/version")
    if [[ "$global_version" != "none" ]]; then
        export DNVM_GLOBAL_VERSION="$global_version"
    fi

    # Add DNVM bin to PATH
    export PATH="$DNVM_ROOT/bin:$PATH"

    # Setup auto-detection for .nvmrc files
    _dnvm_setup_hooks
}

# dnvm use <version> - Use specific Node version for current session
function dnvm-use() {
    local version="$1"

    if [[ -z "$version" ]]; then
        echo "Usage: dnvm use <version>"
        return 1
    fi

    # Normalize version (remove 'v' prefix)
    version=$(echo "$version" | sed 's/^v//')

    # Pull the Node.js Docker image for this version
    if ! docker pull "node:$version" >/dev/null 2>&1; then
        echo "Warning: Failed to pull docker image node:$version"
        echo "Make sure Docker is running and you have internet connection"
    fi

    # Remove previous version from PATH if exists
    if [[ -n "$DNVM_CURRENT_VERSION" && "$DNVM_CURRENT_VERSION" != "$version" ]]; then
        export PATH=$(echo "$PATH" | sed "s|$DNVM_ROOT/bin/$DNVM_CURRENT_VERSION:||g")
        DNVM_PREVIOUS_VERSION="$DNVM_CURRENT_VERSION"
    fi

    # Ensure version is set up
    mkdir -p "$DNVM_ROOT/bin/$version"
    _dnvm_generate_wrappers "$version"

    # Install default packages from file
    _dnvm_install_default_packages "$version"

    # Add new version to PATH - ensure it's at the front
    local new_path="$DNVM_ROOT/bin/$version:$DNVM_ROOT/bin"
    export PATH="$new_path:$PATH"

    export DNVM_CURRENT_VERSION="$version"
}

# dnvm global <version> - Set default Node version
function dnvm-global() {
    local version="$1"

    if [[ -z "$version" ]]; then
        return
    fi

    # Normalize version
    version=$(echo "$version" | sed 's/^v//')

    # Save to config
    echo "$version" > "$DNVM_CONFIG_DIR/version"

    # Auto-setup the version
    _dnvm_ensure_version "$version"
}

# dnvm versions - List available versions
function dnvm-versions() {
    ls -1 "$DNVM_ROOT/versions" 2>/dev/null || true
}

# dnvm current - Show current version
function dnvm-current() {
    if [[ -n "$DNVM_CURRENT_VERSION" ]]; then
        echo "$DNVM_CURRENT_VERSION"
    else
        true
    fi
}

# dnvm reload - Regenerate wrapper scripts for current version or global version
function dnvm-reload() {
    local version

    # Use current version if set, otherwise use global version
    if [[ -n "$DNVM_CURRENT_VERSION" ]]; then
        version="$DNVM_CURRENT_VERSION"
    else
        version="$DNVM_GLOBAL_VERSION"
    fi

    if [[ -n "$version" ]]; then
        _dnvm_generate_wrappers "$version"
        echo "Reloaded wrappers for version $version"
    else
        echo "No active or global version to reload wrappers for. Use 'dnvm use <version>' or 'dnvm global <version>' first."
        return 1
    fi
}

# Check if a package is globally installed for a specific Node version
function _dnvm_is_package_installed() {
    local version="$1"
    local package="$2"

    if [[ -z "$version" || -z "$package" ]]; then
        return 1
    fi

    # Check if package binary exists in the version's bin directory
    if [[ -f "$DNVM_ROOT/versions/$version/bin/$package" ]]; then
        return 0
    fi

    return 1
}

# Install a single package globally for a specific Node version
function _dnvm_install_package() {
    local version="$1"
    local package="$2"

    if [[ -z "$version" || -z "$package" ]]; then
        echo "Error: Version and package required for _dnvm_install_package" >&2
        return 1
    fi

    echo "Installing $package..." >&2

    # Use dnvm-node-exec to run npm install in Docker container
    # Execute in a subshell to isolate file descriptors and prevent while loop interruption
    local result
    result=$("$DNVM_ROOT/bin/dnvm-node-exec" "$version" npm install -g "$package" >/dev/null 2>&1; echo $?)

    if [[ "$result" -eq 0 ]]; then
        # Regenerate wrappers after installation
        _dnvm_generate_wrappers "$version"
        echo "✓ Successfully installed $package" >&2
        return 0
    else
        echo "✗ Failed to install $package (exit code: $result)" >&2
        return 1
    fi
}

# Process default packages file and install missing packages
function _dnvm_install_default_packages() {
    local version="$1"

    if [[ -z "$version" ]]; then
        echo "Error: Version required for _dnvm_install_default_packages" >&2
        return 1
    fi

    local default_packages_file="$DNVM_CONFIG_DIR/default-packages"

    # Check if default-packages file exists
    if [[ ! -f "$default_packages_file" ]]; then
        return 0  # No default packages to install
    fi

    # Read packages from file using a simple approach that avoids while loops with redirection
    # Process the file line by line to filter out comments and empty lines
    local packages=()
    local line

    # Use exec to avoid subshell issues, process line by line
    exec 3< "$default_packages_file"
    while IFS= read -r -u 3 line || [[ -n "$line" ]]; do
        # Skip empty lines and comments
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi

        # Remove whitespace
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        if [[ -n "$line" ]]; then
            packages+=("$line")
        fi
    done
    exec 3<&-

    local package_count=${#packages[@]}

    if [[ $package_count -gt 0 ]]; then
        # Process each package individually without any redirections that could interfere
        local i=1
        while [[ $i -lt $package_count ]]; do
            local package="${packages[$i]}"

            # Check if package is already installed
            if ! _dnvm_is_package_installed "$version" "$package"; then
                if ! _dnvm_install_package "$version" "$package"; then
                    echo "✗ Failed to install $package, continuing..." >&2
                fi
            fi

            ((i++))
        done
    fi
}

# Generate wrapper scripts for version-specific binaries
function _dnvm_generate_wrappers() {
    local version="$1"

    if [[ -z "$version" ]]; then
        echo "Error: Version parameter required for _dnvm_generate_wrappers" >&2
        return 1
    fi

    local version_bin_dir="$DNVM_ROOT/versions/$version/bin"
    local wrapper_dir="$DNVM_ROOT/bin/$version"

    # Remove all existing wrappers first
    rm -rf $wrapper_dir

    # Ensure wrapper directory exists
    mkdir -p "$wrapper_dir"

    # Check if version bin directory exists
    if [[ ! -d "$version_bin_dir" ]]; then
        return 0
    fi

    # Find all executable files in version bin directory
    local executables
    executables=($(find "$version_bin_dir" -maxdepth 1 -type f -executable 2>/dev/null))
    executables+=($(find "$version_bin_dir" -maxdepth 1 -type l -executable 2>/dev/null))

    if [[ ${#executables[@]} -eq 0 ]]; then
        return 0
    fi

    # Generate wrapper for each executable
    for executable in "${executables[@]}"; do
        local basename=$(basename "$executable")
        local wrapper_path="$wrapper_dir/$basename"

        # Create wrapper script
        cat > "$wrapper_path" << EOF
#!/usr/bin/env zsh
# DNVM wrapper for $basename (Node.js $version)

# Execute $basename via dnvm-node-exec
exec "\$DNVM_ROOT/bin/dnvm-node-exec" "$version" "/home/node/bin/$basename" "\$@"
EOF

        # Make wrapper executable
        chmod +x "$wrapper_path"
    done
}

# Auto-detection hooks
function _dnvm_setup_hooks() {
    # Auto-detect .nvmrc files when changing directories
    function dnvm_chpwd() {
        if [[ -f ".nvmrc" ]]; then
            local requested_version=$(cat .nvmrc | sed 's/^v//' | tr -d '\n')
            if [[ "$requested_version" != "$DNVM_CURRENT_VERSION" ]]; then
                dnvm-use "$requested_version"
            fi
        fi
    }

    # Add hook if not already added
    if [[ -z "$chpwd_functions[dnvm_chpwd]" ]]; then
        add-zsh-hook chpwd dnvm_chpwd
    fi
}

# Function to handle DNVM commands - defined first
function _dnvm_main() {
    case "$1" in
        "use")
            shift
            dnvm-use "$@"
            ;;
        "global")
            shift
            dnvm-global "$@"
            ;;
        "versions"|"list")
            dnvm-versions
            ;;
        "current")
            dnvm-current
            ;;
        "reload")
            dnvm-reload
            ;;
        "")
            echo "DNVM - Docker Node Version Manager"
            echo "Usage: dnvm <command> [args]"
            echo "Commands: use, global, versions, current, reload"
            ;;
        *)
            echo "Unknown command: $1"
            echo "Available commands: use, global, versions, current, reload"
            return 1
            ;;
    esac
}

# Node wrapper function that uses current version or global version
function _dnvm_node() {
    local version

    # Use current version if set, otherwise use global version
    if [[ -n "$DNVM_CURRENT_VERSION" ]]; then
        version="$DNVM_CURRENT_VERSION"
    else
        version="$DNVM_GLOBAL_VERSION"
    fi

    # Execute node via dnvm-node-exec
    "$DNVM_ROOT/bin/dnvm-node-exec" "$version" node "$@"
}

# NPM wrapper function that uses current version or global version
function _dnvm_npm() {
    local version

    # Use current version if set, otherwise use global version
    if [[ -n "$DNVM_CURRENT_VERSION" ]]; then
        version="$DNVM_CURRENT_VERSION"
    else
        version="$DNVM_GLOBAL_VERSION"
    fi

    if [[ -f "$DNVM_ROOT/bin/npm" ]]; then
        command npm "$@"
        return $?
    fi

    # Execute npm via dnvm-node-exec
    "$DNVM_ROOT/bin/dnvm-node-exec" "$version" npm "$@"
}

# Create aliases after function definition
alias nvm='_dnvm_main'  # For compatibility with standard nvm commands
alias dnvm='_dnvm_main'  # Main DNVM command
alias node='_dnvm_node'  # Node alias using DNVM
alias npm='_dnvm_npm'    # NPM alias using DNVM

# Initialize everything
_dnvm_init
