# digest
VERIFIED 2026-08-17. Headline: the "no sklearn in Haskell" premise is NEWLY FALSE. `dataframe-learn` 2.4.1.0 (uploaded 2026-08-14, MIT) ships LinearModel.Regression/Logistic, SVM(+RFF), DecisionTree(+Regression), PCA(+Kernel), KMeans, DBSCAN, GMM, Boosting.GBM, Boosting.AdaBoost, SymbolicRegression, ModelSelection, Metrics(+Report), Synthesis, Segmented — module list read verbatim from dataframe-learn.cabal. It is PURE HASKELL: build-depends = base, aeson, containers, parallel, random, text, vector, dataframe-{core,operations,expr-serializer}. No hmatrix, no BLAS/LAPACK, no C deps. Its test suite contains `Learn.SklearnParity` and `Learn.Metamorphic` — parity vs scikit-learn is actually asserted. Parent `dataframe` 3.5.0.0 (2026-08-14), 261 stars, 1267 commits, commits daily, tested GHC 9.4.8/9.6.7/9.8.4/9.10.3/9.12.2. Risk: ONE maintainer (Michael Chavinda), rapid major-version churn (3.x / 2.x), CI Linux-only.

hasktorch: ALIVE and the strongest DL option. 0.2.2.0 on Hackage 2026-05-04; GitHub 4522 commits, 1.2k stars, commits 2026-07-28 (vmap/vmap2/vscan, PureGenerator, GHC 9.12 nix). libtorch-ffi 2.0.2.0 binds libtorch 2.5.0 default, cu117/cu118/cu121; auto-downloads libtorch binaries. Typed + untyped tensors. BUT: CI workflows are cabal/stack/nix on Linux+macOS only — NO Windows workflow, and upstream states it supports only OSX and Linux. HARD BLOCKER for a Windows 11 dev machine (WSL2/Docker required).

Autodiff three-way: `ad` 4.5.6 (Hackage 2024-05-01, commits 2026-01-20, Kmett) — mature, general, but scalar/Traversable-shaped, not array-efficient. `backprop` 0.2.7.2 (2025-06-05, Justin Le) — heterogeneous reverse-mode BVar graphs, stable, composes with hmatrix/vector-sized, but ops need manual lifting; low activity. `horde-ad` 0.3.0.0 (Hackage 2026-04-14, commits 2026-08-12, 6163 commits, only 46 stars, GHC 9.10.3/9.12.4/9.14.1) — array-level, generates symbolic derivative programs, claims CPU-competitive vs ad/backprop, supports FC/RNN/CNN/ResNet, but README self-describes as "an early prototype", "not recommended for production", "will fail on cases not found in current tests".

Stats core is healthy, all under Alexey Khudyakov: statistics 0.16.5.0 (2026-01-09, commits 2026-06-23), mwc-random 0.15.3.0 (2025-12-30), math-functions 0.3.4.4 (2024-03-30). random 1.3.1 (2025-04-04, CLC-maintained). monad-bayes 1.3.0.5 (2025-10-07, Tweag) — repo commits 2026-08-17 but nearly all bot flake.lock bumps.

DEAD/stale: grenade (Hackage 0.1.0 2017-04-12, last commit 2023-12-08), neural 0.3.0.1 (2017-07-27), mltool 0.2.0.1 (2018-06-10), Learning 0.1.0 (2018-02-26), xgboost-haskell 0.1.0.0 (2017-10-19), hmatrix-gsl 0.19.0.1 (2018-04-22). hmatrix 0.20.2 dates to 2021-03-08, last commit 2024-02-21, 69 open issues, and needs OpenBLAS via MSYS2 on Windows (PR #147: "OpenBLAS building on Windows is not working") — a liability, not a foundation.

ONNX: hs-onnxruntime-capi 0.1.0.0 (2025-07-24, GHC 9.6.7–9.12.2) exists but is AGPL-3.0-only — license-incompatible with a permissive toolkit. menoh is abandoned.

Coordination: DataHaskell roadmap v1.0 (Nov 2026 → Q4 2027) already names dataframe + Hasktorch + distributed-process as pillars, with "unified ML library" and "dataframe-to-Hasktorch integration" as explicit workstreams; self-identified gaps are maintainers, viz, docs, deployment. A prior DataHaskell attempt stalled on "too ambitious roadmaps".

# key_insights
- The single biggest strategic fact: the classical-ML gap closed in 2026 — dataframe-learn 2.4.1.0 (2026-08-14) is a pure-Haskell, MIT, actively-developed sklearn analogue with regression, logistic, SVM, decision trees, GBM, AdaBoost, KMeans, DBSCAN, GMM, PCA/kernel-PCA and cross-validation, and it tests itself for scikit-learn parity — so building a fresh sklearn clone would duplicate live work rather than fill a hole.
- A new toolkit's highest-leverage position is integration and the layers nobody owns (visualization, model serialization/serving, ONNX interop under a permissive license, a dataframe-to-hasktorch bridge), not re-implementing estimators that now exist.
- hasktorch is a genuinely usable DL foundation in 2026 — active weekly commits, libtorch 2.5.0, typed and untyped tensors, CUDA, auto-downloaded binaries — but it has no Windows support at all, which is a hard blocker on the user's Windows 11 machine and forces WSL2, Docker, or Linux/macOS.
- Windows is a systematic ecosystem-wide weakness: not one surveyed project (hasktorch, dataframe, hmatrix) runs Windows CI, so a toolkit that promises Windows support must own that testing itself — though the pure-Haskell layers (dataframe-learn, statistics, massiv, vector) have no C dependencies and should port cleanly.
- hmatrix is the wrong foundation for anything new: last release 2021-03-08, last commit 2024-02-21, 69 open issues, and a documented broken OpenBLAS build on Windows — prefer vector/massiv for pure-Haskell numerics or hasktorch tensors for accelerated work.
- Autodiff has no single winner: use backprop for stable typed reverse-mode over existing Haskell types today, ad for generic scalar/forward-mode work, and treat horde-ad as the research bet on array-level AD that its own README calls an early prototype unsuitable for production.
- If a toolkit builds on hasktorch it inherits libtorch's autograd for free, which is often the pragmatic answer that sidesteps the ad-vs-backprop-vs-horde-ad choice entirely for deep learning workloads.
- Bus factor is the ecosystem's dominant systemic risk — dataframe rests on one person, statistics/math-functions/mwc-random all on Alexey Khudyakov, horde-ad on Mikolaj Konarski — so a new project's durable contribution may be maintenance capacity and CI rather than novel code.
- The AGPL-3.0-only license on hs-onnxruntime-capi makes it unusable inside a permissively-licensed toolkit, leaving a clean opening for permissive ONNX Runtime bindings as a well-scoped, high-value first deliverable.
- DataHaskell already has a published roadmap (v1.0 Nov 2026, targeting Q4 2027) naming the same three pillars a new toolkit would want, so the project should decide deliberately whether to join that effort or compete — and note their predecessor stalled from over-ambitious scope.
- dataframe's rapid major-version churn (dataframe 3.5.0.0 against dataframe-learn 2.4.1.0) means any dependency on it needs tight version bounds and a tolerance for API breakage.
- grenade, neural, mltool, Learning, and xgboost-haskell are all effectively dead (newest Hackage upload 2018) and should be treated as reference reading or salvage material, never as dependencies.

# libraries

## dataframe-learn (Pure-Haskell scikit-learn analogue: linear/logistic regression, SVM (+random Fourier features), decision trees (classification + regression), GBM, AdaBoost, KMeans, DBSCAN, GMM, PCA + kernel PCA, symbolic regression, model selection/CV, metrics + reports, feature synthesis)
STATUS: ACTIVELY DEVELOPED. v2.4.1.0 uploaded 2026-08-14 (three days ago). MIT. tested-with GHC ==9.4.8 || ==9.6.7 || ==9.8.4 || ==9.10.3 || ==9.12.2. Maintainer mchav (Michael Chavinda). Part of the dataframe multi-package split.
ASSESS: STRENGTH: this single package invalidates the premise that Haskell lacks a classical-ML layer. Crucially it is pure Haskell — build-depends is base, aeson, containers, parallel, random, text, vector, dataframe-{core,operations,expr-serializer}, with NO hmatrix/BLAS/LAPACK — so it is portable to Windows without a C toolchain. The parent test suite includes Learn.SklearnParity and Learn.Metamorphic, meaning scikit-learn agreement is an asserted invariant, not a marketing claim. WEAKNESS: single maintainer (bus factor 1); version churn implies an unstable API; CI is Linux-only; pure-Haskell numerics without BLAS will lose badly to sklearn on large dense problems. FIT: the natural partner or upstream for a new toolkit — contribute here rather than reimplement.
EVID: https://hackage.haskell.org/package/dataframe-learn ; https://hackage.haskell.org/package/dataframe-learn-2.4.1.0/dataframe-learn.cabal

## dataframe (Pandas/Polars-style DataFrame: CSV/Parquet/JSON I/O, typed expression DSL, groupby/join/window, columnar storage with bitmap nullability, three API layers (untyped, typed, monadic), terminal + HTML plotting, descriptive statistics)
STATUS: VERY ACTIVE. v3.5.0.0 uploaded 2026-08-14. 261 stars, 1267 commits, near-daily commits through 2026-08-14 (memory-pressure work, Int32 packed-text offsets). MIT. GHC 9.4–9.12. Maintainer mchav.
ASSESS: STRENGTH: the pandas-equivalent tier of the stack, and it is the most actively developed data-science package in Haskell right now; subject of a Haskell Foundation tech proposal and a named DataHaskell pillar. WEAKNESS: single maintainer; major version 3.x after ~20 months implies aggressive breaking changes; Linux-only CI; Parquet/Arrow paths add dependency weight. FIT: the obvious data-ingestion and tabular substrate for a new toolkit — depend on it with tight bounds, or coordinate directly with mchav.
EVID: https://hackage.haskell.org/package/dataframe ; https://github.com/mchav/dataframe ; https://api.github.com/repos/mchav/dataframe/commits

## hasktorch (Haskell bindings to PyTorch's libtorch C++ library; typed and untyped tensors, autograd, NN layers, optimizers, CUDA and Apple MPS backends)
STATUS: ACTIVE AND HEALTHY. Hackage 0.2.2.0 uploaded 2026-05-04. GitHub: 4522 commits, 1.2k stars, most recent commits 2026-07-28 (vmap/vmap2/vscan in Torch.Typed.Representable, value-threaded PureGenerator + multinomial sampling, nix GHC 9.12 support via PR #796). Depends on libtorch-ffi >=2.0.2.0 && <2.0.3 and template-haskell >=2.20.0 && <2.24. libtorch-ffi 2.0.2.0 (2026-05-04) defaults to libtorch 2.5.0, overridable via LIBTORCH_VERSION, with cu117/cu118/cu121 variants. CI: cabal-linux (GHC 9.8.4), cabal-macos, stack-linux, stack-macos, nix-linux, cabal-linux-gpu.
ASSESS: ANSWER TO Q2: usable, not too fragile — this is no longer the flaky research toy it was around 2019-2021. It tracks a modern libtorch (2.5.0), gets real feature work (vmap in July 2026), auto-downloads libtorch binaries so there is no manual C++ install, and gives you GPU plus a battle-tested autograd engine for free. STRENGTHS: only credible route to GPU deep learning in Haskell; typed tensor API is a genuine differentiator over Python; Nix/Docker/JupyterLab paths exist. WEAKNESSES: NO WINDOWS SUPPORT — there is no Windows CI workflow and upstream says it supports only OSX and Linux; heavyweight FFI build; narrow tested GHC window (CI pins 9.8.4, nix reaching 9.12); documented CUDA tensor-movement and MPS-fallback issues; no tested-with field in the cabal file. FIT: adopt as the optional DL/accelerator backend behind an abstraction, never as the mandatory core, and plan WSL2/Docker for the Windows dev machine.
EVID: https://hackage.haskell.org/package/hasktorch ; https://github.com/hasktorch/hasktorch ; https://api.github.com/repos/hasktorch/hasktorch/commits ; https://hackage.haskell.org/package/libtorch-ffi ; https://api.github.com/repos/hasktorch/hasktorch/contents/.github/workflows

## horde-ad (Higher-Order Reverse Derivatives Efficiently — array-oriented automatic differentiation that generates symbolic derivative programs; supports fully-connected, recurrent, convolutional and residual network architectures)
STATUS: ACTIVE RESEARCH. Hackage 0.3.0.0 uploaded 2026-04-14; GitHub commits as recent as 2026-08-12; 6163 commits but only 46 stars, 6 forks. GHC 9.10.3 / 9.12.4 / 9.14.1, base >=4.20.1 && <4.23. Maintainers Mikolaj Konarski and tomsmeding.
ASSESS: The most technically ambitious AD in Haskell and the only one designed around ARRAY operations rather than scalars, which is exactly what ML gradients need; README claims benchmarks competitive with ad and backprop on CPU. But it self-describes as 'an early prototype' in engine performance, API design and tooling, warns it 'will fail on cases not found in current tests' and that users must add missing primitives themselves, and is explicitly NOT recommended for production. Supports only a narrowly typed class of source programs with limited higher-orderness. Tracks the newest GHCs (uniquely, 9.14.1). FIT: the right long-term research bet and worth prototyping against, but not a foundation to ship a v1 toolkit on; a 46-star, effectively-one-maintainer project is a serious dependency risk.
EVID: https://hackage.haskell.org/package/horde-ad ; https://github.com/Mikolaj/horde-ad ; https://api.github.com/repos/Mikolaj/horde-ad/commits

## backprop (Heterogeneous reverse-mode automatic differentiation via explicit BVar computation graphs; you write the forward function and it derives the gradient)
STATUS: MATURE, LOW ACTIVITY. v0.2.7.2 uploaded 2025-06-05. base >=4.7 && <5. Maintainer Justin Le (justin@jle.im).
ASSESS: ANSWER TO Q3 (pragmatic pick): the most production-appropriate AD in Haskell today. Stable, well-documented, still receiving releases in 2025, and it composes with existing types (hmatrix matrices, vector-sized) rather than demanding you rewrite numerics into its own array language. WEAKNESS: operations must be manually lifted into BVar form, so coverage is whatever you or upstream wrote; performance is good but not array-fused; development is slow. FIT: the safest autodiff foundation for a new toolkit's CPU/pure-Haskell path — use backprop now, watch horde-ad, and let hasktorch's libtorch autograd cover the GPU path.
EVID: https://hackage.haskell.org/package/backprop

## ad (General-purpose automatic differentiation — forward, reverse, and mixed mode; Taylor towers; sparse and dense modes over Traversable structures)
STATUS: MAINTAINED BUT SLOW. v4.5.6 uploaded 2024-05-01; GitHub commits 2026-01-20 ('copyright bump', 'add AdditionalTests') and 2025-03-03 ('Regenerate CI'). base >=4.9 && <5. Maintainers Edward Kmett, Eric Mertens, Ryan Scott.
ASSESS: The most mathematically general and battle-hardened AD in the ecosystem, with a maintainer team rather than a single person — the lowest bus-factor risk of the three. But it is architected for scalar and Traversable-shaped problems, so it does not vectorize over tensors and will not deliver competitive ML training performance. Recent commits are housekeeping, not feature work. FIT: correct choice for optimization, root-finding, scientific computing and gradient checks inside a toolkit; wrong choice as the engine for neural-network training.
EVID: https://hackage.haskell.org/package/ad ; https://api.github.com/repos/ekmett/ad/commits

## statistics (Statistical distributions, hypothesis tests, resampling/bootstrap, regression, correlation, quantiles, kernel density estimation, histograms)
STATUS: HEALTHY. v0.16.5.0 uploaded 2026-01-09; repo commits 2026-06-23 ('Allow doctest-0.25'), 2026-02-25, 2026-01-31 (Kruskal-Wallis NaN fix). Maintainer Alexey Khudyakov. Depends on vector, mwc-random >=0.15.3.0, math-functions >=0.3.4.1.
ASSESS: Genuinely maintained, correctness-focused (recent commits are real bug fixes such as the Kruskal-Wallis identical-sample NaN failure), and explicitly targets 'high performance, numerical robustness, and use of good algorithms'. Pure Haskell on top of vector, so it is Windows-portable. WEAKNESS: coverage is narrower than scipy.stats; single maintainer who also carries math-functions and mwc-random — one person is the load-bearing pillar of Haskell numerics. FIT: adopt directly as the stats layer; there is no reason to reimplement it.
EVID: https://hackage.haskell.org/package/statistics ; https://api.github.com/repos/haskell/statistics/commits

## mwc-random (High-quality, fast pseudo-random number generation (Marsaglia MWC256) plus sampling from common distributions)
STATUS: HEALTHY. v0.15.3.0 uploaded 2025-12-30. Maintainer Alexey Khudyakov (orig. Bryan O'Sullivan).
ASSESS: Fast, well-established, and the de-facto RNG for numerical work; a required dependency of both statistics and monad-bayes so it is not going away. Pure Haskell, no C deps, portable. FIT: use for sampling-heavy paths (bootstrap, MCMC, stochastic optimizers, minibatch shuffling).
EVID: https://hackage.haskell.org/package/mwc-random

## random (Standard-library random number generation interface (RandomGen/StatefulGen))
STATUS: HEALTHY. v1.3.1 uploaded 2025-04-04. Maintained by the Core Libraries Committee (core-libraries-committee@haskell.org) with lehins, Bodigrim, DominicSteinitz, topos.
ASSESS: The lowest-risk dependency in the whole survey — committee-maintained, not person-maintained. The modern 1.2+/1.3 API with StatefulGen is a real improvement and interoperates with mwc-random. FIT: use random for the public API surface and mwc-random where throughput matters; dataframe-learn already depends on random.
EVID: https://hackage.haskell.org/package/random

## monad-bayes (Probabilistic programming: monadic inference with importance sampling, SMC, MCMC, RM-SMC, particle filters)
STATUS: MAINTAINED, LOW SUBSTANTIVE ACTIVITY. v1.3.0.5 uploaded 2025-10-07. Repo commits dated 2026-08-17/2026-08-16/2026-08-10 but these are automated flake.lock nixpkgs bumps by github-actions[bot] plus merges by Manuel Bärenz, not feature work. Maintainer dominic.steinitz@tweag.io (Tweag).
ASSESS: Intellectually the strongest showcase of what Haskell offers that Python does not — composable inference transformers with real type safety, backed by peer-reviewed research and corporate (Tweag) sponsorship. WEAKNESS: recent repo activity is dependency-bot noise, so read it as stable-but-coasting rather than growing; heavy dependency footprint (brick, vty, lens, pipes, log-domain) is odd for a library and will bloat a toolkit. FIT: an excellent optional Bayesian/PPL module, and a differentiator worth featuring, but pin it carefully and do not put it on the core dependency path.
EVID: https://hackage.haskell.org/package/monad-bayes ; https://api.github.com/repos/tweag/monad-bayes/commits

## hmatrix (Purely functional interface to linear algebra — LAPACK/BLAS-backed matrices, decompositions (SVD, QR, Cholesky, eigen), linear solvers, plus GSL/GLPK extras)
STATUS: SEMI-DORMANT. Latest release 0.20.2 uploaded 2021-03-08 (no newer version; a 2023-01-09 metadata revision only). Last repo commit 2024-02-21. 398 stars, 69 open issues, 3 open PRs. Maintainer Dominic Steinitz / Alberto Ruiz. Flags: openblas, disable-default-paths, no-random_r.
ASSESS: The historical de-facto numpy-equivalent and still what grenade and much older code build on — but a five-year-old release with 69 open issues is a liability, not a foundation. Critically for this project, Windows is its worst platform: it requires linking OpenBLAS import libraries via MSYS2, and PR #147 is titled 'Currently OpenBLAS building on Windows is not working'. FIT: AVOID as a hard dependency. Note that dataframe-learn deliberately does not depend on it. If BLAS-class performance is eventually required, plan a pluggable backend rather than baking hmatrix in.
EVID: https://hackage.haskell.org/package/hmatrix ; https://hackage.haskell.org/package/hmatrix-0.20.2 ; https://api.github.com/repos/haskell-numerics/hmatrix/commits ; https://github.com/haskell-numerics/hmatrix/pull/147

## hmatrix-gsl (GNU Scientific Library bindings — special functions, numerical integration, ODE solving, optimization, root finding)
STATUS: STALE. v0.19.0.1 uploaded 2018-04-22. Maintainers Alberto Ruiz, Dominic Steinitz.
ASSESS: Eight years without a release, and it inherits every hmatrix problem plus a hard GSL C dependency that is genuinely painful to satisfy on Windows. FIT: do not depend on it. If special functions are needed, math-functions covers much of the ground in pure Haskell and is maintained.
EVID: https://hackage.haskell.org/package/hmatrix-gsl

## massiv (Multi-dimensional arrays with fusion, stencils, and automatic parallel computation)
STATUS: MAINTAINED. v1.0.5.0 uploaded 2025-05-31. Maintainer Alexey Kuleshevich.
ASSESS: The best pure-Haskell n-dimensional array library — stable at 1.0, real fusion, effortless parallelism, delayed/manifest representation distinction, and no C toolchain requirement so it builds anywhere including Windows. WEAKNESS: no BLAS-level GEMM performance and no GPU. FIT: a strong candidate for the toolkit's CPU tensor/array substrate, pairing with vector, and a much safer base than hmatrix.
EVID: https://hackage.haskell.org/package/massiv

## vector (Efficient boxed/unboxed/storable arrays with stream fusion — the foundational numeric container type)
STATUS: HEALTHY. v0.13.2.0 uploaded 2024-10-31. Maintained by the Haskell Libraries Team with Alexey Kuleshevich, Aleksey Khudyakov, Andrew Lelechenko.
ASSESS: Committee/team-maintained bedrock that statistics, dataframe-learn, massiv and nearly everything else already depend on. Zero adoption risk. FIT: unavoidable and correct — build on it.
EVID: https://hackage.haskell.org/package/vector

## grenade (Dependently-typed, composable neural network library with type-level-checked layer shapes (CNNs, RNNs))
STATUS: DORMANT. Hackage 0.1.0 uploaded 2017-04-12 (only 1,237 total downloads). GitHub last commits 2023-12-08 ('bump/adjust all bounds', README fixes) — 1.4k stars, 201 commits, 18 open issues, 6 open PRs, Travis CI badge. No archived/deprecated notice. Maintainers Huw Campbell, Erik de Castro Lopo.
ASSESS: The most-starred Haskell NN library and still the canonical demonstration that type-level shape checking catches dimension errors at compile time (README cites ~1.5% MNIST error, 12 minutes single-core). But Hackage has been frozen since 2017, GitHub has been quiet for over two and a half years, and it sits on the stale hmatrix. FIT: study its type-level layer-composition API as design inspiration — that idea is worth carrying forward — but do not depend on it.
EVID: https://hackage.haskell.org/package/grenade ; https://github.com/HuwCampbell/grenade ; https://api.github.com/repos/HuwCampbell/grenade/commits

## neural (Neural networks in native Haskell with a compositional/categorical API)
STATUS: DEAD. v0.3.0.1 uploaded 2017-07-27. Maintainer Lars Bruenjes.
ASSESS: Nine years stale. Of historical interest only. FIT: ignore.
EVID: https://hackage.haskell.org/package/neural

## mltool (Machine Learning Toolbox — linear/logistic regression, SVM, neural networks, softmax/multi-SVM classifiers, PCA, K-Means)
STATUS: DEAD. v0.2.0.1 uploaded 2018-06-10. Maintainer aignatyev17.
ASSESS: Until 2026 this was the closest thing Haskell had to a classical-ML toolkit, and it has been untouched for eight years — a useful illustration of why the sklearn gap was real. It is now superseded by dataframe-learn, which covers a strict superset (adds DBSCAN, GMM, boosting, kernel PCA, model selection, metrics) and is actively maintained. FIT: ignore, except as evidence of prior art.
EVID: https://hackage.haskell.org/package/mltool

## Learning (Micro-library of common ML tools — supervised learning, evaluation metrics, PCA)
STATUS: DEAD. v0.1.0 uploaded 2018-02-26. Maintainer Bogdan Penkovsky.
ASSESS: Tiny and abandoned for eight years; its own docs point users to mltool as the fuller option. FIT: ignore.
EVID: https://hackage.haskell.org/package/Learning

## xgboost-haskell (FFI bindings to the XGBoost gradient-boosting library, built on foundation)
STATUS: DEAD. v0.1.0.0 uploaded 2017-10-19. MIT. Maintainer sighingnow (Tao He).
ASSESS: Nine years stale and built on the unusual `foundation` prelude. There is also a LightGBM Haskell wrapper described in a community blog post but it is not on Hackage. Gradient boosting is now served natively by DataFrame.Boosting.GBM and DataFrame.Boosting.AdaBoost in dataframe-learn, in pure Haskell. FIT: ignore the bindings; if XGBoost/LightGBM-class performance is ever needed, fresh FFI bindings would be a well-scoped contribution.
EVID: https://hackage.haskell.org/package/xgboost-haskell

## hs-onnxruntime-capi (Low-level Haskell bindings to the ONNX Runtime C API for cross-framework model inference)
STATUS: EARLY, LICENSE-CONSTRAINED. v0.1.0.0 uploaded 2025-07-24. Supports GHC 9.6.7 through 9.12.2. Licensed AGPL-3.0-only. Maintainer Wen Kokke.
ASSESS: The only current ONNX Runtime binding, and it would be the cheapest route to running models trained anywhere else (PyTorch, sklearn via skl2onnx) inside Haskell — a genuinely valuable capability for a toolkit that cannot match Python's training ecosystem. BLOCKER: AGPL-3.0-only is incompatible with a permissively licensed (MIT/BSD) toolkit and would virally constrain downstream users. It is also 0.1.0.0 and low-level C API only, with no idiomatic wrapper. FIT: do not depend on it; permissively-licensed ONNX Runtime bindings are one of the clearest unclaimed high-value niches in the ecosystem.
EVID: https://hackage.haskell.org/package/hs-onnxruntime-capi

## menoh (Haskell binding to the Menoh MKL-DNN-based DNN inference library for ONNX models (VGG16 example included))
STATUS: ABANDONED. pfnet-research project; upstream Menoh itself is no longer developed.
ASSESS: Dead end — the underlying Menoh C++ library is itself defunct, so the binding cannot be revived meaningfully. FIT: ignore.
EVID: https://hackage.haskell.org/package/menoh ; https://github.com/pfnet-research/menoh-haskell

## math-functions (Special mathematical functions (gamma, beta, erf, incomplete functions) and numeric utilities underpinning the statistics package)
STATUS: STABLE, QUIET. v0.3.4.4 uploaded 2024-03-30. Maintainer Alexey Khudyakov (orig. Bryan O'Sullivan).
ASSESS: Mature and largely feature-complete for its scope, so a two-year gap since release is less alarming here than elsewhere; it is a required dependency of statistics and is pure Haskell. Concentrates further risk on Khudyakov, who maintains this plus statistics plus mwc-random. FIT: adopt transitively via statistics; a useful place to contribute if the toolkit needs additional special functions.
EVID: https://hackage.haskell.org/package/math-functions

# sources
https://hackage.haskell.org/package/hasktorch
https://github.com/hasktorch/hasktorch
https://api.github.com/repos/hasktorch/hasktorch/commits
https://api.github.com/repos/hasktorch/hasktorch/contents/.github/workflows
https://hackage.haskell.org/package/hasktorch-0.2.2.0/hasktorch.cabal
https://hackage.haskell.org/package/libtorch-ffi
https://hackage.haskell.org/package/dataframe
https://hackage.haskell.org/package/dataframe-3.5.0.0/dataframe.cabal
https://hackage.haskell.org/package/dataframe-learn
https://hackage.haskell.org/package/dataframe-learn-2.4.1.0/dataframe-learn.cabal
https://github.com/mchav/dataframe
https://api.github.com/repos/mchav/dataframe/commits
https://api.github.com/repos/mchav/dataframe/contents/.github/workflows
https://raw.githubusercontent.com/mchav/dataframe/main/.github/workflows/ci.yml
https://raw.githubusercontent.com/mchav/dataframe/main/.github/workflows/haskell-ci.yml
https://discourse.haskell.org/t/pre-hftp-proposal-dataframe-library-for-haskell/10973
http://www.datahaskell.org/docs/community/roadmap.html
https://hackage.haskell.org/package/ad
https://api.github.com/repos/ekmett/ad/commits
https://hackage.haskell.org/package/backprop
https://hackage.haskell.org/package/horde-ad
https://github.com/Mikolaj/horde-ad
https://api.github.com/repos/Mikolaj/horde-ad/commits
https://hackage.haskell.org/package/statistics
https://api.github.com/repos/haskell/statistics/commits
https://hackage.haskell.org/package/math-functions
https://hackage.haskell.org/package/mwc-random
https://hackage.haskell.org/package/random
https://hackage.haskell.org/package/monad-bayes
https://api.github.com/repos/tweag/monad-bayes/commits
https://hackage.haskell.org/package/hmatrix
https://hackage.haskell.org/package/hmatrix-0.20.2
https://api.github.com/repos/haskell-numerics/hmatrix/commits
https://github.com/haskell-numerics/hmatrix/pull/147
https://hackage.haskell.org/package/hmatrix-gsl
https://hackage.haskell.org/package/massiv
https://hackage.haskell.org/package/vector
https://hackage.haskell.org/package/grenade
https://github.com/HuwCampbell/grenade
https://api.github.com/repos/HuwCampbell/grenade/commits
https://hackage.haskell.org/package/neural
https://hackage.haskell.org/package/mltool
https://hackage.haskell.org/package/Learning
https://hackage.haskell.org/package/xgboost-haskell
https://hackage.haskell.org/package/hs-onnxruntime-capi
https://github.com/pfnet-research/menoh-haskell
https://www.haskell.org/ghc/
https://downloads.haskell.org/ghc/9.14.1-alpha1/docs/users_guide/9.14.1-notes.html