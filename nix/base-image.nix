{ pkgs, self }:
let
  passwdFile = pkgs.writeTextDir "etc/passwd" ''
    root:x:0:0:root:/root:/bin/bash
    sshd:x:74:74:Privilege-separated SSH:/var/empty:/bin/false
    nobody:x:65534:65534:nobody:/var/empty:/bin/false
  '';

  nixNetRc = pkgs.writeTextDir "etc/nix/netrc" ''
    machine clearmind.me
      password eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjQyOTQ5NjcyOTUsIm5iZiI6MTc3NTM4MTE0OCwic3ViIjoic2VsZi1haS1ybyIsImh0dHBzOi8vand0LmF0dGljLnJzL3YxIjp7ImNhY2hlcyI6eyJzZWxmLWFpIjp7InIiOjF9fX19.dVGjEwsJMS5BfIKg-lXSKf1xflwy6IlLSOhyxXp5HcCYuqx29VOVsvAacJPe8pJtF8fyAtP4px8vOL3LfGMpro4Zx96fsBDUsP_gwHsvckjwBEOk6_06M-xla_YIokFt5sOW_Vfkh5euk2t47Am2i4vJMYcntYGlE0ZTPZEZtGpchFSk690tWSK3ekMqFnw0GXCW9T3kc2qPuyhIrcn2EakFWDaR-0SMD8fn15ONwux6ActHb1tp1myyYXCVrvzDSeCw0lMnqGv582dJHZt5uD_sINUkKgRzM0l0P72aVoe_KPGs6eI0MppAMZl5vxjLK7M8amfjL5Rzt2-A0-gyGfTcCsqPuWcV022iD3eiVsQ36fpoyCjfrazdQf8F-qsmLDMw_bcfhcqOUxw2KPugpa74tCAPlnagYcWSTetpPIaJw1VEFUpPy66mf4bW7PW-iyNVG5DbB3bPHTJotzdwu67_M-AnLI061cKz67dSzxXQl1VLShj4qhwWyCQh7KxoASTsPnph5SPYzU59MpzDtzRX8JDAfdzkaI4o88utF4dcWYaodSqYdfyQzoVzTWpMAtwz7wMpnRZy2fN-GC_7bwOr6GspWfO0sBoSdoU9Qp12BOMzR5JYOxEZvkMRMPHo3hdzH6D3FRrXlokX4FqKjLws5_O9dkRoday3O4mo7_I
  '';

  nixRegistry = pkgs.writeTextDir "etc/nix/registry.json" ''
    {
      "flakes": [
        {
          "from": {
            "id": "self-ai",
            "type": "indirect"
          },
          "to": {
            "path": "${self.outPath}",
            "type": "path"
          }
        }
      ],
      "version": 2
    }
  '';

  nixConf = pkgs.writeTextDir "etc/nix/nix.conf" ''
    extra-substituters = https://clearmind.me/attic/self-ai https://cache.flox.dev https://nix-community.cachix.org https://cache.nixos-cuda.org
    extra-trusted-substituters = https://cache.flox.dev https://nix-community.cachix.org https://cache.nixos-cuda.org
    extra-trusted-public-keys = self-ai:YNZICHKQpYE2PkLDj7OjIibm4fZOF2DrCvJ5hDPRJuY= flox-cache-public-1:7F4OyH7ZCnFhcze3fJdfyXYLQw/aV7GEed86nQ7IsOs= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs= cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M=
    extra-experimental-features = flakes nix-command
    build-users-group =
    netrc-file = /etc/nix/netrc
  '';

  groupFile = pkgs.writeTextDir "etc/group" ''
    root:x:0:
    sshd:x:74:
    nobody:x:65534:
  '';

  shadowFile = pkgs.writeTextDir "etc/shadow" ''
    root:*:1::::::
    sshd:*:1::::::
    nobody:*:1::::::
  '';

  nssSwitchFile = pkgs.writeTextDir "etc/nsswitch.conf" ''
    passwd: files
    group: files
    shadow: files
    hosts: files dns
  '';

  sshdConfigFile = pkgs.writeTextDir "etc/ssh/sshd_config" ''
    Port 22
    AddressFamily any
    ListenAddress 0.0.0.0
    ListenAddress ::

    HostKey /etc/ssh/ssh_host_ed25519_key
    HostKey /etc/ssh/ssh_host_rsa_key

    PermitRootLogin prohibit-password
    PubkeyAuthentication yes
    AuthorizedKeysFile .ssh/authorized_keys

    PasswordAuthentication no
    KbdInteractiveAuthentication no
    UsePAM no

    Subsystem sftp ${pkgs.openssh}/libexec/sftp-server

    PrintMotd no
    AcceptEnv LANG LC_*
  '';

  opensshBin = pkgs.buildEnv {
    name = "openssh-bin";
    paths = [ pkgs.openssh ];
    pathsToLink = [
      "/bin"
      "/libexec"
    ];
  };

  entrypoint = pkgs.writeShellScriptBin "entrypoint" ''
    set -euo pipefail
    set -x

    function log() {
      echo "$1" > /dev/stderr
    }

    mkdir -p /root/.ssh
    chmod 700 /root/.ssh

    mkdir -p /tmp
    chmod 1777 /tmp

    mkdir -p /var/empty
    chmod 711 /var/empty

    mkdir -p /run/sshd

    if [ -z "''${SSH_PUBLIC_KEY:-}" ]; then
      log "ERROR: SSH_PUBLIC_KEY environment variable is not set"
      exit 1
    fi

    echo "$SSH_PUBLIC_KEY" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys

    if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
      ${pkgs.openssh}/bin/ssh-keygen -t ed25519 \
        -f /etc/ssh/ssh_host_ed25519_key -N ""
    fi
    if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
      ${pkgs.openssh}/bin/ssh-keygen -t rsa -b 4096 \
        -f /etc/ssh/ssh_host_rsa_key -N ""
    fi

    DRIVER_VERSION=$(cat /proc/driver/nvidia/version | ${pkgs.gnused}/bin/sed -n 's/.*Module.* \([0-9]\+\(\.[0-9]\+\)\+\).*/\1/p')

    ${pkgs.util-linux}/bin/mount | ${pkgs.gnugrep}/bin/grep -F .so."$DRIVER_VERSION" | ${pkgs.gawk}/bin/awk '{ print $3 }'| while read FILE; do
      LINK=$(dirname "$FILE")/$(basename "$FILE" ".$DRIVER_VERSION").1
      if ! test -e "$LINK"; then
        log "Creating $LINK"
        ln -s "$FILE" "$LINK"
      fi
    done

    log "Starting SSH daemon"
    ${pkgs.openssh}/bin/sshd -D -e -f /etc/ssh/sshd_config
  '';

  etcEnvironment = pkgs.writeTextDir "etc/environment" ''
    SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt
    LD_LIBRARY_PATH=/lib/x86_64-linux-gnu
  '';

in
pkgs.dockerTools.buildImage {
  name = "nix-ssh";
  tag = "latest";

  copyToRoot = with pkgs; [
    # Common
    bash
    coreutils
    util-linux
    gnugrep
    gawk
    gnused
    cacert
    tini
    python313Packages.huggingface-hub
    wget
    attic-client
    git

    # Debug
    nix
    nano
    curl
    strace
    findutils
    binutils
    less

    # System
    opensshBin
    passwdFile
    groupFile
    shadowFile
    nssSwitchFile
    sshdConfigFile
    etcEnvironment
    entrypoint
    nixConf
    nixRegistry
    nixNetRc
  ];
  config = {
    Cmd = [
      "${pkgs.tini}/bin/tini"
      "--"
      "${entrypoint}/bin/entrypoint"
    ];
    ExposedPorts = {
      "22/tcp" = { };
    };
    Env = [
      "PATH=/bin"
    ];
  };
}
