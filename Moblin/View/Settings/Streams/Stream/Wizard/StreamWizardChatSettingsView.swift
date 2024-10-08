import SwiftUI

struct StreamWizardChatSettingsView: View {
    @EnvironmentObject private var model: Model

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $model.wizardChatBttv, label: {
                    Text("BTTV emotes")
                })
                Toggle(isOn: $model.wizardChatFfz, label: {
                    Text("FFZ emotes")
                })
                Toggle(isOn: $model.wizardChatSeventv, label: {
                    Text("7TV emotes")
                })
            }
            Section {
                if model.wizardNetworkSetup == .direct {
                    NavigationLink {
                        StreamWizardSummarySettingsView()
                    } label: {
                        WizardNextButtonView()
                    }
                } else {
                    NavigationLink {
                        StreamWizardObsRemoteControlSettingsView()
                    } label: {
                        WizardNextButtonView()
                    }
                }
            }
        }
        .navigationTitle("Chat")
        .toolbar {
            CreateStreamWizardToolbar()
        }
    }
}
