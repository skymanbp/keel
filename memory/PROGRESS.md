# PROGRESS — HSDS

*Generated: 2026-08-18T10:02:33* · via stop · D:\Projects\HSDS

> SINGLE SOURCE OF TRUTH for session handoff. Always full-rewrite from SQLite
> table `progress`. **Never append. Never patch by hand.**

## 0. Session

🟢 **Current session**: `#f627a4e5`  ·  started `2026-08-18 02:06`  ·  last write `2026-08-18 10:02`  ·  trigger `stop`

> If your Claude session ID does NOT start with `f627a4e5`, this row was written by a different session — treat the §3 todos / §6 files as that session's work, not yours.

*(no prior compacted sessions yet)*

## 1. Current Request

本仓库用于开发Haskell语言专用Data Science / Machine Learning工具包，旨在让Haskell也能拥有强大的DS/ML开发能力。包本身语言为纯英文。你来进行调研、思考、比对、设计，给出详细完整的多步骤计划。

## 2. Status

**Done** —    DataFrame PR not required—four capability packages (keel-dyn, keel-abi, keel-onnx, keel-linalg) have zero upstream dependencies; dataframe-core is a standard Hackage library dependency only in keel umbrella package.; Upstream PR track (steps #1 CI PR and #9 PR group) removed from plan; 3 Windows test bugs discovered in fork CI will be filed as separate DataHaskell/dataframe issues, not blocking keel.; Fork CI (skymanbp/dataframe run 32095552668) final result: 4/4 builds green; Windows tests: 3 named upstream bugs (tmp hardcoding, CRLF×2, quote boundary) caught; macOS tests all green.; Release strategy: build all five packages locally (Windows primary validation), then single publish batch (Hackage 0.1 + Stackage nightly); no incremental upstream PRs.

**In-flight** — Local development plan now 10 steps: P0 proof→L1 dyn→L2 abi→L3 onnx→L4 linalg→L5 umbrella+tutorials→build CI→Hackage release→Stackage nightly→(optional) Discourse; ccm 3/10 done or in-flight.; keel modular architecture: four independent ability packages (dyn/abi/onnx/linalg) + umbrella coordination via doctor/setup utilities; frame↔buffer bridge in umbrella only, no circular deps.

**Blocked** —  *(none)*

## 3. Open Todos

- [ ] `medium` keel-dyn L1 complete: Windows/POSIX dual-platform runtime dynamic loader (LoadLibrary/dlopen) FunPtr resolution—Windows smoke test 1/1 PASS (GetTickCount64 + negative examples)
- [ ] `medium` commit e90d4c2.

## 4. Plan (sequenced next steps)

keel-dyn L1 complete: Windows/POSIX dual-platform runtime dynamic loader (LoadLibrary/dlopen) FunPtr resolution—Windows smoke test 1/1 PASS (GetTickCount64 + negative examples); commit e90d4c2.

## 5. Critical Context (must-know memories)

- #43 `decision` [scope] Upstream PR track (steps #1 CI PR and #9 PR group) removed from plan; 3 Windows test bugs discovered in fork CI will be filed as separate DataHaskell/dataframe issues, not blocking keel.
- #42 `decision` [architecture] DataFrame PR not required—four capability packages (keel-dyn, keel-abi, keel-onnx, keel-linalg) have zero upstream dependencies; dataframe-core is a standard Hackage library dependency only in keel um
- #41 `task` [roadmap] Complete all locally-completable development steps first, then publish remaining work as independent repositories without needing DataFrame PR.
- #40 `decision` [project_structure] Architecture decision: only borrow DataFrame repository for that single component, all other packages developed independently and published separately to own repositories.
- #31 `result` [fork_CI_results] Fork CI results: 4/4 builds pass (Windows+macOS), macOS tests 100% pass, Windows tests fail on 3 upstream migration bugs (hardcoded /tmp, CRLF×2, quote boundary)
- #30 `result` [P0_build_verification] P0 dual build verification complete: Hackage user path PASS (173s, smoke test ok), source tree PASS (217s after MAX_PATH fix); both paths compile cleanly with GHC 9.12.4
- #2 `decision` [dependency_strategy] DataHaskell initiative stalled; HLearn abandoned by Izbicki; vector, statistics, ad packages actively maintained but mature/stable rather than cutting-edge; recommend building on proven foundations (v
- #1 `arch` [ecosystem_landscape] Haskell ML/DS ecosystem fragmented: hasktorch (PyTorch bindings), hmatrix (linear algebra), accelerate (GPU via LLVM), massiv (parallel arrays), backprop (autodiff), statistics (basic stats); no unifi
- #49 `decision` [release] Release strategy: build all five packages locally (Windows primary validation), then single publish batch (Hackage 0.1 + Stackage nightly); no incremental upstream PRs.
- #46 `config` [roadmap] Local development plan now 10 steps: P0 proof→L1 dyn→L2 abi→L3 onnx→L4 linalg→L5 umbrella+tutorials→build CI→Hackage release→Stackage nightly→(optional) Discourse; ccm 3/10 done or in-flight.

## 6. Files Touched This Session

**edit**:
  - `d:\Projects\HSDS\.github\workflows\ci.yml`
  - `d:\Projects\HSDS\packages\keel-linalg\src\Keel\Linalg\Backend.hs`
  - `C:\Users\skyma\AppData\Local\Temp\claude\d--Projects-HSDS\f627a4e5-ac32-4940-bb23-883811ffb134\scratchpad\plan_refined.json`
  - `d:\Projects\HSDS\packages\keel\keel.cabal`
  - `d:\Projects\HSDS\packages\keel\app\Main.hs`
  - `d:\Projects\HSDS\packages\keel\src\Keel\Setup.hs`

## 7. Pre-compact Transcript Pointer

If you need raw conversation history before compaction, read:

```
C:\Users\skyma\.claude\projects\d--Projects-HSDS\f627a4e5-ac32-4940-bb23-883811ffb134.jsonl
```

This is a JSONL file: one message per line. Read with the Read tool.

---
*This file is the handoff contract for the next session. Read it FIRST.*
*Spec: `docs/CONTRACTS.md#handoff-contract` · Anti-patch contract: `docs/CONTRACTS.md#anti-patch-contract`*