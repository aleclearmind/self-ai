{ pkgs }:
let
  wrapWithBins =
    drv: deps:
    pkgs.symlinkJoin {
      name = "${drv.name}-wrapped";
      paths = [ drv ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        for f in $out/bin/*; do
          wrapProgram "$f" \
            --prefix PATH : ${pkgs.lib.makeBinPath deps}
        done
      '';
    };

  easycontrol = import ./easycontrol.nix { inherit pkgs; };
in
{
  whisper = wrapWithBins pkgs.whisper-cpp [ pkgs.ffmpeg-headless ];
  llama = pkgs.llama-cpp;
  vllm = pkgs.vllm;
  ollama = pkgs.ollama-cuda;
  easycontrol = easycontrol;
}
