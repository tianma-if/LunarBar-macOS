import SwiftUI

struct MainPopupView: View {
    @ObservedObject var viewModel: CalendarViewModel

    var body: some View {
        VStack(spacing: 16) {
            CalendarGridView(viewModel: viewModel)
        }
        .padding(18)
    }
}

struct MainPopupView_Previews: PreviewProvider {
    static var previews: some View {
        MainPopupView(viewModel: CalendarViewModel())
            .frame(width: 360, height: 430)
    }
}
