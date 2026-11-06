import SwiftUI
import WaanguCoreKit

// MARK: - Bubble Helpers

@ViewBuilder
func forwardedIndicator(for message: MessageDataItem, forwardedLabel: String = "Forwarded") -> some View {
    if message.forwarded == true {
        HStack(spacing: 4) {
            Image(systemName: "arrowshape.turn.up.forward.fill")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(forwardedLabel)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .italic()
        }
        .padding(.bottom, 2)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Reusable forward button.
/// Only shown for message types where a quick forward button makes sense:
/// image, video, audio (voice message), and document.
/// Text, calls, contacts, and location use the context menu instead.
/// Hidden while upload/download is still pending or the transfer failed.
func bubbleForwardButton(message: MessageDataItem, chatVM: ChatRoomViewModel, isSelectionMode: Bool) -> some View {
    let isSupportedType: Bool = {
        switch message.typeMessage {
        case .IMAGE, .VIDEO, .VIDEO_NOTE, .AUDIO, .VOICE, .DOCUMENT:
            return true
        default:
            return false
        }
    }()

    let isTransferComplete = !message.message.shouldUploadDownload && !message.message.shouldRetry

    return Group {
        if isSupportedType && isTransferComplete && !isSelectionMode && !message.isViewOnce {
            Button {
                chatVM.onMessageAction(.forward, to: .message(message))
            } label: {
                Image(systemName: "arrowshape.turn.up.right.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .padding(10)
                    .foregroundColor(Color(.systemGray))
                    .clipShape(Circle())
            }
            .accessibilityLabel(
                chatVM.translationService?
                    .resolve(key: ChatTranslationKeys.MENU_FORWARD, module: ChatTranslationKeys.MODULE)
                    .value ?? "Forward"
            )
            .transition(.asymmetric(
                insertion: .scale.combined(with: .opacity),
                removal: .scale.combined(with: .opacity)
            ))
        }
    }
}

struct BubbleView: View {
    let row: MessageRow
    let channel: ChannelItem
    /// Nil for anything that carries no sender identity — own messages, system
    /// records, every row of a direct chat — which is also what suppresses the
    /// gutter. See `GroupSenderRunResolver`.
    let senderRunPosition: SenderRunPosition?
    @ObservedObject var uploadVM: FileUploadViewModel
    /// Held, not observed: the room view model is a service locator here, and
    /// subscribing every bubble to it re-rendered the whole timeline on any change.
    let chatVM: ChatRoomViewModel
    /// The three pieces of room state a bubble actually reacts to, passed in as
    /// values by the message list — which is already observing them — rather than
    /// read back off `chatVM`, which would re-introduce the subscription.
    let isSelectionMode: Bool
    let isContextMenuVisible: Bool
    let isGroupAdmin: Bool
    var contactsUseCases: ContactsUseCasesProtocol
    let opusPlaybackService: any OpusPlaybackServiceProtocol
    let navigationCoord: ChatsTabCoordinator
    let globalAudioPlaybackManager: GlobalAudioPlaybackManager
    var onGroupIntroAddMembers: (() -> Void)?
    var onGroupIntroInviteLink: (() -> Void)?
    var onJoinRequestCheckpointTap: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    
    /// A record the backend projected into the thread rather than something a user
    /// sent. It renders as a checkpoint and nothing else: no bubble, no sender
    /// name above it, no reactions, no ticks.
    private var systemRecordAction: ChatActionItem? {
        guard case .message(let message) = row else { return nil }
        return ChatActionItem(
            groupEvent: message,
            conversationId: chatVM.conversationId,
            groupName: channel.name
        )
    }

    /// A group thread indents every received row by a gutter, even the rows that
    /// do not draw the face, so a run of bubbles keeps one left edge.
    private var showsSenderGutter: Bool {
        senderRunPosition != nil && systemRecordAction == nil
    }

    private var resolvedSenderName: String? {
        row.primaryMessage.map {
            chatVM.senderDisplayName(forSenderId: $0.senderId, stampedName: $0.senderName)
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if showsSenderGutter {
                senderAvatarGutter
            }

            VStack(alignment: .leading, spacing: 0) {
                if senderRunPosition?.isFirstOfRun == true,
                   systemRecordAction == nil,
                   let name = resolvedSenderName, !name.isEmpty {
                    senderNameTextView(senderName: name)
                }

                composeDynamicBubbleView(contactsUseCases: contactsUseCases)
                    .overlay(alignment: row.primaryMessage?.reactionAnchor ?? .bottom) {
                        if let message = row.primaryMessage,
                           systemRecordAction == nil,
                           message.hasReactions,
                           !isContextMenuVisible {
                            MessageReactionView(message: message)
                                .offset(y: 15)
                                .padding(.horizontal)
                        }
                    }
            }
        }
        .padding(.bottom, row.primaryMessage?.hasReactions == true && !isContextMenuVisible ? 24 : 8)
    }

    // MARK: - Sender Avatar Gutter

    /// Draws the sender's face on the row that closes their run, and holds the
    /// same width empty on every other row of it.
    @ViewBuilder
    private var senderAvatarGutter: some View {
        Group {
            if senderRunPosition?.isLastOfRun == true, let message = row.primaryMessage {
                GroupSenderAvatarView(
                    imageUrl: chatVM.senderAvatarURL(forSenderId: message.senderId),
                    fallbackName: resolvedSenderName ?? message.senderName
                )
            } else {
                Color.clear
                    .frame(width: GroupSenderAvatarView.diameter, height: 0)
            }
        }
        .frame(width: GroupSenderAvatarView.gutterWidth, alignment: .leading)
        .padding(.leading, 6)
        .padding(.bottom, 2)
    }

    // MARK: - Bubble Content Builder
    @ViewBuilder
    private func composeDynamicBubbleView(contactsUseCases: ContactsUseCasesProtocol) -> some View {
        switch row {
        case .message(let message):
            // The timeline never builds a `.message` row for a system record, but
            // this is the last gate before the bubble container — anything that
            // slipped through renders as the checkpoint it is.
            if let action = systemRecordAction {
                BubbleCheckpointView(
                    action: action,
                    translator: chatVM.translationService
                )
            } else {
                bubble(for: message, contactsUseCases: contactsUseCases)
            }
        case .mediaGroup(_, let messages):
            MediaGridBubbleView(
                messages: messages,
                isFromCurrentUser: messages.first?.direction == .sent,
                chatVM: chatVM,
                uploadVM: uploadVM,
                isSelectionMode: isSelectionMode
            )
        case .checkpoint(let action):
            BubbleCheckpointView(
                action: action,
                translator: chatVM.translationService,
                isTappable: action.isJoinRequestCheckpoint && isGroupAdmin,
                onTap: onJoinRequestCheckpointTap
            )
        case .encryptionBanner:
            ChatEncryptionNoticeView(translationService: chatVM.translationService)
        case .groupIntro(let content):
            GroupChatTimelineIntroCard(
                content: content,
                translationService: chatVM.translationService,
                onAddMembers: onGroupIntroAddMembers,
                onInviteLink: onGroupIntroInviteLink
            )
        }
    }
    
    // MARK: - Bubble Factory
    @ViewBuilder
    private func bubble(for message: MessageDataItem, contactsUseCases: ContactsUseCasesProtocol) -> some View {
        if message.isDeleted {
            deletedMessageView(for: message)
        } else if message.isViewOnce {
            // Whatever the type, the thread only ever shows the placeholder; the
            // real bubble is drawn once, in the full-screen viewer.
            BubbleViewOnceView(message: message, uploadVM: uploadVM, chatVM: chatVM, isSelectionMode: isSelectionMode)
        } else {
            switch message.typeMessage {
            case .TEXT:
                BubbleTextView(message: message, chatVM: chatVM, isSelectionMode: isSelectionMode)
            case .IMAGE, .VIDEO:
                BubbleImageView(
                    message: message,
                    uploadVM: uploadVM,
                    chatVM: chatVM,
                    isSelectionMode: isSelectionMode
                )
            case .VIDEO_NOTE:
                BubbleVideoNoteView(
                    message: message,
                    uploadVM: uploadVM,
                    chatVM: chatVM,
                    isSelectionMode: isSelectionMode
                )
            case .AUDIO, .VOICE:
                BubbleVoiceView(
                    message: message,
                    uploadVM: uploadVM,
                    isSelectionMode: isSelectionMode,
                    opusPlaybackService: opusPlaybackService,
                    chatRoomId: chatVM.conversationId,
                    globalAudioManager: globalAudioPlaybackManager,
                    chatVM: chatVM
                )
            case .DOCUMENT:
                BubbleDocumentView(message: message, uploadVM: uploadVM, isSelectionMode: isSelectionMode, chatVM: chatVM)
            case .CALL_AUDIO, .CALL_VIDEO, .MISSING_CALL_AUDIO, .MISSING_CALL_VIDEO:
                BubbleCallView(message: message, isSelectionMode: isSelectionMode, chatVM: chatVM)
            case .ISMONEY:
                // Modification unique de la timeline pour toute la finance
                // conversationnelle. Chaque nouveau type de carte s'enregistre
                // auprès de `FinancialCardRegistry` ; ce `switch` ne bouge plus.
                //
                // Rendait `EmptyView()` : le message traversait le réseau, les
                // mappers et la base, apparaissait dans l'aperçu de conversation
                // et dans la recherche, puis disparaissait du fil.
                financialBubble(for: message)
            case .CONTACT:
                if #available(iOS 16.0, *) {
                    BubbleContactView(
                        message: message,
                        contactsUseCases: contactsUseCases,
                        isSelectionMode: isSelectionMode,
                        navigationCoord: navigationCoord,
                        chatVM: chatVM
                    )
                } else {
                    EmptyView()
                }
            case .LOCATION:
                BubbleLocationView(message: message, isSelectionMode: isSelectionMode, chatVM: chatVM)
            case .POLL:
                BubblePollView(message: message, isSelectionMode: isSelectionMode, chatVM: chatVM)
            case .CHANNEL_INVITE:
                if #available(iOS 16.0, *) {
                    BubbleChannelInviteView(
                        message: message,
                        isSelectionMode: isSelectionMode,
                        onJoin: { channelId in
                            chatVM.handleChannelInviteJoin(channelId: channelId)
                        },
                        chatVM: chatVM
                    )
                } else {
                    EmptyView()
                }
            case .GROUP_CREATED, .GROUP_UPDATED, .USER_ADDED_TO_GROUP, .USER_JOINED_GROUP,
                 .USER_LEFT_GROUP, .USER_REMOVED_FROM_GROUP, .USER_PROMOTED_TO_ADMIN,
                 .USER_DEMOTED_FROM_ADMIN:
                // Unreachable — `composeDynamicBubbleView` diverts system records to
                // a checkpoint before this switch. Present so the switch stays
                // exhaustive, and empty so no future path can bubble one.
                EmptyView()
            case .STATUS:
                // Reply-only type; standalone status messages are not rendered in chat bubbles.
                EmptyView()
            }
        }
    }
    
    // MARK: - Deleted Message View
    @ViewBuilder
    private func deletedMessageView(for message: MessageDataItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "nosign")
                .font(.caption)
            Text(
                chatVM.translationService?.resolve(
                    key: message.isSentByMe
                        ? ChatTranslationKeys.MESSAGE_DELETED_YOU
                        : ChatTranslationKeys.MESSAGE_DELETED,
                    module: ChatTranslationKeys.MODULE
                ).value
                ?? (message.isSentByMe ? "You deleted this message" : "This message was deleted")
            )
            .font(.subheadline)
            .italic()

            // Delete-for-everyone: show pending clock until delete ACK; failed if ACK fails.
            if message.isSentByMe, message.status == .PENDING || message.status == .FAILED {
                MessageStatusIcon(messageStatus: message.status)
            }
        }
        .foregroundColor(ChatBubbleStyle.secondaryForeground(for: colorScheme))
        .fixedSize(horizontal: false, vertical: true)
        .applyDeletedMessageModifiers(message: message)
    }
    
    // MARK: - Sender Name View
    private func senderNameTextView(senderName: String) -> some View {
        Text(senderName)
            .lineLimit(1)
            .foregroundColor(.gray)
            .font(.footnote)
            .padding(.bottom, 2)
            // Matches the leading inset the received bubbles set on themselves,
            // so the name sits over the bubble's edge rather than adrift of it.
            .padding(.leading, 10)
            .padding(.trailing, 8)
    }
}

// MARK: - Convenience Extension
extension MessageRow {
    var primaryMessage: MessageDataItem? {
        switch self {
        case .message(let msg):
            return msg
        case .mediaGroup(_, let msgs):
            return msgs.first
        case .checkpoint, .encryptionBanner, .groupIntro:
            return nil
        }
    }
}


// MARK: - Bulle financière

extension BubbleView {

    /// Carte, note de l'expéditeur, heure et accusés — dans cet ordre, comme
    /// une légende sous une photo. La note dit à l'autre à quoi sert l'argent ;
    /// elle voyage dans `message.message.text` et n'était jamais dessinée.
    @ViewBuilder
    fileprivate func financialBubble(for message: MessageDataItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let payload = message.message.financial {
                // La carte ouvre ses suites — reçu, litige, support. Une
                // carte inerte laisse sans recours au moment précis où
                // quelque chose s'est mal passé.
                //
                // Un geste plutôt qu'un `Button` : la carte de demande porte ses
                // propres boutons (« Payer », « Refuser »), et un bouton dans
                // l'étiquette d'un autre bouton ne reçoit pas le toucher. Les
                // boutons internes l'emportent sur ce geste ; le reste de la
                // carte ouvre ses suites comme avant.
                FinancialCardRegistry.view(for: payload)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // En sélection multiple, le tap appartient à la sélection.
                        guard !isSelectionMode else { return }
                        chatVM.onTapFinancialCard(payload)
                    }
                    .allowsHitTesting(!isSelectionMode)
                    .accessibilityAddTraits(.isButton)
                    // Une carte qui lit au serveur — le partage, qui dit qui a
                    // payé — trouve ici ses services. Les autres l'ignorent.
                    .environment(\.financeFlowSurface, chatVM.financeSurface)
                    .environment(\.financeOperationKeys, chatVM.financeSurface?.operationKeys ?? .processLocal)
                    .environment(\.financeRequestActions, chatVM.financeRequestActions)
            } else {
                // Marqué financier mais sans carte reconstructible : message
                // antérieur au Bloc 1, ou objet pas encore réconcilié. La note
                // existe déjà : elle est affichée quand même.
                PendingFinancialCard(transactionId: message.transactionId)
            }

            financialNoteAndMeta(for: message)
        }
        // Largeur des cartes : une longue note se replie au lieu d'élargir la bulle.
        .frame(maxWidth: 280, alignment: .leading)
        .environment(\.financeCardDirection, message.direction)
        .financialBubbleChrome(direction: message.direction)
    }

    /// Sans note, l'heure se range seule à droite sous la carte ; avec une note,
    /// elle se pose en bas à droite du texte, comme dans une bulle de texte.
    @ViewBuilder
    private func financialNoteAndMeta(for message: MessageDataItem) -> some View {
        let note = message.message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let meta = BubbleMetaOverlay(
            message: message,
            style: .bubble(colorScheme: colorScheme),
            translationService: chatVM.translationService
        )

        if note.isEmpty {
            HStack {
                Spacer(minLength: 0)
                meta
            }
            .padding(.horizontal, 4)
        } else {
            Text(note)
                .foregroundColor(ChatBubbleStyle.foreground(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 16)
                .padding(.horizontal, 4)
                .overlay(alignment: .bottomTrailing) {
                    meta
                        .padding(.trailing, 4)
                        .padding(.bottom, 2)
                }
        }
    }
}

// MARK: - Chrome de bulle pour les cartes financières

private struct FinancialBubbleChrome: ViewModifier {

    let direction: MessageDirection
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(8)
            // Le fond de bulle réel, pas un voile gris. Les cartes financières
            // s'affichaient sur `Color.primary.opacity(0.06)` — un aplat qui ne
            // suit ni le sens du message ni le thème — si bien qu'un paiement ne
            // ressemblait pas à un message dans son propre fil.
            .background(ChatBubbleStyle.background(for: direction))
            // Même rayon que les bulles de texte : à 14 contre 16, la différence
            // se voit sans qu'on sache la nommer.
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .applyTailView(direction)
            // Alignement et retraits asymétriques, comme tout autre message :
            // une carte pleine largeur se lit comme une bannière système, pas
            // comme quelque chose que quelqu'un a envoyé.
            .frame(maxWidth: .infinity,
                   alignment: direction == .sent ? .trailing : .leading)
            .padding(.leading, direction == .received ? 5 : 55)
            .padding(.trailing, direction == .received ? 55 : 5)
    }
}

private extension View {
    func financialBubbleChrome(direction: MessageDirection) -> some View {
        modifier(FinancialBubbleChrome(direction: direction))
    }
}
