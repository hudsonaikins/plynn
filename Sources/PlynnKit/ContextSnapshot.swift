import Foundation
import PlynnCodeContext

/// Context captured at the hotkey boundary for one formatting pass.
///
/// File candidates contain names only. Optional code symbols come from local,
/// opt-in syntax indexing; raw source, comments, and literals are not retained.
public struct ContextSnapshot: Equatable, Sendable {
    public let bundleID: String?
    public let selectedText: String?
    public let workspaceRoot: String?
    public let fileCandidates: [String]
    public let codeSymbols: [CodeSymbol]

    public init(
        bundleID: String? = nil,
        selectedText: String? = nil,
        workspaceRoot: String? = nil,
        fileCandidates: [String] = [],
        codeSymbols: [CodeSymbol] = []
    ) {
        self.bundleID = bundleID
        self.selectedText = selectedText
        self.workspaceRoot = workspaceRoot
        self.fileCandidates = fileCandidates
        self.codeSymbols = codeSymbols
    }

    public var profile: AppCategories.Profile {
        AppCategories.profile(forBundleID: bundleID)
    }

    public func withFileCandidates(_ fileCandidates: [String]) -> ContextSnapshot {
        ContextSnapshot(
            bundleID: bundleID,
            selectedText: selectedText,
            workspaceRoot: workspaceRoot,
            fileCandidates: fileCandidates,
            codeSymbols: codeSymbols)
    }

    public func withCodeSymbols(_ symbols: [CodeSymbol]) -> ContextSnapshot {
        ContextSnapshot(bundleID: bundleID, selectedText: selectedText,
                        workspaceRoot: workspaceRoot, fileCandidates: fileCandidates, codeSymbols: symbols)
    }
}
