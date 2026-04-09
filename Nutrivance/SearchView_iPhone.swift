import SwiftUI

struct SearchView_iPhone: View {
    @EnvironmentObject var searchState: SearchState
    
    var body: some View {
        Group {
            switch searchState.selectedScope {
            case .all:
                SearchView()
            case .nutrition:
                NutrivanceView()
            case .fitness:
                MovanceView()
            case .mentalHealth:
                SpirivanceView()
            }
        }
    }
}

#Preview {
    SearchView_iPhone()
        .environmentObject(SearchState())
}
