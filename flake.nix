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
    {
      self,
      nixpkgs,
      simple-uvnix,
      ...
    }:
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
          basePkgs = import nixpkgs { inherit system; };
          baseImage = import ./nix/base-image.nix { pkgs = basePkgs; inherit self; };
          containerImage = import ./nix/container-image.nix { inherit baseImage; };
          cudaFixesOverlay = import ./nix/cuda/fixes-overlay.nix { inherit lib; };
          pkgsForCapability = import ./nix/cuda/pkgs-for-capability.nix {
            inherit nixpkgs system lib cudaFixesOverlay;
          };
          servicesForPkgs = pkgs: import ./nix/services { inherit pkgs; };

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
                    value = services."${serviceName}";
                  }
                ]
              )
            ) capabilities
          )
        )
      );
    };
}
