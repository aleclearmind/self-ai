# TODO: finish launch-llm and launch-whisper
# TODO: strace to reduce image size
# TODO: we could pin an image to a certain cuda capability https://github.com/NixOS/nixpkgs/blob/nixos-25.11/pkgs/development/python-modules/torch/source/default.nix#L123
#       pytorch, libcublas, libggml-cuda.so, libcudnn_cnn_*.so take GBs
#       vastai search gives you compute_cap (11 different ones as of now)

{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    simple-uvnix.url = "github:aleclearmind/simple-uvnix";
    simple-uvnix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, simple-uvnix, ... }:
    let
      inherit (nixpkgs) lib;
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          devShell = pkgs.mkShell (
            simple-uvnix.lib.addUvVirtualEnvToShell {
              python = pkgs.python3;
              baseShell = {
                packages = [ pkgs.yq-go ];
              };
              inherit pkgs;
              workspaceRoot = ./.;
            }
          );
        in
        {
          default = devShell;
        }
      );

      packages = forAllSystems (
        system:
        let
          cudaPackage =
            {
              name,
              baseName,
              extraPackages,
              pkgs,
            }:
            let
              passwdFile = pkgs.writeTextDir "etc/passwd" ''
                root:x:0:0:root:/root:/bin/bash
                sshd:x:74:74:Privilege-separated SSH:/var/empty:/bin/false
                nobody:x:65534:65534:nobody:/var/empty:/bin/false
              '';

              nixConf = pkgs.writeTextDir "etc/nix/nix.conf" ''
                extra-substituters = https://cache.flox.dev https://nix-community.cachix.org https://cache.nixos-cuda.org
                extra-trusted-substituters = https://cache.flox.dev https://nix-community.cachix.org https://cache.nixos-cuda.org
                extra-trusted-public-keys = flox-cache-public-1:7F4OyH7ZCnFhcze3fJdfyXYLQw/aV7GEed86nQ7IsOs= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs= cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M=
                extra-experimental-features = flakes nix-command
                build-users-group =
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

              etcProfile = pkgs.writeTextDir "etc/profile" ''
                export SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt
                export LD_LIBRARY_PATH=/lib/x86_64-linux-gnu
              '';

              baseImage = pkgs.dockerTools.buildImage {
                name = "vast-ai-nix-${baseName}";
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
                  etcProfile
                  entrypoint
                  nixConf
                ];
              };

            in
            pkgs.dockerTools.buildImage {
              name = "vast-ai-nix-${name}";
              tag = "latest";
              fromImage = baseImage;
              copyToRoot = extraPackages;
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
            };
          # pkgs.runCommand "vast-ai-nix-stripped.tar.gz"
          #   {
          #     nativeBuildInputs = [
          #       pkgs.jq
          #       pkgs.gnutar
          #       pkgs.pigz
          #       pkgs.fakeroot
          #     ];
          #   }
          #   ''
          #     fakeroot bash -euo pipefail -c '
          #       mkdir work && cd work
          #       tar xf ${baseImage}

          #       layer=$(jq -r ".[0].Layers[0]" manifest.json)
          #       mkdir layer
          #       tar xf "$layer" -C layer

          #       # glibc: locale source data + charset converters
          #       rm -rf layer/nix/store/*-glibc-*/share/i18n
          #       rm -rf layer/nix/store/*-glibc-*/share/locale
          #       rm -rf layer/nix/store/*-glibc-*/lib/gconv

          #       # ncurses: keep only common terminal definitions
          #       find layer/nix/store -path "*/share/terminfo" -type d | while read d; do
          #         find "$d" -type f \
          #           ! -name "xterm*" ! -name "linux" ! -name "dumb" \
          #           ! -name "screen*" ! -name "vt100" ! -name "vt220" \
          #           ! -name "tmux*" ! -name "alacritty*" \
          #           -delete
          #         find "$d" -type d -empty -delete
          #       done

          #       # man, doc, info, locale across all packages
          #       find layer/nix/store -maxdepth 3 -path "*/share/man" -type d -exec rm -rf {} + 2>/dev/null || true
          #       find layer/nix/store -maxdepth 3 -path "*/share/doc" -type d -exec rm -rf {} + 2>/dev/null || true
          #       find layer/nix/store -maxdepth 3 -path "*/share/info" -type d -exec rm -rf {} + 2>/dev/null || true
          #       find layer/nix/store -maxdepth 3 -path "*/share/locale" -type d -exec rm -rf {} + 2>/dev/null || true

          #       # repack layer and fix digests
          #       tar cf "$layer" -C layer .
          #       rm -rf layer

          #       newdigest="sha256:$(sha256sum "$layer" | cut -d" " -f1)"
          #       configfile=$(jq -r ".[0].Config" manifest.json)
          #       jq ".rootfs.diff_ids = [\"$newdigest\"]" "$configfile" > config_new.json

          #       newconfighash=$(sha256sum config_new.json | cut -d" " -f1)
          #       mv config_new.json "$newconfighash.json"
          #       jq ".[0].Config = \"$newconfighash.json\"" manifest.json > manifest_new.json
          #       mv manifest_new.json manifest.json
          #       rm -f "$configfile"

          #       tar cf - * | pigz > $out
          #     '
          #   '';
          cudaFixesOverlay = final: prev: {
            pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
              # Disable tests for all Python packages — they're slow, often need
              # hardware (CUDA), and aren't useful when building docker images.
              (_: pyPrev:
                lib.mapAttrs (
                  _: pkg:
                  if lib.isDerivation pkg then
                    pkg.overridePythonAttrs {
                      doCheck = false;
                      pythonImportsCheck = [ ];
                    }
                  else
                    pkg
                ) pyPrev
              )
             (pyFinal: pyPrev: {
                cupy =
                  (pyFinal.callPackage (pyFinal.pkgs.path + "/pkgs/development/python-modules/cupy") {
                    cudaPackages = pyFinal.pkgs.cudaPackages.overrideScope (_: _: { cudnn = null; });
                  }).overrideAttrs
                    (_: {
                      CUPY_NVCC_GENERATE_CODE = "arch=compute_61,code=sm_61";
                    });
                bitsandbytes = pyPrev.bitsandbytes.overridePythonAttrs (old: {
                  cmakeFlags = (old.cmakeFlags or [ ]) ++ [
                    (lib.cmakeFeature "CMAKE_CUDA_ARCHITECTURES" pyFinal.pkgs.cudaPackages.flags.cmakeCudaArchitecturesString)
                  ];
                });

              })
            ];
            # cuda_compat has no source on x86_64 but allowUnsupportedSystem makes
            # meta.available = true, causing the autoAddCudaCompatRunpath hook to
            # try building it. Fix via _cuda.extensions which propagates into all
            # CUDA package sets including rebound ones.
            _cuda = prev._cuda.extend (
              _: cprev: {
                extensions = cprev.extensions ++ [
                  (_: csPrev: {
                    cuda_compat = csPrev.cuda_compat.overrideAttrs (old: {
                      meta = old.meta // {
                        broken = true;
                      };
                    });
                  })
                ];
              }
            );
          };
          pkgsForCapability =
            capability:
            let
              pkgs = import nixpkgs {
                inherit system;
                overlays = [ cudaFixesOverlay ];
                config = {
                  allowUnsupportedSystem = true;
                  allowUnfree = true;
                  cudaSupport = true;
                  rocmSupport = false;
                }
                // (
                  if builtins.isNull capability then
                    { }
                  else
                    {
                      cudaCapabilities = [ capability ];
                      cudaForwardCompat = false;
                    }
                );
              };
              cudaCapabilityToInfo = pkgs._cuda.db.cudaCapabilityToInfo;
              info =
                if builtins.hasAttr "${capability}a" cudaCapabilityToInfo then
                  cudaCapabilityToInfo."${capability}a"
                else
                  cudaCapabilityToInfo."${capability}";
              maxVersion = info.maxCudaMajorMinorVersion;
              version = if builtins.isNull maxVersion then "13.0" else maxVersion;
              suffix = lib.strings.replaceString "." "_" version;
            in
            pkgs."cudaPackages_${suffix}".pkgs;

          capabilities = [
            "6.0"
            "6.1"
            "7.0"
            "7.5"
            "8.0"
            "8.6"
            "8.9"
            "9.0"
            "10.0"
            "12.0"
          ];
          # capabilities =
          #   let
          #     genericPkgs = import nixpkgs {
          #       inherit system;
          #       config = {
          #         allowUnfree = true;
          #         cudaSupport = true;
          #       };
          #     };
          #   in
          #   [ null ] ++ builtins.attrNames genericPkgs._cuda.db.cudaCapabilityToInfo;
          servicesForPkgs = pkgs: {
            whisper = [
              pkgs.ffmpeg-headless
              pkgs.whisper-cpp
            ];
            llama = [ pkgs.llama-cpp ];
            vllm = [ pkgs.vllm ];
            ollama = [ pkgs.ollama-cuda ];
          };
        in
        builtins.listToAttrs (
          lib.flatten (
            builtins.map (
              capability:
              let
                pkgs = pkgsForCapability capability;
                services = servicesForPkgs pkgs;
              in
              (builtins.map (
                serviceName:
                let
                  suffix = if builtins.isNull capability then "" else "-${capability}";
                  name = "${serviceName}${suffix}";
                in
                {
                  name = name;
                  value = cudaPackage {
                    name = name;
                    baseName = "base${suffix}";
                    extraPackages = services."${serviceName}";
                    pkgs = pkgs;
                  };
                }
              ) (builtins.attrNames services))
            ) capabilities
          )
        )

      );
    };

}
