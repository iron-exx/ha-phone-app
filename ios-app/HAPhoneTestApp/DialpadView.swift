import SwiftUI

private let keys: [(digit: String, letters: String)] = [
    ("1", ""), ("2", "ABC"), ("3", "DEF"),
    ("4", "GHI"), ("5", "JKL"), ("6", "MNO"),
    ("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ"),
    ("*", ""), ("0", "+"), ("#", ""),
]

/// Reused 3x: outgoing dial (CALL-03), in-call DTMF (CALL-02), blind
/// transfer target (CALL-04) per D-13/D-14.
struct DialpadView: View {
    let onDigit: (Character) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(keys, id: \.digit) { key in
                Button(action: { onDigit(Character(key.digit)) }) {
                    VStack {
                        Text(key.digit).font(.system(size: 20, weight: .semibold))
                        if !key.letters.isEmpty {
                            Text(key.letters).font(.system(size: 14))
                        }
                    }
                    .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
    }
}
