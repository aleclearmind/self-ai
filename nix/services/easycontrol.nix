# EasyControl — Ghibli-style portrait generation (SD/Flux LoRA).
# https://github.com/Xiaojiu-z/EasyControl
{ pkgs }:
let
  python = pkgs.python312;
  src = pkgs.fetchFromGitHub {
    owner = "Xiaojiu-z";
    repo = "EasyControl";
    rev = "da44fa8e9de1586a2bc36e25947eb6f906ab2eff";
    hash = "sha256-xDYsp4PNN5BDNjkIKQrnOkVx2DL85rcd09SLb+Btel8=";
  };
  pkg = pkgs.stdenv.mkDerivation {
    pname = "easycontrol";
    version = "0.1.0";
    inherit src;
    dontBuild = true;
    dontConfigure = true;
    installPhase = ''
      site=$out/${python.sitePackages}
      mkdir -p $site/src
      cp src/__init__.py src/layers_cache.py src/lora_helper.py \
         src/pipeline.py src/transformer_flux.py $site/src/

      # Extract the Ghibli code block from README.md
      ${python}/bin/python3 -c '
      import re
      with open("README.md") as f:
          readme = f.read()
      m = re.search(
          r"### Ghibli-Style Portrait Generation\s*\n```python\n(.*?)```",
          readme, re.DOTALL,
      )
      assert m, "Could not find Ghibli code block in README.md"
      code = m.group(1)
      code = re.sub(r"^import spaces\n", "", code, flags=re.MULTILINE)
      code = re.sub(r"^@spaces\.GPU\(\)\n", "", code, flags=re.MULTILINE)
      lines = code.rstrip().split("\n")
      indented = "\n".join("    " + line if line.strip() else "" for line in lines)
      result = f"def main():\n{indented}\n\n\nif __name__ == \"__main__\":\n    main()\n"
      with open("ghibli_generate.py", "w") as f:
          f.write(result)
      '
      cp ghibli_generate.py $site/
    '';
  };
  env = python.withPackages (ps: [
    ps.torch
    ps.torchvision
    ps.torchaudio
    ps.diffusers
    ps.easydict
    ps.einops
    ps.peft
    ps.pillow
    ps.protobuf
    ps.requests
    ps.safetensors
    ps.sentencepiece
    ps.transformers
    ps.datasets
    ps.wandb
    ps.gradio
    ps.tqdm
    ps.huggingface-hub
    ps.accelerate
  ]);
in
pkgs.writeShellScriptBin "easycontrol-ghibli" ''
  export PYTHONPATH="${pkg}/${python.sitePackages}''${PYTHONPATH:+:$PYTHONPATH}"
  exec ${env}/bin/python3 -c "from ghibli_generate import main; main()" "$@"
''
