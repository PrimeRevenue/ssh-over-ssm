#!/usr/bin/env bash
set -o nounset -o pipefail

if ! type session-manager-plugin &>/dev/null; then
cat <<EOF && exit 1
  Error! Unable to find session-manager-plugin. See:
  https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
EOF
fi

[[ "$#" -ne 2 ]] && printf "  Usage: ${0} <instance-id|instance-name> <ssh user>\n" && exit 1
[[ -z "${AWS_PROFILE:-}" ]] && printf "  AWS_PROFILE not set!\n" && exit 1

if [[ "$(ps -o comm= -p $PPID)" != "ssh" ]]; then
  ssh -o IdentityFile="~/.ssh/ssm-ssh-tmp" -o ProxyCommand="${0} ${1} ${2}" ${2}@${1}
  exit 0
fi

[[ "$1" =~ ^(i|mi)-([0-9a-f]{8,})$ ]] && iid="$1" || exit 1
[[ $? -ne 0 ]] && printf "  ERROR: could not determine instance-id with provided argument!\n" && exit 1

function cleanup {
  rm -f "${ssh_local}"/ssm-ssh-tmp{,.pub}
}

function tempkey {
  set -o errexit
  trap cleanup EXIT
#  ssh-keygen -t ed25519 -N '' -f "${ssh_local}"/ssm-ssh-tmp -C ssm-ssh-session
  ssh-keygen -t rsa -b 4096 -N '' -f "${ssh_local}"/ssm-ssh-tmp -C ssm-ssh-session
  ssh_pubkey=$(< "${ssh_local}"/ssm-ssh-tmp.pub)
}

# The user is the second input passed into the proxy command script 
ssh_user="$2"

# Name of the authorized_keys file on the remote host. This is pretty standard.
ssh_authkeys='authorized_keys'

# Local ssh directory where the temp private key is created and cleaned up
ssh_local=~/.ssh

# The public key that will be sent to the remote host using the SSM document
ssh_pubkey=$(ssh-add -L 2>/dev/null| head -1) || tempkey

# The name of the ssh directory on the remote host. This is pretty standard.
ssh_remote=.ssh

aws sso login

aws ssm send-command \
  --instance-ids "$iid" \
  --document-name 'SSHSSM' \
  --parameters "USER=$ssh_user,SSHDIR=$ssh_remote,AUTHKEYS=$ssh_authkeys,PUBKEY=$ssh_pubkey" \
  --comment "temporary ssm ssh access" #--debug

aws ssm start-session --document-name AWS-StartSSHSession --target "$iid" #--debug
