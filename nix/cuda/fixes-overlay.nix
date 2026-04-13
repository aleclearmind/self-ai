{ lib }:
final: prev: {
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
          let
            cudaPkgs = pyFinal.pkgs.cudaPackages;
          in
          (pyFinal.callPackage (pyFinal.pkgs.path + "/pkgs/development/python-modules/cupy") {
            cudaPackages = cudaPkgs.overrideScope (_: _: { cudnn = null; });
          }).overrideAttrs
            (old: {
              CUPY_NVCC_GENERATE_CODE = lib.concatMapStringsSep ";" mkGencode flags.cudaCapabilities;
              nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
                pyFinal.pkgs.removeReferencesTo
              ];
              # cupy's cudatoolkit-joined pulls all outputs including -static
              # into the runtime closure. Discover the actual static refs
              # baked into the built .so files and strip them — naming
              # cuda packages at eval time would pull their drvs (notably
              # tensorrt, ~7G) into cupy's input closure for nothing.
              postFixup = (old.postFixup or "") + ''
                find $out -name '*.so' -print0 | while IFS= read -r -d "" f; do
                  for ref in $(strings "$f" \
                      | grep -oE '/nix/store/[a-z0-9]{32}-[^[:space:]/]*-static' \
                      | sort -u); do
                    remove-references-to -t "$ref" "$f"
                  done
                done
              '';
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
        vllm = pyPrev.vllm.overrideAttrs {
          NIX_BUILD_CORES = 8;
          NVCC_THREADS = 4;
          CMAKE_BUILD_TYPE = "Release";
        };
        xformers = pyPrev.xformers.overrideAttrs { NIX_BUILD_CORES = 4; };
        gradio = pyPrev.gradio.overridePythonAttrs {
          doCheck = false;
          doInstallCheck = false;
          pythonImportsCheck = [ ];
        };
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
          libcudla = csPrev.libcudla.overrideAttrs (old: {
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
}
