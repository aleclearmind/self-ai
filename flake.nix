{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
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

    };
}
