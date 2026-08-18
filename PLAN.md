# keel — Plan of Record

**A native-capability and interop floor for Haskell data science.**

**Product name: `keel`** (decided 2026-08-17) — packages `keel-dyn` / `keel-abi` /
`keel-onnx` / `keel-linalg` + umbrella `keel`; repo codename HSDS retired when the repo folder was renamed to keel on 2026-08-18.

Research completed and all load-bearing facts verified against primary sources on
2026-08-17 (13-agent research/design/adversarial-critique workflow; three key facts
re-verified first-party: see §9 Provenance). Every dated claim below carries its
source. Facts about a fast-moving ecosystem decay — re-verify before acting on any
claim older than a few weeks.

---

## 0. Executive summary

The original brief — "build a Haskell DS/ML toolkit so Haskell gains strong DS/ML
capability" — presumes a vacuum that no longer exists. As of 2026-08-14 (three days
before this research), one maintainer (Michael Chavinda, *mchav*) ships a ~24-package
monorepo under the DataHaskell org covering the pandas tier (`dataframe` 3.5.0.0,
`dataframe-core` 2.4.0.0), the scikit-learn tier (`dataframe-learn` 2.4.1.0: linear
models, SVM, trees, GBM, AdaBoost, PCA, k-means, GMM, DBSCAN, cross-validation, grid
search, sklearn-parity tests), plotting (`dataframe-viz` 1.3.1.0, Vega-Lite v5 +
terminal), a lazy query engine with spill-to-disk (`dataframe-lazy`), and a pure-
Haskell Parquet reader — with releases shipping weekly
(https://hackage.haskell.org/package/dataframe, https://hackage.haskell.org/package/dataframe-learn).

**Therefore keel is explicitly NOT a new dataframe, not a new sklearn, and not a new
plotting library.** Competing with a live incumbent in a ~110-person community is the
ecosystem's documented death pattern (javelin: competent Series library, now ~19
downloads/month). Instead, keel occupies the two layers that are verified-empty:

1. **The layer below** — native capability Haskell does not have at all:
   - **Runtime dynamic loading** of native libraries (no build-time C dependency, ever)
   - **ONNX Runtime inference bindings under MIT** (the only existing binding,
     `hs-onnxruntime-capi` 0.1.0.0, is AGPL-3.0-only and frozen since 2025-07-24 —
     verified first-party 2026-08-17)
   - **BLAS/LAPACK that actually installs on Windows** (hmatrix: frozen since
     2021-03-08, Windows issues open since 2017)
2. **The layer beside** — interop and quality the incumbent lacks:
   - **Inbound Arrow C Data Interface** (Haskell has *no* Arrow import path; both prior
     attempts died at 1 and 6 commits) + **DLPack** tensor exchange
   - **Windows CI evidence and portability findings** — produced on our own fork;
     upstream fixes are separate DataFrame-repo work outside this project

The headline capability: **"train anywhere (PyTorch/sklearn), run in Haskell, on
Windows, with GPU, under MIT"** — verified impossible to obtain today, and cheap to
ship (ONNX Runtime v1.29.0, MIT, published 2026-08-12 with official
`onnxruntime-win-x64` + CUDA archives; verified first-party via GitHub API).

Four capability packages + one umbrella, ~32 weeks of part-time work for 1–2
people, with a falsification gate (P0) before any library code is written.
(Upstream-PR track removed from scope 2026-08-18 — §7.1 Q11.)

---

## 1. Verified ecosystem map (2026-08-17)

### 1.1 The incumbent: DataHaskell `dataframe` monorepo

| Fact | Value | Source |
|---|---|---|
| Latest release | dataframe 3.5.0.0, 2026-08-14 | hackage.haskell.org/package/dataframe |
| Activity | 1,267 commits, ~2.5 years, releases weekly | api.github.com/repos/DataHaskell/dataframe |
| Bus factor | 1 (mchav: 1,149 contributions; #2 has 12) | GitHub contributors API |
| API churn | 1.0.0.0 (2026-03-22) → 3.5.0.0 (2026-08-14); 68 releases; typed-schema representation rewritten at 3.3.0.0 | Hackage version history |
| Real adoption | 4 Hackage reverse deps, 3 self-owned; ~302 downloads/30d | packdeps, Hackage |
| Typed layer | `DataFrame.Typed.{Schema,Expr,…}` already ships type-level `[(Symbol,Type)]` schemas, `TExpr`, assertion families, joins schema algebra | hackage-content.haskell.org/package/dataframe-core-2.4.0.0/docs/DataFrame-Typed-Schema.html |
| ML layer | `dataframe-learn` 2.4.1.0: `class Fit cfg input` (3-arg fit, FrameKind indexing), `gridSearch :: … -> [c] -> …` (config-polymorphic), sklearn-parity test suite | …/dataframe-learn-2.4.1.0/docs/DataFrame-Model.html |
| CI | **ubuntu only** — `ci.yml`: runs-on ubuntu-latest, GHC 9.6.7/9.8.4/9.10.3/9.12.2; no windows/macos anywhere (**verified first-party 2026-08-17**) | raw.githubusercontent.com/DataHaskell/dataframe/main/.github/workflows/ci.yml |
| Parquet | Pure-Haskell reader; **no writer** (issue #181 = funded GSoC 2026 project, mentors mchav + adithyaov) | dataframe repo, summer.haskell.org/ideas.html |
| Arrow | Export-to-Python only (`dataframe-arrow`, Hackage builds failing); **no inbound path** | hackage.haskell.org/package/dataframe-arrow |

### 1.2 What is alive, frozen, and dead

**Alive and safe to depend on:** `vector` 0.13.2.0 (3 maintainers, universal),
`statistics` 0.16.5.0 / `mwc-random` / `math-functions` (Khudyakov), `random` 1.3.1
(CLC), `cassava` 0.5.4.1 (co-maintained by mchav — CSV substrate aligned with
dataframe), `streamly` 0.11.1, `hasql` 2.0.1.0, `diagrams-lib` 1.6, `chart-svg`
0.8.3.2.

**Alive but constrained:** `hasktorch` 0.2.2.0 (active, libtorch 2.5.0, in Stackage
nightly — but **no Windows support**, ~2 GB native dep, 38 downloads/30d);
`accelerate` 1.4.0.0 (revived 2026-04 after 6 years — but an EDSL, GPU backend
"probably doesn't work on Windows", absent from every Stackage snapshot); `massiv`
1.0.5.0 (best n-D API, but bus factor 1, decelerating, maintainer's own blocking issue
#146 open); `horde-ad` 0.3.0.0 (most GHC-current numeric stack, self-described "early
prototype, not recommended for production"); `monad-bayes` (stable-but-coasting);
`IHaskell` (Windows support merged 2026-04-09 in PR #1595 but **no Hackage release
carries it** — ihaskell-0.13.0.0 is bounded `ghc <9.13`).

**Frozen / dead — never depend, only mine for design:** `hmatrix` 0.20.2 (2021-03-08;
Windows issues #236/#284 open since 2017/2018; INSTALL.md self-declares out of date),
`Frames` (2023-10-22, GHC ≤9.4.6), `pipes` (2021), `repa` (compat-only), `grenade`
(2017), HLearn (2016, author's postmortem: died rewriting the numeric prelude then
blocking on dependent types), `analyze` (2017), `harrow`/`hs-arrow` (1 and 6 commits),
`hs-onnxruntime-capi` (AGPL-3.0-only, 0.1.0.0, 2025-07-24 — **verified first-party**),
`inline-r` (all Hackage builds failing), `sparkle` (deprecated, left Hackage for Bazel).

### 1.3 Platform constraints (GHC / Windows / distribution)

- **GHC:** 9.14.1 (2025-12-19) is GHC's first LTS; 9.12.4 is current in Stackage
  nightly; **Stackage LTS is frozen on 9.10.3** with no LTS for 9.12/9.14. HLS 2.14
  gives 9.14 only "basic support". GHC #22487 makes `-fllvm` unusable for FP code on
  Windows for GHC ≤9.10 — exactly GHCup's *recommended* version.
- **SIMD:** GHC 9.12/9.14 added real 128-bit SIMD to the x86 NCG, but **zero libraries
  expose it** (vector #251 closed unimplemented). Not load-bearing for this plan.
- **No binary package distribution exists** (no wheel/conda analogue). Every build-time
  native dependency is a manual MSYS2 pacman step in the correct environment (CLANG64
  for GHC ≥9.4.1; MINGW64 deprecated 2026-03-15). This single fact drives the
  architecture's central rule (§4, Rule 1).
- **Tooling votes (State of Haskell 2025, n=1,417):** cabal 83.96% vs Stack 39.59%;
  Hackage 83.56% vs Stackage 33.45%; ghcup 63.45%; HLS 83.35%.
- **LinearTypes** still documented as experimental/"really unreliable"; **Dependent
  Haskell** roadmap declines to estimate Π/Σ types. Neither may be load-bearing.

### 1.4 Cross-language lessons that shaped this plan

- **Polars won on** Arrow memory + a lazy IR + a reified first-class `Expr` API —
  "user must pass a lambda" is an API failure because UDFs are opaque to the
  optimizer. pandas 3.0 capitulated (`pd.col()`, Arrow strings, CoW-only).
- **Spark's typed `Dataset[T]` lost** to untyped DataFrame because Catalyst cannot see
  through lambdas: types must describe the plan, never hide closures inside it.
- **scikit-learn's durable invention** is hyperparameters-as-inspectable-data
  (`get_params`/`set_params`) — that is what makes Pipeline/GridSearchCV/clone generic
  (Buitinck et al., arXiv:1309.0238).
- **The middle-layer protocol dies:** the formally-designed `__dataframe__` interchange
  protocol was deprecated by Polars 1.40 and dropped by scikit-learn 1.9.0, which took
  the pragmatic *narwhals* shim as a dependency instead. Standardize memory at the
  bottom (Arrow C Data Interface, DLPack) and vocabulary at the top; never ship a
  middle-layer object protocol over N=1 implementations.
- **Owl (OCaml) is the definitive warning:** one author, 3,862 commits, technically
  superb full numerical stack; founder left March 2024; no release since 2025-01.
  Breadth built by one person becomes unmaintainable breadth. Breeze (Scala) "mostly
  retired"; DiffSharp stale since 2024-04 despite correctly reusing libtorch.
- **Julia:** Tables.jl (tiny protocol, shipped before implementations) unified the
  ecosystem; Flux vs Lux (two frontends over one backend) fragmented it; TTFX
  reputational damage outlived its technical fix → time-to-first-result is a P0
  budget, not a backlog item.
- **Haskell's own graveyard has exactly four failure modes**, all avoided here:
  (a) rewrite the numeric foundation first (HLearn/SubHask, DataHaskell 2017);
  (b) bet on unshipped GHC features (HLearn on dependent types);
  (c) become uninstallable (sparkle → Bazel; inline-r → failing builds);
  (d) fork/duplicate inside a tiny community (javelin).

---

## 2. Positioning

**One sentence (must open the README): "keel is not a new dataframe."**

keel adds capability Haskell does not have — on Windows, under permissive licenses,
with zero build-time native dependencies — and never competes with it; upstream
engagement is limited to bug reports (fixes = separate DataFrame-repo work,
owner decision 2026-08-18). The tabular/expression vocabulary is the incumbent's
(`DataFrame`, `Column`, `Expr`, `TExpr`) — used, not wrapped, not re-declared.

**Verified target user:** the Haskell developer with an occasional data task (14.53%
of State of Haskell 2025 respondents want ML content) plus the Haskell service that
must run a model trained elsewhere (ONNX). "Data scientists tired of Python" is a
mirage — treat any plan aimed at them as unfunded speculation.

**Honest success metric:** the four capability packages acquire external dependents.
NOT "Haskell has a numpy/pandas/sklearn stack" — that
substantially exists and belongs to someone else. Calibration: the incumbent, after
2.5 years and 1,267 commits, has exactly one external Hackage reverse dependency.

---

## 3. Design space explored (and rejected)

Three complete designs were produced independently and adversarially critiqued; every
load-bearing critique claim was re-verified against primary sources before the ruling.

### 3.1 "Rowan" — type-safety-differentiated (REJECTED — foundation failure)
Typed façade (`Frame (s :: Schema)`) over the incumbent's runtime. **Fatal:** its two
foundational packages duplicate shipped code inside its own dependencies —
`DataFrame.Typed.Schema` / `DataFrame.Typed.Expr` (dataframe-core/-operations 2.4.0.0)
already provide the type-level schema algebra, `TExpr`, `col @"name"`, `#age` labels,
and a *richer* operator set (nullable-aware `.+.` vs `.+`) than Rowan's sketch — and
Rowan's schema kind (`[Field]` + Nullability) does not even unify with the incumbent's
(`[(Symbol,Type)]` + Maybe), making it a competing typed API inside its upstream's
dependency cone (javelin's failure mode aimed at its own upstream). Additional
refuted claims: the reified-opcode "optimizer visibility" argument is vacuous (the
erasure target's AST already carries closures in `UnUDF`/`BinUDF` nodes); units-of-
measure columns are not free (dimensional has no Unbox instances → boxed columns,
excluded from the unboxed kernels and `AllColumnsReal`); the `HasCol` fundep sketch
does not compile.

### 3.2 "Conflux" — ecosystem federation, tidyverse-style (REJECTED — foundation failure)
Five contract packages + adapters + umbrella + docs portal. **Fatal:** its self-named
"single most important adapter" is written against an API that does not exist —
upstream's real `class Fit cfg input` takes three arguments with typed/untyped frame
indexing and `FitResult` schema tagging, which Conflux's two-argument `fit` erases;
its "novel" tuning layer replaces upstream's already-config-polymorphic type-safe
`gridSearch [c]` with a stringly-typed `Map Text ParamValue` — a typed toolkit
shipping a *less*-typed API than the deliberately-untyped incumbent. Every contract
abstracts over N=1 live implementation, inverting the Tables.jl/ChainRulesCore/
narwhals precedent it cites. Its shipped artifacts (curated umbrella, portal,
maintenance badges) are DataHaskell v1's failed inventory with typeclasses attached.

### 3.3 "Quay" — pragmatic interop-first (ADOPTED at ~1/5 scope)
Bind-don't-reimplement; native deps loaded at runtime, never linked; ship the
contracts nobody owns; simple Haskell. **Its own fatal flaws forced the scope cut:**
(a) the zero-copy premise vs the incumbent is false — `Column`'s GADT has **no
Storable constructor** (BoxedColumn/UnboxedColumn/PackedText/MergedColumn;
`Data.Vector.Unboxed` is unpinned ByteArray#, no stable Ptr), so every frame↔buffer
seam is a copy and must be documented as one; (b) its "protocol nobody owns"
(quay-model) is already owned by dataframe-learn; (c) 12 packages/26 weeks is
Owl/HLearn arithmetic; (d) the "15-minute Windows install" promise is unreachable in
a source-only ecosystem. What survives — the L0/L1 capability core and the dependency
philosophy — is the only material across all three designs that delivers capability
Haskell lacks entirely. Two mandatory soundness corrections are baked into §4.

---

## 4. Architecture

### Rules (non-negotiable)

1. **Zero build-time native dependencies, forever.** Every native library (OpenBLAS,
   ONNX Runtime) is loaded at **runtime** via dynamic loading. `cabal install` can
   never fail on a missing C library. This is the structural answer to Haskell having
   no wheel/conda layer, and it is what makes Windows-first real.
2. **Bind, don't reimplement numerics.** Kernels come from OpenBLAS and ONNX Runtime.
   Haskell owns shape logic, ownership, ergonomics.
3. **Never compete with the incumbent.** Gaps in dataframe/* are closed by finished,
   tested PRs that close issues the maintainer already filed — never by rival packages.
4. **Simple Haskell.** `default-language: GHC2021` declared explicitly in every stanza
   (GHC 10.0 silently defaults to GHC2024). No LinearTypes, no OverloadedRecordUpdate,
   no required Template Haskell, no typechecker plugins, no dependent-types bets.
5. **Every package must be independently valuable**, so partial abandonment still
   leaves the ecosystem net-positive.

### Data model (stated once)

keel's own vocabulary is exactly two things:
(a) a `Data.Vector.Storable` buffer + shape/strides metadata (for BLAS, ONNX, DLPack);
(b) two frozen C ABI structs (Arrow C Data/Stream Interface; DLPack).
The seam between (a) and the incumbent's `Column` is an **explicit, documented copy**
(same trade numpy↔pandas makes). No API may pretend a zero-copy path exists where the
Column representation cannot provide one.

### Tier A — capability floor (four packages, net-new, no incumbent)

**A1. `keel-dyn` — the keystone (~300 LOC).** Cross-platform runtime shared-library
loading: `LoadLibraryW`/`GetProcAddress` with `AddDllDirectory` called *before* load
on Windows (OpenBLAS drags libgcc_s/libgomp; ONNX Runtime drags its providers);
`System.Posix.DynamicLinker` elsewhere. Documented search-path policy: env-var
override → per-user data dir → system path. A `Capability` record = resolved `FunPtr`s
via `foreign import ccall "dynamic"`, version tag, **per-symbol lazy resolution** so a
missing symbol degrades one operation, not the library. Independently useful to
hmatrix, duckdb-ffi, IHaskell.

**A2. `keel-abi` — Arrow C Data + Stream Interface (both directions) and DLPack
`DLManagedTensorVersioned` import/export.** Inbound Arrow is the verified ecosystem
gap. Hand-written `Storable` instances for the frozen structs → shipped library has
**no cbits, no C toolchain requirement**; a *test-suite-only* C file of
`_Static_assert(offsetof(...))` checks fails CI on layout drift. Ownership discipline:
import → `ForeignPtr` with the C release callback as finalizer; export → release
callback via `foreign import ccall "wrapper"` freeing a `StablePtr` keep-alive;
borrow → `bracket`. Conformance: pyarrow round-trips both directions in CI on all
three OSes; leak assertions under `+RTS -s`; valgrind on the Linux lane. The inbound
half is offered to dataframe-core as a PR the moment it works.

**A3. `keel-onnx` — the headline.** MIT ONNX Runtime *inference* bindings resolved at
runtime through `OrtGetApiBase()` → struct of function pointers (the C API is designed
for this). Env/Session/SessionOptions/RunOptions/MemoryInfo under `bracket`;
`OrtValue` ↔ Storable buffer zero-copy both ways via `CreateTensorWithDataAsOrtValue`;
shape/dtype introspection; graceful `Maybe` when the runtime is absent. Inference
only — no training, no export. Fills the verified license-shaped hole (sole existing
binding is AGPL-3.0-only and frozen; ONNX Runtime itself is MIT with official
win-x64/CUDA/linux/osx-arm64 archives — all verified first-party 2026-08-17).

**A4. `keel-linalg`.** CBLAS level-3 + LAPACKE drivers (gesv, posv, gels, gesdd,
gesvd, syevd, geev, getrf/getri, potrf/potri, geqrf/orgqr, trtrs) resolved at runtime
from OpenBLAS via keel-dyn, over Storable buffers. Bind `cblas.h`/`lapacke.h` (which
OpenBLAS ships), **never raw Fortran symbols, never hmatrix's build system**.
Mandatory soundness corrections (from the critique, adopted):
  - **Backend pinned immutably at init; no `withBackend` swapping under a pure API.**
    Pure ops over a mutable global via `unsafePerformIO` are unsound under laziness
    and non-deterministic across backends (OpenBLAS vs reference differ in rounding).
    Any op that cannot live on an immutable pin lives in `IO`.
  - **No blanket "nothing hard-fails" claim.** Either a driver has a pure-Haskell
    fallback or it is documented per-driver as requiring a backend.
Named hazard tests: LP64 vs ILP64 (probe `openblas_get_config` at load — MSYS2 ships
both `openblas` and `openblas64`; getting it wrong silently corrupts results above
2^31), symbol-presence drift across BLAS implementations (lazy per-symbol resolution),
Windows DLL transitive deps (ship libgcc_s_seh-1/libgfortran/etc. if the OpenBLAS zip
doesn't), `OPENBLAS_NUM_THREADS=1` default vs the GHC RTS scheduler. Every operation
cross-checked against SciPy in CI to 1e-10 relative error on random and
ill-conditioned inputs.

### Tier B — REMOVED from scope (owner decision, 2026-08-18)

The upstream-PR track (Windows CI donation, type-error quality, leakage
typing, hyperparameter reflection, schema diffs, Arrow donation, IHaskell
release, benchmark verification) is no longer part of this project.
dataframe is consumed strictly as a Hackage dependency. The three Windows
bugs our fork CI discovered (hardcoded /tmp; CRLF roundtrip x2;
quote-spans-boundary — docs/p0/BUILD-REPORT.md) will be fixed via a
SEPARATE DataFrame-repo effort with its own plan, unrelated to keel.
Unchanged principle: keel never ships a rival implementation of anything
the dataframe stack provides.

### Tier C — the thin seam (one package)

**`keel`** — umbrella + `Keel.Doctor` + the `keel` executable:
- `keel setup {blas,onnx}`: SHA-256-pinned downloads into a per-user data dir, with a
  documented offline/air-gapped env-var override AND a "point me at an existing
  libopenblas/onnxruntime" path (corporate proxies), plus third-party license
  attribution.
- `keel doctor`: prints exactly which capabilities resolved, which did not, and the
  one command that fixes each.
- Frame↔buffer marshalling that honestly reports the copy.
- **Explicitly NOT in scope:** a DataFrame, a typed schema layer, an Expr/TExpr, an
  estimator protocol, a plotting grammar, a CSV/Parquet reader, a query optimizer, an
  AD engine, a numeric prelude.

---

## 5. Phased plan

Rough calendar assumes 1–2 part-time people; phases overlap as noted. Every phase ends
in an independently valuable, shippable state.

**Execution order revised 2026-08-18 (owner):** all local development first —
keel-dyn → keel-abi → keel-onnx → keel-linalg → umbrella, verified on this
Windows machine — then one publish stage at the end (GitHub repo, 3-OS CI,
Hackage, Stackage). Per-phase Hackage milestones below are the original
calendar; deliverables unchanged.

### P0 (weeks 1–3) — FALSIFY THE WINDOWS THESIS BEFORE ANY LIBRARY CODE
1. Donate a Windows + macOS CI workflow to DataHaskell/dataframe as a PR.
2. Build the entire dataframe stack locally on this Windows 11 machine
   (dataframe-core, -operations, -csv, -parquet — note: pulls zstd, whose default-on
   `standalone` flag compiles ~24 bundled C files — -learn, -viz); publish the result
   honestly, pass or fail.
3. A one-paragraph Discourse post whose first sentence is "this is not a new
   dataframe", naming the three net-new capabilities.
4. Repo hygiene: MIT LICENSE, GOVERNANCE.md, CONTRIBUTING.md (good-first-issue
   policy), README "what keel is NOT" section.

**HARD GATE — RULED PASSED (2026-08-18):** the stack builds on Windows both
locally and on fork CI (4/4 build lanes green; docs/p0/BUILD-REPORT.md). The
CI-PR half of the gate is moot: upstream-PR work was removed from scope the
same day (§7.1 Q11). Windows differentiator confirmed alive.

### P1 (weeks 3–7) — `keel-dyn` 0.1 to Hackage, alone
Exit: a stranger can dlopen an arbitrary library on Windows/Linux/macOS through it and
get a typed FunPtr back. CI matrix: {windows-latest, ubuntu-latest, macos-14} ×
GHC {9.10.3, 9.12.4, 9.14.1(allowed-to-fail)}.

### P2 (weeks 6–12) — `keel-abi` 0.1 to Hackage
Arrow C Data + Stream both directions; DLPack v-versioned import/export; vendored ABI
headers in test-only cbits; `_Static_assert` layout gate; pyarrow round-trip
conformance in CI on 3 OSes; leak/valgrind gates.

### P3 (weeks 10–18) — `keel-onnx` 0.1: the headline
`OrtGetApiBase()` binding via keel-dyn; full session lifecycle under bracket;
zero-copy OrtValue↔buffer; `keel setup onnx` fetching the checksum-pinned official
archive. **Deliverable = the end-to-end demo:** train in scikit-learn, export with
skl2onnx, run in Haskell on Windows, assert prediction agreement to 1e-6.
Precondition (§7, Q10): one design partner identified who actually needs this.

### P4 — REMOVED (owner decision, 2026-08-18)
The upstream-PR phase is out of this project's scope; see §4 Tier B note and
§7.1 Q11. DataFrame-repo fixes are a separate effort, unrelated to keel.

### P5 (weeks 18–26) — `keel-linalg` 0.1
As specified in §4 A4, with the two soundness corrections and the named hazard tests.
A CI-verified Windows OpenBLAS lane is the thing hmatrix has not had since 2017.

### P6 (weeks 24–32) — `keel` umbrella, doctor, setup, docs, release
Four one-page end-to-end tutorials (ONNX inference on Windows; pyarrow round-trip;
DLPack handoff; BLAS-backed solve with doctor output shown). Cold-install wall-clock
and time-to-first-inference measured as **CI-enforced budgets failing the build on
>20% regression** — publish measured numbers, advertise no absolute promise. Submit
every package to Stackage nightly (do not wait for an LTS). Announce on Discourse,
coordinating with DataHaskell before, not after.

### P7 (ongoing gate, not a phase) — governance and stability
No package reaches 1.0 without two named maintainers. At 1.0: explicit
stable/unstable API split (Polars' 2024-07-01 precedent) + deprecation policy (one
minor release of warning, six-month minimum). "Never fork what we can patch."
Bite-sized-issue board (DataHaskell's survey: contributors want self-contained tasks,
not maintainer roles).

### Deferred (explicitly out, so scope stays honest)
DLPack↔hasktorch bridge (non-Windows only); flag-gated DuckDB escape hatch for
Parquet *write* (retired when the GSoC writer lands); C kernels with runtime cpuid
dispatch; a Storable column representation contributed into dataframe-core (the real
fix for the copy seam — separate owner decision, §7 Q5); a GHC SIMD wrapper library;
anything involving autodiff, NN training, GPU kernels, WASM/JS, distributed compute,
R interop, or a curated library inventory.

---

## 6. Cross-cutting policy

- **GHC:** floor 9.10.3 (Stackage LTS 24.x); primary + CI-default 9.12.4 (Stackage
  nightly, full HLS, the incumbent's own effective ceiling); 9.14.1 tested as
  allowed-to-fail (no Stackage snapshot, basic HLS only, upstream can't build there).
  `default-language: GHC2021` explicit everywhere.
- **Build:** cabal is the documented default; a stack.yaml is a courtesy. Stackage
  nightly submission early; assume no LTS 25 on any schedule.
- **Installability is a hard constraint:** every package `cabal install`-able from
  Hackage on a clean Windows box with no MSYS2 pacman step, forever.
- **License:** MIT recommended (matches dataframe → code moves upstream
  frictionlessly). See §7 Q8 for the Apache-2.0 patent-grant trade-off.
- **Testing oracle:** a Python CI job (pyarrow, numpy, scipy, scikit-learn) cross-
  checks every numerical and interop claim.

---

## 7. Decisions

### 7.1 Decided by the owner (2026-08-17, via structured question round)

| # | Question | **Decision** |
|---|---|---|
| Q1 | P0-gate failure contingency (decided BEFORE P0 runs) | **Narrow to the incumbent-independent packages** (dyn-loader, Arrow/DLPack ABI, ONNX) — they carry no dataframe dependency and remain fully valuable; drop the upstream-dependent halves of Tier B |
| Q2 | Relationship to DataHaskell | **Long-term independent repo.** Interaction with upstream is exclusively finished, tested PRs; no org membership sought |
| Q3 | Package naming | **DECIDED 2026-08-17: product name = `keel`** — unified prefix `keel-dyn` / `keel-abi` / `keel-onnx` / `keel-linalg` + umbrella `keel`; repo codename stays HSDS (superseded 2026-08-18: repo folder renamed to keel). Hackage `keel` verified free (HTTP 404, 2026-08-17; nearest neighbour `keelung` is an unrelated zk-SNARK DSL); only cross-ecosystem collision is the unrelated k8s tool keel.sh (2,720★). Chosen for the "laying the keel" metaphor: laid first, defines the ship, never becomes the ship — the name itself encodes the fixed-scope rule |
| Q6 | Budget | **Full ~32-week plan (P0–P7)**, phases ordered by standalone value so any early stop still leaves net-positive artifacts |
| Q11 | Upstream engagement (2026-08-18) | **All upstream-PR work removed from this project.** dataframe = Hackage dependency only; the three fork-CI-found Windows bugs go to a separate DataFrame-repo effort outside keel; execution is local-first (develop all four packages + umbrella locally, publish in one final stage) |

### 7.2 Still open (recommendations recorded)

| # | Question | Recommendation |
|---|---|---|
| Q4 | ONNX ceiling: inference-only permanently, or eventual training intent (forces hasktorch [no Windows] or a self-built AD [historically fatal])? | Inference-only, stated up front: "train where the ecosystem is, run where your types are" |
| Q5 | Storable column upstream surgery (the real zero-copy fix; months of work on someone else's core type, no keel-branded artifact) | Defer; raise with mchav only after B-track PRs establish trust |
| Q7 | Success metric: accept "single-digit external dependents + landed PRs" as success? | Yes — anything else is self-deception per the adoption data |
| Q8 | License: MIT vs Apache-2.0 (explicit patent grant, relevant for bindings to a Microsoft-owned runtime) | MIT, for upstream mobility |
| Q9 | IHaskell maintenance labor (B8): pure upstream work, possible co-maintenance burden | Do it once, bounded; decline standing co-maintenance unless the project thrives |
| Q10 | Find a design partner running production Haskell who needs ONNX inference BEFORE P3? | Yes — one conversation; if none exists, P3's justification weakens and P5 moves up |

---

## 8. Risk register (top 5)

1. **Incumbent churn** (68 releases; 3 majors in 5 months): depend only on granular
   subpackages (`dataframe-core`, `dataframe-operations`) with tight `>=x.y && <x.(y+1)`
   bounds; funnel every upstream call through one internal Compat module.
2. **Read as a competitor / community split:** behavioral mitigation — B-track PRs
   land before anything that looks like a surface; README opens with the disclaimer.
3. **Dynamic loading sharp edges** (ILP64, symbol drift, DLL search path, thread-pool
   contention, bad DLL = process crash): each has a named test in P5; per-symbol lazy
   resolution everywhere.
4. **Fallback reputation landmine:** a user without OpenBLAS silently benchmarking
   reference GEMM concludes "Haskell is 100× slower." `initBackends` prints one
   unmissable line; benchmarks refuse to run on the fallback without an explicit flag.
5. **ABI ownership bugs are memory-safety bugs:** the `_Static_assert` gate, pyarrow
   round-trip fuzzing, `+RTS -s` leak assertions, and valgrind are the reason P2 is
   budgeted at 6 weeks for "two structs".

---

## 9. Provenance

Full research dossiers (six dimensions, with per-claim source URLs) live in
[docs/research/](docs/research/). The three competing designs and their adversarial
critiques are archived there too. Facts re-verified first-party on 2026-08-17 before
this document was written:

1. `DataHaskell/dataframe` CI is ubuntu-latest only (GHC 9.6.7–9.12.2), no
   windows/macos — raw ci.yml fetched directly.
2. `hs-onnxruntime-capi` is AGPL-3.0-only, 0.1.0.0, uploaded 2025-07-24 — Hackage
   page fetched directly.
3. `microsoft/onnxruntime` license is MIT; latest release v1.29.0 (2026-08-12) ships
   `onnxruntime-win-x64-1.29.0.zip` + CUDA 12/13 variants + linux-x64 + osx-arm64 —
   GitHub API queried directly.
