import SwiftUI

struct MainPopupView: View {
    @ObservedObject var viewModel: CalendarViewModel
    @ObservedObject var weatherViewModel: WeatherViewModel
    @EnvironmentObject private var updateManager: AutoUpdateManager
    @Environment(\.openWindow) private var openWindow

    init(viewModel: CalendarViewModel, weatherViewModel: WeatherViewModel) {
        self.viewModel = viewModel
        self.weatherViewModel = weatherViewModel
    }

    var body: some View {
        VStack(spacing: 14) {
            updateBannerIfNeeded

            WeatherHeaderView(viewModel: weatherViewModel) {
                openWindow(id: "settings")
            }

            CalendarGridView(viewModel: viewModel)
        }
        .padding(18)
        .onAppear {
            viewModel.onAppear()
        }
        .animation(.easeInOut(duration: 0.2), value: updateManager.status)
    }

    @ViewBuilder
    private var updateBannerIfNeeded: some View {
        if let version = updateManager.readyVersion {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)

                Text("新版本 v\(version) 已就绪")
                    .font(.system(size: 12, weight: .medium))

                Spacer()

                Button("重启更新") {
                    updateManager.applyUpdateAndRestart()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .transition(.move(edge: .top).combined(with: .opacity))
        } else if case .downloading(let progress, let version) = updateManager.status {
            HStack(spacing: 8) {
                ProgressView(value: progress > 0 ? progress : nil)
                    .controlSize(.small)
                    .frame(width: 14, height: 14)

                Text("正在下载 v\(version)…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                if progress > 0 {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

struct MainPopupView_Previews: PreviewProvider {
    static var previews: some View {
        MainPopupView(viewModel: CalendarViewModel(), weatherViewModel: WeatherViewModel())
            .frame(width: 360, height: 520)
    }
}
