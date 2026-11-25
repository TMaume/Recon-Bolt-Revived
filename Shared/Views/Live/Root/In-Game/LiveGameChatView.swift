import SwiftUI
import ValorantAPI

enum LiveChatChannel: Identifiable, Hashable {
	case team(roomJID: String, matchID: Match.ID, isPregame: Bool)
	case all(roomJID: String, matchID: Match.ID)
	case party(roomJID: String, partyID: Party.ID)
	
	var id: String {
		switch self {
		case .team(let room, _, let isPregame):
			return "team:\(isPregame ? "pre" : "core"):\(room.lowercased())"
		case .all(let room, _):
			return "all:\(room.lowercased())"
		case .party(let room, _):
			return "party:\(room.lowercased())"
		}
	}
	
	var rawRoomJID: String {
		switch self {
		case .team(let room, _, _), .all(let room, _), .party(let room, _):
			return room
		}
	}
	
	var servicePrefix: String {
		switch self {
		case .team(_, _, let isPregame):
			return isPregame ? "ares-pregame" : "ares-coregame"
		case .all:
			return "ares-coregame"
		case .party:
			return "ares-parties"
		}
	}
	
	var title: LocalizedStringKey {
		switch self {
		case .team: return "Team"
		case .all: return "All"
		case .party: return "Party"
		}
	}
	
	var plainTitle: String {
		switch self {
		case .team: return String(localized: "Team")
		case .all: return String(localized: "All")
		case .party: return String(localized: "Party")
		}
	}
	
	var iconName: String {
		switch self {
		case .team: return "shield.lefthalf.filled"
		case .all: return "globe"
		case .party: return "person.3.fill"
		}
	}
	
	var accentColor: Color {
		switch self {
		case .team: return .valorantBlue
		case .all: return .orange
		case .party: return .purple
		}
	}
	
	func fetchToken(using client: ValorantClient) async throws -> String {
		switch self {
		case .team(_, let matchID, let isPregame):
			if isPregame {
				return try await client.getPregameChatToken(for: matchID)
			} else {
				return try await client.getCoreGameTeamChatToken(for: matchID)
			}
		case .all(_, let matchID):
			return try await client.getCoreGameAllChatToken(for: matchID)
		case .party(_, let partyID):
			return try await client.getPartyMUCToken(for: partyID)
		}
	}
}

struct LiveGameChatView: View {
	let channels: [LiveChatChannel]
	let userID: User.ID
	var playerAgents: [Player.ID: Agent.ID] = [:]
	var allyPlayerIDs: Set<Player.ID> = []
	
	@State private var selectedChannelID: String = ""
	@State private var draftMessage = ""
	@State private var isSending = false
	@State private var joiningChannelIDs: Set<String> = []
	@State private var errorByChannelID: [String: String] = [:]
	@State private var joinedRoomJIDs: Set<String> = []
	
	@EnvironmentObject private var socialManager: SocialManager
	@Environment(\.valorantLoad) private var load
	@Environment(\.assets) private var assets
	@Environment(\.dismiss) private var dismiss
	
	private var activeChannel: LiveChatChannel? {
		channels.first { $0.id == selectedChannelID } ?? channels.first
	}
	
	private func normalizedRoomJID(for channel: LiveChatChannel) -> String {
		socialManager.normalizeMUCRoomJID(channel.rawRoomJID, servicePrefix: channel.servicePrefix)
	}
	
	var body: some View {
		NavigationStack {
			VStack(spacing: 0) {
				if channels.isEmpty {
					emptyNoChannelsView
				} else {
					channelHeaderBar
					Divider()
					messagesArea
				}
			}
			.background(Color.groupedBackground)
			.navigationTitle("Live Match Chat")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .navigationBarTrailing) {
					Button("Done") { dismiss() }
				}
			}
			.safeAreaInset(edge: .bottom) {
				if let activeChannel {
					composerBar(for: activeChannel)
				}
			}
			.onAppear {
				if selectedChannelID.isEmpty, let first = channels.first {
					selectedChannelID = first.id
				}
			}
			.task(id: activeChannel?.id ?? "") {
				guard let channel = activeChannel else { return }
				await connectAndJoin(channel)
			}
			.onDisappear {
				let roomsToLeave = joinedRoomJIDs
				if !roomsToLeave.isEmpty {
					Task {
						for room in roomsToLeave {
							await socialManager.leaveMUCRoom(room)
						}
					}
				}
			}
		}
	}
	
	private var emptyNoChannelsView: some View {
		VStack(spacing: 12) {
			Spacer()
			Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
				.font(.system(size: 40))
				.foregroundStyle(.secondary)
			Text("Chat Unavailable")
				.font(.headline)
			Text("No active live chat channel was exposed by the match server.")
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
				.padding(.horizontal, 36)
			Spacer()
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
	
	private var channelHeaderBar: some View {
		VStack(spacing: 8) {
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 8) {
					ForEach(channels) { channel in
						let isSelected = channel.id == activeChannel?.id
						let room = normalizedRoomJID(for: channel)
						let count = socialManager.mucMessagesByRoom[room]?.count ?? 0
						
						Button {
							selectedChannelID = channel.id
						} label: {
							HStack(spacing: 6) {
								Image(systemName: channel.iconName)
									.font(.caption.weight(.semibold))
								Text(channel.title)
									.font(.subheadline.weight(.semibold))
								if count > 0 {
									Text("\(count)")
										.font(.caption2.weight(.bold))
										.monospacedDigit()
										.padding(.horizontal, 6)
										.padding(.vertical, 2)
										.background(.ultraThinMaterial, in: Capsule())
								}
							}
							.padding(.horizontal, 12)
							.padding(.vertical, 7)
							.foregroundStyle(isSelected ? .white : .primary)
							.background(
								isSelected ? channel.accentColor : Color.secondaryGroupedBackground,
								in: Capsule()
							)
						}
						.buttonStyle(.plain)
					}
				}
				.padding(.horizontal, 16)
				.padding(.top, 10)
			}
			
			if let activeChannel {
				connectionStatusBanner(for: activeChannel)
					.padding(.horizontal, 16)
					.padding(.bottom, 8)
			}
		}
		.background(Color.groupedBackground)
	}
	
	@ViewBuilder
	private func connectionStatusBanner(for channel: LiveChatChannel) -> some View {
		let room = normalizedRoomJID(for: channel)
		let isJoined = socialManager.joinedMUCRooms.contains(room)
		let isJoining = joiningChannelIDs.contains(channel.id)
		let errorText = errorByChannelID[channel.id] ?? socialManager.mucErrorByRoom[room]
		
		HStack(spacing: 8) {
			Circle()
				.fill(statusDotColor(isJoined: isJoined, hasError: errorText != nil))
				.frame(width: 8, height: 8)
			
			if let errorText {
				Text(errorText)
					.font(.caption)
					.foregroundStyle(.red)
					.lineLimit(2)
			} else if isJoining {
				Text("Connecting to \(channel.plainTitle) chat…")
					.font(.caption)
					.foregroundStyle(.secondary)
			} else if isJoined {
				Text("Connected to \(channel.plainTitle) chat")
					.font(.caption)
					.foregroundStyle(.secondary)
			} else {
				Text("Waiting for chat room…")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			
			Spacer()
			
			if !isJoining && (!isJoined || errorText != nil) {
				Button("Retry") {
					Task { await connectAndJoin(channel) }
				}
				.font(.caption.weight(.semibold))
				.foregroundStyle(Color.accentColor)
			}
		}
	}
	
	private func statusDotColor(isJoined: Bool, hasError: Bool) -> Color {
		if hasError { return .red }
		if isJoined { return .green }
		return .orange
	}
	
	@ViewBuilder
	private var messagesArea: some View {
		if let activeChannel {
			let room = normalizedRoomJID(for: activeChannel)
			let messages = socialManager.mucMessagesByRoom[room] ?? []
			
			if messages.isEmpty {
				VStack(spacing: 10) {
					Spacer()
					Image(systemName: activeChannel.iconName)
						.font(.system(size: 32, weight: .light))
						.foregroundStyle(activeChannel.accentColor.opacity(0.8))
					Text("No messages in \(activeChannel.plainTitle) yet")
						.font(.subheadline.weight(.medium))
						.foregroundStyle(.secondary)
					Text("Messages sent or received in-game appear here live.")
						.font(.caption)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
						.padding(.horizontal, 40)
					Spacer()
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else {
				ScrollViewReader { proxy in
					ScrollView {
						LazyVStack(spacing: 10) {
							ForEach(messages) { message in
								messageRow(message, channel: activeChannel)
									.id(message.id)
							}
							Color.clear
								.frame(height: 1)
								.id("chat-bottom")
						}
						.padding(.horizontal, 14)
						.padding(.vertical, 12)
					}
					.onAppear {
						proxy.scrollTo("chat-bottom", anchor: .bottom)
					}
					.onChange(of: messages.count) { _ in
						withAnimation(.easeOut(duration: 0.2)) {
							proxy.scrollTo("chat-bottom", anchor: .bottom)
						}
					}
				}
			}
		}
	}
	
	private func messageRow(_ message: XMPPMUCMessage, channel: LiveChatChannel) -> some View {
		let isSelf = message.isOutgoing
		let agentID = message.senderPUUID.flatMap { playerAgents[$0] }
		let senderLabel = resolvedSenderName(for: message)
		let senderColor: Color = {
			if isSelf { return Color.valorantSelf }
			if let puuid = message.senderPUUID, allyPlayerIDs.contains(puuid) {
				return Color.valorantBlue
			}
			return .secondary
		}()
		
		return HStack(alignment: .bottom, spacing: 8) {
			if isSelf {
				Spacer(minLength: 48)
			} else if let agentID {
				AgentImage.icon(agentID, outlineRadius: 1)
					.frame(width: 28, height: 28)
					.clipShape(Circle())
			}
			
			VStack(alignment: isSelf ? .trailing : .leading, spacing: 3) {
				HStack(spacing: 6) {
					Text(senderLabel)
						.font(.caption2.weight(.semibold))
						.foregroundStyle(senderColor)
					Text(message.timestamp.formatted(date: .omitted, time: .shortened))
						.font(.caption2)
						.foregroundStyle(.tertiary)
				}
				
				Text(message.body)
					.font(.subheadline)
					.foregroundStyle(isSelf ? .white : .primary)
					.padding(.horizontal, 12)
					.padding(.vertical, 8)
					.background(
						isSelf ? channel.accentColor : Color.secondaryGroupedBackground,
						in: RoundedRectangle(cornerRadius: 14, style: .continuous)
					)
			}
			
			if !isSelf {
				Spacer(minLength: 48)
			}
		}
	}
	
	private func resolvedSenderName(for message: XMPPMUCMessage) -> String {
		if message.isOutgoing {
			return String(localized: "You")
		}
		if let puuid = message.senderPUUID {
			if let cachedUser = LocalDataProvider.shared.userManager.loadedObject(for: puuid),
			   !cachedUser.gameName.isEmpty {
				return cachedUser.gameName
			}
			if let friend = socialManager.friendsByJID.values.first(where: { $0.puuid == puuid }),
			   !friend.gameName.isEmpty {
				return friend.gameName
			}
			if let agentID = playerAgents[puuid], let agentName = assets?.agents[agentID]?.displayName {
				return agentName
			}
		}
		let cleanNick = message.senderNick.components(separatedBy: "@").first ?? message.senderNick
		if cleanNick.count > 20, UUID(uuidString: cleanNick) != nil {
			return "Player \(cleanNick.prefix(6))"
		}
		return cleanNick.isEmpty ? "Player" : cleanNick
	}
	
	private func composerBar(for channel: LiveChatChannel) -> some View {
		let room = normalizedRoomJID(for: channel)
		let canSend = !draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			&& socialManager.connectionState == .connected
			&& !isSending
		
		return HStack(spacing: 10) {
			TextField("Message \(channel.plainTitle)…", text: $draftMessage)
				.textFieldStyle(.plain)
				.submitLabel(.send)
				.onSubmit {
					if canSend { sendCurrentMessage(to: channel, normalizedRoom: room) }
				}
				.padding(.horizontal, 14)
				.padding(.vertical, 10)
				.background(Color.secondaryGroupedBackground, in: Capsule())
			
			Button {
				sendCurrentMessage(to: channel, normalizedRoom: room)
			} label: {
				Group {
					if isSending {
						ProgressView()
							.tint(.white)
							.scaleEffect(0.8)
					} else {
						Image(systemName: "arrow.up")
							.font(.subheadline.weight(.bold))
							.foregroundStyle(.white)
					}
				}
				.frame(width: 38, height: 38)
				.background(canSend ? Color.accentColor : Color.secondary.opacity(0.35), in: Circle())
			}
			.disabled(!canSend)
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 10)
		.background(
			Color.groupedBackground.opacity(0.96)
				.ignoresSafeArea(edges: .bottom)
		)
	}
	
	private func connectAndJoin(_ channel: LiveChatChannel) async {
		joiningChannelIDs.insert(channel.id)
		errorByChannelID[channel.id] = nil
		defer { joiningChannelIDs.remove(channel.id) }
		
		await load { client in
			do {
				if socialManager.connectionState != .connected {
					await socialManager.connectIfNeeded(using: client)
					// Wait briefly if an earlier connect task was still in flight.
					for _ in 0..<25 where socialManager.connectionState == .connecting {
						try? await Task.sleep(for: .milliseconds(200))
					}
				}
				
				guard socialManager.connectionState == .connected else {
					if case .failed(let msg) = socialManager.connectionState {
						errorByChannelID[channel.id] = msg
					} else {
						errorByChannelID[channel.id] = String(localized: "Not connected to Riot XMPP chat.")
					}
					return
				}
				
				// GLZ token endpoints (`teamchatmuctoken`, `allchatmuctoken`, `muctoken`) frequently return 500/404; join over XMPP directly when omitted.
				let token = try? await channel.fetchToken(using: client)
				let normalizedRoom = socialManager.normalizeMUCRoomJID(
					channel.rawRoomJID,
					servicePrefix: channel.servicePrefix
				)
				try await socialManager.joinMUCRoom(normalizedRoom, token: token)
				joinedRoomJIDs.insert(normalizedRoom)
			} catch {
				errorByChannelID[channel.id] = error.localizedDescription
			}
		}
	}
	
	private func sendCurrentMessage(to channel: LiveChatChannel, normalizedRoom: String) {
		let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !text.isEmpty else { return }
		
		draftMessage = ""
		isSending = true
		Task {
			defer { isSending = false }
			do {
				if socialManager.connectionState != .connected || !socialManager.joinedMUCRooms.contains(normalizedRoom) {
					await connectAndJoin(channel)
				}
				try await socialManager.sendMUCMessage(text, to: normalizedRoom)
			} catch {
				errorByChannelID[channel.id] = error.localizedDescription
				draftMessage = text
			}
		}
	}
}
