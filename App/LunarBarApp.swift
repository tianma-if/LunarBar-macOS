import SwiftUI

@main
struct LunarBarApp: App {
    @StateObject private var calendarViewModel = CalendarViewModel()
    @StateObject private var weatherViewModel = WeatherViewModel()

    var body: some Scene {
        MenuBarExtra {
            MainPopupView(viewModel: calendarViewModel, weatherViewModel: weatherViewModel)
                .frame(width: 360, height: 520)
                .background(.thinMaterial)
        } label: {
            Image(systemName: "calendar")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)

        Window("LunarBar 设置", id: "settings") {
            WeatherSettingsView(viewModel: weatherViewModel)
        }
        .defaultSize(width: 360, height: 760)
        .windowResizability(.contentSize)
    }
}
