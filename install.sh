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
readonly LINKER_TEST_SOURCE="$TEMPORARY_DIR/link-test.c"
readonly LINKER_TEST_BINARY="$TEMPORARY_DIR/link-test"
readonly LINKER_TEST_LOG="$TEMPORARY_DIR/link-test.log"

BREW=""
MACOS_SDK=""
ALACRITTY_MOUNTED=0
MODE="install"
APPLY_CONFIG=1
FAILED_STEPS=()

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

	rm -f "$HOMEBREW_INSTALLER" "$ALACRITTY_DMG" \
		"$LINKER_TEST_SOURCE" "$LINKER_TEST_BINARY" "$LINKER_TEST_LOG"
	rmdir "$ALACRITTY_MOUNT" "$TEMPORARY_DIR" 2>/dev/null || true
}

record_failure() {
	local description="$1"
	FAILED_STEPS+=("$description")
	printf 'Warning: %s failed; continuing with the remaining steps.\n' \
		"$description" >&2
}

run_step() {
	local description="$1"
	shift

	printf '\n==> %s\n' "$description"
	if "$@"; then
		return 0
	fi

	record_failure "$description"
	return 0
}

print_summary() {
	local description

	if [[ "${#FAILED_STEPS[@]}" -eq 0 ]]; then
		printf '\nInstallation complete. No failed steps were detected.\n'
		return
	fi

	printf '\nInstallation completed with skipped or failed steps:\n' >&2
	for description in "${FAILED_STEPS[@]}"; do
		printf '  - %s\n' "$description" >&2
	done
	printf 'Fix the reported prerequisites and rerun ./install.sh; completed steps are safe to repeat.\n' >&2
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
		load_homebrew_environment || return 1
		return
	fi

	if xcode-select -p >/dev/null 2>&1; then
		:
	else
		printf 'Starting the Xcode Command Line Tools installer.\n'
		printf 'Finish that installation, then run this script again.\n'
		xcode-select --install || return 1
		return 1
	fi

	printf 'Installing Homebrew with its official installer...\n'
	mkdir -p "$TEMPORARY_DIR" || return 1
	curl --fail --location --show-error --silent \
		--output "$HOMEBREW_INSTALLER" \
		https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh || return 1
	/bin/bash "$HOMEBREW_INSTALLER" || return 1

	if find_homebrew; then
		load_homebrew_environment || return 1
	else
		printf 'Homebrew installation completed, but brew was not found.\n' >&2
		return 1
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
		mkdir -p "$TEMPORARY_DIR" "$ALACRITTY_MOUNT" "$HOME/Applications" || return 1
		curl --fail --location --show-error --silent --retry 3 \
			--output "$ALACRITTY_DMG" \
			"https://github.com/alacritty/alacritty/releases/download/v$ALACRITTY_VERSION/Alacritty-v$ALACRITTY_VERSION.dmg" || return 1

		local actual_sha256
		actual_sha256="$(shasum -a 256 "$ALACRITTY_DMG")"
		actual_sha256="${actual_sha256%% *}"
		if [[ "$actual_sha256" != "$ALACRITTY_SHA256" ]]; then
			printf 'Alacritty checksum mismatch; refusing to install it.\n' >&2
			return 1
		fi

		hdiutil attach -quiet -nobrowse -readonly \
			-mountpoint "$ALACRITTY_MOUNT" "$ALACRITTY_DMG" || return 1
		ALACRITTY_MOUNTED=1

		if [[ ! -d "$ALACRITTY_MOUNT/Alacritty.app" ]]; then
			printf 'The Alacritty disk image does not contain Alacritty.app.\n' >&2
			return 1
		fi

		alacritty_app="$HOME/Applications/Alacritty.app"
		ditto "$ALACRITTY_MOUNT/Alacritty.app" "$alacritty_app" || return 1
		hdiutil detach "$ALACRITTY_MOUNT" >/dev/null || return 1
		ALACRITTY_MOUNTED=0
	fi

	# The executable and terminfo entries are the runtime pieces expected by
	# shell scripts. Man pages and completions remain inside the application.
	local brew_prefix
	brew_prefix="$("$BREW" --prefix)" || return 1
	mkdir -p "$HOME/.terminfo/61" || return 1
	install -m 0644 "$alacritty_app/Contents/Resources/61/alacritty" \
		"$HOME/.terminfo/61/alacritty" || return 1
	install -m 0644 "$alacritty_app/Contents/Resources/61/alacritty-direct" \
		"$HOME/.terminfo/61/alacritty-direct" || return 1

	if [[ -e "$brew_prefix/bin/alacritty" || -L "$brew_prefix/bin/alacritty" ]]; then
		printf 'Keeping the existing %s/bin/alacritty entry.\n' "$brew_prefix"
	else
		ln -s "$alacritty_app/Contents/MacOS/alacritty" \
			"$brew_prefix/bin/alacritty" || return 1
	fi
}

select_compatible_macos_sdk() {
	local host_major
	local selected_major
	local selected_sdk
	local compatible_sdk

	selected_sdk="$(xcrun --sdk macosx --show-sdk-path)" || return 1
	selected_major="$(xcrun --sdk macosx --show-sdk-version)" || return 1
	selected_major="${selected_major%%.*}"
	host_major="$(sw_vers -productVersion)" || return 1
	host_major="${host_major%%.*}"
	MACOS_SDK="$selected_sdk"

	if [[ "$selected_major" == "$host_major" ]]; then
		return
	fi

	# Apple updates can temporarily select a newer SDK than the installed
	# command-line linker understands. Prefer an already-installed SDK matching
	# the host OS without deleting SDKs or changing the global developer path.
	compatible_sdk="$(dirname "$selected_sdk")/MacOSX$host_major.sdk"
	if [[ -d "$compatible_sdk" ]]; then
		MACOS_SDK="$compatible_sdk"
		printf 'Using macOS %s SDK for native builds instead of SDK %s.\n' \
			"$host_major" "$selected_major"
	fi
}

native_linker_works() {
	mkdir -p "$TEMPORARY_DIR" || return 1
	printf '%s\n' 'int main(void) { return 0; }' >"$LINKER_TEST_SOURCE"

	if SDKROOT="$MACOS_SDK" cc "$LINKER_TEST_SOURCE" \
		-o "$LINKER_TEST_BINARY" 2>"$LINKER_TEST_LOG"; then
		rm -f "$LINKER_TEST_SOURCE" "$LINKER_TEST_BINARY" "$LINKER_TEST_LOG"
		return 0
	fi

	printf 'The Apple C linker cannot build against %s.\n' "$MACOS_SDK" >&2
	printf 'The installed Command Line Tools and macOS SDK are likely mismatched.\n' >&2
	sed -n '1,20p' "$LINKER_TEST_LOG" >&2
	return 1
}

install_rust_toolchain() {
	# Homebrew's rustup formula is keg-only, so expose it both for this run and
	# through the managed shell configuration.
	local rustup_prefix
	rustup_prefix="$("$BREW" --prefix rustup)" || return 1
	export PATH="$rustup_prefix/bin:$HOME/.cargo/bin:$PATH"
	rustup toolchain install stable --profile default || return 1
	rustup default stable || return 1
	rustup component add rust-analyzer rustfmt clippy || return 1
}

install_proximity_sort() {
	if command -v proximity-sort >/dev/null 2>&1; then
		printf 'proximity-sort is already installed.\n'
		return
	fi

	if command -v cargo >/dev/null 2>&1; then
		:
	else
		printf 'cargo is unavailable; cannot install proximity-sort.\n' >&2
		return 1
	fi

	select_compatible_macos_sdk || return 1
	if native_linker_works; then
		SDKROOT="$MACOS_SDK" cargo install proximity-sort --locked
		return $?
	fi

	printf 'Update or reinstall the Command Line Tools, then rerun this script.\n' >&2
	return 1
}

install_node_toolchain() {
	if command -v fnm >/dev/null 2>&1; then
		:
	else
		printf 'fnm is unavailable; cannot install Node.js.\n' >&2
		return 1
	fi

	eval "$(fnm env --shell bash)" || return 1
	fnm install --lts --corepack-enabled --use || return 1
	local node_version
	node_version="$(fnm current)" || return 1
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
		return 1
	fi
}

apply_chezmoi_config() {
	if command -v chezmoi >/dev/null 2>&1; then
		chezmoi apply --source "$REPOSITORY_ROOT"
		return $?
	fi

	printf 'chezmoi is unavailable; configuration was not applied.\n' >&2
	return 1
}

check_installation() {
	local status=0
	local command_name
	local rustup_prefix
	local -a required_commands=(
		adb alacritty aws bash-language-server cargo chezmoi eza fd fish fnm fzf git jq
		latexmk node nvim pass pdflatex rg ruff rust-analyzer shellcheck
		texlab tmux
	)

	if find_homebrew; then
		load_homebrew_environment
		if "$BREW" bundle check --no-upgrade --file="$BREWFILE"; then
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

	if command -v proximity-sort >/dev/null 2>&1; then
		:
	else
		printf 'Optional command missing: proximity-sort\n' >&2
	fi

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

if ensure_homebrew; then
	run_step "Homebrew packages from $BREWFILE" \
		"$BREW" bundle install --file="$BREWFILE"
	run_step "Rust stable toolchain" install_rust_toolchain
	run_step "optional proximity-sort" install_proximity_sort
	run_step "Node.js LTS toolchain" install_node_toolchain
	run_step "VimTeX latexmk dependency" ensure_latex_tools
	run_step "Alacritty" install_alacritty
else
	record_failure "Homebrew bootstrap"
	printf 'Skipping Homebrew-dependent tools.\n' >&2
fi

if [[ "$APPLY_CONFIG" -eq 1 ]]; then
	run_step "chezmoi configuration" apply_chezmoi_config
fi

print_summary
printf 'Run ./install.sh --check at any time to verify the result.\n'

# Best-effort installation means every independent step gets a chance to run,
# not that callers should mistake an incomplete machine for a successful one.
if [[ "${#FAILED_STEPS[@]}" -gt 0 ]]; then
	exit 1
fi
