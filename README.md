# DNVM - Docker Node Version Manager

DNVM (Docker Node Version Manager) is a Zsh plugin that allows you to easily switch between Node.js versions using Docker containers. It's designed to be compatible with [Antígeno](https://github.com/zsh-users/antigen) and provides a familiar interface similar to [nvm](https://github.com/nvm-sh/nvm).

## Features

- 🚀 **Docker-based**: Each Node.js version runs in an isolated Docker container
- ⚡ **Session-based**: Version changes only affect the current terminal session
- 🔄 **Auto-detection**: Automatically switches versions based on `.nvmrc` files
- 📦 **Global packages**: Seamlessly manages global packages with wrapper generation
- 🎯 **Antígeno compatible**: Easy to install and manage with Antígeno
- 🔧 **Environment variables**: Passes all shell environment variables to containers

## Requirements

- **Docker**: Must be installed and running
- **Zsh**: Compatible Zsh shell
- **Antígeno**: Optional but recommended for easy installation

## Installation

### Manual Installation

1. Clone this repository:
```bash
git clone <your-repo-url> ~/.dnvm
cd ~/.dnvm
```

2. Add to your `.zshrc`:
```zsh
source ~/.dnvm/dnvm.plugin.zsh
```

3. Restart your terminal or source your `.zshrc`:
```bash
source ~/.zshrc
```

### Antígeno Installation (Recommended)

Add this line to your `.zshrc`:
```zsh
antigen bundle <your-github-repo>
```

Then run:
```bash
antigen update
```

## Usage

### Basic Commands

#### Switch to a Node.js version (current session only)
```zsh
dnvm use 18.16.0
dnvm use 20
dnvm use v16.15.0  # 'v' prefix is automatically handled
```

#### Set default global Node.js version
```zsh
dnvm global 20
dnvm global 18.16.0
```

#### List available versions in your DNVM setup
```zsh
dnvm versions
```

#### Show current active version
```zsh
dnvm current
```

### Automatic Version Management

#### .nvmrc Support
Create a `.nvmrc` file in your project:
```bash
echo "20.0.0" > .nvmrc
```

DNVM will automatically switch to this version when you `cd` into the directory.

#### First Time Setup
On first installation, DNVM will:
1. Pull a default LTS Node.js Docker image
2. Install default global packages (yarn, pnpm, npx)
3. Set up necessary directories and configurations

### Global Package Management

#### Install global packages
```zsh
npm install -g create-react-app
yarn global add eslint
```

DNVM will automatically:
- Install the package in the current Node.js version's Docker container
- Generate a wrapper script for the package
- Add the wrapper to your PATH for the current session

#### Using global packages
After installation, you can use the global packages directly:
```zsh
create-react-app my-app
eslint src/
```

#### Default Global Packages from File (New Feature)

Similar to the original NVM, DNVM now supports automatic installation of default global packages when switching to a Node.js version.

**Create a default packages file:**
```zsh
# Create/edit default packages list
vim ~/.config/dnvm/default-packages

# Example content:
yarn
pm2
npm-check-updates
# typescript
nodemon
```

**How it works:**
- When you run `dnvm use <version>`, DNVM automatically checks `~/.config/dnvm/default-packages`
- Packages listed in this file (one per line) are installed globally if not already installed for that Node version
- Lines starting with `#` are treated as comments and ignored
- Wrapper scripts are automatically generated for each installed package

**Example workflow:**
```zsh
# First time using Node 20
dnvm use 20
# Output:
# Checking default packages for Node.js 20...
# Installing yarn globally for Node.js 20...
# ✓ yarn installed successfully
# Installing pm2 globally for Node.js 20...
# ✓ pm2 installed successfully
# Installing npm-check-updates globally for Node.js 20...
# ✓ npm-check-updates installed successfully
# Default package installation completed.
```

**Benefits:**
- ⚡ Fast setup of new Node versions with your favorite tools
- 🔄 Consistent development environment across versions
- 📦 Automatic wrapper generation for easy package access
- 💾 Version-specific package management

### npm Configuration (.npmrc Support)

DNVM automatically manages npm configuration:

- Copies your `~/.npmrc` to each Node.js version
- Creates default `.npmrc` if none exists
- Supports custom registries, cache settings, and authentication

**Example configuration:**
```zsh
# ~/.npmrc dosyası bu örnekte ~/.config/dnvm/npmrc/.npmrc-20.0.0 konumuna kopyalanır
registry=https://registry.npmjs.org/
save-exact=true
progress=false
cache-max=86400
fund=false
audit=false

# DNVM-specific Docker paths
prefix=/home/node/.local
cache=/home/node/.npm-cache

# Authentication
//registry.npmjs.org/:_authToken=your_token_here
```

**Konfigürasyon Dosyası:**
```zsh
# DNVM her Node versiyonu için ayrı .npmrc dosyası oluşturur:
~/.config/dnvm/npmrc/.npmrc-18     # Node 18 konfigürasyonu
~/.config/dnvm/npmrc/.npmrc-20     # Node 20 konfigürasyonu
~/.config/dnvm/npmrc/.npmrc-16     # Node 16 konfigürasyonu
```

### Environment Variables

All your shell's environment variables are automatically passed to the Docker containers:
```zsh
MY_VAR=test node app.js
export API_KEY=secret123
node server.js  # API_KEY will be available in the container
```

### Directory Structure

DNVM uses the XDG Base Directory specification:

```
# Data directory (Docker volumes and binaries)
$XDG_DATA_HOME/dnvm/
├── bin/
│   ├── dnvm-node-exec      # Docker runner
│   └── {version}/          # Version-specific wrappers
│       ├── eslint
│       └── create-react-app
├── volumes/{version}/      # Docker volumes for Node.js data
    └── home/node/...

# Config directory
$XDG_CONFIG_HOME/dnvm/
├── version                 # Global default version
├── default-packages        # List of global packages to install
```

## How It Works

### Docker Integration

Each Node.js version runs in an isolated Docker container:
- **Working directory**: `/app` (mounted from your current directory)
- **Node data volume**: `/home/node` (persistent storage for packages)
- **User permissions**: Current user ID and group ID
- **Environment**: All your shell environment variables

### Wrapper System

Global packages are automatically wrapped:
```zsh
# Generated wrapper example: bin/20.0.0/eslint
#!/usr/bin/env zsh
exec dnvm-node-exec 20.0.0 eslint "$@"
```

### Session Management

- `dnvm use {version}` changes the Node.js version for the current terminal session only
- New terminal windows will use the global default version
- Directory changes automatically trigger .nvmrc detection

### Global Package Management

- Global packages are installed in Docker containers (not on host system)
- Wrapper scripts provide transparent access to these packages
- Packages are automatically re-installed when switching to new versions

## Troubleshooting

### Docker Issues
```bash
# Check if Docker is running
docker info

# Pull a specific Node version manually
docker pull node:18.16.0
```

### Version Not Found
```bash
# Check what versions are available in Docker Hub
curl -s https://registry.hub.docker.com/v1/repositories/library/node/tags | jq -r '.[] | .name' | head -10
```

### Permission Issues
```bash
# Ensure your user has Docker permissions
sudo usermod -aG docker $USER
# Log out and back in for changes to take effect
```

### Reset DNVM
```bash
# Remove all DNVM data and start fresh
rm -rf "$XDG_DATA_HOME/dnvm"
rm -rf "$XDG_CONFIG_HOME/dnvm"
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly with different Node versions
5. Submit a pull request

## License

MIT License - see LICENSE file for details

---

**Happy coding with DNVM! 🎉**
