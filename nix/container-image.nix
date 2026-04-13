{ baseImage }:
{
  name,
  baseName,
  extraPackages,
  pkgs,
}:
pkgs.dockerTools.buildImage {
  name = "vast-ai-nix-${name}";
  tag = "latest";
  fromImage = baseImage;
  copyToRoot = extraPackages;
}
