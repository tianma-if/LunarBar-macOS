import SwiftUI
import AppKit

struct MainPopupView: View {
    @ObservedObject var viewModel: CalendarViewModel
    @StateObject private var weatherViewModel = WeatherViewModel()
    @State private var showingWeatherSettings = false

    var body: some View {
        VStack(spacing: 16) {
            WeatherHeaderView(viewModel: weatherViewModel) {
                showingWeatherSettings = true
            }

            CalendarGridView(viewModel: viewModel)

            Divider()

            HStack {
                Spacer()

                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("退出 LunarBar", systemImage: "power")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(18)
        .sheet(isPresented: $showingWeatherSettings) {
            WeatherSettingsView(viewModel: weatherViewModel)
        }
    }
}

struct MainPopupView_Previews: PreviewProvider {
    static var previews: some View {
        MainPopupView(viewModel: CalendarViewModel())
            .frame(width: 360, height: 520)
    }
}
