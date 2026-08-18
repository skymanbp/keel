# digest
HASKELL PLATFORM/TOOLING FOR DS/ML — verified 2026-08-17.

(1) GHC. Latest stable = 9.14.1 (2025-12-19), the first designated LTS ("at least until early 2028"). 9.14.2-rc1 announced 2026-07-31 targeting week of 13-Aug; downloads.haskell.org still shows only 9.14.2-rc1, so the final has slipped. 9.12.4 (2026-03-27) is newest 9.12; 9.12.5-rc3 in flight. GHC 10.0 (renamed from 9.16) forked 2026-04-01, unreleased; defaults to GHC2024 language edition, makes Type/Constraint fully distinct. Five active branches for too few maintainers (per 2026-06-09 status update); 10.0 gets ≤1yr support vs 9.14 LTS.

SIMD: x86-64 NCG SIMD landed in 9.12; 9.14 added 128-bit integer ops and dropped the -mavx requirement for shuffleFloatX4#/shuffleDoubleX2#; 9.16/10.0 adds 128-wide bitwise logical primops via ghc-experimental plus -mavx512bw/dq/vl. AArch64 SIMD only via LLVM. No maintained wrapper library (primitive-simd last upload 2016-02-01; simd 2014-05-19), so SIMD means raw GHC.Prim unboxed vectors.

-fllvm on Windows: GHC bundles LLVM since 9.4, auto-used from 9.12. GHC ≤9.10 on Windows: -fllvm + floating point → link error `_fltused` (GHC #22487), effectively unusable. GHCup's *recommended* GHC is 9.10.3 — precisely the broken version. A DS toolkit wanting LLVM/SIMD on Windows must require ≥9.12.

Records/types: OverloadedRecordDot stable since 9.2; OverloadedRecordUpdate still marked EXPERIMENTAL and needs RebindableSyntax. LinearTypes experimental since 9.0; multiplicity polymorphism "really unreliable", TH "probably not work". Dependent Haskell roadmap (page updated 2026-08-14): RequiredTypeArguments preview since 9.10, type syntax in expressions since 9.12, VDQ-in-GADTs in 9.14; Π/Σ types unscheduled.

WASM/JS: both tech previews, not in official bindists. GHC wasm now supports GHCi, TemplateHaskell and browser live-coding (9.14). GHCup cross-bindists exist for wasm32-wasi and javascript-unknown-ghcjs but only for Linux/Darwin hosts, newest 9.12.x — no Windows host, so the browser story needs WSL2/Docker.

(2) Interactive. IHaskell supports GHC 8.4–9.14 in git master and gained Windows support via PR #1595 (merged 2026-04-09, MSYS2 CLANG64 zeromq/cairo/pango). But Hackage ihaskell-0.13.0.0 (2025-11-15) is bounded ghc <9.13 and predates Windows support — Windows/9.14 requires building master from source. Stackage nightly carries 0.13.0.0; LTS 24 carries 0.12.0.0. No binary kernel distribution; Docker (gibiansky/ihaskell) and Nix flake are the only turnkey paths. HLS 2.14.0.0 (2026-04-27): full support 9.12.4/9.12.2/9.10.3/9.8.4/9.6.7, only "basic support" for 9.14.1. cabal multi-repl (`--enable-multi-repl`, cabal ≥3.11, GHC ≥9.4) and `cabal repl --build-depends` give ephemeral ghci envs.

(3) Plotting. Nothing is simultaneously maintained, publication-quality, and dependency-light. hvega 0.12.0.7 (2023-09-28) targets Vega-Lite 4.15 vs upstream 6.4.3 — 2 majors behind; README: maintainer "not using it, due to lack of time". Chart 1.9.5 (2023-10-22); Chart-cairo needs gtk2hs cairo (Windows pain); Chart-diagrams is pure Haskell (SVG/PS). chart-svg 0.8.3.2 (2026-01-12, pushed 2026-08-17) is the most active, pure Haskell, SVG-only. gnuplot 0.5.7 (2022) and matplotlib 0.7.7 (2021) both shell out. diagrams-lib 1.6 (2026-08-06) active.

(4) Build. State of Haskell 2025 (n=1417): Cabal 83.96%, Stack 39.59%, Nix 39.48%; ghcup 63.45% install share; GHC 9.12 45.42%, 9.10 44.37%; HLS 83.35%; Hackage 83.56% vs Stackage 33.45%. Stackage LTS is stuck on GHC 9.10.3 (LTS 24.55, 2026-08-16); nightly on 9.12.4 — no snapshot for the 9.14 LTS. accelerate, inline-r and Frames are absent from nightly; hasktorch 0.2.2.0 and dataframe 3.5.0.0 are present. Windows: MSYS2 deprecated MINGW64 on 2026-03-15; GHC ships CLANG64 since 9.4.1 and Stack 3.11.1 now defaults to CLANG64. Native deps (BLAS/LAPACK, zlib, zeromq, cairo/pango) come via `ghcup run --mingw-path -- pacman -S mingw-w64-clang-x86_64-*` plus extra-include-dirs/extra-lib-dirs. Everything builds from source — no wheel equivalent.

(5) Interop. inline-c 0.9.1.10 (2023-09-29), repo idle since 2025-06 but works. inline-r 1.0.2 (2025-07-11), Hackage builds failing, not in Stackage. inline-python 0.2.1.0 (2026-01-13, pushed 2026-08-10) is the live option — quasiquotes, Haskell callbacks from Python, Python ≥3.10 — but CI is Linux-only via pkg-config python3-embed, and there is no numpy/buffer-protocol zero-copy module. cpython 3.9.0 (2024-07-08); ABI pinned to the exact CPython minor version.

Wildcard: DataHaskell/dataframe (mchav) 3.5.0.0, 2026-08-14, 261 stars, split into dataframe-{core,csv,parquet,learn,viz}, with its own preloaded REPL, IHaskell support, terminal + HTML plots, Parquet, typed expression DSL, readthedocs site, and an HF pre-proposal. It already occupies the pandas-shaped niche.

# key_insights
- The GHC version choice is forced and non-obvious: 9.10.3 is what GHCup recommends and what Stackage LTS 24.55 pins, 9.12.4 is what Stackage nightly and full-tier HLS support and the only version where -fllvm works on Windows for floating-point code, and 9.14.1 is the official GHC LTS with no Stackage snapshot and only basic HLS support — so a Windows-first numeric toolkit should floor at 9.12 and test 9.10 and 9.14, not simply follow ghcup's default.
- GHC #22487 makes -fllvm unusable with floating-point code on Windows for GHC <= 9.10, which means the toolchain GHCup hands a brand-new Windows user by default cannot compile SIMD-via-LLVM numeric code at all.
- Haskell has no binary package distribution — Hackage is source-only and there is no wheel or conda analogue — so every native dependency (BLAS/LAPACK, zeromq, cairo, pango, zlib) becomes a manual MSYS2 pacman step in the correct environment, and the only defensible design response is that the toolkit's default install path must have zero C dependencies.
- Windows is mid-migration between MSYS2 environments: MINGW64 was deprecated 2026-03-15 in favour of UCRT64 for the wider world, while GHC has used CLANG64 since 9.4.1 and Stack only just switched its default to CLANG64 in 3.11.1 — mixing environments produces errors Cabal's own documentation calls undecipherable.
- Jupyter-on-Haskell-on-Windows became technically real on 2026-04-09 when IHaskell PR #1595 merged, but the newest Hackage release (ihaskell-0.13.0.0, 2025-11-15) is bounded ghc <9.13 and predates that work, so today Windows notebooks require building git master — cutting a Hackage release is the single highest-leverage unblock in the whole onboarding chain.
- There is no prebuilt IHaskell kernel binary for any platform; the only turnkey notebook paths are Docker (gibiansky/ihaskell), a Nix flake with a cachix cache, and mybinder.org, which means 'pip install jupyterlab' has no equivalent and shipping a prebuilt kernel plus bundled native deps would be a genuine first.
- `cabal repl --build-depends='pkg >= x' --ignore-project` is the closest existing analogue to an ephemeral pip environment and works outside any project, so it — not Jupyter — is the realistic headline quickstart for a Haskell DS toolkit in 2026.
- GHCi structurally cannot render images or rich HTML, so terminal-based plots (the route DataHaskell/dataframe already took) are the honest default and any image output implies either Jupyter or writing files to disk.
- Plotting is the weakest link: nothing is simultaneously maintained, publication-quality, and free of native dependencies — hvega is two Vega-Lite majors behind with an author who says he no longer uses it, Chart-cairo is a Windows trap, matplotlib bindings are stale shell-outs, and chart-svg is the only vigorously maintained pure-Haskell option but emits SVG only.
- hvega cannot produce a static PNG/SVG/PDF from Haskell at all — the Vega-Lite spec needs an external Node or vl-convert renderer — so adding vl-convert-backed export plus a Vega-Lite 6 regeneration would fix the ecosystem's most-cited plotting library in one contribution.
- Chart-diagrams is the only maintained path to publication-grade vector output (SVG/PS/EPS/PDF) with no C dependencies, making the diagrams substrate the safest rendering foundation even though its compile times and type machinery are heavy.
- SIMD is available but raw: x86-64 NCG support landed in 9.12 and grew through 9.14 and 10.0, yet there is no maintained high-level wrapper (primitive-simd last uploaded 2016, simd 2014), no runtime CPU feature detection, and no bridge to Storable/Unboxed vectors — building that layer is real, defensible value and also a real cost.
- LinearTypes should not be load-bearing: multiplicity polymorphism is documented as 'really unreliable' and Template Haskell 'will probably not work', so zero-copy mutation should use ST/IO plus unsafeFreeze rather than linear types.
- OverloadedRecordDot is stable since GHC 9.2 and safe for a df.column-style read API, but OverloadedRecordUpdate is still flagged experimental with an explicit warning against use in long-lived libraries, so update APIs must use explicit combinators or optics.
- Dependent Haskell will not arrive in time to matter: the roadmap page updated 2026-08-14 explicitly declines to estimate when Pi/Sigma types land, and RequiredTypeArguments is erased with no dependent pattern matching, so shape-indexed tensors must still carry runtime shape checks.
- The browser story is unreachable from a Windows development machine: GHCup's cross-compiler bindists for wasm32-wasi and javascript-unknown-ghcjs exist only for Linux and Darwin hosts and stop at GHC 9.12, so any WASM ambition costs a WSL2, Docker, or Linux CI lane.
- GHC 10.0 will silently flip code with no explicit language edition to GHC2024 — turning on DataKinds, GADTs and six other extensions — so the toolkit should declare `default-language: GHC2021` or `GHC2024` explicitly from day one rather than inherit a semantics change.
- cabal has decisively won: 83.96% of the 2025 survey uses it against 39.59% for Stack and 39.48% for Nix, 63.45% install via ghcup, and 83.56% pull packages from Hackage against only 33.45% from Stackage — so cabal plus Hackage is the default distribution channel and a stack.yaml is a courtesy, not a requirement.
- Stackage LTS has been frozen on GHC 9.10.3 for a year with no LTS 25 and no snapshot for GHC's own 9.14 LTS, so a toolkit that depends on Stackage curation for co-installability inherits a two-major-version lag; getting into nightly early is cheap insurance.
- The DS core is better curated than reputation suggests — hmatrix, vector, massiv, statistics, cassava, Chart, chart-svg, hvega, ihaskell, inline-c, streamly, hasktorch and dataframe are all in Stackage nightly — but inline-r, accelerate and Frames are in no snapshot at all, marking the R, GPU and typed-frames tiers as structurally fragile.
- hmatrix has had no release since 2021-03-08 and no commit since 2024-06-25 yet remains the only mature dense linear algebra library and still builds on GHC 9.12, so either taking over its maintenance or shipping a pure-Haskell/SIMD fallback is unavoidable.
- inline-python (0.2.1.0, actively developed through 2026-08-10) is the live bridge to the entire numpy/pandas/sklearn/matplotlib world and is explicitly modelled on HaskellR, but its CI is Ubuntu-only using pkg-config python3-embed and it has no numpy buffer-protocol module, so every array crosses as a Python list — adding Windows support or zero-copy numpy marshalling would be a sharply-scoped, high-impact contribution.
- DataHaskell/dataframe 3.5.0.0 (uploaded 2026-08-14, 261 stars, split into core/csv/parquet/learn/viz) already ships exactly the onboarding the brief asks for — one cabal install yielding a preloaded REPL, IHaskell support, Parquet, terminal and HTML plots, and decision trees — so a new project must either build on it or stake out a sharply different thesis such as static-shape tensors and serious ML, where dataframe-learn is thin.
- The realistic 'pip install + jupyter' equivalent in 2026 is a three-step chain — ghcup PowerShell one-liner, then cabal install of a zero-native-dependency toolkit, then `cabal repl --build-depends` or a prebuilt IHaskell kernel — and the only genuinely missing piece is that last prebuilt kernel plus a Hackage release of IHaskell master.
- HLS at 83.35% adoption with type-on-hover and completion is Haskell's strongest ergonomic advantage over Python for a typed DS API, but it does not work inside Jupyter cells, so the editor experience is strictly better than the notebook experience — an argument for making script-and-editor the primary supported workflow rather than chasing notebook parity.

# libraries

## GHC (compiler) (The compiler; defines what language features and codegen a DS toolkit can rely on)
STATUS: Latest stable 9.14.1 (2025-12-19), first designated LTS, supported 'at least until early 2028'. 9.12.4 (2026-03-27). 9.14.2-rc1 (2026-07-31) NOT yet final as of 2026-08-17 — downloads.haskell.org lists only 9.14.2-rc1. 9.12.5-rc3 in flight. GHC 10.0 (ex-9.16) forked 2026-04-01, unreleased, no alpha on downloads server. Five active branches, maintainer-constrained.
ASSESS: Strong: twice-yearly cadence, now with a real LTS line. For a new toolkit, GHC 9.10.3 + 9.12.4 is the pragmatic support floor/ceiling (matches Stackage LTS + nightly and the survey's 45%/44% usage); 9.14 gains you the LTS guarantee but no Stackage snapshot and only 'basic' HLS support. 10.0 will silently change semantics by defaulting to GHC2024 (DataKinds, GADTs on) — plan for it.
EVID: https://www.haskell.org/ghc/ ; https://endoflife.date/api/v1/products/ghc/ ; https://downloads.haskell.org/ghc/ ; https://discourse.haskell.org/t/2026-06-09-informal-ghc-release-status-update-of-a-sort/14250 ; https://discourse.haskell.org/t/ghc-9-14-2-rc1-is-now-available/14490 ; https://ghc.gitlab.haskell.org/ghc/doc/users_guide/9.16.1-notes.html

## GHC SIMD primops (Vectorized float/int arithmetic — the floor under any competitive numeric kernel)
STATUS: x86-64 NCG SIMD since 9.12; 9.14 added 128-bit integer ops and removed the -mavx requirement for shuffleFloatX4#/shuffleDoubleX2#; FMA (fmaddDoubleX2#) and min/max primops in X86/AArch64/PowerPC NCG + LLVM + wasm/JS backends; 9.16/10.0 adds 128-wide bitwise and/or/xor via ghc-experimental and -mavx512bw/-mavx512dq/-mavx512vl/-mgfni. AArch64 SIMD is LLVM-only (9.8+). Exposed as unboxed GHC.Prim types (FloatX4#, DoubleX2#, …).
ASSESS: Usable but raw and incomplete. Missing: sqrt/abs on vectors, mask/conditional ops, runtime CPU feature detection (flags are per-module), 256/512-bit NCG coverage, vectorcall on Windows. No boxed/Storable/Unboxed-vector bridge in the compiler — a toolkit must build its own SIMD layer. That is real, defensible engineering value but also real cost.
EVID: https://minoki.github.io/posts/2025-01-13-ghc-simd.html ; https://downloads.haskell.org/ghc/latest/docs/users_guide/9.14.1-notes.html ; https://ghc.gitlab.haskell.org/ghc/doc/users_guide/9.16.1-notes.html

## primitive-simd / simd (SIMD wrappers) (Would-be ergonomic layer over GHC's SIMD primops (Data.Primitive.SIMD))
STATUS: DEAD. primitive-simd last Hackage upload 2016-02-01, GitHub last push 2020-04-03, 6 stars. simd last upload 2014-05-19, last push 2015-06-25, 23 stars. Neither in Stackage.
ASSESS: Confirms the gap: there is no maintained high-level SIMD API in Haskell in 2026. A new toolkit either writes this layer or forgoes SIMD. primitive-simd's type-family design (uniform interface + Prim/Storable/Unboxed instances) is a good prior-art template even though the code is stale.
EVID: https://hackage.haskell.org/package/primitive-simd ; https://github.com/ajscholl/primitive-simd ; https://github.com/mikeizbicki/simd

## GHC LLVM backend (-fllvm) (Alternative codegen; required for AArch64 SIMD and best autovectorization)
STATUS: GHC bundles LLVM on Windows since 9.4; from GHC 9.12+ the bundled LLVM is used automatically. On non-Windows you install LLVM yourself (9.12 wants LLVM >=13 && <=19). BLOCKER: GHC <=9.10 on Windows fails to link any floating-point code under -fllvm — undefined symbol _fltused, GHC issue #22487.
ASSESS: Critical Windows constraint. GHCup's *recommended* GHC is 9.10.3, exactly the version where -fllvm is unusable for numeric code on Windows. A DS toolkit that wants LLVM/SIMD on Windows must set its floor at GHC 9.12. Documenting this is itself a contribution — it is nowhere in the onboarding path.
EVID: https://minoki.github.io/posts/2025-01-06-ghc-llvm-backend.html

## OverloadedRecordDot / OverloadedRecordUpdate (Record ergonomics for column/frame APIs (df.column style))
STATUS: OverloadedRecordDot: since GHC 9.2, stable, no caveat in the user guide. OverloadedRecordUpdate: since 9.2 but still labelled EXPERIMENTAL — 'inadvisable to start using this extension for long-lived libraries just yet' — and still requires RebindableSyntax plus hand-written getField/setField.
ASSESS: Safe to build a read API on record dot. Do NOT build an update/mutation API on OverloadedRecordUpdate; use explicit combinators or optics instead, or the toolkit inherits a moving target.
EVID: https://ghc.gitlab.haskell.org/ghc/doc/users_guide/exts/overloaded_record_update.html

## LinearTypes (Potential mechanism for safe in-place mutation of arrays/buffers without copying)
STATUS: Experimental since GHC 9.0 and still so in the 9.14.1 user guide: 'expect bugs, warts, and bad error messages; everything down to the syntax is subject to change'. Linear let/where and linear record/GADT fields work. Multiplicity polymorphism is 'incomplete and experimental… expect it to be really unreliable'. No linear pattern synonyms, @-patterns or view patterns. Template Haskell 'will probably not work'.
ASSESS: Tempting for zero-copy array APIs, but multiplicity polymorphism unreliability makes generic linear containers impractical today, and the TH gap collides with any codegen/deriving strategy. Use ST/IO + unsafeFreeze for mutation; treat linear types as a research side-track, not a foundation.
EVID: https://downloads.haskell.org/ghc/latest/docs/users_guide/exts/linear_types.html

## Dependent Haskell (RequiredTypeArguments / visible forall) (Would enable shape-indexed tensors with ergonomic, erasable dimension arguments)
STATUS: Roadmap page last updated 2026-08-14. Shipped: standalone kind signatures, type abstractions in patterns, visible type/kind application, modifiers syntax. RequiredTypeArguments = feature preview since 9.10, partially implemented (GHC proposal #281 not fully); type syntax in expressions since 9.12; VDQ in GADTs added for 9.14. Π/Σ types, universal promotion and dependent Core all still unsatisfied prerequisites; roadmap explicitly declines to estimate a timeline.
ASSESS: Do not design the toolkit's type-level shape story around anything past GHC2024 + DataKinds/TypeFamilies/singletons-style encodings. Visible forall is nice sugar for dimension arguments on 9.10+, but it is erased — no dependent pattern matching — so runtime shape checks are still mandatory.
EVID: https://ghc.serokell.io/dh ; https://ghc.gitlab.haskell.org/ghc/doc/users_guide/exts/required_type_arguments.html

## GHC WebAssembly backend (Browser/notebook-in-browser deployment story)
STATUS: Tech preview; 'not included in the official bindists yet'. Targets wasm32-wasi. GHC 9.14 added GHCi + TemplateHaskell over wasm and a browser mode for live-coding via a local HTTP server, with JavaScript FFI (JSVal as a GC'd Haskell value). RTS is single-threaded; cyclic JS/Haskell references need manual freeJSVal; blocking on async JSFFI inside a C FFI callback raises WouldBlockException. GHCup cross-metadata carries wasm32-wasi bindists only up to 9.12.x, hosts Linux + Darwin only.
ASSESS: The most credible future browser story (real GHCi, real TH), but it is not reachable from a Windows dev box — no Windows host bindist. Any browser ambition costs a WSL2/Docker/Linux CI lane. Defer; do not put it on the critical path.
EVID: https://ghc.gitlab.haskell.org/ghc/doc/users_guide/wasm.html ; https://raw.githubusercontent.com/haskell/ghcup-metadata/master/ghcup-cross-0.1.0.yaml

## GHC JavaScript backend (Alternative browser target (GHCJS successor))
STATUS: Tech preview, 'not ready for use in production', not in GHC release bindists — historically required building GHC as a cross-compiler; GHCup now ships unofficial cross-bindists javascript-unknown-ghcjs for 9.6.2/9.6.7/9.10.x/9.12.1/9.12.2, Linux and Darwin hosts only, each pinned to a specific emscripten version (e.g. 3.1.74 for 9.6.7). No Template Haskell.
ASSESS: Weaker than wasm for a DS toolkit: no TH, emscripten version pinning, no Windows host, stalled at 9.12. Only 6.25% of survey respondents target JavaScript. Skip.
EVID: https://raw.githubusercontent.com/haskell/ghcup-metadata/master/ghcup-cross-0.1.0.yaml ; https://discourse.haskell.org/t/javascript-webassembly-backend/6787

## GHCup (The de facto toolchain installer; the first 60 seconds of onboarding)
STATUS: v0.2.6.2 (2026-06-16). Metadata ghcup-0.1.0.yaml tags: GHC Recommended = 9.10.3, GHC Latest = 9.14.1; cabal Recommended = 3.16.1.0, Latest = 3.18.1.0; HLS Recommended = Latest = 2.14.0.0; Stack Recommended = Latest = 3.11.1. On Windows the PowerShell bootstrap additionally installs MSYS2. 63.45% of survey respondents install GHC via ghcup. Known Windows friction: antivirus interference, MSYS2 curl/cert-revocation failures, MAX_PATH.
ASSESS: The one genuinely good piece of onboarding — a single PowerShell line yields GHC+cabal+HLS+Stack+MSYS2. But its *recommended* GHC (9.10.3) is the version where -fllvm is broken on Windows, and it installs no data-science anything. The toolkit must pin GHC explicitly rather than accept ghcup's default.
EVID: https://raw.githubusercontent.com/haskell/ghcup-metadata/master/ghcup-0.1.0.yaml ; https://github.com/haskell/ghcup-hs/releases ; https://www.haskell.org/ghcup/install/ ; https://discourse.haskell.org/t/state-of-haskell-2025-results/13755

## cabal-install (Primary build tool and dependency solver)
STATUS: 3.18.1.0 released 2026-07-29; 3.16.1.0 is ghcup-recommended. 3.18 calls Cabal library functions directly instead of via the Setup interface (10-15% speedups), adds a parsec cabal.project parser with line/col errors, recursive file globs, --enable-library-bytecode (needs GHC 10+, pairs with GHCi -fprefer-byte-code), reinstallable base/template-haskell on GHC 9.14+, and fixes HSEC-2026-0006 (Windows arbitrary-file deletion). Builds only with GHC 9.4+. Survey: 83.96% use Cabal; satisfaction 49.76% agree/strongly agree.
ASSESS: Clear winner and the right default. `cabal repl --build-depends=...` (usable outside a project, with --ignore-project) is the closest thing Haskell has to an ephemeral `pip install` env and should be the toolkit's advertised quickstart. Multi-repl (--enable-multi-repl, cabal >=3.11 + GHC >=9.4) matters for a multi-package toolkit but has known ghc-options and -unit ordering bugs.
EVID: https://github.com/haskell/cabal/releases ; https://discourse.haskell.org/t/cabal-3-18-1-0-released/14556 ; https://cabal.readthedocs.io/en/latest/cabal-commands.html ; https://www.well-typed.com/blog/2026/06/haskell-ecosystem-report-march-may-2026/

## Stack (Alternative build tool with curated snapshots)
STATUS: 3.11.1 (2026-06-13), repo pushed 2026-08-17. Now defaults msys-environment to CLANG64 instead of MINGW64 because MSYS2 deprecated MINGW64 on 2026-03-15 and GHC has used CLANG64 since 9.4.1. Adds experimental --semaphore parallel compilation (GHC 9.10.1+), !include config directive, Hpack 0.39.6. Survey: 39.59% usage, 38.31% say they do not use Stack at all.
ASSESS: Actively maintained and now the *better-configured* option on Windows out of the box, but it is the minority tool and inherits Stackage's GHC lag. Support it as a secondary path (ship a stack.yaml) but make cabal the documented default.
EVID: https://discourse.haskell.org/t/ann-stack-3-11-1/14272 ; https://github.com/commercialhaskell/stack/releases ; https://www.msys2.org/docs/environments/

## Stackage (Curated, co-installable snapshot — the closest Haskell has to a distro)
STATUS: LTS 24.55 (2026-08-16) on GHC 9.10.3; nightly 2026-08-16 on GHC 9.12.4. NO LTS 25 exists — LTS is still on the 9.10 series a year after LTS 24, and there is no snapshot at all for GHC 9.14, the official GHC LTS. Present in nightly: hmatrix-0.20.2, vector-0.13.2.0, massiv-1.0.5.0, statistics-0.16.5.0, cassava-0.5.4.1, Chart-1.9.5, chart-svg-0.8.3.2, hvega-0.12.0.7, ihaskell-0.13.0.0, inline-c-0.9.1.10, streamly-0.11.1, gnuplot-0.5.7, matplotlib-0.7.7, gloss-1.13.2.2, diagrams-lib-1.5.1, hasktorch-0.2.2.0, dataframe-3.5.0.0. ABSENT from nightly: inline-r, accelerate, Frames. Only 33.45% of users get packages from Stackage vs 83.56% from Hackage.
ASSESS: Coverage of the DS core is better than reputation suggests, but the two structural problems are (a) LTS pinned to GHC 9.10 while GHC's own LTS is 9.14, and (b) the GPU/R/typed-frames tier is simply not curated. Getting the new toolkit into nightly early is cheap and buys co-installability; do not assume an LTS 25 will appear on any schedule.
EVID: https://www.stackage.org/snapshots ; https://www.stackage.org/nightly ; https://www.stackage.org/lts-24.55 ; https://discourse.haskell.org/t/state-of-haskell-2025-results/13755

## Haskell Language Server (HLS) (IDE/LSP — type-on-hover and completion, which substitutes for docstrings in exploratory work)
STATUS: 2.14.0.0 (2026-04-27). Full support: GHC 9.12.4, 9.12.2, 9.10.3, 9.8.4, 9.6.7. Only BASIC support (tier-1 plugins only) for GHC 9.14.1. Adds ExplicitLevelImports support, faster startup in multipleComponents session mode, better out-of-project file handling, Note hover/completion, smart-case module and cabal-file path completion. Survey: 83.35% of respondents use HLS; VS Code 41.62%.
ASSESS: Mature and the single strongest ergonomic asset Haskell has over Python for a typed DS API — but it is another reason to target 9.12 rather than 9.14: choosing the GHC LTS costs you plugin coverage. Note HLS does not work inside Jupyter cells, so notebook UX is strictly worse than editor UX.
EVID: https://haskell-language-server.readthedocs.io/en/latest/support/ghc-version-support.html ; https://github.com/haskell/haskell-language-server/releases ; https://blog.haskell.org/hls-2-14-0-0/

## IHaskell (Jupyter kernel — the notebook onboarding story)
STATUS: 2646 stars, repo pushed 2026-08-15. Master supports GHC 8.4–9.14. Windows support merged 2026-04-09 (PR #1595 by sheaf: new IHaskell.Windows.IO module replacing the unix package's handle redirection; also fixed a repeated-initUnit perf bug, 6 min → seconds). BUT the latest Hackage release, ihaskell-0.13.0.0 (2025-11-15), is bounded ghc >=8.4 && <9.13 and predates the Windows work. Native prereqs: Windows needs MSYS2 CLANG64 zeromq+cairo+pango; Linux needs libzmq3-dev, libcairo2-dev, libpango1.0-dev, libmagic-dev, libblas-dev, liblapack-dev. Turnkey paths: Docker (gibiansky/ihaskell), Nix flake (ihaskell.cachix.org), mybinder.org.
ASSESS: The critical finding: Jupyter-on-Windows-Haskell became technically possible four months ago but is NOT shippable via `cabal install ihaskell` yet — it requires building git master. There is no prebuilt kernel binary for any platform. This is the single highest-leverage gap the project could close (fund/push a Hackage release, or ship a prebuilt kernel + prebuilt native-dep bundle).
EVID: https://github.com/IHaskell/IHaskell ; https://github.com/IHaskell/IHaskell/pull/1595 ; https://hackage.haskell.org/package/ihaskell ; https://raw.githubusercontent.com/IHaskell/IHaskell/master/README.md

## GHCi (as a data REPL) (Default interactive loop when Jupyter is unavailable)
STATUS: 9.14 adds multiple home units in GHCi, numeric diagnostic codes, and a :stepout debugger command. cabal >=3.11 + GHC >=9.4 gives --enable-multi-repl; `cabal repl --build-depends='pkg >= x'` works outside a project with --ignore-project. GHC 10 + cabal 3.18 --enable-library-bytecode pairs with -fprefer-byte-code for faster loads. 41.74% of survey respondents list GHCi as an IDE; ghcid 20.07%. Well-Typed is actively improving bytecode memory usage.
ASSESS: Adequate for typed exploration and vastly better than it was, but structurally cannot display images or rich HTML — no display protocol. Terminal plots (as dataframe does) are the honest fallback. The `cabal repl --build-depends` one-liner is the best 'pip install + repl' analogue available and should be the toolkit's headline quickstart.
EVID: https://downloads.haskell.org/ghc/latest/docs/users_guide/9.14.1-notes.html ; https://cabal.readthedocs.io/en/latest/cabal-commands.html ; https://www.well-typed.com/blog/2026/06/haskell-ecosystem-report-march-may-2026/

## hvega + ihaskell-hvega (Vega-Lite grammar-of-graphics bindings; the natural notebook plotting layer)
STATUS: hvega 0.12.0.7, last Hackage upload 2023-09-28, targets Vega-Lite 4.15 while upstream Vega-Lite is at 6.4.3 (2026-04-24) — two major versions behind. Repo pushed 2026-01-09, 60 stars, 25 open issues. README from the author: 'At present I am not using it, due to lack of time. Please pop on over to GitHub… if you would like to help.' ihaskell-hvega was uploaded more recently (2026-01-09). No native static export — toHtmlFile emits HTML; PNG/SVG/PDF need external Node/vl-convert.
ASSESS: Best-in-class API design, effectively unmaintained content-wise, and cannot produce a publication figure without a non-Haskell renderer. Either adopt/refresh it (highest-value, clearly-wanted contribution: regenerate against Vega-Lite 6 and add a vl-convert-backed static export) or route around it.
EVID: https://hackage.haskell.org/package/hvega ; https://github.com/DougBurke/hvega ; https://github.com/vega/vega-lite/releases

## Chart (+ Chart-cairo, Chart-diagrams) (Classic 2D plotting library, the closest analogue to matplotlib's role)
STATUS: Chart 1.9.5 uploaded 2023-10-22, maintainers TimDocker + bravit, repo pushed 2026-01-18, 436 stars, 63 open issues. Still in Stackage nightly on GHC 9.12.4, so it builds. Chart-cairo 1.9.3 (2023-10-23) needs the gtk2hs cairo binding — documented Windows/macOS workarounds, GTK all-in-one bundle. Chart-diagrams 1.9.5.1 (2023-10-23, revised 2026-01-18) is pure Haskell via diagrams-svg + diagrams-postscript (SVG/PS/EPS/PDF), no C deps.
ASSESS: The only maintained path to a real publication-quality raster/vector figure without native deps is Chart-diagrams. Chart-cairo is a Windows trap — do not put it on the default install path. Chart's API is dated (lens-heavy, imperative EC monad) but the backend split is the right architecture to reuse.
EVID: https://hackage.haskell.org/package/Chart ; https://hackage.haskell.org/package/Chart-diagrams ; https://github.com/timbod7/haskell-chart ; https://wiki.haskell.org/Diagrams/Install/Install-cairo

## chart-svg (Modern pure-Haskell SVG charting)
STATUS: 0.8.3.2, Hackage 2026-01-12, repo pushed 2026-08-17 (most actively maintained plotting package found). Author Tony Day. SVG output only. Zero C dependencies. In Stackage nightly. Only 23 stars, 5 open issues. Depends on numhask, lens, cubicbezier.
ASSESS: The healthiest maintenance signal in Haskell plotting and the cleanest dependency story (matters enormously on Windows). Weaknesses: SVG-only (no direct PDF/PNG for journals), tiny community, and an idiosyncratic optics-first API that ties the toolkit to numhask. Strong candidate as the default backend if paired with an SVG→PDF converter.
EVID: https://hackage.haskell.org/package/chart-svg ; https://github.com/tonyday567/chart-svg

## gnuplot bindings (Shell-out wrapper to gnuplot for 2D/3D plots)
STATUS: 0.5.7 uploaded 2022-02-13 (revision 4 on 2026-01-07), maintainer Henning Thielemann, darcs-hosted. Tested only with GHC 7.4.2–8.6.5 per its own metadata. In Stackage nightly. Rated 1.5/5 on Hackage.
ASSESS: Genuinely publication-quality output (gnuplot is a journal-grade engine) but requires the user to install gnuplot separately, the binding is barely maintained, and its declared GHC test range stops at 8.6.5. Viable as an optional escape hatch for users who already live in gnuplot; not a foundation.
EVID: https://hackage.haskell.org/package/gnuplot ; https://www.stackage.org/nightly/package/gnuplot-0.5.7

## matplotlib (Haskell bindings) (Shell-out bindings to Python matplotlib — the pragmatic publication-quality route)
STATUS: 0.7.7, last Hackage upload 2021-11-08, Hackage reports 'All reported builds failed as of 2021-11-08' and a failing test suite. Repo abarbu/matplotlib-haskell last pushed 2024-04-05, 86 stars. Requires python3 on PATH plus matplotlib, numpy, scipy, tk; optional texlive for LaTeX labels. Still present in Stackage nightly at 0.7.7.
ASSESS: Delivers genuinely publication-quality output today, and is the only Haskell option that does so with no argument. But it is stale, string-templated (no type safety in the generated Python), and duplicates what inline-python could do properly. Strong argument for building the plotting escape hatch on inline-python instead of resurrecting this.
EVID: https://hackage.haskell.org/package/matplotlib ; https://github.com/abarbu/matplotlib-haskell

## gloss (Simple real-time 2D vector graphics / animation over OpenGL)
STATUS: 1.13.2.2, last Hackage upload 2022-03-20, repo benl23x5/gloss last pushed 2025-04-12, 424 stars, only 4 open issues. In Stackage nightly.
ASSESS: Not a plotting library and not publication-quality — it is an OpenGL animation toy for teaching and games, and it drags in GLUT/OpenGL native deps. Irrelevant to a DS toolkit except for interactive/animated demos. Exclude.
EVID: https://github.com/benl23x5/gloss ; https://www.stackage.org/nightly/package/gloss-1.13.2.2

## diagrams (Declarative vector graphics EDSL underlying Chart-diagrams)
STATUS: diagrams-lib 1.6 uploaded 2026-08-06 (very recent); umbrella repo diagrams/diagrams pushed 2025-04-18, 228 stars. Backends: diagrams-svg, diagrams-postscript (pure Haskell), diagrams-cairo, diagrams-rasterific. diagrams-lib 1.5.1 in Stackage nightly.
ASSESS: Alive and just released a major bump. As a rendering substrate it gives SVG + PostScript/PDF with no C dependencies, which is exactly what publication output on Windows needs. Heavy type machinery and slow compiles are the cost. Best used indirectly, as Chart-diagrams does.
EVID: https://hackage.haskell.org/package/diagrams-lib ; https://github.com/diagrams/diagrams

## inline-c (Embed C in Haskell — the route to BLAS/LAPACK/FFTW/custom kernels)
STATUS: 0.9.1.10, last Hackage upload 2023-09-29, repo fpco/inline-c last pushed 2025-06-09, 306 stars, 16 open issues. Declared tested with GHC 9.2.8/9.4.7/9.6.2. In Stackage nightly and LTS.
ASSESS: Low-velocity but stable and in Stackage — the safest interop dependency of the three. Its Vector/ByteString marshalling contexts are exactly what a numeric toolkit needs for calling into C kernels. Risk is bus-factor, not brokenness; the toolkit should be prepared to vendor or co-maintain it.
EVID: https://hackage.haskell.org/package/inline-c ; https://github.com/fpco/inline-c ; https://www.stackage.org/nightly/package/inline-c-0.9.1.10

## inline-r (HaskellR) (Embed R — instant access to the entire CRAN statistics ecosystem)
STATUS: 1.0.2 uploaded 2025-07-11, maintainers Facundo Dominguez / Mathieu Boespflug / Roman Cheplyaka / Connor Baker (Tweag). Repo tweag/HaskellR pushed 2026-06-29, 587 stars. Hackage build status: 'All reported builds failed as of 2025-07-11' (PlanningFailed). NOT in Stackage LTS or nightly (404 in both).
ASSESS: Strategically the most under-rated interop option — CRAN is where the statistics actually lives, and inline-r's quasiquoter design is the model inline-python copied. But absence from Stackage plus failing Hackage builds means it cannot be a required dependency. Optional flag-gated integration only.
EVID: https://hackage.haskell.org/package/inline-r ; https://github.com/tweag/HaskellR ; https://www.stackage.org/nightly/package/inline-r

## inline-python (Embed CPython in Haskell — the pragmatic bridge to numpy/pandas/sklearn/matplotlib)
STATUS: 0.2.1.0 uploaded 2026-01-13, author/maintainer Aleksey Khudyakov, repo Shimuuar/inline-python pushed 2026-08-10 (actively developed), 18 stars. Quasiquotes ([pye|…|], [pycode|…|]), captures Haskell vars with _hs suffix, ToPy/FromPy instances incl. Complex, Text, ByteString, Maybe, Integer/Natural; Haskell functions callable FROM Python. Python >= 3.10. Depends on inline-c >= 0.9.1. CI matrix is Ubuntu-only, GHC 9.2.8–9.12.2, Python 3.10–3.14, discovered via `pkg-config python3-embed`. Source tree has NO numpy module. Not in Stackage.
ASSESS: By far the most alive interop project and explicitly modelled on HaskellR. Two blocking gaps for DS use: (1) no Windows or macOS CI at all, and pkg-config python3-embed is not how Python is found on Windows; (2) no numpy buffer-protocol / zero-copy array marshalling, so every array crosses as a Python list. Closing either would be a high-impact, well-scoped contribution and would give the toolkit an instant plotting + sklearn escape hatch.
EVID: https://hackage.haskell.org/package/inline-python ; https://github.com/Shimuuar/inline-python ; https://raw.githubusercontent.com/Shimuuar/inline-python/master/.github/workflows/ci.yml ; https://raw.githubusercontent.com/Shimuuar/inline-python/master/ChangeLog.md

## cpython (Raw bindings to the CPython 3 C API (CPython.Simple convenience layer))
STATUS: 3.9.0, uploaded 2024-07-08, maintainer Adam Zsigmond, repo zsedem/haskell-cpython last pushed 2025-01-20, 30 stars. README warns: the Python 3 C API is stable but the ABI is not — a binary compiled against 3.7.1 must run against 3.7.x. Not in Stackage.
ASSESS: Lower-level and less active than inline-python, and the ABI pinning makes redistributable binaries essentially impossible. Use inline-python (which does not depend on it) rather than this.
EVID: https://hackage.haskell.org/package/cpython ; https://github.com/zsedem/haskell-cpython

## DataHaskell/dataframe (mchav) (Incumbent pandas-equivalent — the direct competitor/collaborator for this project)
STATUS: 3.5.0.0 uploaded 2026-08-14, repo pushed 2026-08-14, 261 stars, MIT. GHC 9.4–9.12. Split into dataframe-core / -csv / -parquet / -learn / -viz (all uploaded 2026-08-06..14). Three API layers (untyped, type-level schema, monadic) over one runtime DataFrame; CSV/Parquet/JSON/TSV; typed expression DSL; lazy streaming engine with filter fusion, predicate pushdown and dead-column elimination; bitmap-backed nullability. Ships its OWN REPL (`dataframe` command, imports preloaded, :declareColumns macro), IHaskell notebook support, terminal plots (histogram/scatter/line/bar/box/pie/heatmap/corr-matrix) and interactive HTML plots. dataframe-learn: decision trees (TAO), feature synthesis, k-fold CV, stratified sampling. Docs at dataframe.readthedocs.io. In Stackage nightly. Was floated as a Haskell Foundation pre-proposal (discourse, 2024-12-07).
ASSESS: MOST IMPORTANT COMPETITIVE FACT of this survey. It already solves the exact onboarding problem the brief poses — one `cabal install dataframe` gives a preloaded REPL, notebook support and plots — and it is shipping weekly. A new toolkit must either (a) build on it / contribute the layers it lacks (real linear algebra, SIMD, GPU, publication-quality vector plots, GHC 9.14 support), or (b) articulate a sharply different thesis (e.g. static-shape tensors + ML, where dataframe-learn is thin). Duplicating its dataframe layer would be wasted effort.
EVID: https://hackage.haskell.org/package/dataframe ; https://github.com/DataHaskell/dataframe ; https://dataframe.readthedocs.io/en/latest/ ; https://discourse.haskell.org/t/pre-hftp-proposal-dataframe-library-for-haskell/10973 ; https://www.stackage.org/nightly/package/dataframe-3.5.0.0

## hmatrix (BLAS/LAPACK-backed linear algebra — the numpy.linalg equivalent)
STATUS: STALE. Latest Hackage upload 0.20.2 on 2021-03-08; repo haskell-numerics/hmatrix last pushed 2024-06-25, 398 stars, 72 open issues. Still carried in Stackage LTS 24.55 and nightly, so it builds on GHC 9.12. Windows requires OpenBLAS from MSYS2 (mingw-w64-clang-x86_64-openblas 0.3.33 built 2026-04, or ucrt64 0.3.32 built 2026-03) plus explicit --flag hmatrix:openblas and extra-include-dirs/extra-lib-dirs.
ASSESS: Five years without a release, yet it is the only mature dense linear algebra option and it still builds. The Windows story is the worst onboarding step in the entire stack — a pacman invocation plus two path flags that no first-time user will get right. Any serious toolkit either takes over hmatrix maintenance, vendors a BLAS build, or ships a pure-Haskell/SIMD fallback so the default install never touches native BLAS.
EVID: https://hackage.haskell.org/package/hmatrix ; https://github.com/haskell-numerics/hmatrix/blob/master/INSTALL.md ; https://packages.msys2.org/packages/mingw-w64-clang-x86_64-openblas ; https://www.stackage.org/lts-24.55/package/hmatrix-0.20.2

## MSYS2 / native dependency toolchain on Windows (How every C dependency (BLAS, zlib, zeromq, cairo, pango) actually reaches a Windows user)
STATUS: MSYS2 deprecated the MINGW64 environment on 2026-03-15; recommended default is now UCRT64 (GCC/UCRT/libstdc++). GHC has shipped CLANG64 (LLVM/Clang, UCRT, libc++) since 9.4.1, and Stack 3.11.1 changed its default to CLANG64. Cabal docs require setting extra-include-dirs / extra-lib-dirs to <msys-dir>\<environment>\{include,lib}; the ghcup bootstrap normally does this. Packages installed as mingw-w64-<env>-x86_64-<pkg> are invisible from a different environment. zlib >= 0.7 needs a real MSYS2 zlib or falls back to bundled sources.
ASSESS: The deepest structural gap for a Windows-first DS toolkit: Haskell has no wheel/conda equivalent, so every native dep is a manual pacman step in the *right* MSYS2 environment, and the ecosystem is mid-migration (MINGW64 deprecated, UCRT64 recommended for the world, CLANG64 used by GHC). Environment mismatch produces 'undecipherable errors' by Cabal's own admission. Design principle: the default install path must have ZERO native dependencies.
EVID: https://www.msys2.org/docs/environments/ ; https://cabal.readthedocs.io/en/stable/how-to-run-in-windows.html ; https://discourse.haskell.org/t/ann-stack-3-11-1/14272 ; https://github.com/commercialhaskell/stack/issues/6557

## hasktorch / accelerate (GPU + deep learning) (Existing ML/GPU capability to interoperate with rather than rebuild)
STATUS: hasktorch 0.2.2.0 Hackage 2026-05-04, repo pushed 2026-07-28, 1211 stars, 90 open issues — and it IS in Stackage nightly 2026-08-16. accelerate Hackage 2026-04-02 but absent from Stackage LTS and nightly (404 both).
ASSESS: hasktorch being in Stackage nightly is a meaningful upgrade in its status and makes it the credible deep-learning tier; it wraps libtorch, so it re-imports the native-dependency problem. accelerate's absence from any snapshot signals fragility. Neither should be a required dependency; both are integration targets.
EVID: https://www.stackage.org/nightly/package/hasktorch-0.2.2.0 ; https://hackage.haskell.org/package/accelerate ; https://github.com/hasktorch/hasktorch

# sources
https://www.haskell.org/ghc/
https://endoflife.date/api/v1/products/ghc/
https://downloads.haskell.org/ghc/
https://discourse.haskell.org/t/2026-06-09-informal-ghc-release-status-update-of-a-sort/14250
https://discourse.haskell.org/t/ghc-9-14-2-rc1-is-now-available/14490
https://ghc.gitlab.haskell.org/ghc/doc/users_guide/9.16.1-notes.html
https://downloads.haskell.org/ghc/latest/docs/users_guide/9.14.1-notes.html
https://minoki.github.io/posts/2025-01-13-ghc-simd.html
https://minoki.github.io/posts/2025-01-06-ghc-llvm-backend.html
https://ghc.gitlab.haskell.org/ghc/doc/users_guide/exts/overloaded_record_update.html
https://downloads.haskell.org/ghc/latest/docs/users_guide/exts/linear_types.html
https://ghc.serokell.io/dh
https://ghc.gitlab.haskell.org/ghc/doc/users_guide/exts/required_type_arguments.html
https://ghc.gitlab.haskell.org/ghc/doc/users_guide/wasm.html
https://discourse.haskell.org/t/javascript-webassembly-backend/6787
https://raw.githubusercontent.com/haskell/ghcup-metadata/master/ghcup-0.1.0.yaml
https://raw.githubusercontent.com/haskell/ghcup-metadata/master/ghcup-cross-0.1.0.yaml
https://github.com/haskell/ghcup-hs/releases
https://www.haskell.org/ghcup/install/
https://www.haskell.org/ghcup/guide/
https://github.com/haskell/cabal/releases
https://discourse.haskell.org/t/cabal-3-18-1-0-released/14556
https://cabal.readthedocs.io/en/latest/cabal-commands.html
https://cabal.readthedocs.io/en/stable/how-to-run-in-windows.html
https://discourse.haskell.org/t/ann-stack-3-11-1/14272
https://github.com/commercialhaskell/stack/releases
https://github.com/commercialhaskell/stack/issues/6557
https://www.msys2.org/docs/environments/
https://www.stackage.org/snapshots
https://www.stackage.org/nightly
https://www.stackage.org/lts-24.55
https://www.stackage.org/blog
https://discourse.haskell.org/t/state-of-haskell-2025-results/13755
https://docs.google.com/spreadsheets/d/e/2PACX-1vSnlNIbbiAGv8ERkYJq7vGt391kM7XsHhllKGmTt9PPZOLnEVtdlSznf6A9vI5wJJNRcfH6HgLvgRLE/pub?output=csv
https://haskell-language-server.readthedocs.io/en/latest/support/ghc-version-support.html
https://github.com/haskell/haskell-language-server/releases
https://blog.haskell.org/hls-2-14-0-0/
https://github.com/IHaskell/IHaskell
https://raw.githubusercontent.com/IHaskell/IHaskell/master/README.md
https://github.com/IHaskell/IHaskell/pull/1595
https://hackage.haskell.org/package/ihaskell
https://hackage.haskell.org/package/hvega
https://github.com/DougBurke/hvega
https://github.com/vega/vega-lite/releases
https://hackage.haskell.org/package/Chart
https://hackage.haskell.org/package/Chart-diagrams
https://github.com/timbod7/haskell-chart
https://wiki.haskell.org/Diagrams/Install/Install-cairo
https://hackage.haskell.org/package/chart-svg
https://github.com/tonyday567/chart-svg
https://hackage.haskell.org/package/diagrams-lib
https://github.com/diagrams/diagrams
https://hackage.haskell.org/package/gnuplot
https://hackage.haskell.org/package/matplotlib
https://github.com/abarbu/matplotlib-haskell
https://github.com/benl23x5/gloss
https://hackage.haskell.org/package/inline-c
https://github.com/fpco/inline-c
https://hackage.haskell.org/package/inline-r
https://github.com/tweag/HaskellR
https://hackage.haskell.org/package/inline-python
https://github.com/Shimuuar/inline-python
https://raw.githubusercontent.com/Shimuuar/inline-python/master/.github/workflows/ci.yml
https://raw.githubusercontent.com/Shimuuar/inline-python/master/ChangeLog.md
https://hackage.haskell.org/package/cpython
https://github.com/zsedem/haskell-cpython
https://hackage.haskell.org/package/dataframe
https://github.com/DataHaskell/dataframe
https://dataframe.readthedocs.io/en/latest/
https://discourse.haskell.org/t/pre-hftp-proposal-dataframe-library-for-haskell/10973
https://hackage.haskell.org/package/hmatrix
https://github.com/haskell-numerics/hmatrix/blob/master/INSTALL.md
https://packages.msys2.org/packages/mingw-w64-clang-x86_64-openblas
https://hackage.haskell.org/package/primitive-simd
https://github.com/ajscholl/primitive-simd
https://github.com/mikeizbicki/simd
https://www.well-typed.com/blog/2026/06/haskell-ecosystem-report-march-may-2026/
https://github.com/hasktorch/hasktorch
https://hackage.haskell.org/package/accelerate
https://github.com/vega/vl-convert