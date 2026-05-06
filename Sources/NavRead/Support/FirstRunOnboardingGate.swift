struct FirstRunOnboardingState: Equatable {
    var hasCompleted: Bool
    var hasStarted: Bool
    var shouldPresent: Bool
}

enum FirstRunOnboardingGate {
    static func resolve(
        hasCompleted: Bool,
        hasStarted: Bool,
        libraryExistedBeforeSetup: Bool
    ) -> FirstRunOnboardingState {
        if hasCompleted {
            return FirstRunOnboardingState(hasCompleted: true, hasStarted: hasStarted, shouldPresent: false)
        }

        if hasStarted {
            return FirstRunOnboardingState(hasCompleted: false, hasStarted: true, shouldPresent: true)
        }

        if libraryExistedBeforeSetup {
            return FirstRunOnboardingState(hasCompleted: true, hasStarted: false, shouldPresent: false)
        }

        return FirstRunOnboardingState(hasCompleted: false, hasStarted: true, shouldPresent: true)
    }
}
