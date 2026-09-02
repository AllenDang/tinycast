import Foundation

@MainActor
struct PresentationActions {
    typealias Confirm = @MainActor (
        String, String, String, String, DialogTone, DialogAction.Role
    ) async -> Bool
    typealias Notice = @MainActor (String, String, String, DialogTone) async -> Void
    typealias ReportFailure = @MainActor (String, String, String, String?) async -> Bool
    typealias ShowMessage = @MainActor (String, DialogTone) -> Void
    typealias PickVolume = @MainActor (Float32) async -> Float32?

    let confirm: Confirm
    let notice: Notice
    let reportFailure: ReportFailure
    let showMessage: ShowMessage
    let pickVolume: PickVolume
}
