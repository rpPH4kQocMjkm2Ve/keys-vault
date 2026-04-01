_keys_vault() {
    local cur prev
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    case "$prev" in
        --dir|--cipher-dir)
            COMPREPLY=($(compgen -d -- "$cur"))
            return
            ;;
    esac

    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "--dir --cipher-dir -h --help --version" -- "$cur"))
        return
    fi

    COMPREPLY=($(compgen -W "init open close status passwd" -- "$cur"))
}

complete -F _keys_vault keys-vault
