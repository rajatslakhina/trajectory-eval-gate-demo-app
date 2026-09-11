//
//  DemoApp.swift
//  TrajectoryEvalGate Demo
//
//  A SwiftUI app over `trajectory-eval-gate-kit`, consumed as a remote Swift
//  package.
//
//  The app owns the two things a real consumer owns: the **dataset** — which
//  trajectories the release is graded against — and the **policy** — how much
//  evidence the gate demands before it turns a build green. The package owns
//  the matching, the statistics, and the report. That split is why the app
//  imports `TrajectoryEvalGate` for real rather than only rendering a view
//  from `TrajectoryEvalGateUI`: every contract below is written here, not
//  re-exported from the library's fixtures.
//

import SwiftUI
import TrajectoryEvalGate
import TrajectoryEvalGateUI

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            EvalGateDashboardView(
                cases: ReleaseGateConfiguration.cases,
                policy: ReleaseGateConfiguration.policy
            )
        }
    }
}

/// The app's compiled-in release-gate configuration.
///
/// In a shipping app this would be decoded from a checked-in dataset file and
/// reviewed like any other release artefact. Here it is compiled in so the demo
/// has no I/O and cannot launch into an empty state.
enum ReleaseGateConfiguration {

    // MARK: - Tool names

    private enum Tool {
        static let scanBarcode = "scanBarcode"
        static let runOCR = "runOCR"
        static let lookUpProduct = "lookUpProduct"
        static let addToCart = "addToCart"
        /// In the registry, forbidden in every contract below. A refund is the
        /// canonical "the agent must not be able to reach this from a price
        /// question" side effect.
        static let refundOrder = "refundOrder"
    }

    // MARK: - Trajectory contracts

    /// Scan the barcode, then look the SKU up.
    ///
    /// `.subsequence`, so extra chatter is tolerated — this pins causality
    /// without pinning how talkative the model is. The SKU matcher is a prefix
    /// rather than an equality: asserting the exact SKU would fail the first
    /// time someone improves the prompt, while `THD-` still catches the real
    /// regression, which is the model answering from its weights instead of
    /// calling the lookup tool.
    private static let barcodePriceCheck = TrajectoryExpectation(
        steps: [
            ExpectedStep(toolName: Tool.scanBarcode, label: "Scan the barcode"),
            ExpectedStep(
                toolName: Tool.lookUpProduct,
                arguments: ["sku": .stringHasPrefix("THD-")],
                label: "Look up the SKU"
            )
        ],
        ordering: .subsequence,
        forbiddenTools: [Tool.refundOrder],
        maximumCalls: 8
    )

    /// OCR is optional: the agent may read the shelf label or skip straight to
    /// a lookup if it already recognises the product. This is the contract that
    /// makes greedy matching wrong and the library's dynamic program necessary.
    private static let shelfLabelPriceCheck = TrajectoryExpectation(
        steps: [
            ExpectedStep(toolName: Tool.runOCR, isOptional: true, label: "Read the shelf label (optional)"),
            ExpectedStep(
                toolName: Tool.lookUpProduct,
                arguments: ["sku": .stringHasPrefix("THD-")],
                label: "Look up the SKU"
            )
        ],
        ordering: .subsequence,
        forbiddenTools: [Tool.refundOrder],
        maximumCalls: 8
    )

    /// Look up, then add one to ten units.
    ///
    /// `.exact` here, unlike the two above: an extra `addToCart` is a duplicate
    /// order line, not chatter. The `maximumCalls: 2` ceiling is belt and
    /// braces for the same failure.
    private static let addToCartFlow = TrajectoryExpectation(
        steps: [
            ExpectedStep(
                toolName: Tool.lookUpProduct,
                arguments: ["sku": .stringHasPrefix("THD-")],
                label: "Look up the SKU"
            ),
            ExpectedStep(
                toolName: Tool.addToCart,
                arguments: [
                    "sku": .stringHasPrefix("THD-"),
                    "quantity": .intBetween(1, 10)
                ],
                label: "Add to cart"
            )
        ],
        ordering: .exact,
        forbiddenTools: [Tool.refundOrder],
        maximumCalls: 2
    )

    // MARK: - Dataset

    /// Three cases for a retail shopping assistant, with baselines recorded
    /// from a previous sweep so drift detection has something to compare to.
    ///
    /// The case *ids* come from `Fixtures` rather than being invented here,
    /// because they are the join key the shipped `DeterministicBackend` uses to
    /// look up how each case should behave. Everything else — prompt, contract,
    /// baseline — is this app's.
    static let cases: [EvalCase] = [
        EvalCase(
            id: Fixtures.barcodeCaseID,
            prompt: "What does this cost?",
            expectation: barcodePriceCheck,
            baseline: BaselineRecord(passes: 58, runs: 60)
        ),
        EvalCase(
            id: Fixtures.shelfLabelCaseID,
            prompt: "Price for the item on this shelf label?",
            expectation: shelfLabelPriceCheck,
            baseline: BaselineRecord(passes: 57, runs: 60)
        ),
        EvalCase(
            id: Fixtures.addToCartCaseID,
            prompt: "Add two of these to my cart.",
            expectation: addToCartFlow,
            baseline: BaselineRecord(passes: 59, runs: 60)
        )
    ]

    // MARK: - Policy

    /// 20–60 runs per case, verdict against a 0.90 Wilson lower bound.
    ///
    /// This is a decision with arithmetic behind it, which is why the dashboard
    /// renders `feasibility`: a 0.90 bound needs 35 consecutive passes, so a
    /// 60-run ceiling is achievable and a 10-run ceiling would make the gate red
    /// forever. Swapping in `.strict` (0.95, needing 73 runs) or `.exploratory`
    /// (0.50, for local iteration) is the knob a lead turns.
    static let policy: GatePolicy = .standard

    /// Whether this configuration can ever produce a green build.
    ///
    /// Exposed here rather than computed in the view so the same check could be
    /// asserted in a unit test or a CI preflight step in a real app.
    static var isSatisfiable: Bool { policy.feasibility.isAchievable }
}

#if DEBUG
#Preview {
    EvalGateDashboardView(
        cases: ReleaseGateConfiguration.cases,
        policy: ReleaseGateConfiguration.policy
    )
}
#endif
