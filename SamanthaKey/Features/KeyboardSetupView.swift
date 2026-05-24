import SwiftUI
import UIKit

struct KeyboardSetupView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Label("keyboard.setup.badge", systemImage: "keyboard")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.quietInk)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, AppSpacing.xs)
                        .samanthaGlass(in: Capsule(style: .continuous), tint: AppTheme.keyTint.opacity(0.18))

                    Text("keyboard.setup.title")
                        .font(.largeTitle.bold())
                        .lineLimit(3)
                        .minimumScaleFactor(0.78)

                    Text("keyboard.setup.body")
                        .font(.body)
                        .foregroundStyle(AppTheme.muted)
                        .lineSpacing(3)
                }

                AppSection {
                    SetupStep(number: "1", title: "keyboard.setup.step1", detail: "keyboard.setup.step1.body")
                    SetupStep(number: "2", title: "keyboard.setup.step2", detail: "keyboard.setup.step2.body")
                    SetupStep(number: "3", title: "keyboard.setup.step3", detail: "keyboard.setup.step3.body")
                }

                Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                    Label("keyboard.setup.open_settings", systemImage: "gearshape.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color(white: 0.78))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.black, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)

                Text("keyboard.setup.privacy")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AppSpacing.lg)
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .navigationTitle("keyboard.setup.nav")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SetupStep: View {
    let number: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(.black)
                .frame(width: 28, height: 28)
                .background(AppTheme.successTint, in: Circle())

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
