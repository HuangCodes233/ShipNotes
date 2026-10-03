import SwiftUI

struct SelectAppEmptyState: View {
    var description: String

    var body: some View {
        ContentUnavailableView {
            Label(L("Select an App"), systemImage: "hand.point.up.left")
        } description: {
            Text(description)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
