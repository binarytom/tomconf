function fish_fzf_key_bindings
    if command -q fzf
        fzf --fish | source
    end
end
