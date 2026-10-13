fish_add_path --global /opt/homebrew/opt/rustup/bin /usr/local/opt/rustup/bin "$HOME/.cargo/bin"

if test -f "$HOME/.cargo/env.fish"
    source "$HOME/.cargo/env.fish"
end
