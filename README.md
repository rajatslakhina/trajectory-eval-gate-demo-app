# TrajectoryEvalGate — Demo App

**A release gate for an on-device agent, with the arithmetic showing.**

A SwiftUI app that runs an agent eval sweep against three trajectory contracts
and renders the verdict the way a lead would have to defend it in a release
meeting: not "3 of 3 passed", but a pass-rate **lower bound**, the sample size
that bound is worth, and whether the policy could ever have passed in the first
place.

It consumes
[`trajectory-eval-gate-kit`](https://github.com/rajatslakhina/trajectory-eval-gate-kit)
as a **version-pinned remote Swift package** — this repo contains no copy of the
library, only `Demo.xcodeproj` and one Swift file.

---

## Why this matters

Apple's Evaluations framework (iOS/macOS 27) lets an iOS team grade a
tool-calling trajectory the way XCTest grades a function. That solves
measurement. It does not answer the question a release actually turns on:

> The suite is green. How confident are we, and how many samples is that
> confidence worth?

With `n = 3` and `s = 3`, the 95% Wilson lower bound on the true pass rate is
**0.44**. A system that fails more than half the time is entirely consistent
with three green runs. This app makes that concrete on screen:

Tapping **Run the gate** on the shipped dataset produces exactly this — the
figures below are measured, not illustrative (see **Verification**):

```
EVAL GATE FAIL: 2/3 cases cleared · 1 failing · 2 flaky · 109 runs

price-check-barcode      PASS   52/53   bound 0.901   stopped early
price-check-shelf-label  FAIL   18/20   bound 0.699   stopped early
add-to-cart              PASS   35/35   bound 0.901   stopped early, 1 errored run
```

Read the middle row. **18 of 20 is an observed pass rate of exactly 0.90 — and
the gate fails it**, because the 95% lower bound on that rate is 0.699. Every
"require a 90% pass rate" gate in the wild goes green on that row. That single
line is the whole argument, on screen, in one tap.

The rest of what the app puts in front of you:

- **A feasibility banner.** The policy's threshold is checked against its run
  ceiling *before* anything runs. A 0.90 lower bound needs 35 consecutive
  passes; ask for 0.95 with a 10-run ceiling and the banner says the gate can
  never pass, with the arithmetic attached. That misconfiguration normally gets
  diagnosed as "the feature is broken."
- **A bound bar per case.** A filled bar for the achieved lower bound, a tick
  mark for the required threshold. Green only when the bar passes the tick —
  the observed rate is displayed beside it and is deliberately not what the
  colour is keyed to.
- **Early stopping, visible.** All three cases stop before the 60-run ceiling,
  for two different reasons. `add-to-cart` stops at **35** because that is
  exactly where a perfect run's bound crosses 0.90. `price-check-shelf-label`
  stops at **20** for the opposite reason: two failures that early make 0.90
  unreachable inside the ceiling, so the remaining 40 runs would cost money and
  change nothing. On a metered backend that is the difference between a £3 gate
  and a £9 one.
- **Flaky is not the same as failing.** Two cases are flagged flaky, and one of
  them *passes*. `price-check-barcode` clears the bar at 52/53 and is still
  unstable; the report says both things rather than collapsing them.
- **Three outcomes, not two.** `pass`, `fail`, and `inconclusive` — a build must
  not be marked broken because the eval infrastructure ran out of tokens, and
  must not be marked green either. `add-to-cart` logs one errored run and is
  still graded on the 35 that completed.
- **A dataset that is not all-green.** A demo where everything passes
  demonstrates nothing.

The backend is `DeterministicBackend`, a seeded fake, so the same tap produces
the same report on every device. In a real app that is the one type you swap:
the library's `EvaluationBackend` protocol is where an adapter over Apple's
Evaluations framework and Foundation Models plugs in.

## Screenshots

**There are none, and this section will not pretend otherwise.**

The Simulator run could not be performed on this run. Requesting control of the
Simulator returned, verbatim:

> Computer-use access to "Simulator" can't be approved during a scheduled run.
> To grant it, send a message in this conversation (the approval card will
> appear), or add the app to the scheduled task's settings. (Retrying returns
> this same result.)

There is therefore no `Demo/Screenshots/` directory in this repo. See
**Verification** below for exactly what *was* established, and what it does and
does not prove.

## How to run it

```bash
git clone https://github.com/rajatslakhina/trajectory-eval-gate-demo-app.git
cd trajectory-eval-gate-demo-app
open Demo.xcodeproj
```

Then in Xcode: wait for **Package Dependencies** to resolve
`trajectory-eval-gate-kit` from GitHub (at `1.1.0` or the latest `1.x` — see
below), select the **Demo** scheme,
pick any iOS Simulator, and **Build & Run** (⌘R). Tap **Run the gate**.

The scheme is committed as shared (`Demo.xcodeproj/xcshareddata/xcschemes/`), so
it is selectable on a fresh clone. No signing team is required for a Simulator
build.

## How it is wired

`Demo/DemoApp.swift` is the whole app. It imports both products:

- `TrajectoryEvalGate` — the app owns the **dataset** and the **policy**, which
  is what a real consumer owns. `ReleaseGateConfiguration` holds the three
  `EvalCase`s and the `GatePolicy`, and exposes the feasibility check.
- `TrajectoryEvalGateUI` — the dashboard view, which takes both as parameters.

The package reference in `project.pbxproj` is an `XCRemoteSwiftPackageReference`
pointing at the library's real GitHub URL, pinned with
`upToNextMajorVersion` from `1.1.0`:

```
repositoryURL = "https://github.com/rajatslakhina/trajectory-eval-gate-kit.git";
requirement = { kind = upToNextMajorVersion; minimumVersion = 1.1.0; };
```

A version requirement rather than `branch = main` deliberately: branch-tracking
means every clone and every CI run resolves whatever `main` happened to be that
day, which is the wrong default for something anyone else might open.

Being exact about what this does and does not pin: `upToNextMajorVersion` from
`1.1.0` resolves the **highest available `1.x`**, which today is `1.1.0` and
tomorrow may not be. No `Package.resolved` is committed — Xcode generates one on
first resolve, and CI prints it — so a fresh clone is pinned to the major
version, not to a single commit. That is the right trade-off for a consumer of a
library, and the wrong one to describe as "pinned to the tag".

## Verification

Two buckets, because "it compiles" and "it ran" are different claims and only
one of them is made here.

**Verified — this actually happened.**

- The library was built clean (`rm -rf .build` first) with
  `-Xswiftc -warnings-as-errors` on Swift 6.0.3, Linux aarch64 — zero warnings —
  and its **82 XCTest cases pass with 0 failures**.
- `Demo.xcodeproj` was checked structurally before being committed: braces
  33/33, parentheses 24/24, 22 object ids defined, and **zero dangling
  references**. The shared scheme's `BlueprintIdentifier` matches the `Demo`
  target's id.
- The sweep figures quoted at the top of this README were **measured**, by
  running this app's dataset and policy through the library's test target on
  Linux against the same `DeterministicBackend` the app uses. The backend is
  seeded, so the app produces the same numbers. They are not illustrative and
  they are not a screenshot transcribed from memory.

- **CI is green.** The `macos-15` job ran `xcodebuild -resolvePackageDependencies`
  and then `xcodebuild build -scheme Demo -destination 'generic/platform=iOS
  Simulator'`, and every step succeeded. Two things follow, and only two: the
  version-pinned remote package genuinely **resolves from GitHub** — not from a
  local path, not from a checkout sitting next door — and `Demo/DemoApp.swift`
  genuinely **compiles** against it. Read the live result at
  [Actions](https://github.com/rajatslakhina/trajectory-eval-gate-demo-app/actions)
  rather than trusting this paragraph; a run ID quoted here goes stale on the
  next commit.

**Not established.**

- The app was **not launched**. It was not installed on a Simulator, no UI was
  observed, and no interaction was performed. "Compiles for a Simulator" and
  "ran on a Simulator" are different claims, and neither is being made from the
  other.
- No screenshots exist.

## The library

[`trajectory-eval-gate-kit`](https://github.com/rajatslakhina/trajectory-eval-gate-kit)
— trajectory contracts, DP and bipartite-matching trajectory matching, Wilson
confidence bounds, gate feasibility, sequential sampling under a budget,
flake-vs-regression classification, and Cohen's-kappa judge calibration. Pure
Swift, no framework dependency, tested on Linux.
Release: [v1.1.0](https://github.com/rajatslakhina/trajectory-eval-gate-kit/releases/tag/v1.1.0).

## Licence

MIT.
