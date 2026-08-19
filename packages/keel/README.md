# keel

The umbrella over the keel capability packages
([keel-dyn](https://hackage.haskell.org/package/keel-dyn),
[keel-abi](https://hackage.haskell.org/package/keel-abi),
[keel-linalg](https://hackage.haskell.org/package/keel-linalg),
[keel-onnx](https://hackage.haskell.org/package/keel-onnx)):

- `keel doctor` — reports exactly which native capabilities resolve on
  this machine, which do not, and the one command that fixes each;
- `keel setup <openblas|onnx>` — checksum-pinned installation of the
  native runtimes into the per-user keel directory;
- `Keel.Bridge` — the explicit frame ↔ buffer copy between
  [dataframe](https://hackage.haskell.org/package/dataframe-core)
  columns and the `Storable` buffers keel-linalg and keel-abi take.
  Nulls are refused, not imputed.

```text
$ keel doctor
[ok]  keel-dyn      pure Haskell over the OS loader; no native dependency
[ok]  keel-abi      frozen C ABI structs, hand-laid-out; no native dependency
[ok]  keel-linalg   OpenBLAS 0.3.30 ...
[ok]  keel-onnx     ONNX Runtime 1.24.4 ...
```

keel is deliberately NOT a dataframe, a schema layer, an estimator
protocol, or a numeric prelude. It is the Windows-first capability and
interop floor for doing data science in Haskell: load native
capability, exchange buffers with the ecosystem, verify the setup.

Tutorials and the full design rationale live in the
[project repository](https://github.com/skymanbp/keel).
