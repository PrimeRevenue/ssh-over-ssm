
# ssh-over-ssm
Configure SSH and use AWS SSM to connect to instances. Requires git-managing your configs for quick setup and keeping users up-to-date and in sync.

## Main Changes from Original

The original branch from elpy1 is a brilliant take on leveraging SSM to connect securely over SSH. Here at Prime Revenue, we wanted to expand on it to faciliate all end user ssh access to both AWS hosts and legecy, On-Premise hosts. With such a broader scope, we made the following modifcations:

- First, we wanted to only use this ssh-over-ssm project to allow end user ssh access to servers using SSM, and only for shell access to servers. With full access to SSM, end users would have far more access to the system than needed. And with how this works as an SSH proxy command, end users would be able to change the SendCommand using the general "Run Command" in their `~/bin/ssh-ssm.sh` to whatever they want since that is within the user's home directory. In the spirit of least amount of privilege neccassary, we create an SSM document that mimics the original branch's SendCommand, and then give the end user only access to that SSM document. When calling the proxy command, it uses that custom document instead of the general "Run Command" document with contents that could easily be changed by the end user. 
- Second, we also wanted to use this to connect to on-premise hosts. Since the shell script of the Proxy Command only expects EC2 hosts that start with `i-*`, we made it check for both `i-*` and `mi-*` so it also checks for our registered on-premise hosts.
- Third, we decided to go with a well organzied github for the ssh configs with no support for the python script. The python command is used for two things: updating the SSM agent and trying to the instance ID when it doesn't match the regex in the Proxy Command. Only admins need to be able to update SSM agents, so it is a good thing that not everyone have access to that fucntionality in our use case. Also in the original branch during the Proxy Command, the python script is called when a hostname is passed to the proxy command script that does not match an instance ID. That python script then lookups to see if there is an instance ID with that name. For the scope of which we want to use this project, it would be too much to also keep up with every user's python environment. To make it less complicated rollout with less requirements for support, we will fail the script if it is called with a hostname that doesn't begin with `i-*` or `mi-*` with the assumption that the ssh config is correct.
- Forth, some of the timeouts have been increased slightly. During testing of this branch, timeouts were encountered with on-premise testing at the original branch's default values. A slight increase has aliviated that.

##Prerequisite:

- A custom SSM document that only takes in the needed paraters for uploading the public key. Here is an example cloudformation
```
Description: >
  Document for creating temporary keys for ssh access using SSM

Parameters:
  DocumentName:
    Description: Name of the SSH SSM Document
    Type: String
    Default: SSHSSM

Resources:
  SSHSSMDocument:
    Type: AWS::SSM::Document
    Properties:
      Name: !Ref DocumentName
      DocumentType: Command
      Content:
        schemaVersion: '2.2'
        description: State Manager Bootstrap Example
        parameters:
          USER:
            type: "String"
            description: "ssh user"
          AUTHKEYS:
            type: "String"
            description: "authorized key"
            default: ".ssh/authorized_keys"
          PUBKEY:
            type: "String"
            description: "pub key to publish"
        mainSteps:
          - action: "aws:runShellScript"
            name: "example"
            inputs:
              runCommand:
              - "u=`getent passwd {{ USER }}` && x=`echo $u |cut -d: -f6` || exit 1"
              - "grep '{{ PUBKEY }}' $x/{{ AUTHKEYS }} && exit 1"
              - "printf '{{ PUBKEY }}' | tee -a $x/{{ AUTHKEYS }} && sleep 20"
              - "sed -i s,'{{ PUBKEY }}',, $x/{{ AUTHKEYS }}"

Outputs:
  SSHSSMDocumentOutput:
    Description: SSM Document Resource
    Value: !Ref SSHSSMDocument
```

- The end user must have permission to the document along with start session. This is a really useful reference for IAM permissions:
https://iam.cloudonaut.io/

Following is the original README with some edits to the timeouts plus removing parts about the python script. 

## Info and requirements
Recently I was required to administer AWS instances via Session Manager. After downloading the required plugin and initiating a SSM session locally using `aws ssm start-session` I found myself in a situation where I couldn't easily copy a file from my machine to the server (e.g. SCP, sftp, rsync etc). After some reading of AWS documentation I found it's possible to connect via SSH over SSM, solving this issue. You also get all the other benefits and functionality of SSH e.g. encryption, proxy jumping, port forwarding, socks etc.

At first I really wasn't too keen on SSM but now I'm an advocate! Some cool features:

- You can connect to your private instances inside your VPC without jumping through a public-facing bastion or instance
- You don't need to store any SSH keys locally or on the server.
- Users only require necessary IAM permissions and ability to reach their regional SSM endpoint (via HTTPS).
- SSM 'Documents' available to restrict users to specific tasks e.g. `AWS-PasswordReset` and` AWS-StartPortForwardingSession`.
- Due to the way SSM works it's unlikely to find yourself blocked by network-level security, making it a great choice if you need to get out to the internet from inside a restrictive network :p

### Requirements
- Instances must have access to ssm.{region}.amazonaws.com
- IAM instance profile allowing SSM access must be attached to EC2 instance
- SSM agent must be installed on EC2 instance
- AWS cli requires you install `session-manager-plugin` locally

Existing instances with SSM agent already installed may require agent updates.

## How it works
You configure each of your instances in your SSH config and specify `ssh-ssm.sh` to be executed as a `ProxyCommand` with your `AWS_PROFILE` environment variable set.
If your key is available via ssh-agent it will be used by the script, otherwise a temporary key will be created, used and destroyed on termination of the script. The public key is copied across to the instance using `aws ssm send-command` and then the SSH session is initiated through SSM using `aws ssm start-session` (with document `AWS-StartSSHSession`) after which the SSH connection is made. The public key copied to the server is removed after 15 seconds and provides enough time for SSH authentication.

## Installation and Usage
This tool is intended to be used in conjunction with `ssh`. It requires that you've configured your awscli (`~/.aws/{config,credentials}`) properly and you spend a small amount of time planning and updating your ssh config.

### SSH config

Now that all of our instances are running an up-to-date agent we need to update our SSH config.

Example of basic `~/.ssh/config`:
```
Host confluence-prod.personal
  Hostname i-0xxxxxxxxxxxxxe28
  User ec2-user
  ProxyCommand bash -c "AWS_PROFILE=atlassian-prod ~/bin/ssh-ssm.sh %h %r"

Host jira-stg.personal
  Hostname i-0xxxxxxxxxxxxxe49
  User ec2-user
  ProxyCommand bash -c "AWS_PROFILE=atlassian-nonprod ~/bin/ssh-ssm.sh %h %r"

Host jenkins-master.personal
  Hostname i-0xxxxxxxxxxxxx143
  User centos
  ProxyCommand bash -c "AWS_PROFILE=jenkins-home ~/bin/ssh-ssm.sh %h %r"

Match Host i-*
  IdentityFile ~/.ssh/ssm-ssh-tmp
  PasswordAuthentication no
  GSSAPIAuthentication no
```
Above we've configured 3 separate instances for SSH access over SSM, specifying the username, instance ID and host to use for local commands i.e. `ssh {host}`. We also set our `AWS_PROFILE` as per awscli configuration. If you only have a few instances to configure this might be OK to work with, but when you've got a large number of instances and different AWS profiles (think: work-internal, work-clients, personal) you're bound to end up with a huge config file and lots of repetition. I've taken a slightly different approach by splitting up my config into fragments and using ssh config directive `Include`. It is currently set up similar to below.

Example `~/.ssh/config`:
```
Host *
  Include conf.d/internal/*
  Include conf.d/clients/*
  Include conf.d/personal/*
  KeepAlive yes
  Protocol 2
  ServerAliveInterval 30
  ConnectTimeout 30

Match exec "find ~/.ssh/conf.d -type f -name '*_ssm' -exec grep '%h' {} +"
  IdentityFile ~/.ssh/ssm-ssh-tmp
  PasswordAuthentication no
  GSSAPIAuthentication no
```

Example `~/.ssh/conf.d/personal/atlassian-prod_ssm`:
```
Host confluence-prod.personal
  Hostname i-0xxxxxxxxxxxxxe28

Host jira-prod.personal
  Hostname i-0xxxxxxxxxxxxxe49

Host bitbucket-prod.personal
  Hostname i-0xxxxxxxxxxxxx835

Match host i-*
  User ec2-user
  ProxyCommand bash -c "AWS_PROFILE=atlassian-prod ~/bin/ssh-ssm.sh %h %r"
```

All SSM hosts are saved in a fragment ending in '\_ssm'. Within the config fragment I include each instance, their corresponding hostname (instance ID) and a `Match` directive containing the relevant `User` and `ProxyCommand`. This approach is not required but I personally find it neater and better for management.

### Testing/debugging SSH connections

Show which config file and `Host` you match against and the final command executed by SSH:
```
ssh -G confluence-prod.personal 
```

Debug connection issues:
```
ssh -vvv user@host
```

For further informaton consider enabling debug for `aws` (edit ssh-ssm.sh):
```
aws ssm --debug command
```

Once you've tested it and you're confident it's all correct give it a go! Remember to place `ssh-ssm.sh` in `~/bin/` (or wherever you prefer).

### Example usage
SSH:
```
[elpy1@testbox ~]$ aws-mfa
INFO - Validating credentials for profile: default
INFO - Your credentials are still valid for 14105.807801 seconds they will expire at 2020-01-25 18:06:08
[elpy1@testbox ~]$ ssh confluence-prod.personal
Last login: Sat Jan 25 08:59:40 2020 from localhost

       __|  __|_  )
       _|  (     /   Amazon Linux 2 AMI
      ___|\___|___|

https://aws.amazon.com/amazon-linux-2/
[ec2-user@ip-10-xx-x-x06 ~]$ logout
Connection to i-0fxxxxxxxxxxxxe28 closed.
```

SCP:
```
[elpy@testbox ~]$ scp ~/bin/ssh-ssm.sh bitbucket-prod.personal:~
ssh-ssm.sh                                                                                       100%  366    49.4KB/s   00:00

[elpy@testbox ~]$ ssh bitbucket-prod.personal ls -la ssh\*
-rwxrwxr-x 1 ec2-user ec2-user 366 Jan 26 07:27 ssh-ssm.sh
```

SOCKS:
```
[elpy@testbox ~]$ ssh -f -nNT -D 8080 jira-prod.personal
[elpy@testbox ~]$ curl -x socks://localhost:8080 ipinfo.io/ip
54.xxx.xxx.49
[elpy@testbox ~]$ whois 54.xxx.xxx.49 | grep -i techname
OrgTechName:   Amazon EC2 Network Operations
```

DB tunnel:
```
[elpy@testbox ~]$ ssh -f -nNT -oExitOnForwardFailure=yes -L 5432:db1.host.internal:5432 jira-prod.personal
[elpy@testbox ~]$ ss -lt4p sport = :5432
State      Recv-Q Send-Q Local Address:Port                 Peer Address:Port
LISTEN     0      128       127.0.0.1:postgres                        *:*                     users:(("ssh",pid=26130,fd=6))
[elpy@testbox ~]$ psql --host localhost --port 5432
Password:
```

Required is adding each instance to our `~/.ssh/config` so that we can use `ssh` directly. Infrastructure as code is here to stay.  It is not required for you to pre-configure your AWS profile if you're happy to specify it or switch to it each time you use `ssh`

Example `~/.ssh/config`:
```
Host jenkins-dev* instance1 instance3 instance6
  ProxyCommand ~/bin/ssh-ssm.sh %h %r

...

Match host i-*
  StrictHostKeyChecking no
  IdentityFile ~/.ssh/ssm-ssh-tmp
  PasswordAuthentication no
  GSSAPIAuthentication no
  ProxyCommand ~/bin/ssh-ssm.sh %h %r
```

This would enable you to ssh to instances with names: `instance1`, `instance3`, `instance6` and any instance beginning with name `jenkins-dev`. Keep in mind you need to specify the AWS profile and the `User` as we have not pre-configured it. Example below.

SSH:
```
[elpy@testbox ~]$ AWS_PROFILE=home ssh centos@jenkins-dev-slave-autoscale01
Last login: Mon Feb 24 03:45:15 2020 from localhost
[centos@ip-10-xx-x-x53 ~]$ logout
Connection to i-0xxxxxxxxxxxxx67a closed.
```

A different approach you could take (with even less pre-configuration required) is to prepend ALL `ssh` commands to SSM instances with `ssm.`, see below.

Example `~/.ssh/config`:
```
Match host ssm.*
  IdentityFile ~/.ssh/ssm-ssh-tmp
  StrictHostKeyChecking no
  PasswordAuthentication no
  GSSAPIAuthentication no
  ProxyCommand ~/bin/ssh-ssm.sh %h %r
```
Once again, this requires you enter the username and specify AWS profile when using `ssh` as we have not pre-configured it. If you use the same distro and user on all instances you could add and specify `User` in the `Match` block above. Example below.

SSH:
```
[elpy1@testbox ~]$ AWS_PROFILE=atlassian-prod ssh ec2-user@ssm.confluence-autoscale-02
Last login: Sat Feb 15 06:57:02 2020 from localhost

       __|  __|_  )
       _|  (     /   Amazon Linux 2 AMI
      ___|\___|___|

https://aws.amazon.com/amazon-linux-2/
[ec2-user@ip-10-xx-x-x06 ~]$ logout
Connection to ssm.confluence-autoscale-02 closed.

```

Maybe others have come up with other cool ways to utilise SSH and AWS SSM. Feel free to reach out and/or contribute with ideas!

