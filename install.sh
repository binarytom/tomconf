#!/usr/bin/env bash

set -Eeuo pipefail

REPOSITORY_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT
readonly BREWFILE="$REPOSITORY_ROOT/Brewfile"
readonly TEMPORARY_DIR="$REPOSITORY_ROOT/tmp/bootstrap"
readonly HOMEBREW_INSTALLER="$TEMPORARY_DIR/homebrew-install.sh"
readonly ALACRITTY_VERSION="0.17.0"
readonly ALACRITTY_SHA256="ad8d7de35fb38e43184776cac6dfee05ca325caa0b6639a06a55e54e4b026620"
readonly ALACRITTY_DMG="$TEMPORARY_DIR/Alacritty-v$ALACRITTY_VERSION.dmg"
readonly ALACRITTY_MOUNT="$TEMPORARY_DIR/alacritty-volume"

BREW=""
ALACRITTY_MOUNTED=0
MODE="install"
APPLY_CONFIG=1

usage() {
	cat <<'EOF'
Usage: ./install.sh [--check] [--skip-config]

Install the macOS tools used by this repository and apply its chezmoi config.

Options:
  --check        Report missing tools without installing anything.
  --skip-config  Install tools, but do not run chezmoi apply.
  -h, --help     Show this help.
EOF
}

cleanup() {
	if [[ "$ALACRITTY_MOUNTED" -eq 1 ]]; then
		hdiutil detach "$ALACRITTY_MOUNT" >/dev/null 2>&1 || true
	fi

	rm -f "$HOMEBREW_INSTALLER" "$ALACRITTY_DMG"
	rmdir "$ALACRITTY_MOUNT" "$TEMPORARY_DIR" 2>/dev/null || true
}

while [[ "$#" -gt 0 ]]; do
	case "$1" in
		--check)
			MODE="check"
			;;
		--skip-config)
			APPLY_CONFIG=0
			;;
		-h | --help)
			usage
			exit 0
			;;
		*)
			printf 'Unknown option: %s\n\n' "$1" >&2
			usage >&2
			exit 2
			;;
	esac
	shift
done

if [[ "$(uname -s)" != "Darwin" ]]; then
	printf 'This installer manages the macOS configuration only.\n' >&2
	exit 1
fi

find_homebrew() {
	if command -v brew >/dev/null 2>&1; then
		BREW="$(command -v brew)"
	elif [[ -x /opt/homebrew/bin/brew ]]; then
		BREW="/opt/homebrew/bin/brew"
	elif [[ -x /usr/local/bin/brew ]]; then
		BREW="/usr/local/bin/brew"
	else
		return 1
	fi
}

load_homebrew_environment() {
	eval "$("$BREW" shellenv)"
}

ensure_homebrew() {
	if find_homebrew; then
		load_homebrew_environment
		return
	fi

	if xcode-select -p >/dev/null 2>&1; then
		:
	else
		printf 'Starting the Xcode Command Line Tools installer.\n'
		printf 'Finish that installation, then run this script again.\n'
		xcode-select --install
		exit 1
	fi

	printf 'Installing Homebrew with its official installer...\n'
	mkdir -p "$TEMPORARY_DIR"
	curl --fail --location --show-error --silent \
		--output "$HOMEBREW_INSTALLER" \
		https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh
	/bin/bash "$HOMEBREW_INSTALLER"

	if find_homebrew; then
		load_homebrew_environment
	else
		printf 'Homebrew installation completed, but brew was not found.\n' >&2
		exit 1
	fi
}

alacritty_is_installed() {
	[[ -d /Applications/Alacritty.app || -d "$HOME/Applications/Alacritty.app" ]]
}

install_alacritty() {
	local alacritty_app
	if [[ -d /Applications/Alacritty.app ]]; then
		alacritty_app="/Applications/Alacritty.app"
		printf 'Alacritty is already installed.\n'
	elif [[ -d "$HOME/Applications/Alacritty.app" ]]; then
		alacritty_app="$HOME/Applications/Alacritty.app"
		printf 'Alacritty is already installed.\n'
	else
		printf 'Installing Alacritty %s from its verified official DMG...\n' "$ALACRITTY_VERSION"
		mkdir -p "$TEMPORARY_DIR" "$ALACRITTY_MOUNT" "$HOME/Applications"
		curl --fail --location --show-error --silent --retry 3 \
			--output "$ALACRITTY_DMG" \
			"https://github.com/alacritty/alacritty/releases/download/v$ALACRITTY_VERSION/Alacritty-v$ALACRITTY_VERSION.dmg"

		local actual_sha256
		actual_sha256="$(shasum -a 256 "$ALACRITTY_DMG")"
		actual_sha256="${actual_sha256%% *}"
		if [[ "$actual_sha256" != "$ALACRITTY_SHA256" ]]; then
			printf 'Alacritty checksum mismatch; refusing to install it.\n' >&2
			exit 1
		fi

		hdiutil attach -quiet -nobrowse -readonly \
			-mountpoint "$ALACRITTY_MOUNT" "$ALACRITTY_DMG"
		ALACRITTY_MOUNTED=1

		if [[ ! -d "$ALACRITTY_MOUNT/Alacritty.app" ]]; then
			printf 'The Alacritty disk image does not contain Alacritty.app.\n' >&2
			exit 1
		fi

		alacritty_app="$HOME/Applications/Alacritty.app"
		ditto "$ALACRITTY_MOUNT/Alacritty.app" "$alacritty_app"
		hdiutil detach "$ALACRITTY_MOUNT" >/dev/null
		ALACRITTY_MOUNTED=0
	fi

	# The executable and terminfo entries are the runtime pieces expected by
	# shell scripts. Man pages and completions remain inside the application.
	local brew_prefix
	brew_prefix="$("$BREW" --prefix)"
	mkdir -p "$HOME/.terminfo/61"
	install -m 0644 "$alacritty_app/Contents/Resources/61/alacritty" \
		"$HOME/.terminfo/61/alacritty"
	install -m 0644 "$alacritty_app/Contents/Resources/61/alacritty-direct" \
		"$HOME/.terminfo/61/alacritty-direct"

	if [[ -e "$brew_prefix/bin/alacritty" || -L "$brew_prefix/bin/alacritty" ]]; then
		printf 'Keeping the existing %s/bin/alacritty entry.\n' "$brew_prefix"
	else
		ln -s "$alacritty_app/Contents/MacOS/alacritty" \
			"$brew_prefix/bin/alacritty"
	fi
}

install_language_toolchains() {
	# Homebrew's rustup formula is keg-only, so expose it both for this run and
	# through the managed shell configuration.
	local rustup_prefix
	rustup_prefix="$("$BREW" --prefix rustup)"
	export PATH="$rustup_prefix/bin:$HOME/.cargo/bin:$PATH"
	rustup toolchain install stable --profile default
	rustup default stable
	rustup component add rust-analyzer rustfmt clippy

	if command -v proximity-sort >/dev/null 2>&1; then
		printf 'proximity-sort is already installed.\n'
	else
		cargo install proximity-sort --locked
	fi

	eval "$(fnm env --shell bash)"
	fnm install --lts --corepack-enabled --use
	local node_version
	node_version="$(fnm current)"
	fnm default "$node_version"
}

ensure_latex_tools() {
	# BasicTeX publishes its commands through this stable system symlink. VimTeX
	# uses latexmk by default, but the compact distribution may omit it.
	export PATH="/Library/TeX/texbin:$PATH"
	if command -v latexmk >/dev/null 2>&1; then
		return
	fi

	if command -v tlmgr >/dev/null 2>&1; then
		sudo tlmgr install latexmk
	else
		printf 'BasicTeX was installed, but tlmgr is not available.\n' >&2
		exit 1
	fi
}

check_installation() {
	local status=0
	local command_name
	local rustup_prefix
	local -a required_commands=(
		adb alacritty aws bash-language-server cargo chezmoi eza fd fish fnm fzf git jq
		latexmk node nvim pass pdflatex proximity-sort rg ruff rust-analyzer shellcheck
		texlab tmux
	)

	if find_homebrew; then
		load_homebrew_environment
		if "$BREW" bundle check --file="$BREWFILE"; then
			:
		else
			status=1
		fi
	else
		printf 'Missing: Homebrew\n' >&2
		return 1
	fi

	export PATH="$HOME/.cargo/bin:/Library/TeX/texbin:$PATH"
	if rustup_prefix="$("$BREW" --prefix rustup 2>/dev/null)"; then
		export PATH="$rustup_prefix/bin:$PATH"
	else
		status=1
	fi

	for command_name in "${required_commands[@]}"; do
		if command -v "$command_name" >/dev/null 2>&1; then
			:
		else
			printf 'Missing command: %s\n' "$command_name" >&2
			status=1
		fi
	done

	if alacritty_is_installed; then
		:
	else
		printf 'Missing application: Alacritty\n' >&2
		status=1
	fi

	if [[ -d /Applications/Skim.app || -d "$HOME/Applications/Skim.app" ]]; then
		:
	else
		printf 'Missing application: Skim\n' >&2
		status=1
	fi

	return "$status"
}

if [[ "$MODE" == "check" ]]; then
	check_installation
	exit $?
fi

trap cleanup EXIT

ensure_homebrew
printf 'Installing packages declared in %s...\n' "$BREWFILE"
"$BREW" bundle install --file="$BREWFILE"
install_language_toolchains
ensure_latex_tools
install_alacritty

if [[ "$APPLY_CONFIG" -eq 1 ]]; then
	printf 'Applying the macOS configuration with chezmoi...\n'
	chezmoi apply --source "$REPOSITORY_ROOT"
fi

printf '\nInstallation complete. Run ./install.sh --check at any time to verify it.\n'
