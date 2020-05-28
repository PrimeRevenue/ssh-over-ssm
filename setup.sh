#!/bin/bash

if [ ! -d ~/bin/ ]; then
  echo "Creating bin dir in home dir"
  mkdir ~/bin/
else
  echo "bin directory already exists"
fi

if [ ! -f ~/bin/ssh-ssm.sh  ]; then
  echo "Creating symlink for the SSH over SSM shell script"
  DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
  ln -s $DIR/ssh-ssm.sh ~/bin/ssh-ssm.sh
else
  echo "The SSH over SSM shell script file already exists"
fi
