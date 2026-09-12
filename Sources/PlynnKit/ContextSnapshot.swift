import Foundation
import PlynnCodeContext

/// Context captured at the hotkey boundary for one formatting pass.
///
/// File candidates contain names only. Optional code symbols come from local,
/// opt-in syntax indexing. Source files require a separate opt-in and are held
/// only for this dictation; bounded relevant excerpts reach the local model.
public struct ContextSnapshot: Equatable, Sendable {
    public let bundleID: String?
    public let selectedText: String?
    public let workspaceRoot: String?
    public let fileCandidates: [String]
    public let codeSymbols: [CodeSymbol]
    public let codeFiles: [CodeSourceFile]

    public init(
        bundleID: String? = nil,
        selectedText: String? = nil,
        workspaceRoot: String? = nil,
        fileCandidates: [String] = [],
        codeSymbols: [CodeSymbol] = [],
        codeFiles: [CodeSourceFile] = []
    ) {
        self.bundleID = bundleID
        self.selectedText = selectedText
        self.workspaceRoot = workspaceRoot
        self.fileCandidates = fileCandidates
        self.codeSymbols = codeSymbols
        self.codeFiles = codeFiles
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
            codeSymbols: codeSymbols, codeFiles: codeFiles)
    }

    public func withCodeSymbols(_ symbols: [CodeSymbol]) -> ContextSnapshot {
        ContextSnapshot(bundleID: bundleID, selectedText: selectedText,
                        workspaceRoot: workspaceRoot, fileCandidates: fileCandidates, codeSymbols: symbols,
                        codeFiles: codeFiles)
    }

    public func withCodeContext(_ code: CodeWorkspaceContext) -> ContextSnapshot {
        ContextSnapshot(bundleID: bundleID, selectedText: selectedText,
                        workspaceRoot: workspaceRoot, fileCandidates: fileCandidates,
                        codeSymbols: code.symbols, codeFiles: code.files)
    }
}
