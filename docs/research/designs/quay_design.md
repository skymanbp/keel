# name
Quay

# philosophy
Quay is a wharf, not a factory: data science capability arrives in Haskell by *docking* to things that already work, and almost nothing is grown locally.

Five rules, in priority order.

1. DO NOT REBUILD THE DATAFRAME. `dataframe` 3.5.0.0 / `dataframe-core` 2.4.0.0 (uploaded 2026-08-14, https://hackage.haskell.org/package/dataframe-core) is a live, columnar, three-API-tier, Parquet-reading, lazily-optimizing dataframe with a scikit-learn-shaped `dataframe-learn` 2.4.1.0 on top. Rebuilding it splits an ecosystem whose own roadmap names "No community of maintainers and contributors" as its top gap. Quay depends on it with tight bounds and upstreams the gaps.

2. BIND, DON'T REIMPLEMENT NUMERICS. Kernels come from OpenBLAS (CBLAS/LAPACKE C ABI), ONNX Runtime (MIT, https://github.com/microsoft/onnxruntime/blob/main/LICENSE), and optionally DuckDB. Haskell owns shape logic, ownership, ergonomics, and the plan — not the inner loop. The projects that died (HLearn/SubHask, DataHaskell's 2017 "NumPy for Haskell") all died rewriting the numeric foundation first.

3. NATIVE DEPENDENCIES ARE LOADED AT RUNTIME, NEVER LINKED AT BUILD TIME. This is the single most important engineering decision and it is what makes Windows-first real. `cabal install quay` has zero `extra-libraries`, zero pkg-config, zero MSYS2 pacman step, and cannot fail on a missing C library. BLAS/LAPACK, ONNX Runtime and DuckDB are `LoadLibraryW`/`dlopen`'d at first use through a capability record; if absent, a pure-Haskell fallback runs and prints one loud line. hmatrix's five-year-stale build system, not its API, is what makes hmatrix unusable — so we do not have a build system to be stale. ONNX Runtime's C API (`OrtGetApiBase()` returning a struct of function pointers) is *designed* for exactly this.

4. SHIP THE CONTRACTS NOBODY OWNS, FIRST, AS TINY PACKAGES. The Arrow C Data Interface (inbound — Haskell has no inbound implementation at all; `dataframe-arrow` is export-to-Python only), DLPack, and a scikit-learn-style estimator/hyperparameter protocol. Julia's Tables.jl and ChainRulesCore prove that a small protocol released *before* the implementations unifies an ecosystem; `__dataframe__` proves that a fat middle-layer protocol does not.

5. SIMPLE HASKELL. GHC2021, rank-1 types, plain records, a handful of type classes, runtime shape checks, `OverloadedRecordDot` for reads. No LinearTypes (GHC 9.14 still documents multiplicity polymorphism as "really unreliable"), no type-level shapes in v1, no dependent-Haskell bets, no new numeric prelude. Types describe the *plan* and the *ownership*, never hide closures inside it (Spark's `Dataset[T]` lesson).

The product promise is a number: on a bare Windows 11 box, `ghcup` one-liner → `cabal install quay` → `quay setup` → a working CSV→model→plot script in under 15 minutes, with no C toolchain step the user has to get right.

# scope
IN v1 (target ~24 weeks):

- Arrow C Data Interface + Arrow C Stream Interface, both directions (import AND export), with correct release-callback ownership. Zero build-time dependency on any Arrow library, per the spec's design (https://arrow.apache.org/docs/format/CDataInterface.html).
- DLPack `DLManagedTensorVersioned` import/export (DLPack ≥1.0 struct; ≥1.3 also adds a C-level exchange API — https://github.com/dmlc/dlpack/releases).
- A strided n-D `Tensor` over `Data.Vector.Storable` buffers: offset+shape+strides (LMAD, orthotope-style), so transpose/slice/broadcast are O(1) metadata only.
- CBLAS L3 + ~15 LAPACKE drivers via runtime-loaded OpenBLAS, plus a pure-Haskell reference fallback for gemm/potrf/gesv/gels so nothing ever hard-fails.
- DataFrame bridge: `dataframe` ⇄ Arrow (the inbound half the ecosystem lacks), unboxed numeric column ⇄ `Tensor` with documented zero-copy conditions, and `Generic`/HKD record ⇄ DataFrame conversion (closing the "two independent type systems" seam users complain about).
- An estimator/transformer/pipeline/cross-validation/metrics protocol with hyperparameters-as-inspectable-`Generic`-records and JSON model serialization — the piece nobody in Haskell has.
- Protocol adapters wrapping `dataframe-learn`'s existing estimators, plus BLAS-backed ridge/lasso/logistic/PCA/k-means where dense linear algebra dominates.
- MIT-licensed ONNX Runtime **inference** bindings (the existing `hs-onnxruntime-capi` 0.1.0.0 is AGPL-3.0-only, verified on Hackage — license-incompatible and a clean hole to fill). Windows/Linux/macOS, CPU by default.
- Plotting: Vega-Lite spec emission plus static PNG/SVG/PDF export via a runtime-fetched `vl-convert` binary, with a terminal fallback. Static export is the single most-requested missing capability in Haskell plotting.
- `quay` CLI: `quay setup {blas,onnx,duckdb,vl-convert}` (checksum-pinned downloads into a user data dir), `quay doctor` (what is loaded, what is missing, what fallback you are on), `quay repl` (preloaded ghci).
- `quay-python`: a Cabal `foreign-library` of `type: native-shared` (https://cabal.readthedocs.io/en/stable/cabal-package-description-file.html) exposing Haskell pipelines to Python as an `ArrowArrayStream`. Being callable FROM Python is worth more than calling Python.
- CI on Windows + Linux + macOS, GHC 9.10.3 / 9.12.4 / 9.14.1.

EXPLICITLY OUT of v1:

- A new DataFrame type, a new CSV reader, a new Parquet codec, a new query optimizer. Use `dataframe-core`, `dataframe-fastcsv`, `dataframe-parquet`, `dataframe-lazy`. The Parquet *writer* gap (issue #181) is already a funded GSoC 2026 project; contribute there, do not race it.
- Autodiff and neural-network training. No `ad`/`backprop`/`horde-ad` engine of our own; deep learning is served by ONNX inference now and a DLPack bridge to hasktorch later (non-Windows).
- GPU kernels, an `accelerate` backend, a SIMD wrapper library. Real gaps, wrong project, wrong decade for a 24-week v1.
- Type-level shapes/schemas as the flagship API, LinearTypes, dependent-Haskell features, WASM/JS targets, distributed compute, R interop (`inline-r`'s Hackage builds fail and it is in no Stackage snapshot).
- A curated "which library should I use" inventory. That was original DataHaskell's main artifact and its named failure mode ("ordering from a diner").

# architecture
SIX LAYERS. Each layer is independently useful and independently publishable; if the project dies at layer N, layers 1..N-1 are still net-positive contributions to Haskell.

L0 — ABI (`quay-abi`, `quay-dyn`). Pure Haskell, no C toolchain requirement beyond GHC's own.
  * `quay-abi` hand-writes `Storable` instances for the frozen C structs — `ArrowSchema`, `ArrowArray`, `ArrowArrayStream`, `DLTensor`, `DLManagedTensorVersioned` — rather than generating them with inline-c, so the package has no cbits and builds anywhere. A test-suite-only C file with `_Static_assert(offsetof(...))` checks against the vendored upstream headers proves the layouts in CI; that C file never ships in the library.
  * Ownership model: producer allocates, consumer calls `release`, which recursively frees and NULLs itself. Haskell maps this exactly: imported structures become `ForeignPtr` with the C release callback installed as the finalizer; exported structures get a release callback built with `foreign import ccall "wrapper"` that frees a `StablePtr` to the Haskell-side keep-alive. `bracket` covers the borrow case. This is the one place where GHC's resource idioms are strictly better than C++'s.
  * `quay-dyn` is ~300 lines: `LoadLibraryW`/`GetProcAddress` under `if os(windows)`, `System.Posix.DynamicLinker` otherwise; a search-path policy (env var override → `quay setup` user data dir → system path); `AddDllDirectory` before load on Windows because OpenBLAS pulls in `libgcc_s`/`libgomp`; and a `Capability` record type: a resolved shared library is a plain Haskell record of `FunPtr`s obtained via `foreign import ccall "dynamic"` wrappers, plus a version tag.

L1 — Arrays (`quay-array`, `quay-linalg`).
  * The tensor is `offset + shape + strides + ForeignPtr` over a `Data.Vector.Storable` buffer. `vector` is chosen as the buffer because it is the only piece of the numeric ecosystem with three maintainers and universal adoption (hmatrix, massiv, orthotope, ox-arrays, statistics and dataframe all depend on it), and `Storable` is directly `Ptr`-compatible for BLAS and for Arrow buffers.
  * dtype is a closed GADT (`DType a`) whose constructors are exactly the Arrow primitive types plus f32/f64/i8..i64/u8..u64/bool. One dtype vocabulary spans tensors, Arrow columns and DLPack — no translation table, no dtype zoo.
  * Broadcasting is a shape rule (dims equal, or one is 1) that produces a zero-stride view, never a copy. `materialize` is the only thing that allocates and it is always explicit in the type (`IO`).
  * `quay-linalg` selects a backend once at startup. `Backend` is a record of resolved function pointers; the default is chosen by `initBackends` and stored in a top-level `IORef`, so user-facing ops are pure (`gemm :: Tensor Double -> Tensor Double -> Tensor Double` via `unsafePerformIO` over the pinned backend) — hmatrix's ergonomics without hmatrix's build system. `withBackend` gives explicit override for tests and benchmarks. LAPACKE (the C interface, `lapacke.h`) is bound, never raw Fortran symbols: it avoids name mangling entirely and it is what OpenBLAS ships headers for.

L2 — Tables (`quay-frame`, `quay-io`). Adapters, not a dataframe.
  * `quay-frame` depends on `dataframe-core` and `dataframe-operations` only (never the umbrella `dataframe`), with `>=2.4 && <2.5`-style bounds, and isolates every upstream call behind one internal `Quay.Frame.Compat` module so a breaking 3.6.0.0 is a one-file patch rather than a rewrite.
  * Three bridges: (a) DataFrame ⇄ ArrowArrayStream, chunked, so pyarrow/Polars/DuckDB hand data over without serialization; (b) `Column ⇄ Tensor`, zero-copy exactly when the column is an `UnboxedColumn` of a numeric type with no validity bitmap, and an explicit copying path (returning a `Copied`/`Borrowed` tag) otherwise — users are told, never surprised; (c) `Generic`-derived record ⇄ DataFrame, so ordinary Haskell types cross the runtime-typed column boundary without boilerplate.
  * `quay-io` holds the flag-gated heavy connectors: DuckDB via its C API through `quay-dyn` (gives Parquet *write*, Arrow, and out-of-core SQL for the price of one optional runtime), and an Arrow IPC/Feather reader written in Haskell against `quay-abi`'s type vocabulary.

L3 — Modelling (`quay-model`, `quay-learn`, `quay-onnx`).
  * `quay-model` is the protocol and ships **before** any algorithm, deliberately, with a dependency footprint of base/aeson/vector/quay-array. It encodes scikit-learn's actual invention: hyperparameters are a plain inspectable record (`Generic`-derived to/from a `[(Text, ParamValue)]`), a fitted model is separate data, and therefore `Pipeline`, `kFoldCV`, `gridSearchCV`, `clone`, and JSON checkpointing are all generic over third-party estimators. Estimators are records-of-functions, not a class, so a wrapped `dataframe-learn` model, a BLAS-backed model and an ONNX session are all the same thing to a pipeline.
  * `quay-learn` = adapters + the dense models where BLAS actually wins (ridge via `gels`/`posv`, PCA via `gesdd`, k-means via `gemm`-based distance blocks, logistic regression via L-BFGS over `gemv`).
  * `quay-onnx` binds ONNX Runtime's C API through `quay-dyn`. `OrtValue` ⇄ `Tensor` is zero-copy in both directions via `CreateTensorWithDataAsOrtValue`. Inference only.

L4 — Output (`quay-plot`). Vega-Lite specs as `aeson` `Value`s (reusing `dataframe-viz`'s spec vocabulary where it already exists), HTML always, and static PNG/SVG/PDF by shelling out to a `vl-convert` binary fetched by `quay setup`. Terminal ANSI fallback for ghci.

L5 — Product (`quay`, `quay-python`). Umbrella prelude with one import (`import Quay`) that fixes the verbose-qualified-name complaint; a CLI whose `setup`/`doctor` commands own all native-dependency friction so no library ever has to; and a `native-shared` foreign library so Python calls Haskell.

DATA MODEL, stated once: one buffer vocabulary (`Data.Vector.Storable` over pinned memory), one dtype vocabulary (Arrow primitive types), two ABI contracts (Arrow C Data for tabular, DLPack for tensors), one ownership discipline (`ForeignPtr` + release callback + `bracket`). Everything else in the stack is a view or an adapter over those four things.

CONTROL FLOW for a typical job: CSV/Parquet/Arrow → `dataframe` DataFrame (upstream's engine does the wrangling and the lazy pushdown) → `quay-frame` projects the model matrix into a contiguous `Tensor Double` → `quay-model` pipeline fits via `quay-linalg` or `dataframe-learn` or `quay-onnx` → metrics → `quay-plot` spec → HTML/PDF, and/or `quay-abi` exports the result as an ArrowArrayStream to Python.

GHC POLICY: floor 9.10.3 (Stackage LTS 24.x), primary/CI-default 9.12.4 (Stackage nightly, full HLS 2.14 support, and the first version where `-fllvm` links floating-point code on Windows — GHC #22487 makes `-fllvm` unusable on Windows for ≤9.10, which is precisely GHCup's *recommended* GHC), forward-tested 9.14.1 (GHC's first LTS). Every cabal file declares `default-language: GHC2021` explicitly, so GHC 10.0's switch of the default to GHC2024 does not silently change semantics.

GOVERNANCE, treated as a deliverable and not an afterthought (the Owl lesson: 3,862 commits by one author, founder gone, no release since Jan 2025): MIT license to match `dataframe` so code moves upstream frictionlessly; every package has a one-page CONTRIBUTING with a bite-sized-issue label (DataHaskell's survey found contributors want self-contained tasks, not maintainer roles); two commit-bit holders minimum before v0.1 is announced; every package must be individually valuable so that partial abandonment is survivable.

# dependency_strategy
BUILD ON (hard dependencies, tight bounds):
- `vector` >=0.13 && <0.15 — the only numeric-ecosystem package with three maintainers (Kuleshevich, Khudyakov, Lelechenko) and universal adoption; `Data.Vector.Storable` is directly Ptr-compatible for BLAS, Arrow buffers and DLPack. This is the interchange currency and we never invent another buffer.
- `primitive`, `text`, `bytestring`, `containers`, `aeson`, `random` — boot-adjacent, safe.
- `dataframe-core` and `dataframe-operations` at `>=2.4 && <2.5`, plus `dataframe-csv`/`dataframe-fastcsv`/`dataframe-parquet`/`dataframe-learn`/`dataframe-viz` at equally tight bounds. Never the umbrella `dataframe` package. Every upstream call goes through one internal `Quay.Frame.Compat` module. Rationale: the incumbent went 1.0.0.0 (2026-03-22) to 3.5.0.0 (2026-08-14) in five months across 68 releases; the exposure has to be one file, not the whole codebase.
- `statistics` / `mwc-random` / `math-functions` — genuinely maintained, pure Haskell, Windows-clean. Do not reimplement distributions or tests.

WRAP AT RUNTIME, NEVER LINK (the load-bearing decision):
- OpenBLAS (CBLAS + LAPACKE C interfaces). On Windows the system-level story is already solved — GHC ≥9.4.1 ships a CLANG64 MSYS2 environment and `mingw-w64-clang-x86_64-openblas` installs `libopenblas.dll` plus headers at `/clang64/include/openblas/{cblas.h,lapacke.h}` (note the `openblas/` subdirectory — a classic misconfiguration) — but we still do not link it, because a build-time dependency means `cabal install` can fail. `quay setup blas` fetches or locates the DLL/.so/.dylib; `quay-dyn` loads it. Binding the C interfaces rather than raw Fortran symbols eliminates name mangling and avoids the symbol-drift class of bug that blas-ffi documents (it had to drop SCABS1/DCABS1 because OpenBLAS and ATLAS lack them).
- ONNX Runtime (MIT, https://github.com/microsoft/onnxruntime/blob/main/LICENSE), official prebuilt archives for win-x64/linux-x64/osx-arm64. Its C API is `OrtGetApiBase()` returning a struct of function pointers, so runtime loading is the *intended* usage, not a hack.
- DuckDB (optional, flag-gated) — buys Parquet write, Arrow-native result sets, and out-of-core SQL for one optional runtime instead of years of work. Never a required dependency: a mandatory libduckdb would forfeit the zero-native-dependency property that is the whole differentiator.
- `vl-convert` binary (optional) for static PNG/SVG/PDF plot export.

AVOID:
- `hmatrix` — its API (especially `Static`) is worth studying, its packaging is not. Last release 0.20.2 on 2021-03-08, last commit 2024-02-21, Windows issues #236 (2017) and #284 (2018) still open, INSTALL.md self-describes as "very out of date", and its cabal flags (`openblas`, `disable-default-paths`, `no-random_r`) are patches over portability holes. Its `os(windows)` stanza sets `extra-libraries` with no path logic — precisely the failure mode runtime loading removes.
- `massiv` — the best n-D API in Haskell and the right thing to imitate, but bus factor 1, no release since 2025-05-31, no commit since 2025-07-08, maintainer's own issue #146 blocking 1.1.0.0 still open, `tested-with` capped at 9.12.1, no BLAS. We copy orthotope's stride model and massiv's API vocabulary; we depend on neither. An optional `quay-massiv` adapter is a post-v1 nicety.
- `Frames` (last release AND commit 2023-10-22, GHC ≤9.4.6) and its `pipes` substrate (frozen since 2021). Mine for design, never depend.
- `hs-onnxruntime-capi` — AGPL-3.0-only (verified on Hackage, 0.1.0.0, 2025-07-24). Virally incompatible with an MIT toolkit. Writing permissive bindings is the correct response and is a genuine ecosystem contribution.
- `hasktorch` and `accelerate` as required dependencies. hasktorch's README lists Linux and macOS only — no Windows — and it is a ~2 GB opaque C++ dependency; accelerate is an EDSL that cannot be the substrate for a numpy-shaped API and its GPU backend "probably doesn't work on Windows". Both are DLPack-bridge targets post-v1, behind flags.
- `inline-r` (all Hackage builds failing, absent from every Stackage snapshot), `lens` (dependency weight on a toolkit whose selling point is installability), `hvega` (two Vega-Lite majors behind, maintainer states he is not using it), `Chart-cairo` (a Windows trap via gtk2hs).
- Any new numeric prelude. This is the specific thing that killed HLearn (SubHask) and the specific thing DataHaskell promised in 2017 and never shipped. Two independent efforts died on this hill; we do not walk up it.

UPSTREAM RATHER THAN VENDOR (contributions offered as PRs, not kept private):
- Arrow C Data Interface *import* into `dataframe` — the inbound half it lacks. This is `quay-abi` + a thin adapter, and it is worth more to the ecosystem inside `dataframe` than inside `quay`.
- Independent benchmarking of `dataframe` against the duckdblabs db-benchmark (upstream issue #115, still open) — its numbers are self-published on a Chromebook, and third-party verification is a real contribution.
- Static export for the plotting stack, and a Vega-Lite 6 regeneration for `hvega` if its maintainer wants it.
- Windows CI for anything in the chain that lacks it (nothing surveyed runs Windows CI). Offering CI capacity and bug reports is how a newcomer earns commit bits in an ecosystem whose #1 stated gap is maintainers.
- Do NOT compete for the Parquet writer: it is GSoC 2026's funded, mentored project (mchav + adithyaov, 175–350h). Use DuckDB as the interim write path and say so publicly.

INSTALLABILITY IS A HARD CONSTRAINT, not a preference. `sparkle` died by leaving Hackage for a Bazel-only GitHub build; `inline-r` is dying of failing Hackage builds. Every quay package must be `cabal install`-able from Hackage on a clean Windows box with no MSYS2 pacman step, forever. Stackage nightly submission happens at v0.1; no LTS is assumed, since LTS has been frozen on GHC 9.10.3 for a year with no snapshot for GHC's own 9.14 LTS.

# package_breakdown
- **quay-abi**: Arrow C Data Interface + Arrow C Stream Interface + DLPack, both directions, with correct release-callback ownership. Hand-written Storable instances for the frozen C structs; a test-suite-only C file with _Static_assert offsetof checks proves layout in CI. No cbits in the shipped library, so no C toolchain requirement. Fills the ecosystem's single largest verified hole: Haskell has NO inbound Arrow implementation (dataframe-arrow is export-to-Python only; harrow and hs-arrow are abandoned at 1 and 6 commits). (builds on: base, vector (Storable), text, bytestring, primitive. foreign import ccall "wrapper" for release callbacks; StablePtr for keep-alives. Zero third-party native deps by design.)
- **quay-dyn**: Cross-platform runtime shared-library loading and symbol resolution (~300 LOC). LoadLibraryW/GetProcAddress + AddDllDirectory on Windows, System.Posix.DynamicLinker elsewhere; documented search-path policy (env override -> quay-setup user data dir -> system); a Capability record = resolved FunPtrs + version tag. This package is why quay has no build-time native dependencies anywhere in the stack. (builds on: base, filepath, directory; Win32 under `if os(windows)`, unix otherwise (the same guard trick dataframe already uses to stay Windows-clean).)
- **quay-array**: Strided n-D tensor: offset + shape + strides (LMAD) over a Data.Vector.Storable buffer, with a closed GADT dtype whose constructors are exactly the Arrow primitive types. Transpose/slice/broadcast/reshape are O(1) metadata-only views; materialize is the only allocating op and lives in IO. Arrow buffer import and DLPack import/export land here. (builds on: vector, quay-abi. Design copied from orthotope's stride/LMAD representation (the cleanest in the ecosystem) without depending on it, since orthotope explicitly disclaims kernels and we need the dtype set to be Arrow's.)
- **quay-linalg**: CBLAS level-3 plus ~15 LAPACKE drivers (gesv, posv, gels, gesdd, gesvd, syevd, geev, getrf/getri, potrf/potri, geqrf/orgqr, trtrs) resolved at runtime from libopenblas via quay-dyn, plus a pure-Haskell reference fallback for gemm/potrf/gesv/gels so no operation can hard-fail on a machine with no BLAS. Backend pinned once by initBackends; user-facing ops are pure, with withBackend for explicit override. (builds on: quay-array, quay-dyn. Binds the C interfaces (cblas.h/lapacke.h), never Fortran symbols, sidestepping the name-mangling and symbol-drift fragility that both hmatrix and blas-ffi document.)
- **quay-frame**: Adapter layer over the incumbent dataframe: DataFrame <-> ArrowArrayStream (chunked, zero-copy), Column <-> Tensor with an explicit Borrowed/Copied tag so users are never silently charged for a copy, and Generic/HKD record <-> DataFrame conversion that closes the 'two independent type systems' seam. Also the ergonomic prelude that answers the verbose-qualified-imports complaint (dataframe issue #152). Explicitly NOT a dataframe. (builds on: dataframe-core >=2.4 && <2.5, dataframe-operations, quay-abi, quay-array. All upstream calls funnel through one internal Quay.Frame.Compat module so a breaking upstream major is a one-file patch (dataframe went 1.0.0.0 -> 3.5.0.0 in five months).)
- **quay-model**: THE PROTOCOL PACKAGE, released before any algorithm. Estimator/Transformer as records-of-functions; hyperparameters as a plain Generic record convertible to/from [(Text, ParamValue)]; Fitted models as separate serializable data. Pipeline, kFoldCV, gridSearchCV, trainTestSplit, clone, JSON checkpointing, and the metrics/report surface are all generic over third-party estimators. Deliberately tiny and dependency-light, versioned YYYY.MM-style alongside semver, so competing implementations cannot fork the ecosystem (the Tables.jl / ChainRulesCore playbook). (builds on: base, aeson, vector, containers, random, quay-array. No dependency on quay-learn, quay-linalg, dataframe, or ONNX — that is the point.)
- **quay-learn**: Protocol adapters wrapping dataframe-learn 2.4.x's existing estimators (GBM, AdaBoost, decision trees, SVM/RFF, DBSCAN, GMM, symbolic regression) into quay-model, plus BLAS-backed implementations of the models where dense linear algebra dominates: ridge/lasso/elastic-net via gels/posv, PCA via gesdd, k-means via gemm distance blocks, logistic regression via L-BFGS over gemv. Preprocessing transformers (impute, scale, one-hot, polynomial) as protocol Transformers. (builds on: quay-model, quay-linalg, quay-frame, dataframe-learn >=2.4 && <2.5, statistics, mwc-random)
- **quay-onnx**: MIT-licensed ONNX Runtime C API bindings, inference only, resolved at runtime through OrtGetApiBase() -> struct of function pointers (the C API is designed for exactly this loading pattern). OrtValue <-> Tensor is zero-copy via CreateTensorWithDataAsOrtValue. Wrapped as a quay-model Predictor so an ONNX model drops into a Haskell pipeline like any other estimator. Fills a verified license-shaped hole: the only existing binding, hs-onnxruntime-capi 0.1.0.0 (2025-07-24), is AGPL-3.0-only. (builds on: quay-dyn, quay-array, quay-model. Runtime binaries fetched by `quay setup onnx` from the official microsoft/onnxruntime GitHub releases (MIT-licensed, prebuilt onnxruntime-win-x64 / linux-x64 / osx-arm64 archives).)
- **quay-plot**: Vega-Lite specs as aeson Values with a typed combinator surface (scatter/line/hist/bar/box/heatmap, facet, layer, regression overlay); HTML output always; static PNG/SVG/PDF by invoking a vl-convert binary fetched by `quay setup vl-convert`; ANSI terminal fallback for ghci where GHCi structurally cannot render images. Static export is the ecosystem's single most-cited plotting gap — hvega cannot produce a static file from Haskell at all. (builds on: aeson, text, quay-frame, dataframe-viz (reusing its spec vocabulary rather than duplicating it), typed-process for the vl-convert call)
- **quay-io**: Flag-gated heavy connectors kept out of the core dependency path: DuckDB via its C API through quay-dyn (buying Parquet WRITE, Arrow-native result sets, and out-of-core SQL for one optional runtime), and a pure-Haskell Arrow IPC/Feather reader written against quay-abi's dtype vocabulary. Parquet READS stay with dataframe-parquet; we do not duplicate it. (builds on: quay-abi, quay-dyn, quay-frame, dataframe-parquet (reads), zstd/zlib/snappy only if the IPC reader needs them)
- **quay**: Umbrella prelude (one `import Quay` gives frames, tensors, models, plots) plus the `quay` executable: `quay setup {blas,onnx,duckdb,vl-convert}` does checksum-pinned downloads into a per-user data directory; `quay doctor` reports exactly which backends resolved, which fell back, and what the user should install; `quay repl` launches ghci with the prelude preloaded; `quay new` scaffolds a project. All native-dependency friction is owned here so no library ever has to own it. (builds on: every quay-* package, plus http-client-tls / tar / zlib / cryptohash-sha256 confined to the executable stanza so the libraries stay light)
- **quay-python**: A Cabal `foreign-library` of `type: native-shared` exposing Haskell pipelines to Python as an ArrowArrayStream, shipped alongside a `pyquay` PyPI wheel. Makes Haskell callable FROM Python, which the Julia postmortem literature identifies as worth more than calling Python. Also the honest migration path: a team can adopt one typed Haskell ETL stage without leaving their Python stack. (builds on: quay-abi, quay, and Cabal's foreign-library stanza (native-shared; mod-def-file on Windows))
- **quay-torch**: POST-v1, optional, non-Windows. DLPack bridge between quay-array Tensors and hasktorch tensors, giving GPU training without quay itself ever depending on libtorch. Deliberately deferred: hasktorch has no Windows support at all, and making it a required dependency would forfeit the project's main differentiator. (builds on: quay-abi (DLPack), hasktorch >=0.2.2)

# mvp_milestones
- M0 — Skeleton and CI (weeks 1-2). Create the cabal multi-package project with an explicit `default-language: GHC2021` in every stanza (GHC 10.0 will otherwise silently flip to GHC2024). cabal.project with per-package stanzas; a `stack.yaml` as a courtesy only. GitHub Actions matrix: {windows-latest, ubuntu-latest, macos-14} x GHC {9.10.3, 9.12.4, 9.14.1}, cabal 3.16/3.18, with 9.12.4 as the required gate and 9.14.1 allowed-to-fail initially (HLS only has 'basic support' there). Add a Python 3.12 job with pyarrow, numpy, scipy and scikit-learn installed — every numerical and interop claim gets cross-checked against them, and that job is the project's real test oracle. MIT LICENSE, CONTRIBUTING.md with a `good-first-issue` policy, and a written statement in the README of what quay is NOT (not a dataframe, not a Parquet codec, not an AD engine). Nothing published yet.
- M1 — quay-abi: the Arrow C Data + Stream Interface and DLPack, both directions (weeks 2-6). Vendor `abi.h` (Arrow) and `dlpack.h` into a test-only cbits directory; hand-write the `Storable` instances in Haskell so the shipped library needs no C compiler; add a test-suite C file of `_Static_assert(offsetof(...) == N)` checks that fails CI if any layout drifts. Implement: import (release callback becomes the ForeignPtr finalizer), borrow (`bracket`), export (release callback via `foreign import ccall "wrapper"` freeing a StablePtr keep-alive), and the streaming variants. Conformance test both directions against pyarrow in the Python CI job: Haskell writes a stream over a pipe, pyarrow reads and validates; pyarrow writes, Haskell reads and validates; assert zero leaks under `+RTS -s` and valgrind on Linux. PUBLISH quay-abi 0.1 TO HACKAGE. This is the first artifact, it is independently valuable to anyone in Haskell, and it fills a hole two prior attempts (harrow, hs-arrow) abandoned.
- M2 — quay-dyn + quay-linalg: BLAS/LAPACK without a build-time dependency (weeks 5-9). quay-dyn first: LoadLibraryW/GetProcAddress under `if os(windows)` with AddDllDirectory called before load (OpenBLAS pulls libgcc_s/libgomp on Windows), System.Posix.DynamicLinker elsewhere, plus the documented search order. Then bind CBLAS L3 (gemm/symm/syrk/trsm) and the LAPACKE drivers gesv, posv, gels, gesdd, gesvd, syevd, geev, getrf/getri, potrf/potri, geqrf/orgqr, trtrs — all through `foreign import ccall "dynamic"` wrappers over resolved FunPtrs. Write the pure-Haskell reference fallback for gemm/potrf/gesv/gels so no call can hard-fail. Detect and handle the LP64-vs-ILP64 split (MSYS2 ships both `openblas` and `openblas64`) by probing a sentinel call at load time. Set OPENBLAS_NUM_THREADS=1 by default and document the interaction with the GHC RTS scheduler. `quay setup blas` downloads a checksum-pinned OpenBLAS for the platform. Every op is cross-checked against SciPy in CI to 1e-10 relative error on random and ill-conditioned inputs.
- M3 — quay-array + quay-frame: tensors, and the bridge to the incumbent (weeks 8-13). quay-array: the strided Tensor with the Arrow-aligned dtype GADT, O(1) transpose/slice/broadcast/reshape, explicit `materialize`, plus DLPack and Arrow-buffer import/export wired to quay-abi. Property tests: every view op composed with materialize equals the numpy result computed in the Python job. quay-frame: DataFrame <-> ArrowArrayStream (chunked), `columnTensor` returning an explicit Borrowed/Copied tag (zero-copy holds only for an UnboxedColumn of numeric type with no validity bitmap — anything else copies and says so), `toMatrix`/`toVector`, and the Generic/HKD record bridge. Immediately open a PR to DataHaskell/dataframe offering the Arrow *import* path upstream; that is the moment the project stops looking like a competitor.
- M4 — quay-model: the protocol package, shipped before any algorithm (weeks 12-16). Estimator/Transformer records-of-functions, `Hyper` with a Generic default for to/fromParams, Pipeline with Step/Terminal, `setParam`/`applyParams` addressing by (stepName, paramName), KFold/Stratified CV, gridSearchCV, trainTestSplit, the regression and classification metric surface with a `renderReport`, and aeson-based saveModel/loadModel. Publish standalone with a base+aeson+vector+quay-array dependency footprint and a versioning note that the protocol is versioned separately from the implementations. Then quay-learn: adapters wrapping dataframe-learn's estimators into the protocol (zero new algorithms), plus BLAS-backed ridge/lasso/elastic-net (gels/posv), PCA (gesdd), k-means (gemm distance blocks) and logistic regression (L-BFGS over gemv), each validated against scikit-learn in CI on fixed seeds — mirroring dataframe-learn's own `Learn.SklearnParity` discipline. Preprocessing transformers: impute, standard-scale, one-hot, polynomial.
- M5 — quay-onnx: run any model trained anywhere, on Windows (weeks 15-19). Bind the ONNX Runtime C API through OrtGetApiBase() -> struct of function pointers, resolved by quay-dyn. Env/Session/SessionOptions/RunOptions/MemoryInfo lifecycle under `bracket`; OrtValue <-> Tensor zero-copy via CreateTensorWithDataAsOrtValue in both directions; shape and dtype introspection; graceful `Maybe` when the runtime is absent. `quay setup onnx` fetches the official checksum-pinned prebuilt archive (onnxruntime-win-x64 / linux-x64 / osx-arm64) from the MIT-licensed microsoft/onnxruntime releases. Wrap a loaded session as a quay-model Predictor so an ONNX model is a pipeline step. Ship an end-to-end example: train in scikit-learn, export with skl2onnx, run in Haskell, assert prediction agreement to 1e-6. This is a capability nothing else in Haskell offers under a permissive license.
- M6 — quay-plot: Vega-Lite plus the static export nobody has (weeks 18-21). Typed combinators emitting Vega-Lite specs as aeson Values, reusing dataframe-viz's spec vocabulary where it already covers the mark; `writeHtml` always works with an embedded vega-embed loader; `writeStatic` shells out via typed-process to a vl-convert binary fetched by `quay setup vl-convert`, returning `Either RenderError ()` rather than throwing; `plotTerm` gives an ANSI fallback because GHCi structurally cannot render images. Golden-file tests on the emitted JSON, and a rendered-PDF smoke test in CI on all three platforms.
- M7 — quay + quay-python + launch (weeks 20-26). The umbrella prelude so one `import Quay` covers frames, tensors, models and plots. The `quay` executable: `setup` (checksum-pinned downloads into a per-user data dir, with an offline/air-gapped override via env var), `doctor` (prints exactly which backends resolved, which fell back, and the one command that fixes each), `repl` (ghci with the prelude preloaded), `new` (project scaffold). quay-python: a Cabal `foreign-library` of `type: native-shared` (with a mod-def-file on Windows) exposing pipelines as an ArrowArrayStream, plus a `pyquay` wheel. Docs: five end-to-end tutorials that each fit on one page (CSV->model->plot; Parquet->groupby->plot; pyarrow round-trip; ONNX inference; calling Haskell from Python). Measure and publish the headline number — clean Windows 11 box to first plot, in minutes. Submit every package to Stackage nightly (do not wait for an LTS; LTS has been frozen on GHC 9.10.3 for a year). Announce on Haskell Discourse and coordinate publicly with DataHaskell before, not after, the announcement. Recruit a second commit-bit holder as a release blocker.
- POST-v1 (not scheduled, listed so scope stays honest): quay-io's DuckDB connector and pure-Haskell Arrow IPC reader; quay-torch's DLPack bridge to hasktorch on non-Windows; a massiv adapter; C kernels with runtime CPU dispatch for the element-wise paths (the ox-arrays approach, which is the only thing in Haskell that actually gets SIMD today); and only then, if the project is still alive and staffed, a GHC-SIMD wrapper library.

# risks
- INCUMBENT CHURN IS THE #1 OPERATIONAL RISK. dataframe went 1.0.0.0 (2026-03-22) to 3.5.0.0 (2026-08-14) across 68 total releases, and 3.3.0.0 rewrote the typed-schema representation outright. Every upstream call must sit behind one Quay.Frame.Compat module with tight bounds on dataframe-core/-operations only. Contingency if churn becomes untenable: quay-frame drops to Arrow-level interop and stops tracking the typed layer. Do NOT fork the dataframe — that is the failure this design exists to avoid.
- THE PROJECT MAY STILL READ AS DUPLICATION AND SPLIT A ~110-PERSON COMMUNITY. DataHaskell's own roadmap names 'No community of maintainers and contributors' as its top gap, and javelin is the cautionary case: a competent Series library by a Haskell Foundation contributor that now pulls ~19 downloads a month. Mitigation is behavioural, not architectural — upstream the Arrow import, the benchmarks and the Windows CI as PRs to dataframe before publishing anything that looks like a competing surface, and state in the README that quay does not contain a dataframe. If mchav wants quay-abi and quay-model inside the DataHaskell org, that is a win, not a loss.
- RUNTIME DYNAMIC LOADING IS THE DESIGN'S BEST IDEA AND ITS SHARPEST EDGE. Failure modes to budget for: (a) LP64 vs ILP64 integer width — MSYS2 ships both openblas and openblas64 and getting it wrong silently corrupts results on n > 2^31, so probe a sentinel call at load; (b) symbol presence drift across reference-BLAS / OpenBLAS / MKL / Accelerate (blas-ffi had to remove SCABS1/DCABS1 for exactly this) — resolve lazily per-symbol and degrade per-operation, never all-or-nothing; (c) Windows DLL search path — OpenBLAS drags libgcc_s and libgomp, so AddDllDirectory must run before LoadLibraryW; (d) OpenBLAS's own thread pool fighting the GHC RTS scheduler — default OPENBLAS_NUM_THREADS=1 and document it; (e) a bad DLL crashes the process with no Haskell exception. Every one of these needs a named test.
- THE PURE-HASKELL FALLBACK IS A REPUTATION LANDMINE. A user who never runs `quay setup blas` gets reference gemm and concludes Haskell is 10-100x slower than numpy. Mitigations: initBackends prints one unmissable line naming the backend and the fix; `quay doctor` exists; benchmarks refuse to run on the fallback without an explicit flag; the README leads with the setup step. If the loud-banner approach proves insufficient in user testing, consider making fallback opt-in and hard-failing instead — a clear error beats a silent 100x.
- ZERO-COPY IS CONDITIONAL AND USERS WILL BE SURPRISED. dataframe's Column is an existential GADT with BoxedColumn / UnboxedColumn / PackedText / MergedColumn variants and an Arrow-style Maybe Bitmap for validity; only an UnboxedColumn of a numeric type with no bitmap can become a Tensor without a copy. The Borrowed/Copied tag in the type makes this visible, but a wide DataFrame of boxed columns will materialize the whole model matrix and the memory spike will look like a bug. Needs documentation, a `quay explain-copy` diagnostic, and honest benchmarks.
- SCOPE IS TOO LARGE FOR THE STAFFING THIS ECOSYSTEM SUPPLIES. Twelve packages in 26 weeks assumes sustained effort, and the field's history is uniformly the opposite: Owl (3,862 commits by one author, founder gone, no release since 2025-01-13), HLearn (dead 2016), Breeze ('mostly retired'), DiffSharp (no push since 2024-04-15). The structural mitigation is that milestones are ordered by standalone value — quay-abi alone is a real contribution, quay-model alone is a real contribution — so abandonment after M2 still leaves the ecosystem better off. The social mitigation is a hard release blocker: no v0.1 announcement until a second person holds a commit bit.
- THE TARGET USER MAY NOT EXIST IN SUFFICIENT NUMBERS. The only verified buyer is 'Haskell developers with an occasional data task' (State of Haskell 2025, n=1,417: 14.53% want ML content). 'Data scientists tired of Python' is contradicted by evidence — mchav found DS outsiders hard to even get through a survey, and the DataHaskell Q1 2026 report drew 4 points on HN. dataframe itself pulls ~302 Hackage downloads in 30 days against pandas' ~755.8M/month on PyPI. quay-python (callable FROM Python) is the hedge, but it is a hedge, not a proof. Validate with two design-partner conversations before M4, not after M7.
- ONNX AND DUCKDB BINARY DISTRIBUTION IS A SUPPLY-CHAIN AND CI PROBLEM. `quay setup` downloads third-party binaries at runtime: it needs pinned SHA-256s, a documented offline/air-gapped override, correct third-party license attribution, and a policy for what happens when an upstream release URL disappears. Corporate environments block outbound downloads; if `quay setup` is the only path to usable performance, quay is unusable behind a proxy. Needs a documented 'point me at an existing libopenblas' env var from day one.
- GHC AND SNAPSHOT VERSION SQUEEZE. Stackage LTS has been pinned to GHC 9.10.3 for a year with no LTS for GHC's own 9.14 LTS; HLS 2.14.0.0 gives 9.14.1 only 'basic support'; and GHC #22487 makes -fllvm unusable for floating-point code on Windows for GHC <= 9.10, which is exactly GHCup's recommended version. Testing three GHCs on three OSes is nine CI lanes for a small team. Contingency: 9.14 lane is allowed-to-fail until HLS and Stackage catch up, and the docs must state the -fllvm/Windows floor explicitly since it is documented nowhere in the onboarding path.
- ARROW/DLPACK LAYOUT AND OWNERSHIP BUGS ARE MEMORY-SAFETY BUGS, NOT LOGIC BUGS. Getting a release callback wrong produces a use-after-free or a leak, not a type error, and the Haskell side is where the StablePtr keep-alives and finalizer ordering can go subtly wrong under GHC's GC. The _Static_assert layout tests, valgrind on the Linux lane, leak assertions under +RTS -s, and pyarrow round-trip fuzzing are not optional extras — they are the reason M1 is budgeted at four weeks for what looks like two structs.
- PLOTTING STILL DEPENDS ON AN EXTERNAL BINARY FOR ANYTHING PUBLICATION-GRADE. writeStatic requires vl-convert; without it users get HTML only, which is the same gap hvega has had for years. A pure-Haskell fallback would mean rendering Vega-Lite in Haskell, which is out of scope. Honest framing: quay makes static export possible with one setup command instead of impossible, and that is the whole claim.
- DEEP LEARNING IS DELIBERATELY ABSENT AND SOMEONE WILL CALL THAT DISQUALIFYING. v1 offers ONNX inference and no training. Training on Windows requires either hasktorch (Linux/macOS only) or an autodiff engine we have explicitly refused to build (horde-ad self-describes as an early prototype not recommended for production). The position is defensible — train where the ecosystem is, run where your types are — but it must be stated up front rather than discovered.

# api_sketch
-- ============================================================
-- quay-abi : the two structs that are the entire interop surface
-- ============================================================
module Quay.ABI.Arrow where

data ArrowSchema        -- opaque; Storable, layout matches the frozen C struct
data ArrowArray
data ArrowArrayStream

-- Import: we take ownership. The C release callback becomes the ForeignPtr finalizer.
importArray  :: Ptr ArrowSchema -> Ptr ArrowArray -> IO RecordBatch
-- Borrow: producer keeps ownership for the duration of the action.
withArray    :: Ptr ArrowSchema -> Ptr ArrowArray -> (RecordBatch -> IO r) -> IO r
-- Export: release callback built with `foreign import ccall "wrapper"`,
-- freeing a StablePtr keep-alive. Consumer calls release; we do not.
exportArray  :: RecordBatch -> IO (ForeignPtr ArrowSchema, ForeignPtr ArrowArray)

-- Streams (multi-batch), the shape every real handoff actually takes.
importStream :: Ptr ArrowArrayStream -> IO (IO (Maybe RecordBatch))
exportStream :: IO (Maybe RecordBatch) -> IO (ForeignPtr ArrowArrayStream)

module Quay.ABI.DLPack where
data DLManagedTensorVersioned
toDLPack   :: Tensor a -> IO (ForeignPtr DLManagedTensorVersioned)
fromDLPack :: Ptr DLManagedTensorVersioned -> IO SomeTensor

-- ============================================================
-- quay-array : strided views, Arrow dtypes, O(1) metadata ops
-- ============================================================
module Quay.Array where

data DType a where              -- exactly the Arrow primitive set
  TF32 :: DType Float ; TF64 :: DType Double
  TI32 :: DType Int32 ; TI64 :: DType Int64
  TU8  :: DType Word8 ; TBool :: DType Bool
  -- ...

data Tensor a = Tensor
  { tDType   :: !(DType a)
  , tShape   :: !(U.Vector Int)     -- rank = length
  , tStrides :: !(U.Vector Int)     -- in elements, may be 0 (broadcast) or negative
  , tOffset  :: !Int
  , tBuffer  :: !(S.Vector a)       -- pinned, Storable, Ptr-compatible
  }

fromStorable :: Storable a => DType a -> [Int] -> S.Vector a -> Either ShapeError (Tensor a)
shape        :: Tensor a -> [Int]
rank         :: Tensor a -> Int

transpose    :: [Int] -> Tensor a -> Either ShapeError (Tensor a)   -- O(1)
sliceDim     :: Int -> Int -> Int -> Tensor a -> Either ShapeError (Tensor a)
broadcastTo  :: [Int] -> Tensor a -> Either ShapeError (Tensor a)   -- zero-stride view
reshape      :: [Int] -> Tensor a -> Either ShapeError (Tensor a)   -- view if contiguous
isContiguous :: Tensor a -> Bool
materialize  :: Storable a => Tensor a -> IO (Tensor a)             -- only allocating op
unsafeWithPtr:: Tensor a -> (Ptr a -> IO r) -> IO r                 -- requires contiguous

-- ============================================================
-- quay-linalg : runtime-loaded OpenBLAS, pure fallback, pure API
-- ============================================================
module Quay.LinAlg where

data Backend = Backend { backendName :: !Text, backendKind :: !BackendKind, ... }
data BackendKind = OpenBLAS | ReferenceHaskell

initBackends :: IO Backend        -- resolve once at startup; pins a global IORef
withBackend  :: Backend -> IO r -> IO r
currentBackend :: IO Backend

gemm  :: Double -> Tensor Double -> Tensor Double -> Tensor Double   -- alpha*A*B
gemv  :: Tensor Double -> Tensor Double -> Tensor Double
solve :: Tensor Double -> Tensor Double -> Either LinAlgError (Tensor Double)  -- gesv
chol  :: Tensor Double -> Either LinAlgError (Tensor Double)                  -- potrf
lstsq :: Tensor Double -> Tensor Double -> Either LinAlgError (Tensor Double)  -- gels
svd   :: Tensor Double -> Either LinAlgError (Tensor Double, Tensor Double, Tensor Double)
eigSym:: Tensor Double -> Either LinAlgError (Tensor Double, Tensor Double)

-- ============================================================
-- quay-frame : adapters over the incumbent dataframe. NOT a dataframe.
-- ============================================================
module Quay.Frame where
import DataFrame (DataFrame)      -- dataframe-core >=2.4 && <2.5

-- Arrow, both directions -- the inbound half Haskell has never had.
fromArrowStream :: Ptr ArrowArrayStream -> IO DataFrame
toArrowStream   :: DataFrame -> IO (ForeignPtr ArrowArrayStream)

-- Column <-> Tensor. The tag is the API: users are told when they pay for a copy.
data Owned a = Borrowed !(Tensor a) | Copied !(Tensor a)
columnTensor :: Text -> DataFrame -> IO (Either FrameError (Owned Double))
toMatrix     :: [Text] -> DataFrame -> IO (Either FrameError (Tensor Double)) -- n x p, row-major
toVector     :: Text   -> DataFrame -> IO (Either FrameError (Tensor Double))

-- Generic bridge: ordinary Haskell records cross the runtime-typed column boundary.
fromRecords :: (Generic r, GToFrame (Rep r)) => [r] -> DataFrame
toRecords   :: (Generic r, GFromFrame (Rep r)) => DataFrame -> Either FrameError [r]

-- ============================================================
-- quay-model : the protocol. Ships before any algorithm.
-- ============================================================
module Quay.Model where

data ParamValue = PDouble !Double | PInt !Int | PText !Text | PBool !Bool
class Hyper p where
  hyperName    :: proxy p -> Text
  toParams     :: p -> [(Text, ParamValue)]
  fromParams   :: [(Text, ParamValue)] -> Either ParamError p
  default toParams   :: (Generic p, GHyper (Rep p)) => p -> [(Text, ParamValue)]
  default fromParams :: (Generic p, GHyper (Rep p)) => [(Text, ParamValue)] -> Either ParamError p

data Estimator p f = Estimator
  { estName    :: !Text
  , estParams  :: !p
  , estFit     :: p -> Tensor Double -> Tensor Double -> IO f    -- X, y -> fitted
  , estPredict :: f -> Tensor Double -> IO (Tensor Double)
  , estEncode  :: f -> Value                                     -- aeson: checkpointing
  , estDecode  :: Value -> Either String f
  }

data Transformer p t = Transformer
  { trName  :: !Text, trParams :: !p
  , trFit   :: p -> Tensor Double -> IO t
  , trApply :: t -> Tensor Double -> IO (Tensor Double) }

data Step where
  Step     :: (Hyper p) => Text -> Transformer p t -> Step
  Terminal :: (Hyper p) => Text -> Estimator p f  -> Step

pipeline :: [Step] -> Pipeline
fit      :: Pipeline -> Tensor Double -> Tensor Double -> IO FittedPipeline
predict  :: FittedPipeline -> Tensor Double -> IO (Tensor Double)
clone    :: Pipeline -> Pipeline
setParam :: Text -> Text -> ParamValue -> Pipeline -> Either ParamError Pipeline  -- "gbm" "depth"

data CV = KFold !Int !Seed | Stratified !Int !Seed
crossValidate :: CV -> Metric -> Pipeline -> Tensor Double -> Tensor Double -> IO CVResult
gridSearchCV  :: CV -> Metric -> [[(Text, Text, ParamValue)]]
              -> Pipeline -> Tensor Double -> Tensor Double -> IO GridResult

trainTestSplit  :: Double -> Seed -> DataFrame -> IO (DataFrame, DataFrame)
regressionReport     :: Tensor Double -> Tensor Double -> Report
classificationReport :: Tensor Double -> Tensor Double -> Report
renderReport :: Report -> Text
saveModel :: FilePath -> FittedPipeline -> IO ()
loadModel :: FilePath -> IO (Either String FittedPipeline)

-- ============================================================
-- quay-plot
-- ============================================================
module Quay.Plot where
data Spec                                   -- ToJSON => a Vega-Lite spec
scatter  :: Text -> Text -> DataFrame -> Spec
line     :: Text -> Text -> DataFrame -> Spec
hist     :: Text -> DataFrame -> Spec
colorBy  :: Text -> Spec -> Spec
facetBy  :: Text -> Spec -> Spec
title    :: Text -> Spec -> Spec
writeHtml   :: FilePath -> Spec -> IO ()                     -- always works
data Static = PNG !Int | SVG | PDF
writeStatic :: Static -> FilePath -> Spec -> IO (Either RenderError ())  -- needs vl-convert
plotTerm    :: Spec -> IO ()                                 -- ANSI fallback for ghci

-- ============================================================
-- WORKED EXAMPLE: CSV -> wrangle -> pipeline -> CV -> evaluate -> plot -> Python
-- ============================================================
{-# LANGUAGE OverloadedStrings, TypeApplications #-}
module Main where

import Quay                              -- umbrella prelude
import qualified Quay.Frame  as F
import qualified DataFrame          as D  -- upstream engine, unchanged
import qualified DataFrame.Functions as E -- upstream expression DSL, unchanged
import qualified Quay.Model  as M
import qualified Quay.Learn  as L
import qualified Quay.Plot   as P

main :: IO ()
main = do
  be <- initBackends
  -- prints e.g. "quay: linalg backend = OpenBLAS 0.3.34 (loaded)"  or
  --             "quay: linalg backend = ReferenceHaskell -- run `quay setup blas` for 10-100x"
  putStrLn ("backend: " <> show (backendKind be))

  -- 1. LOAD -- upstream reader; Parquet and Arrow are one-line swaps
  raw <- D.readCsv "data/housing.csv"

  -- 2. WRANGLE -- upstream expression DSL; no lambdas, so the lazy planner can see it
  let df = D.select ["log_price","rooms_per_hh","income","age","lat","lon"]
         . D.derive "rooms_per_hh" (E.col @Double "rooms" / E.col @Double "households")
         . D.derive "log_price"    (E.log (E.col @Double "price"))
         . D.filterWhere (E.col @Double "price" `E.gt` E.lit 0)
         $ raw

  -- 3. SPLIT + project the model matrix (zero-copy for unboxed Double columns)
  (trainDf, testDf) <- M.trainTestSplit 0.2 (M.seed 42) df
  let feats = ["rooms_per_hh","income","age","lat","lon"]
  Right xTr <- F.toMatrix feats       trainDf
  Right yTr <- F.toVector "log_price" trainDf
  Right xTe <- F.toMatrix feats       testDf
  Right yTe <- F.toVector "log_price" testDf

  -- 4. PIPELINE -- hyperparameters are plain records, so grid search is generic
  let pipe = M.pipeline
        [ M.Step     "impute" (L.simpleImputer  L.imputerDefaults { L.impStrategy = L.Median })
        , M.Step     "scale"  (L.standardScaler L.scalerDefaults)
        , M.Terminal "gbm"    (L.gbm           L.gbmDefaults { L.gbmTrees = 400 })
        ]
      grid = [ [("gbm","learningRate",PDouble lr), ("gbm","maxDepth",PInt d)]
             | lr <- [0.03,0.05,0.10], d <- [3,4,6] ]

  gr  <- M.gridSearchCV (M.KFold 5 (M.seed 7)) M.RMSE grid pipe xTr yTr
  Right tuned <- pure (M.applyParams (M.bestParams gr) pipe)
  fitted <- M.fit tuned xTr yTr

  -- 5. EVALUATE
  yHat <- M.predict fitted xTe
  putStrLn (unpack (M.renderReport (M.regressionReport yTe yHat)))
  --   RMSE 0.2314   MAE 0.1702   R^2 0.8461   n 4128
  M.saveModel "housing.quay.json" fitted

  -- 6. PLOT -- HTML always; PDF if `quay setup vl-convert` has run
  let predDf = F.fromRecords [ Pred a p | (a,p) <- F.zipTensors yTe yHat ]
      spec   = P.title "predicted vs actual"
             $ P.scatter "actual" "predicted" predDf
  P.writeHtml "pred_vs_actual.html" spec
  _ <- P.writeStatic P.PDF "pred_vs_actual.pdf" spec

  -- 7. HAND THE RESULT TO PYTHON, ZERO COPY
  --    on the Python side:  pyquay.stream(handle) -> pyarrow.RecordBatchReader
  stream <- F.toArrowStream (D.derive "residual"
              (E.col @Double "actual" - E.col @Double "predicted") predDf)
  publishStream "housing-residuals" stream

data Pred = Pred { actual :: !Double, predicted :: !Double } deriving (Generic)

-- ============================================================
-- Same pipeline, ONNX model trained in PyTorch, no retraining
-- ============================================================
runOnnx :: FilePath -> Tensor Double -> IO (Tensor Double)
runOnnx path x = do
  rt   <- Quay.ONNX.load                       -- runtime dlopen; Nothing if not installed
  sess <- Quay.ONNX.newSession rt path
  Quay.ONNX.run sess [("input", x)] ["output"] >>= \[y] -> pure y
-- and as a pipeline step:
--   M.Terminal "onnx" (Quay.ONNX.asEstimator sess)

# critique (score 4)
## fatal
- ZERO-COPY IS IMPOSSIBLE AGAINST THE INCUMBENT — THE ARCHITECTURE'S CENTRAL PREMISE IS FALSE. The design states one buffer vocabulary ('Data.Vector.Storable over pinned memory') and promises 'Column <-> Tensor, zero-copy exactly when the column is an UnboxedColumn of a numeric type with no validity bitmap'. Verified: dataframe-core 2.4.0.0's Column GADT has BoxedColumn (Data.Vector), UnboxedColumn (Data.Vector.Unboxed), PackedText and MergedColumn, and there is NO Storable-backed representation (https://hackage-content.haskell.org/package/dataframe-core-2.4.0.0/docs/DataFrame-Internal-Column.html). Data.Vector.Unboxed is ByteArray#-backed: unpinned, GC-movable, no Storable instance, no stable Ptr. So the ONE case the design names as zero-copy is exactly the case where zero-copy is impossible. Consequences the design does not budget for: (a) `Borrowed` is an unreachable constructor — every columnTensor/toMatrix is a copy, and toMatrix is not even a memcpy but a p-column gather into row-major n x p; (b) `toArrowStream` cannot be zero-copy either, because the Arrow C Data Interface requires buffers that stay valid after the call returns under a release callback, which unpinned ByteArray# cannot provide — so the 'hand the result to Python, zero copy' headline in the worked example is wrong; (c) the workaround (unsafe FFI on ByteArray# under UnliftedFFITypes) is unusable here because an `unsafe` call blocks the capability for the whole GEMM/Arrow lifetime. Quay would have three buffer vocabularies (Storable, Unboxed/Boxed, C-owned Arrow) and a copy at every seam. This is fixable only by contributing a Storable column representation into dataframe-core upstream — which is a different project than the one proposed, and is nowhere in the 26 weeks.
- THE FLAGSHIP 'PROTOCOL NOBODY OWNS' IS ALREADY SHIPPED BY THE INCUMBENT, IN AN INCOMPATIBLE PARADIGM. quay-model is described as 'the piece nobody in Haskell has'. Verified false: dataframe-learn 2.4.1.0 (MIT, 2026-08-14, https://hackage.haskell.org/package/dataframe-learn) exposes DataFrame.ModelSelection with `crossValidate` (explicitly the cross_val_score analogue) and `gridSearch`, fitted preprocessing steps as Transforms that compose as a monoid via `<>`, `applyTransform`, `compileThrough` to fold a pipeline into one expression, inspectable sklearn-style model records (coefficients, centroids, components, support), and rmse/mse/r2/accuracy/precision/recall/f1/classificationReport. The paradigms are opposed, not complementary: upstream `fit` returns an inspectable record and `predict` returns an `Expr` over named columns; Quay's Estimator is `p -> Tensor Double -> Tensor Double -> IO f` over anonymous matrices. So (i) the claimed hole does not exist, and (ii) the 'protocol adapters wrapping dataframe-learn's existing estimators' are not adapters — each one must fabricate a DataFrame with synthetic column names from a Tensor, fit, then evaluate the returned Expr back into a Tensor, per fold, per grid point. By the design's own cited evidence (Tables.jl/ChainRulesCore won because they preceded and were adopted by the implementations; __dataframe__ lost; javelin was a competent second implementation that now pulls ~19 downloads/month), a protocol imposed on an incumbent that already has one is fragmentation, not unification.
- SCOPE vs STAFFING IS THE EXACT ARITHMETIC THAT KILLED EVERY PRIOR EFFORT. Twelve packages, six layers, three novel ABI bindings (Arrow C Data + Stream, DLPack, ONNX Runtime C API), a runtime dynamic loader with per-platform search policy, a BLAS/LAPACKE binding plus a pure-Haskell reference LAPACK, a tensor library, a frame bridge, an ML protocol plus estimators, a plotting layer, a CLI package manager, and a Windows foreign-library Python bridge — in 26 weeks across 9 CI lanes with 1-3 developers. Owl had one author at 3,862 commits and stalled; HLearn died; Breeze is 'mostly retired'; DiffSharp has not been pushed since 2024-04-15; mchav alone needed ~2.5 years and 1,267 commits to reach dataframe 3.5. The design's mitigation ('layers 1..N-1 are still net-positive') is honest but is an argument for shipping only layers 0-1 and quay-onnx, not for planning M0-M7. Every downstream milestone (M3-M7) is contingent on the copy-free premise refuted above, so the realistic outcome is quay-abi + quay-dyn + quay-onnx shipped and the rest abandoned mid-flight — the Owl breadth failure at 1/5 scale.
- THE HEADLINE PRODUCT PROMISE IS ARITHMETICALLY UNREACHABLE. 'On a bare Windows 11 box, ghcup one-liner -> cabal install quay -> quay setup -> a working CSV->model->plot script in under 15 minutes' is stated as THE number the project is judged on. Haskell has no binary package distribution (the digest's own finding), so `cabal install quay` compiles, from source, on a cold store: 12 quay packages, the dataframe monorepo (core, operations, csv or fastcsv with AVX2 cbits, parquet, learn, viz), aeson, statistics, plus zstd — whose `standalone` flag defaults to True and therefore compiles ~24 bundled C files (verified: https://hackage-content.haskell.org/package/zstd-0.1.3.0/src/zstd.cabal) — plus http-client-tls/tar/zlib/cryptohash-sha256 for the CLI. The ghcup bootstrap alone (GHC + cabal + HLS + MSYS2) is a multi-hundred-MB download. Then `quay setup blas/onnx/vl-convert` fetches three more third-party archives (OpenBLAS x64 zip alone is 40.4 MB, https://api.github.com/repos/OpenMathLib/OpenBLAS/releases/latest). A 15-minute cold-start on Windows is off by a large factor, and the project has staked its identity on that number.
## rationale
This is the best-informed design I have seen for this problem and it still should not be built as specified. Three of its twelve packages (quay-abi, quay-dyn, quay-onnx) are genuinely unclaimed, correctly scoped, and independently valuable; the other nine rest on a premise that is factually wrong and a hole that is already filled.\n\nThe refutation is concrete, not stylistic. (1) The architecture's stated data model — 'one buffer vocabulary, Data.Vector.Storable over pinned memory' — cannot survive contact with the incumbent it depends on: dataframe-core 2.4.0.0's Column GADT offers only boxed, Unboxed, PackedText and Merged variants with no Storable representation, and Data.Vector.Unboxed is unpinned ByteArray#-backed with no stable Ptr. The exact case the design names as zero-copy is the case where zero-copy is provably impossible, which makes `Borrowed` unreachable, makes `toArrowStream` a copy (Arrow's release-callback contract requires buffers valid after return), and deletes the performance rationale for projecting frames into BLAS tensors at all. (2) quay-model is announced as 'the piece nobody in Haskell has' while dataframe-learn 2.4.1.0 already ships crossValidate, gridSearch, monoidal Transform pipelines, compileThrough, inspectable model records and the full metric surface — in an Expr-over-named-columns paradigm that the Tensor-of-Double protocol cannot adapt cheaply. The design cites Tables.jl and __dataframe__ as its evidence base and then does the __dataframe__ thing. (3) Twelve packages and nine CI lanes in 26 weeks with 1-3 developers is the same arithmetic that produced Owl, HLearn, Breeze and DiffSharp.\n\nSecondary but serious: `gemm` made pure by unsafePerformIO over a swappable global backend is unsound under laziness and non-deterministic across backends, forfeiting the exact property the audience buys Haskell for; the pure-Haskell fallback covers four drivers and leaves PCA and eigendecomposition to hard-fail under a 'nothing ever hard-fails' banner; the estimator/grid API is stringly typed; the pipeline has no heterogeneous-column path, so it cannot cross-validate a categorical feature without leakage; the worked example uses partial `Right x <-` matches four times; and the 15-minute Windows promise, which the design nominates as its scoreboard, is unreachable in a source-only ecosystem that will compile the dataframe monorepo plus zstd's bundled C sources on a cold store.\n\nOn the history question: it dodges the two famous Haskell-DS killers (no new numeric prelude, no unshipped-language-feature bet) and lands on a third and a fourth. It is DataHaskell's curation failure re-expressed as code — a derivative glue layer whose value is a function of libraries it does not control, pinned to an incumbent that shipped three major versions in five months — and it is javelin at the model-protocol layer: a competent second implementation in a community of roughly 110 people, which historically produces fragmentation and then a corpse rather than competition.\n\nThe honest verdict is that the correct project is inside this document and is about one fifth its size: ship quay-abi and quay-dyn, ship MIT ONNX Runtime inference bindings, donate Windows CI and independent benchmarks, and take the copy problem upstream as a Storable column representation for dataframe-core. That sequence is achievable by two part-timers, leaves the ecosystem strictly better off at every checkpoint, and — unlike Quay as proposed — does not require a data scientist to ever type `setParam \"gbm\" \"learningRate\"`.\n\nSources: https://hackage-content.haskell.org/package/dataframe-core-2.4.0.0/docs/DataFrame-Internal-Column.html ; https://hackage.haskell.org/package/dataframe-learn ; https://hackage-content.haskell.org/package/zstd-0.1.3.0/src/zstd.cabal ; https://cabal.readthedocs.io/en/stable/cabal-package-description-file.html ; https://github.com/haskell/cabal/issues/9982 ; https://api.github.com/repos/OpenMathLib/OpenBLAS/releases/latest ; https://github.com/xianyi/OpenBLAS/issues/1112 ; https://hackage.haskell.org/package/dataframe-parquet ; https://discourse.haskell.org/t/snappy-hs-snappy-compression-in-haskell/12757
