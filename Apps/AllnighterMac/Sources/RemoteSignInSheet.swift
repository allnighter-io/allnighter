import AllnighterCore
import SwiftUI

struct RemotePairingPromptSheet: View {
    @Environment(RemoteAccountModel.self) private var remoteAccount
    @Environment(\.dismiss) private var dismiss

    let request: RemotePairRequest

    var body: some View {
        VStack(alignment: .leading, spacing: ALSpace.s5) {
            Text("Trust \(request.displayName)?")
                .font(ALFont.title)
                .foregroundStyle(ALColor.textPrimary)

            Text("This iPhone asked to control team runs on this Mac. Approve only if you started pairing on your phone.")
                .font(ALFont.body)
                .foregroundStyle(ALColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: ALSpace.s4) {
                Button("Not now") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Trust iPhone") {
                    Task {
                        await remoteAccount.approvePairing(deviceId: request.deviceId)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(ALSpace.s6)
        .frame(width: 460)
    }
}
