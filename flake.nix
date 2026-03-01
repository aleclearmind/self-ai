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
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        in
        {
          ollama = pkgs.writeShellScriptBin "ollama" ''
            exec nix run --override-input nixpkgs nixpkgs/nixos-25.11 --impure github:aleclearmind/nixGL/8b4cf8637c0b0bdbe433a8758395f8ee58148c54 -- ${pkgs.ollama-cuda}/bin/ollama "$@"
          '';
        }
      );

    };
}
