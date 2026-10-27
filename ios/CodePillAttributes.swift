import ActivityKit
import Foundation

/// ActivityAttributes defining the static and dynamic state for Dynamic Island
public struct CodePillAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Current status: "Thinking", "Editing file", "Running tests", "Done"
        public var status: String
        /// Target file being edited, e.g. "main.rs"
        public var currentFile: String?
        /// Detailed description of the current action
        public var stepDescription: String
        /// Whether the agent is actively executing
        public var isBusy: Bool
        /// Whether the action is waiting for user confirmation
        public var needsApproval: Bool

        public init(
            status: String,
            currentFile: String? = nil,
            stepDescription: String,
            isBusy: Bool = true,
            needsApproval: Bool = false
        ) {
            self.status = status
            self.currentFile = currentFile
            self.stepDescription = stepDescription
            self.isBusy = isBusy
            self.needsApproval = needsApproval
        }
    }

    /// Static session metadata
    public var projectName: String
    public var promptSummary: String

    public init(projectName: String, promptSummary: String) {
        self.projectName = projectName
        self.promptSummary = promptSummary
    }
}
