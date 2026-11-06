import SwiftUI
import WaanguCoreKit

struct EmojiPicker: View {
    @State private var selectedCategory: EmojiCategory = .recent
    @State private var searchText = ""
    @State private var scrollOffset: CGFloat = 0
    @Namespace private var categoryNamespace
    @State private var showEmojiePicker = false
    @State private var recentEmojis: [String] = []
    @State private var selectedIcons: [String] = []
    @Binding var selectedIcon : String
    let translationService: (any TranslationServiceProtocol)?
    
    func addRecentEmoji(_ emoji: String) {
        // Remove if it already exists, then add to front
        recentEmojis.removeAll { $0 == emoji }
        recentEmojis.insert(emoji, at: 0)
        
        // Limit to 20 recent emojis
        if recentEmojis.count > 20 {
            recentEmojis.removeLast()
        }
        
        // Save to UserDefaults
        UserDefaults.standard.set(recentEmojis, forKey: "recentEmojis")
    }
    
    var body: some View {
        VStack{
            Button("", systemImage: "smiley") {
                showEmojiePicker = true
            }
        }
        .chatAppearanceSheet(isPresented: $showEmojiePicker, onDismiss: {
            showEmojiePicker = false
            for icon in selectedIcons {
                addRecentEmoji(icon)
                debugLog("saved icon \(icon)")
            }
            
        }){
            if #available(iOS 16.0, *) {
                VStack(spacing: 0) {
                    // Search bar
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                            .font(.system(size: 16))
                        
                        TextField(translationService?.resolve(key: ChatTranslationKeys.STORIES_SEARCH, module: ChatTranslationKeys.MODULE).value ?? "Search", text: $searchText)
                            .font(.system(size: 16))
                        
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 16))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    
                    Divider()
                    
                    // Emoji grid with ScrollViewReader for category navigation
                    //                ScrollViewReader { proxy in
                    //                    ScrollView {
                    //                        LazyVStack(spacing: 20, pinnedViews: []) {
                    //                            ForEach(EmojiCategory.allCases, id: \.self) { category in
                    //                                VStack(alignment: .leading, spacing: 12) {
                    //                                    Text(category.title)
                    //                                        .font(.system(size: 14, weight: .medium))
                    //                                        .foregroundColor(.gray)
                    //                                        .padding(.horizontal, 16)
                    //                                        .id(category)
                    //
                    //                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 12) {
                    //                                        ForEach(category.emojis, id: \.self) { emoji in
                    //                                            Button(action: {
                    //                                                print("Selected: \(emoji)")
                    //                                            }) {
                    //                                                Text(emoji)
                    //                                                    .font(.system(size: 32))
                    //                                            }
                    //                                        }
                    //                                    }
                    //                                    .padding(.horizontal, 12)
                    //                                }
                    //                            }
                    //                        }
                    //                        .padding(.vertical, 16)
                    //                    }
                    //                    .onChange(of: selectedCategory) { newCategory in
                    //                        withAnimation {
                    //                            proxy.scrollTo(newCategory, anchor: .top)
                    //                        }
                    //                    }
                    //                }
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 20, pinnedViews: []) {
                                ForEach(EmojiCategory.allCases, id: \.self) { category in
                                    VStack(alignment: .leading, spacing: 12) {
                                        // Section title
                                        Text(category.title)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.gray)
                                            .padding(.horizontal, 16)
                                            .id(category)
                                        
                                        // Emoji grid
                                        LazyVGrid(
                                            columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8),
                                            spacing: 12
                                        ) {
                                            // ✅ Show recent emojis dynamically if category == .recent
                                            ForEach(category == .recent ? recentEmojis : category.emojis, id: \.self) { emoji in
                                                Button(action: {
                                                    //                                                addRecentEmoji(emoji)
                                                    selectedIcons.removeAll { $0 == emoji } // remove duplicates
                                                    selectedIcons.insert(emoji, at: 0)       // add to front
                                                    if selectedIcons.count > 20 {            // optional limit
                                                        selectedIcons.removeLast()
                                                    }
                                                    debugLog("Selected: \(emoji) recent \(selectedIcons)")
                                                    selectedIcon = selectedIcon + emoji
                                                    //                                                selectedIcons.append(emoji)
                                                }) {
                                                    Text(emoji)
                                                        .font(.system(size: 32))
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                    }
                                    // ✅ Hide the “Recent” section if it’s empty
                                    .opacity(category == .recent && recentEmojis.isEmpty ? 0 : 1)
                                    .frame(height: category == .recent && recentEmojis.isEmpty ? 0 : nil)
                                }
                            }
                            .padding(.vertical, 16)
                        }
                        .onChange(of: selectedCategory) { newCategory in
                            withAnimation {
                                proxy.scrollTo(newCategory, anchor: .top)
                            }
                        }
                    }
                    
                    
                    Divider()
                    
                    // Category tabs
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment:.center,spacing: 0) {
                            Spacer()
                            ForEach(EmojiCategory.allCases, id: \.self) { category in
                                Button(action: {
                                    selectedCategory = category
                                }) {
                                    VStack(alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/,spacing: 8) {
                                        Image(systemName: category.icon)
                                            .font(.system(size: 16))
                                            .foregroundColor(selectedCategory == category ? Color(hex: "00A884") : .gray)
                                        //                                    .frame(width: 1)
                                        
                                        if selectedCategory == category {
                                            Rectangle()
                                                .fill(Color(hex: "00A884"))
                                                .frame(height: 2)
                                        } else {
                                            Rectangle()
                                                .fill(Color.clear)
                                                .frame(height: 2)
                                        }
                                    }
                                    .frame(width: 38)
                                }
                            }
                            Spacer()
                        }
                        //                .padding(.horizontal, 8)
                    }
                    .frame(height: 50)
                    .background(Color(.systemBackground))
                }
                .background(Color(.systemBackground)).presentationDragIndicator(.visible)
                .presentationDetents([.medium, .large])
            } else {
                // Fallback on earlier versions
            }
        }.onAppear {
            if let saved = UserDefaults.standard.array(forKey: "recentEmojis") as? [String] {
                recentEmojis = saved
            }
        }
    }
}
