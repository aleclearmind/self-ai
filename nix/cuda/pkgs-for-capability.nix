{
  nixpkgs,
  system,
  lib,
  cudaFixesOverlay,
}:
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
pkgs."cudaPackages_${suffix}".pkgs
