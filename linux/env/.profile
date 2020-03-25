#!/bin/bash
# ~/.profile: executed by the command interpreter for login shells.
# This file is not read by bash(1), if ~/.bash_profile or ~/.bash_login
# exists.
# see /usr/share/doc/bash/examples/startup-files for examples.
# the files are located in the bash-doc package.

# the default umask is set in /etc/profile; for setting the umask
# for ssh logins, install and configure the libpam-umask package.
#umask 022

# if running bash
# if [ -n "$ZSH_VERSION" ]; then
#     # include .bashrc if it exists
#     if [ -f "$HOME/.zshrc" ]; then
# 	. "$HOME/.zshrc"
#     fi
# fi

# set PATH so it includes user's private bin directories
PATH="$HOME/bin:$HOME/.local/bin:$PATH"
JAVA_HOME="/opt/jdk"
MAVEN_HOME="/opt/maven"
PHABRICATOR_HOME="/opt/phabricator"
FZF_HOME="/home/lieh/.fzf"
PATH="$JAVA_HOME/bin:$MAVEN_HOME/bin:$PHABRICATOR_HOME/arcanist/bin:$FZF_HOME/bin:$PATH"

export EDITOR=vim
export JAVA_HOME
export MAVEN_HOME
export PATH="$HOME/.cargo/bin:$PATH"
