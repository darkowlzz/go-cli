# bash completion for storageos                            -*- shell-script -*-

__debug()
{
    if [[ -n ${BASH_COMP_DEBUG_FILE} ]]; then
        echo "$*" >> "${BASH_COMP_DEBUG_FILE}"
    fi
}

# Homebrew on Macs have version 1.3 of bash-completion which doesn't include
# _init_completion. This is a very minimal version of that function.
__my_init_completion()
{
    COMPREPLY=()
    _get_comp_words_by_ref "$@" cur prev words cword
}

__index_of_word()
{
    local w word=$1
    shift
    index=0
    for w in "$@"; do
        [[ $w = "$word" ]] && return
        index=$((index+1))
    done
    index=-1
}

__contains_word()
{
    local w word=$1; shift
    for w in "$@"; do
        [[ $w = "$word" ]] && return
    done
    return 1
}

__handle_reply()
{
    __debug "${FUNCNAME[0]}"
    case $cur in
        -*)
            if [[ $(type -t compopt) = "builtin" ]]; then
                compopt -o nospace
            fi
            local allflags
            if [ ${#must_have_one_flag[@]} -ne 0 ]; then
                allflags=("${must_have_one_flag[@]}")
            else
                allflags=("${flags[*]} ${two_word_flags[*]}")
            fi
            COMPREPLY=( $(compgen -W "${allflags[*]}" -- "$cur") )
            if [[ $(type -t compopt) = "builtin" ]]; then
                [[ "${COMPREPLY[0]}" == *= ]] || compopt +o nospace
            fi

            # complete after --flag=abc
            if [[ $cur == *=* ]]; then
                if [[ $(type -t compopt) = "builtin" ]]; then
                    compopt +o nospace
                fi

                local index flag
                flag="${cur%%=*}"
                __index_of_word "${flag}" "${flags_with_completion[@]}"
                if [[ ${index} -ge 0 ]]; then
                    COMPREPLY=()
                    PREFIX=""
                    cur="${cur#*=}"
                    ${flags_completion[${index}]}
                    if [ -n "${ZSH_VERSION}" ]; then
                        # zfs completion needs --flag= prefix
                        eval "COMPREPLY=( \"\${COMPREPLY[@]/#/${flag}=}\" )"
                    fi
                fi
            fi
            return 0;
            ;;
    esac

    # check if we are handling a flag with special work handling
    local index
    __index_of_word "${prev}" "${flags_with_completion[@]}"
    if [[ ${index} -ge 0 ]]; then
        ${flags_completion[${index}]}
        return
    fi

    # we are parsing a flag and don't have a special handler, no completion
    if [[ ${cur} != "${words[cword]}" ]]; then
        return
    fi

    local completions
    completions=("${commands[@]}")
    if [[ ${#must_have_one_noun[@]} -ne 0 ]]; then
        completions=("${must_have_one_noun[@]}")
    fi
    if [[ ${#must_have_one_flag[@]} -ne 0 ]]; then
        completions+=("${must_have_one_flag[@]}")
    fi
    COMPREPLY=( $(compgen -W "${completions[*]}" -- "$cur") )

    if [[ ${#COMPREPLY[@]} -eq 0 && ${#noun_aliases[@]} -gt 0 && ${#must_have_one_noun[@]} -ne 0 ]]; then
        COMPREPLY=( $(compgen -W "${noun_aliases[*]}" -- "$cur") )
    fi

    if [[ ${#COMPREPLY[@]} -eq 0 ]]; then
        declare -F __custom_func >/dev/null && __custom_func
    fi

    __ltrim_colon_completions "$cur"
}

# The arguments should be in the form "ext1|ext2|extn"
__handle_filename_extension_flag()
{
    local ext="$1"
    _filedir "@(${ext})"
}

__handle_subdirs_in_dir_flag()
{
    local dir="$1"
    pushd "${dir}" >/dev/null 2>&1 && _filedir -d && popd >/dev/null 2>&1
}

__handle_flag()
{
    __debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    # if a command required a flag, and we found it, unset must_have_one_flag()
    local flagname=${words[c]}
    local flagvalue
    # if the word contained an =
    if [[ ${words[c]} == *"="* ]]; then
        flagvalue=${flagname#*=} # take in as flagvalue after the =
        flagname=${flagname%%=*} # strip everything after the =
        flagname="${flagname}=" # but put the = back
    fi
    __debug "${FUNCNAME[0]}: looking for ${flagname}"
    if __contains_word "${flagname}" "${must_have_one_flag[@]}"; then
        must_have_one_flag=()
    fi

    # if you set a flag which only applies to this command, don't show subcommands
    if __contains_word "${flagname}" "${local_nonpersistent_flags[@]}"; then
      commands=()
    fi

    # keep flag value with flagname as flaghash
    if [ -n "${flagvalue}" ] ; then
        flaghash[${flagname}]=${flagvalue}
    elif [ -n "${words[ $((c+1)) ]}" ] ; then
        flaghash[${flagname}]=${words[ $((c+1)) ]}
    else
        flaghash[${flagname}]="true" # pad "true" for bool flag
    fi

    # skip the argument to a two word flag
    if __contains_word "${words[c]}" "${two_word_flags[@]}"; then
        c=$((c+1))
        # if we are looking for a flags value, don't show commands
        if [[ $c -eq $cword ]]; then
            commands=()
        fi
    fi

    c=$((c+1))

}

__handle_noun()
{
    __debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    if __contains_word "${words[c]}" "${must_have_one_noun[@]}"; then
        must_have_one_noun=()
    elif __contains_word "${words[c]}" "${noun_aliases[@]}"; then
        must_have_one_noun=()
    fi

    nouns+=("${words[c]}")
    c=$((c+1))
}

__handle_command()
{
    __debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    local next_command
    if [[ -n ${last_command} ]]; then
        next_command="_${last_command}_${words[c]//:/__}"
    else
        if [[ $c -eq 0 ]]; then
            next_command="_$(basename "${words[c]//:/__}")"
        else
            next_command="_${words[c]//:/__}"
        fi
    fi
    c=$((c+1))
    __debug "${FUNCNAME[0]}: looking for ${next_command}"
    declare -F $next_command >/dev/null && $next_command
}

__handle_word()
{
    if [[ $c -ge $cword ]]; then
        __handle_reply
        return
    fi
    __debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"
    if [[ "${words[c]}" == -* ]]; then
        __handle_flag
    elif __contains_word "${words[c]}" "${commands[@]}"; then
        __handle_command
    elif [[ $c -eq 0 ]] && __contains_word "$(basename "${words[c]}")" "${commands[@]}"; then
        __handle_command
    else
        __handle_noun
    fi
    __handle_word
}

_storageos_cluster_create()
{
    last_command="storageos_cluster_create"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--name=")
    local_nonpersistent_flags+=("--name=")
    flags+=("--size=")
    two_word_flags+=("-s")
    local_nonpersistent_flags+=("--size=")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_cluster_health()
{
    last_command="storageos_cluster_health"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--format=")
    local_nonpersistent_flags+=("--format=")
    flags+=("--quiet")
    flags+=("-q")
    local_nonpersistent_flags+=("--quiet")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_cluster_inspect()
{
    last_command="storageos_cluster_inspect"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--format=")
    two_word_flags+=("-f")
    local_nonpersistent_flags+=("--format=")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_cluster_rm()
{
    last_command="storageos_cluster_rm"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--force")
    flags+=("-f")
    local_nonpersistent_flags+=("--force")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_cluster()
{
    last_command="storageos_cluster"
    commands=()
    commands+=("create")
    commands+=("health")
    commands+=("inspect")
    commands+=("rm")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_namespace_create()
{
    last_command="storageos_namespace_create"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--description=")
    two_word_flags+=("-d")
    local_nonpersistent_flags+=("--description=")
    flags+=("--display-name=")
    local_nonpersistent_flags+=("--display-name=")
    flags+=("--label=")
    local_nonpersistent_flags+=("--label=")
    flags+=("--name=")
    local_nonpersistent_flags+=("--name=")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_namespace_inspect()
{
    last_command="storageos_namespace_inspect"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--format=")
    two_word_flags+=("-f")
    local_nonpersistent_flags+=("--format=")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_namespace_ls()
{
    last_command="storageos_namespace_ls"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--format=")
    local_nonpersistent_flags+=("--format=")
    flags+=("--quiet")
    flags+=("-q")
    local_nonpersistent_flags+=("--quiet")
    flags+=("--selector=")
    two_word_flags+=("-s")
    local_nonpersistent_flags+=("--selector=")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_namespace_rm()
{
    last_command="storageos_namespace_rm"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--force")
    flags+=("-f")
    local_nonpersistent_flags+=("--force")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_namespace_update()
{
    last_command="storageos_namespace_update"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--description=")
    two_word_flags+=("-d")
    local_nonpersistent_flags+=("--description=")
    flags+=("--display-name=")
    local_nonpersistent_flags+=("--display-name=")
    flags+=("--label-add=")
    local_nonpersistent_flags+=("--label-add=")
    flags+=("--label-rm=")
    local_nonpersistent_flags+=("--label-rm=")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_namespace()
{
    last_command="storageos_namespace"
    commands=()
    commands+=("create")
    commands+=("inspect")
    commands+=("ls")
    commands+=("rm")
    commands+=("update")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_node_health()
{
    last_command="storageos_node_health"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cluster=")
    local_nonpersistent_flags+=("--cluster=")
    flags+=("--cp")
    local_nonpersistent_flags+=("--cp")
    flags+=("--dp")
    local_nonpersistent_flags+=("--dp")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_node_inspect()
{
    last_command="storageos_node_inspect"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--format=")
    two_word_flags+=("-f")
    local_nonpersistent_flags+=("--format=")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_node_ls()
{
    last_command="storageos_node_ls"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--format=")
    local_nonpersistent_flags+=("--format=")
    flags+=("--quiet")
    flags+=("-q")
    local_nonpersistent_flags+=("--quiet")
    flags+=("--selector=")
    two_word_flags+=("-s")
    local_nonpersistent_flags+=("--selector=")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_node()
{
    last_command="storageos_node"
    commands=()
    commands+=("health")
    commands+=("inspect")
    commands+=("ls")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_policy_create()
{
    last_command="storageos_policy_create"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--group=")
    local_nonpersistent_flags+=("--group=")
    flags+=("--namespace=")
    local_nonpersistent_flags+=("--namespace=")
    flags+=("--policies=")
    local_nonpersistent_flags+=("--policies=")
    flags+=("--stdin")
    local_nonpersistent_flags+=("--stdin")
    flags+=("--user=")
    local_nonpersistent_flags+=("--user=")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_policy_inspect()
{
    last_command="storageos_policy_inspect"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--format=")
    two_word_flags+=("-f")
    local_nonpersistent_flags+=("--format=")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_policy_ls()
{
    last_command="storageos_policy_ls"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--format=")
    local_nonpersistent_flags+=("--format=")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_policy_rm()
{
    last_command="storageos_policy_rm"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_policy()
{
    last_command="storageos_policy"
    commands=()
    commands+=("create")
    commands+=("inspect")
    commands+=("ls")
    commands+=("rm")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_pool_create()
{
    last_command="storageos_pool_create"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--active")
    local_nonpersistent_flags+=("--active")
    flags+=("--controllers=")
    local_nonpersistent_flags+=("--controllers=")
    flags+=("--default")
    local_nonpersistent_flags+=("--default")
    flags+=("--default-driver=")
    local_nonpersistent_flags+=("--default-driver=")
    flags+=("--description=")
    two_word_flags+=("-d")
    local_nonpersistent_flags+=("--description=")
    flags+=("--drivers=")
    local_nonpersistent_flags+=("--drivers=")
    flags+=("--label=")
    local_nonpersistent_flags+=("--label=")
    flags+=("--name=")
    local_nonpersistent_flags+=("--name=")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_pool_inspect()
{
    last_command="storageos_pool_inspect"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--format=")
    two_word_flags+=("-f")
    local_nonpersistent_flags+=("--format=")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_pool_ls()
{
    last_command="storageos_pool_ls"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--format=")
    local_nonpersistent_flags+=("--format=")
    flags+=("--quiet")
    flags+=("-q")
    local_nonpersistent_flags+=("--quiet")
    flags+=("--selector=")
    two_word_flags+=("-s")
    local_nonpersistent_flags+=("--selector=")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_pool_rm()
{
    last_command="storageos_pool_rm"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--force")
    flags+=("-f")
    local_nonpersistent_flags+=("--force")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_pool()
{
    last_command="storageos_pool"
    commands=()
    commands+=("create")
    commands+=("inspect")
    commands+=("ls")
    commands+=("rm")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_rule_create()
{
    last_command="storageos_rule_create"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--action=")
    two_word_flags+=("-a")
    local_nonpersistent_flags+=("--action=")
    flags+=("--active")
    local_nonpersistent_flags+=("--active")
    flags+=("--description=")
    two_word_flags+=("-d")
    local_nonpersistent_flags+=("--description=")
    flags+=("--label=")
    local_nonpersistent_flags+=("--label=")
    flags+=("--name=")
    local_nonpersistent_flags+=("--name=")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace=")
    flags+=("--selector=")
    two_word_flags+=("-s")
    local_nonpersistent_flags+=("--selector=")
    flags+=("--weight=")
    two_word_flags+=("-w")
    local_nonpersistent_flags+=("--weight=")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_rule_inspect()
{
    last_command="storageos_rule_inspect"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--format=")
    two_word_flags+=("-f")
    local_nonpersistent_flags+=("--format=")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_rule_ls()
{
    last_command="storageos_rule_ls"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--format=")
    local_nonpersistent_flags+=("--format=")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace=")
    flags+=("--quiet")
    flags+=("-q")
    local_nonpersistent_flags+=("--quiet")
    flags+=("--selector=")
    two_word_flags+=("-s")
    local_nonpersistent_flags+=("--selector=")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_rule_rm()
{
    last_command="storageos_rule_rm"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--force")
    flags+=("-f")
    local_nonpersistent_flags+=("--force")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_rule_update()
{
    last_command="storageos_rule_update"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--action=")
    two_word_flags+=("-a")
    local_nonpersistent_flags+=("--action=")
    flags+=("--active")
    local_nonpersistent_flags+=("--active")
    flags+=("--description=")
    two_word_flags+=("-d")
    local_nonpersistent_flags+=("--description=")
    flags+=("--label-add=")
    local_nonpersistent_flags+=("--label-add=")
    flags+=("--label-rm=")
    local_nonpersistent_flags+=("--label-rm=")
    flags+=("--operator=")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--operator=")
    flags+=("--selector=")
    two_word_flags+=("-s")
    local_nonpersistent_flags+=("--selector=")
    flags+=("--weight=")
    two_word_flags+=("-w")
    local_nonpersistent_flags+=("--weight=")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_rule()
{
    last_command="storageos_rule"
    commands=()
    commands+=("create")
    commands+=("inspect")
    commands+=("ls")
    commands+=("rm")
    commands+=("update")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_user_create()
{
    last_command="storageos_user_create"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--groups=")
    local_nonpersistent_flags+=("--groups=")
    flags+=("--password=")
    local_nonpersistent_flags+=("--password=")
    flags+=("--role=")
    local_nonpersistent_flags+=("--role=")
    flags+=("--username=")
    local_nonpersistent_flags+=("--username=")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_user_inspect()
{
    last_command="storageos_user_inspect"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--format=")
    two_word_flags+=("-f")
    local_nonpersistent_flags+=("--format=")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_user_ls()
{
    last_command="storageos_user_ls"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--admin-only")
    local_nonpersistent_flags+=("--admin-only")
    flags+=("--format=")
    local_nonpersistent_flags+=("--format=")
    flags+=("--quiet")
    flags+=("-q")
    local_nonpersistent_flags+=("--quiet")
    flags+=("--user-only")
    local_nonpersistent_flags+=("--user-only")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_user_rm()
{
    last_command="storageos_user_rm"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_user_update()
{
    last_command="storageos_user_update"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--add-groups=")
    local_nonpersistent_flags+=("--add-groups=")
    flags+=("--groups=")
    local_nonpersistent_flags+=("--groups=")
    flags+=("--password")
    local_nonpersistent_flags+=("--password")
    flags+=("--remove-groups=")
    local_nonpersistent_flags+=("--remove-groups=")
    flags+=("--role=")
    local_nonpersistent_flags+=("--role=")
    flags+=("--username=")
    local_nonpersistent_flags+=("--username=")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_user()
{
    last_command="storageos_user"
    commands=()
    commands+=("create")
    commands+=("inspect")
    commands+=("ls")
    commands+=("rm")
    commands+=("update")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_version()
{
    last_command="storageos_version"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--format=")
    two_word_flags+=("-f")
    local_nonpersistent_flags+=("--format=")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_volume_create()
{
    last_command="storageos_volume_create"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--description=")
    two_word_flags+=("-d")
    local_nonpersistent_flags+=("--description=")
    flags+=("--fstype=")
    two_word_flags+=("-f")
    local_nonpersistent_flags+=("--fstype=")
    flags+=("--label=")
    local_nonpersistent_flags+=("--label=")
    flags+=("--name=")
    local_nonpersistent_flags+=("--name=")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace=")
    flags+=("--nodeSelector=")
    local_nonpersistent_flags+=("--nodeSelector=")
    flags+=("--pool=")
    two_word_flags+=("-p")
    local_nonpersistent_flags+=("--pool=")
    flags+=("--size=")
    two_word_flags+=("-s")
    local_nonpersistent_flags+=("--size=")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_volume_inspect()
{
    last_command="storageos_volume_inspect"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--format=")
    two_word_flags+=("-f")
    local_nonpersistent_flags+=("--format=")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_volume_ls()
{
    last_command="storageos_volume_ls"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--format=")
    local_nonpersistent_flags+=("--format=")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace=")
    flags+=("--quiet")
    flags+=("-q")
    local_nonpersistent_flags+=("--quiet")
    flags+=("--selector=")
    two_word_flags+=("-s")
    local_nonpersistent_flags+=("--selector=")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_volume_mount()
{
    last_command="storageos_volume_mount"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--fsType=")
    two_word_flags+=("-m")
    local_nonpersistent_flags+=("--fsType=")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_volume_rm()
{
    last_command="storageos_volume_rm"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--force")
    flags+=("-f")
    local_nonpersistent_flags+=("--force")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_volume_unmount()
{
    last_command="storageos_volume_unmount"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--force")
    flags+=("-f")
    local_nonpersistent_flags+=("--force")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_volume_update()
{
    last_command="storageos_volume_update"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--description=")
    two_word_flags+=("-d")
    local_nonpersistent_flags+=("--description=")
    flags+=("--label-add=")
    local_nonpersistent_flags+=("--label-add=")
    flags+=("--label-rm=")
    local_nonpersistent_flags+=("--label-rm=")
    flags+=("--size=")
    two_word_flags+=("-s")
    local_nonpersistent_flags+=("--size=")
    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos_volume()
{
    last_command="storageos_volume"
    commands=()
    commands+=("create")
    commands+=("inspect")
    commands+=("ls")
    commands+=("mount")
    commands+=("rm")
    commands+=("unmount")
    commands+=("update")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--help")
    flags+=("-h")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_storageos()
{
    last_command="storageos"
    commands=()
    commands+=("cluster")
    commands+=("namespace")
    commands+=("node")
    commands+=("policy")
    commands+=("pool")
    commands+=("rule")
    commands+=("user")
    commands+=("version")
    commands+=("volume")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--config=")
    local_nonpersistent_flags+=("--config=")
    flags+=("--debug")
    flags+=("-D")
    local_nonpersistent_flags+=("--debug")
    flags+=("--help")
    flags+=("-h")
    flags+=("--host=")
    two_word_flags+=("-H")
    local_nonpersistent_flags+=("--host=")
    flags+=("--log-level=")
    two_word_flags+=("-l")
    local_nonpersistent_flags+=("--log-level=")
    flags+=("--password=")
    two_word_flags+=("-p")
    local_nonpersistent_flags+=("--password=")
    flags+=("--username=")
    two_word_flags+=("-u")
    local_nonpersistent_flags+=("--username=")
    flags+=("--version")
    flags+=("-v")
    local_nonpersistent_flags+=("--version")

    must_have_one_flag=()
    must_have_one_noun=()
    must_have_one_noun+=("cluster")
    must_have_one_noun+=("namespace")
    must_have_one_noun+=("node")
    must_have_one_noun+=("policy")
    must_have_one_noun+=("pool")
    must_have_one_noun+=("rule")
    must_have_one_noun+=("user")
    must_have_one_noun+=("version")
    must_have_one_noun+=("volume")
    noun_aliases=()
}

__start_storageos()
{
    local cur prev words cword
    declare -A flaghash 2>/dev/null || :
    if declare -F _init_completion >/dev/null 2>&1; then
        _init_completion -s || return
    else
        __my_init_completion -n "=" || return
    fi

    local c=0
    local flags=()
    local two_word_flags=()
    local local_nonpersistent_flags=()
    local flags_with_completion=()
    local flags_completion=()
    local commands=("storageos")
    local must_have_one_flag=()
    local must_have_one_noun=()
    local last_command
    local nouns=()

    __handle_word
}

if [[ $(type -t compopt) = "builtin" ]]; then
    complete -o default -F __start_storageos storageos
else
    complete -o default -o nospace -F __start_storageos storageos
fi

# ex: ts=4 sw=4 et filetype=sh
