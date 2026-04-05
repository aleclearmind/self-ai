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
    { self, nixpkgs, simple-uvnix, ... }:
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
          baseImage =
            let
              pkgs = import nixpkgs {
                inherit system;
              };

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
                UsePAM yes

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
            };
          containerImage =
            {
              name,
              baseName,
              extraPackages,
              pkgs,
            }:
            let
              x = 2;
            in
            pkgs.dockerTools.buildImage {
              name = "vast-ai-nix-${name}";
              tag = "latest";
              fromImage = baseImage;
              copyToRoot = extraPackages;
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
              (
                pyFinal: pyPrev:
                let
                  flags = pyFinal.pkgs.cudaPackages.flags;
                  mkGencode =
                    cap:
                    let
                      sm = lib.replaceStrings [ "." ] [ "" ] cap;
                    in
                    "arch=compute_${sm},code=sm_${sm}";
                in
                {
                  cupy =
                    (pyFinal.callPackage (pyFinal.pkgs.path + "/pkgs/development/python-modules/cupy") {
                      cudaPackages = pyFinal.pkgs.cudaPackages.overrideScope (_: _: { cudnn = null; });
                    }).overrideAttrs
                      (_: {
                        CUPY_NVCC_GENERATE_CODE = lib.concatMapStringsSep ";" mkGencode flags.cudaCapabilities;
                      });
                  # Generated .cpp files OOM gcc/nvcc — too few shards.
                  # https://github.com/pytorch/pytorch/issues/178666
                  torch = pyPrev.torch.overrideAttrs (old: {
                    # Limit parallelism — flash-attention backward kernels and
                    # large .cu files each eat several GB of RAM under nvcc.
                    NIX_BUILD_CORES = 4;

                    postPatch =
                      (old.postPatch or "")
                      + (
                        let
                          shards = 16;
                          range = lib.lists.range 0 (shards - 1);
                          mkSrc = prefix: i: ''"''${TORCH_SRC_DIR}/csrc/autograd/generated/${prefix}_${toString i}.cpp"'';
                          sedBlock = prefix: lib.concatStringsSep "\\\n" (map (mkSrc prefix) range);
                        in
                        ''
                          # Increase all codegen shards to ${toString shards}
                          sed -i 's/num_shards=5/num_shards=${toString shards}/g' \
                            tools/autograd/gen_trace_type.py \
                            tools/autograd/gen_variable_type.py
                          sed -i 's/num_shards = 5/num_shards = ${toString shards}/' \
                            tools/autograd/gen_autograd_functions.py
                          sed -i \
                            -e 's/num_shards=4 if dispatch_key == DispatchKey.CPU else 1/num_shards=${toString shards}/' \
                            -e 's/num_shards=5/num_shards=${toString shards}/g' \
                            -e 's/num_shards=4,/num_shards=${toString shards},/' \
                            torchgen/gen.py

                          # Update hardcoded file lists in caffe2/CMakeLists.txt
                          sed -i '/TraceType_0\.cpp/,/TraceType_4\.cpp/c\${sedBlock "TraceType"}' caffe2/CMakeLists.txt
                          sed -i '/VariableType_0\.cpp/,/VariableType_4\.cpp/c\${sedBlock "VariableType"}' caffe2/CMakeLists.txt
                          sed -i '/python_functions_0\.cpp/,/python_functions_4\.cpp/c\${sedBlock "python_functions"}' caffe2/CMakeLists.txt
                        ''
                      );
                  });
                  jax = pyPrev.jax.overrideAttrs {
                    doCheck = false;
                    doInstallCheck = false;
                    pythonImportsCheck = [ ];
                  };
                  bitsandbytes = pyPrev.bitsandbytes.overridePythonAttrs (old: {
                    cmakeFlags = (old.cmakeFlags or [ ]) ++ [
                      (lib.cmakeFeature "COMPUTE_CAPABILITY" flags.cmakeCudaArchitecturesString)
                    ];
                  });
                  llama-cpp-python = pyPrev.llama-cpp-python.overridePythonAttrs (old: {
                    cmakeFlags = (old.cmakeFlags or [ ]) ++ [
                      (lib.cmakeFeature "CMAKE_CUDA_ARCHITECTURES" flags.cmakeCudaArchitecturesString)
                    ];
                  });
                  vllm = pyPrev.vllm.overrideAttrs { NIX_BUILD_CORES = 4; };
                }
              )
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
                    # Fix missing _CCCL_PP_SPLICE_WITH_IMPL20 in CCCL preprocessor.h.
                    # IMPL21 chains to IMPL19 (skipping 20), causing an off-by-one when
                    # __CUDA_ARCH_LIST__ has >=17 entries.
                    cuda_cccl = csPrev.cuda_cccl.overrideAttrs {
                      postInstall = ''
                                                f=$out/include/cuda/std/__cccl/preprocessor.h
                                                chmod u+w "$f"
                                                sed -i -e '/^#define _CCCL_PP_SPLICE_WITH_IMPL19(SEP, P1, \.\.\.)/a\
                        #define _CCCL_PP_SPLICE_WITH_IMPL20(SEP, P1, ...) _CCCL_PP_CAT(P1##SEP, _CCCL_PP_SPLICE_WITH_IMPL19(SEP, __VA_ARGS__))' \
                                                    -e 's/\(#define _CCCL_PP_SPLICE_WITH_IMPL21(SEP, P1, \.\.\.)\) *_CCCL_PP_CAT(P1##SEP, _CCCL_PP_SPLICE_WITH_IMPL19(SEP, __VA_ARGS__))/\1 _CCCL_PP_CAT(P1##SEP, _CCCL_PP_SPLICE_WITH_IMPL20(SEP, __VA_ARGS__))/' \
                                                    "$f"
                      '';
                    };
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
              # TODO: update maxVersion to 13.0 once we use a version of torch supporting it (2.9.1 doesn't)
              version =
                if (builtins.isNull capability) || (builtins.isNull maxVersion) then "12.9" else maxVersion;
              suffix = lib.strings.replaceString "." "_" version;
            in
            pkgs."cudaPackages_${suffix}".pkgs;

          capabilities = [
            null
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
              pkgs.whisper-cpp
              pkgs.ffmpeg-headless
            ];
            llama = [ pkgs.llama-cpp ];
            vllm = [ pkgs.vllm ];
            ollama = [ pkgs.ollama-cuda ];
          };
        in
        {
          "container-base" = baseImage;
        }
        // builtins.listToAttrs (
          lib.flatten (
            builtins.map (
              capability:
              let
                pkgs = pkgsForCapability capability;
                services = servicesForPkgs pkgs;
                forEachService = handler: (lib.flatten (builtins.map handler (builtins.attrNames services)));
                suffix = if builtins.isNull capability then "" else "-${capability}";
              in
              forEachService (
                serviceName:
                let
                  name = "${serviceName}${suffix}";
                in
                [
                  # Produce the container image
                  {
                    name = "container-${name}";
                    value = containerImage {
                      name = name;
                      baseName = "base${suffix}";
                      extraPackages = services."${serviceName}";
                      pkgs = pkgs;
                    };
                  }
                  {
                    name = name;
                    # WIP: don't get the first, make a wrapper that pulls both
                    #      maybe make a script launching the service directly
                    value = builtins.elemAt services."${serviceName}" 0;
                  }
                ]
              )
            ) capabilities
          )
        )

      );
    };
}
