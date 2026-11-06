//import SwiftUI
//
//struct MenuSelectionField: View {
//    let label: String
//    @Binding var selection: String?
//    let placeholder: String
//    let options: [String]
//
//    init(
//        label: String,
//        selection: Binding<String?>,
//        placeholder: String = "Choose",
//        options: [String]
//    ) {
//        self.label = label
//        _selection = selection
//        self.placeholder = placeholder
//        self.options = options
//    }
//
//    var body: some View {
//        VStack(alignment: .leading, spacing: 10) {
//            Text(label)
//                .font(.system(size: 15, weight: .semibold))
//                .foregroundColor(AppColors.iconLabel.opacity(0.9))
//
//            Menu {
//                ForEach(options, id: \.self) { option in
//                    Button(option) {
//                        selection = option
//                    }
//                }
//            } label: {
//                MenuSelectionFieldLabel(
//                    text: selection ?? placeholder,
//                    isPlaceholder: selection == nil
//                )
//            }
//        }
//    }
//}
