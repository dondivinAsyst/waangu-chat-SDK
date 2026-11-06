
import SwiftUI

// MARK: - Model

public struct DropdownOption: Identifiable, Equatable {
    public let id: String
    public let label: String
    public let emoji: String?
    public  let description: String?
    
    public init(id: String, label: String, emoji: String? = "", description: String? = "") {
        self.id = id
        self.label = label
        self.emoji = emoji
        self.description = description
    }
}


// MARK: - Dropdown Panel (floating overlay)

public struct DropdownPanel: View {
    let options: [DropdownOption]
    let selected: [String]
    let isMulti: Bool
    let onSelect: (String) -> Void
    let onDone: () -> Void

    @State private var search: String = ""

    var filteredOptions: [DropdownOption] {
        search.isEmpty ? options : options.filter {
            $0.label.localizedCaseInsensitiveContains(search)
        }
    }
    public init(options: [DropdownOption], selected: [String], isMulti: Bool, onSelect: @escaping (String) -> Void, onDone: @escaping () -> Void) {
        self.options = options
        self.selected = selected
        self.isMulti = isMulti
        self.onSelect = onSelect
        self.onDone = onDone
    }

    public  var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                TextField("Search...", text: $search)
                    .font(.system(size: 14))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().opacity(0.5)

            // Options list
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    if filteredOptions.isEmpty {
                        VStack(spacing: 8) {
                            Text("🔍").font(.system(size: 28))
                            Text("No results found")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        ForEach(Array(filteredOptions.enumerated()), id: \.element.id) { index, opt in
                            OptionRow(
                                option: opt,
                                isSelected: selected.contains(opt.id),
                                index: index,
                                onTap: { onSelect(opt.id) }
                            )
                        }
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
            }
            .frame(maxHeight: 240)

            // Footer for multi
            if isMulti {
                Divider().opacity(0.5)
                HStack {
                    Text("\(selected.count) selected")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Done", action: onDone)
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(
                            LinearGradient(
                                colors: [.brandPrimary, .brandPrimary.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .shadow(color: Color.indigo.opacity(0.3), radius: 6, y: 2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.14), radius: 24, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.systemGray4).opacity(0.7), lineWidth: 1.5)
        )
    }
}

// MARK: - SelectDropdown

public struct SelectDropdown: View {
    let options: [DropdownOption]
    let label: String
    let placeholder: String
    let isMulti: Bool
    var errorMessage: String? = nil

    @State private var isOpen: Bool = false
    @Binding var selected: [String]
    @State private var triggerSize: CGSize = .zero
    @State private var triggerFrame: CGRect = .zero
    @State private var openUpward: Bool = false

    private var hasError: Bool { errorMessage != nil }

    var selectedOptions: [DropdownOption] {
        options.filter { selected.contains($0.id) }
    }

    private func closeDropdown() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            isOpen = false
        }
    }
    
    public init(options: [DropdownOption], label: String, placeholder: String, isMulti: Bool, errorMessage: String? = nil, selected: Binding<[String]>,) {
        self.options = options
        self.label = label
        self.placeholder = placeholder
        self.isMulti = isMulti
        self.errorMessage = errorMessage
        self._selected = selected
    }

    public  var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // MARK: Label Row
            HStack(spacing: 8) {
                Text(label)
                    .font(.appInputLabel)
                    .foregroundStyle(hasError ? Color.appError : Color.brandPrimary)
//                    .tracking(0.5)
                    .padding(.leading, 10)

                Text(isMulti ? "Multiple" : "Unique")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background( Color.brandPrimary.opacity(0.12) )
                    .foregroundColor(.brandPrimary )
                    .clipShape(Capsule())
            }

            // MARK: Trigger Button
            Button(action: {
                let screenHeight: CGFloat = UIScreen.main.bounds.height - 40
                let spaceBelow = screenHeight - triggerFrame.maxY
                let estimatedPanelHeight: CGFloat = 300
                openUpward = spaceBelow < estimatedPanelHeight && triggerFrame.minY > estimatedPanelHeight

                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    isOpen.toggle()
                }
            }) {
                HStack(spacing: 10) {
                    Group {
                        if selected.isEmpty {
                            Text(placeholder)
                                .foregroundColor(Color(.placeholderText))
                                .font(.system(size: 15))
                        } else if isMulti {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(selectedOptions) { opt in
                                        TagView(option: opt) {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                selected.removeAll { $0 == opt.id }
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        } else {
                            HStack(spacing: 6) {
                                Text(selectedOptions.first?.emoji ?? "")
                                    .font(.system(size: 18))
                                Text(selectedOptions.first?.label ?? "")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 8) {
                        if !selected.isEmpty {
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selected.removeAll()
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color(.systemGray3))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isOpen)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .frame(minHeight: 52)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.ultraThinMaterial)
                        .shadow(
                            color: isOpen ? Color.brandPrimary.opacity(0.15) : Color.black.opacity(0.06),
                            radius: isOpen ? 16 : 8,
                            y: 3
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            hasError ? Color.appError : (isOpen ? Color.brandPrimary.opacity(0.6) : Color(.systemGray4).opacity(0.8)),
                            lineWidth: hasError ? 1.5 : 1.5
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            triggerSize = geo.size
                            triggerFrame = geo.frame(in: .global)
                        }
                        .onChange(of: geo.size) { _, newSize in
                            triggerSize = newSize
                        }
                        .onChange(of: geo.frame(in: .global)) { _, newFrame in
                            triggerFrame = newFrame
                        }
                }
            )
            .overlay {
                if isOpen {
                    Color.black.opacity(0.001)
                        .frame(width: 10000, height: 10000)
                        .contentShape(Rectangle())
                        .onTapGesture { closeDropdown() }
                }
            }
            .overlay(alignment: openUpward ? .bottomLeading : .topLeading) {
                if isOpen {
                    DropdownPanel(
                        options: options,
                        selected: selected,
                        isMulti: isMulti,
                        onSelect: { id in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if isMulti {
                                    if selected.contains(id) {
                                        selected.removeAll { $0 == id }
                                    } else {
                                        selected.append(id)
                                    }
                                } else {
                                    selected = [id]
                                    closeDropdown()
                                }
                            }
                        },
                        onDone: { closeDropdown() }
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: triggerSize.width)
                    .offset(y: openUpward ? -60 : triggerSize.height + 6)

                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.92, anchor: openUpward ? .bottom : .top).combined(with: .opacity),
                        removal: .scale(scale: 0.92, anchor: openUpward ? .bottom : .top).combined(with: .opacity)
                    ))
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.appInputError)
                    .foregroundStyle(Color.appError)
            }
        }
        .zIndex(isOpen ? 999 : 0)
    }
}

// MARK: - OptionRow

public struct OptionRow: View {
    let option: DropdownOption
    let isSelected: Bool
    let index: Int
    let onTap: () -> Void

    @State private var appeared = false
    
    public init(option: DropdownOption, isSelected: Bool, index: Int, onTap: @escaping () -> Void) {
        self.option = option
        self.isSelected = isSelected
        self.index = index
        self.onTap = onTap
    
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if option.emoji?.isEmpty == false {
                    Text(option.emoji ?? "")
                        .font(.system(size: 22))
                        .frame(width: 30)
                }
               

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                    if ((option.description?.isEmpty) == nil) {
                        Text(option.description ?? "")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ZStack {
                    Circle()
                        .fill(isSelected
                              ? LinearGradient(colors: [.brandPrimary, .brandPrimary.opacity(0.5)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                              : LinearGradient(colors: [Color(.systemGray5), Color(.systemGray5)],
                                               startPoint: .top, endPoint: .bottom))
                        .frame(width: 24, height: 24)
                        .shadow(color: isSelected ? Color.indigo.opacity(0.4) : .clear, radius: 5, y: 2)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
                .scaleEffect(isSelected ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.brandPrimary.opacity(0.09) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -8)
        .onAppear {
            withAnimation(.easeOut(duration: 0.25).delay(Double(index) * 0.04)) {
                appeared = true
            }
        }
    }
}

// MARK: - TagView

struct TagView: View {
    let option: DropdownOption
    let onRemove: () -> Void

    @State private var appeared = false

    var body: some View {
        HStack(spacing: 5) {
            Text(option.emoji ?? "").font(.system(size: 13))
            Text(option.label).font(.system(size: 12, weight: .semibold))
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(
            LinearGradient(
                colors: [.brandPrimary,.brandPrimary.opacity(0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .foregroundColor(.white)
        .clipShape(Capsule())
        .shadow(color: Color.brandPrimary.opacity(0.3), radius: 4, y: 2)
        .scaleEffect(appeared ? 1 : 0.5)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                appeared = true
            }
        }
    }
}

// MARK: - Demo ContentView

struct ContentView1: View {
    @State private var selectedFruits: [String] = []
    @State private var selectedCountry: [String] = []

    let fruits: [DropdownOption] = [
        .init(id: "apple",      label: "Apple",      emoji: "🍎", description: "Crisp & sweet"),
        .init(id: "banana",     label: "Banana",     emoji: "🍌", description: "Tropical & creamy"),
        .init(id: "grape",      label: "Grape",      emoji: "🍇", description: "Juicy & rich"),
        .init(id: "mango",      label: "Mango",      emoji: "🥭", description: "Exotic & vibrant"),
        .init(id: "strawberry", label: "Strawberry", emoji: "🍓", description: "Fresh & bright"),
        .init(id: "peach",      label: "Peach",      emoji: "🍑", description: "Soft & fragrant"),
        .init(id: "lemon",      label: "Lemon",      emoji: "🍋", description: "Zesty & sharp"),
        .init(id: "watermelon", label: "Watermelon", emoji: "🍉", description: "Cool & refreshing"),
    ]

    let countries: [DropdownOption] = [
        .init(id: "us", label: "United States",  emoji: "🇺🇸", description: "North America"),
        .init(id: "uk", label: "United Kingdom", emoji: "🇬🇧", description: "Europe"),
        .init(id: "jp", label: "Japan",          emoji: "🇯🇵", description: "East Asia"),
        .init(id: "fr", label: "France",         emoji: "🇫🇷", description: "Europe"),
        .init(id: "au", label: "Australia",      emoji: "🇦🇺", description: "Oceania"),
        .init(id: "br", label: "Brazil",         emoji: "🇧🇷", description: "South America"),
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.96, blue: 1.0),
                    Color(red: 0.91, green: 0.94, blue: 1.0),
                    Color(red: 0.96, green: 0.90, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 6) {
                        Text("SelectDropdown")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("iOS-style · Smooth animations · Multi & Single")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)
                    Spacer().frame(height: 300)

                    VStack(spacing: 24) {
                        SelectDropdown(
                            options: fruits,
                            label: "Favorite Fruits",
                            placeholder: "Pick your favorites...",
                            isMulti: true,
                            selected: $selectedFruits
                        )

                        SelectDropdown(
                            options: countries,
                            label: "Country",
                            placeholder: "Select a country...",
                            isMulti: false,
                            selected: $selectedCountry
                        )

                        VStack(alignment: .leading, spacing: 8) {
                            Text("NOTES".uppercased())
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                                .tracking(0.5)
                            TextField("Type something here...", text: .constant(""))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(.ultraThinMaterial)
                                        .shadow(color: Color.black.opacity(0.05), radius: 6, y: 2)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color(.systemGray4).opacity(0.8), lineWidth: 1.5)
                                )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("EMAIL".uppercased())
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                                .tracking(0.5)
                            TextField("your@email.com", text: .constant(""))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(.ultraThinMaterial)
                                        .shadow(color: Color.black.opacity(0.05), radius: 6, y: 2)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color(.systemGray4).opacity(0.8), lineWidth: 1.5)
                                )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
        }
    }
}

#Preview {
    ContentView1()
}

