import SwiftUI

@main
struct LunarBarApp: App {
    @StateObject private var calendarViewModel = CalendarViewModel()

    var body: some Scene {
        MenuBarExtra {
            MainPopupView(viewModel: calendarViewModel)
                .frame(width: 360, height: 430)
                .background(.thinMaterial)
        } label: {
            Image(systemName: "calendar")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)
    }
}
