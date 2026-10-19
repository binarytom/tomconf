abbr -a yr 'cal -y'
abbr -a c cargo
abbr -a e nvim
abbr -a vim nvim
abbr -a m make
abbr -a o open
abbr -a g git
abbr -a gc 'git checkout'
abbr -a ga 'git add -p'
abbr -a vimdiff 'nvim -d'
abbr -a ct 'cargo t'
abbr -a ais "aws ec2 describe-instances | jq '.Reservations[] | .Instances[] | {iid: .InstanceId, type: .InstanceType, key:.KeyName, state:.State.Name, host:.PublicDnsName}'"
abbr -a print 'lp -h cups.csail.mit.edu -d xerox9 -oDuplex=DuplexNoTumble -oStapleLocation=SinglePortrait'
abbr -a gah 'git stash; and git pull --rebase; and git stash pop'

# Set paths per shell instead of overwriting Fish's persistent universal value.
# System paths are inherited, so only package-manager paths need to be added.
fish_add_path --global /usr/local/sbin /usr/local/bin
fish_add_path --global /opt/homebrew/sbin /opt/homebrew/bin

if command -q eza
	abbr -a l 'eza'
	abbr -a ls 'eza'
	abbr -a ll 'eza -l'
	abbr -a lll 'eza -la'
else
	abbr -a l 'ls'
	abbr -a ll 'ls -l'
	abbr -a lll 'ls -la'
end

for autojump_config in /opt/homebrew/share/autojump/autojump.fish /usr/local/share/autojump/autojump.fish
	if test -f "$autojump_config"
		source "$autojump_config"
		break
	end
end

function ssh
	if test (count $argv) -eq 0
		/usr/bin/ssh
		return $status
	end

	switch $argv[1]
	case "*.amazonaws.com" "ubuntu@*"
		env TERM=xterm /usr/bin/ssh $argv
	case "*"
		/usr/bin/ssh $argv
	end
end

function apass
	if test (count $argv) -ne 1
		pass $argv
		return
	end

	asend (pass $argv[1] | head -n1)
end

function asend
	if test (count $argv) -ne 1
		echo "No argument given"
		return
	end

	adb shell input text (echo $argv[1] | sed -e 's/ /%s/g' -e 's/\([[()<>{}$|;&*\\~"\'`]\)/\\\\\1/g')
end

function remote_alacritty
	# https://gist.github.com/costis/5135502
	if test (count $argv) -ne 1
		echo "Usage: remote_alacritty HOST" >&2
		return 2
	end

	set -l terminfo_file (mktemp)
	or return 1
	infocmp alacritty > "$terminfo_file"
	or begin
		command rm -f "$terminfo_file"
		return 1
	end

	# Preserve the first failure while still removing both temporary copies.
	set -l result 0
	scp "$terminfo_file" "$argv[1]:alacritty.ti"
	or set result $status
	if test $result -eq 0
		ssh "$argv[1]" tic alacritty.ti
		or set result $status
		ssh "$argv[1]" rm alacritty.ti
		set -l remote_cleanup_status $status
		if test $remote_cleanup_status -ne 0; and test $result -eq 0
			set result $remote_cleanup_status
		end
	end
	command rm -f "$terminfo_file"
	return $result
end

# Type - to move up to top parent dir which is a repository
function d
	while test $PWD != "/"
		if test -d .git
			break
		end
		cd ..
	end
end

# Fish git prompt
set __fish_git_prompt_showuntrackedfiles 'yes'
set __fish_git_prompt_showdirtystate 'yes'
set __fish_git_prompt_showstashstate ''
set __fish_git_prompt_showupstream 'none'
set -g fish_prompt_pwd_dir_length 3

# colored man output
# from http://linuxtidbits.wordpress.com/2009/03/23/less-colors-for-man-pages/
setenv LESS_TERMCAP_mb \e'[01;31m'       # begin blinking
setenv LESS_TERMCAP_md \e'[01;38;5;74m'  # begin bold
setenv LESS_TERMCAP_me \e'[0m'           # end mode
setenv LESS_TERMCAP_se \e'[0m'           # end standout-mode
setenv LESS_TERMCAP_so \e'[38;5;246m'    # begin standout-mode - info box
setenv LESS_TERMCAP_ue \e'[0m'           # end underline
setenv LESS_TERMCAP_us \e'[04;38;5;146m' # begin underline

setenv FZF_DEFAULT_COMMAND 'fd --type file --follow'
setenv FZF_CTRL_T_COMMAND 'fd --type file --follow'
setenv FZF_DEFAULT_OPTS '--height 20%'

# Fish should not add things to clipboard when killing
# See https://github.com/fish-shell/fish-shell/issues/772
set FISH_CLIPBOARD_CMD "cat"

function fish_user_key_bindings
	bind \cz 'fg>/dev/null ^/dev/null'
	if functions -q fish_fzf_key_bindings
		fish_fzf_key_bindings
	end
end

function fish_prompt
	set_color brblack
	echo -n "["(date "+%H:%M")"] "
	set_color blue
	echo -n (hostname)
	if [ $PWD != $HOME ]
		set_color brblack
		echo -n ':'
		set_color yellow
		echo -n (basename $PWD)
	end
	set_color green
	printf '%s ' (__fish_git_prompt)
	set_color red
	echo -n '| '
	set_color normal
end

function fish_greeting
	# Keep the greeting useful at a glance: uptime excludes users and load averages,
	# while disk usage shows only the three values relevant during normal work.
	set -l raw_uptime (string trim -- (uptime))
	set -l uptime_summary (string replace -r '^.*? up +' '' -- $raw_uptime)
	set uptime_summary (string replace -r ', +[0-9]+ users?.*$' '' -- $uptime_summary)
	if test "$uptime_summary" = "$raw_uptime"
		set uptime_summary unavailable
	end
	set -l root_disk (string split -n ' ' -- (df -h / | tail -n 1))

	echo
	set_color brblack
	printf '  ╭─ '
	set_color --bold cyan
	printf '%s\n' (hostname -s)

	set_color brblack
	printf '  │  '
	set_color normal
	printf '%s\n' (uname -sr)

	set_color brblack
	printf '  │  up      '
	set_color normal
	printf '%s\n' $uptime_summary

	set_color brblack
	printf '  ╰─ disk /  '
	set_color normal
	printf '%s used / %s  %s\n' $root_disk[3] $root_disk[2] $root_disk[5]

	# An empty heading creates visual noise, so the TODO section only exists when
	# the user has actually written something down.
	if test -s ~/todo
		echo
		set_color --bold yellow
		echo '  TODO'
		set_color normal
		while read -l todo_item
			if test -n "$todo_item"
				set_color yellow
				printf '  • '
				set_color normal
				printf '%s\n' $todo_item
			end
		end < ~/todo
	end

	set_color normal
	echo
end

fish_add_path --global "$HOME/.local/bin"
