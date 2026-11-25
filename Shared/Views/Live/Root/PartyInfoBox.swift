import SwiftUI
import ValorantAPI
import HandyOperators

struct PartyInfoBox: View {
	var userID: User.ID
	@Binding var party: Party
	var partyPlayer: PartyPlayer? = nil
	@Binding var shouldAutoShow: Bool
	var onPartyChanged: () async -> Void = {}
	var onStartPracticeRange: () async -> Void = {}
	
	@State private var showingSettings = false
	@State private var isTogglingAccessibility = false
	@State private var isStartingRange = false
	@State private var selectedProfileMemberID: Player.ID?
	@State private var processingRequestID: String?
	
	@Environment(\.valorantLoad) private var load
	
	var member: Party.Member {
		party.members.firstElement(withID: userID)
		?? party.members.first! // can be nil while switching accounts
	}
	
	private var isSelfOwner: Bool {
		member.isOwner
	}
	
	var body: some View {
		VStack(spacing: 14) {
			VStack(spacing: 10) {
				ForEach(party.members) { partyMember in
					PartyMemberRow(
						party: $party,
						member: partyMember,
						userID: userID,
						isSelfOwner: isSelfOwner,
						onViewProfile: { selectedProfileMemberID = partyMember.id },
						onPartyChanged: onPartyChanged
					)
				}
			}
			
			if isSelfOwner && !party.requests.isEmpty {
				joinRequestsSection
			}
			
			if let incomingRequests = partyPlayer?.requests.filter({ $0.partyID != party.id }),
			   !incomingRequests.isEmpty {
				incomingInvitesSection(incomingRequests)
			}
			
			Divider()
				.opacity(0.45)
			
			bottomControlsBar
		}
		.background(
			NavigationLink(
				"",
				isActive: Binding(
					get: { selectedProfileMemberID != nil },
					set: { if !$0 { selectedProfileMemberID = nil } }
				)
			) {
				if let selectedProfileMemberID {
					MatchListView(userID: selectedProfileMemberID)
				}
			}
			.hidden()
		)
		.sheet(isPresented: $showingSettings) {
			PartySettingsView(
				party: $party,
				userID: userID,
				shouldAutoShow: $shouldAutoShow,
				onPartyChanged: onPartyChanged,
				onStartPracticeRange: onStartPracticeRange
			)
		}
	}
	
	private var bottomControlsBar: some View {
		HStack(spacing: 10) {
			accessibilitySegmentedPill
			
			Spacer(minLength: 4)
			
			matchmakingPill
			
			Spacer(minLength: 4)
			
			practiceRangeButton
			
			Button {
				showingSettings = true
			} label: {
				Image(systemName: "ellipsis")
					.font(.body.weight(.semibold))
					.foregroundStyle(Color.accentColor)
					.frame(width: 42, height: 42)
					.background(Color.tertiaryGroupedBackground, in: Circle())
			}
			.accessibilityLabel("Party Settings")
		}
	}
	
	private var accessibilitySegmentedPill: some View {
		let canToggle = isSelfOwner && party.state == .default && !isTogglingAccessibility
		
		return HStack(spacing: 2) {
			accessibilityButton(.open, icon: "lock.open", canToggle: canToggle)
			accessibilityButton(.closed, icon: "lock", canToggle: canToggle)
		}
		.padding(4)
		.background(Color.tertiaryGroupedBackground, in: Capsule())
		.opacity((isSelfOwner && party.state == .default) ? 1 : 0.65)
	}
	
	private func accessibilityButton(
		_ target: Party.Accessibility,
		icon: String,
		canToggle: Bool
	) -> some View {
		let isActive = party.accessibility == target
		return Button {
			guard party.accessibility != target else { return }
			setAccessibility(to: target)
		} label: {
			Image(systemName: icon)
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(isActive ? Color.accentColor : .secondary)
				.frame(width: 38, height: 32)
				.background {
					if isActive {
						Capsule()
							.fill(Color.secondaryGroupedBackground)
							.shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
					}
				}
		}
		.buttonStyle(.plain)
		.disabled(!canToggle)
		.accessibilityLabel(target == .open ? "Open Party" : "Closed Party")
	}
	
	@ViewBuilder
	private var matchmakingPill: some View {
		switch party.state {
		case .inMatchmaking:
			AsyncButton {
				await load {
					party = try await $0.leaveMatchmaking(in: party.id)
				}
			} label: {
				HStack(spacing: 8) {
					Image(systemName: "stop.fill")
						.font(.caption.weight(.bold))
					queueTimer(entryTime: party.queueEntryTime)
				}
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(Color.accentColor)
				.padding(.horizontal, 18)
				.padding(.vertical, 11)
				.background(Color.accentColor.opacity(0.16), in: Capsule())
				.overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1))
			}
			.buttonStyle(.plain)
		case .default:
			let canStart = isSelfOwner && party.members.allSatisfy(\.isReady)
			AsyncButton {
				await load {
					party = try await $0.joinMatchmaking(in: party.id)
				}
			} label: {
				HStack(spacing: 7) {
					Text("Start")
						.font(.headline.weight(.semibold))
					Image(systemName: "play.fill")
						.font(.caption.weight(.bold))
				}
				.foregroundStyle(Color.accentColor)
				.padding(.horizontal, 20)
				.padding(.vertical, 11)
				.background(Color.tertiaryGroupedBackground, in: Capsule())
			}
			.buttonStyle(.plain)
			.disabled(!canStart)
			.opacity(canStart ? 1 : 0.45)
		default:
			EmptyView()
		}
	}
	
	private var practiceRangeButton: some View {
		let canEnterRange = party.members.count <= 1 && party.state == .default && !isStartingRange
		return Button {
			Task {
				isStartingRange = true
				defer { isStartingRange = false }
				await onStartPracticeRange()
			}
		} label: {
			Group {
				if isStartingRange {
					ProgressView()
						.tint(Color.accentColor)
				} else {
					Image(systemName: "scope")
						.font(.body.weight(.semibold))
						.foregroundStyle(Color.accentColor)
				}
			}
			.frame(width: 42, height: 42)
			.background(Color.tertiaryGroupedBackground, in: Circle())
		}
		.buttonStyle(.plain)
		.disabled(!canEnterRange)
		.opacity((party.members.count <= 1 && party.state == .default) ? 1 : 0.4)
		.accessibilityLabel("Practice Range")
	}
	
	private var joinRequestsSection: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("Join Requests")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
			
			ForEach(party.requests) { request in
				RequestPlayerRow(
					request: request,
					isProcessing: processingRequestID == request.id,
					onDecline: { declineJoinRequest(request) }
				)
			}
		}
	}
	
	private func incomingInvitesSection(_ requests: [Party.JoinRequest]) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("Party Invites")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
			
			ForEach(requests) { request in
				IncomingInviteRow(
					request: request,
					isProcessing: processingRequestID == request.id,
					onAccept: { acceptPartyInvite(request) },
					onDecline: { declinePartyInvite(request) }
				)
			}
		}
	}
	
	private static let queueTimeFormatter = DateComponentsFormatter() <- {
		$0.zeroFormattingBehavior = .pad
		$0.allowedUnits = [.minute, .second]
	}
	
	func queueTimer(entryTime: Date) -> some View {
		TimelineView(.periodic(from: entryTime, by: 1)) { context in
			let elapsed = max(0, context.date.timeIntervalSince(entryTime))
			let time = Self.queueTimeFormatter.string(from: elapsed) ?? "0:00"
			Text(time)
				.monospacedDigit()
		}
	}
	
	private func setAccessibility(to accessibility: Party.Accessibility) {
		Task {
			isTogglingAccessibility = true
			defer { isTogglingAccessibility = false }
			await load {
				party = try await $0.setPartyAccessibility(in: party.id, to: accessibility)
			}
		}
	}
	
	private func declineJoinRequest(_ request: Party.JoinRequest) {
		Task {
			processingRequestID = request.id
			defer { processingRequestID = nil }
			await load {
				party = try await $0.declinePartyRequest(request.id, in: party.id)
			}
		}
	}
	
	private func acceptPartyInvite(_ request: Party.JoinRequest) {
		Task {
			processingRequestID = request.id
			defer { processingRequestID = nil }
			await load {
				party = try await $0.joinParty(request.partyID)
			}
			await onPartyChanged()
		}
	}
	
	private func declinePartyInvite(_ request: Party.JoinRequest) {
		Task {
			processingRequestID = request.id
			defer { processingRequestID = nil }
			await load {
				try await $0.declinePartyInvite(for: request.partyID)
			}
			await onPartyChanged()
		}
	}
	
	struct PartyMemberRow: View {
		@Binding var party: Party
		let member: Party.Member
		let userID: User.ID
		let isSelfOwner: Bool
		var onViewProfile: () -> Void
		var onPartyChanged: () async -> Void
		
		@State private var isSettingReady = false
		@State private var isRunningAction = false
		
		@LocalData var memberUser: User?
		@LocalData var summary: CareerSummary?
		
		@Environment(\.valorantLoad) private var load
		
		init(
			party: Binding<Party>,
			member: Party.Member,
			userID: User.ID,
			isSelfOwner: Bool,
			onViewProfile: @escaping () -> Void = {},
			onPartyChanged: @escaping () async -> Void = {}
		) {
			self._party = party
			self.member = member
			self.userID = userID
			self.isSelfOwner = isSelfOwner
			self.onViewProfile = onViewProfile
			self.onPartyChanged = onPartyChanged
			self._memberUser = .init(id: member.id)
			self._summary = .init(id: member.id)
		}
		
		var body: some View {
			let iconSize = 48.0
			
			HStack(spacing: 12) {
				PlayerCardImage.small(member.identity.cardID)
					.frame(width: iconSize, height: iconSize)
					.mask(RoundedRectangle(cornerRadius: 10, style: .continuous))
				
				VStack(alignment: .leading, spacing: 2) {
					if let memberUser {
						HStack(spacing: 0) {
							Text(memberUser.gameName)
								.font(.headline.weight(.semibold))
							Text("#\(memberUser.tagLine)")
								.font(.subheadline)
								.foregroundStyle(.secondary)
						}
						.lineLimit(1)
						.minimumScaleFactor(0.8)
					} else {
						Text("Member", comment: "Party Box: shown when member's name is not yet loaded")
							.font(.headline)
							.foregroundStyle(.secondary)
					}
					
					if member.isReady {
						Text("Ready", comment: "Party Box")
							.font(.subheadline)
							.foregroundStyle(.secondary)
					} else {
						Text("Not Ready", comment: "Party Box")
							.font(.subheadline.weight(.medium))
							.foregroundStyle(.secondary)
					}
				}
				
				Spacer(minLength: 8)
				
				if member.id == userID {
					if isSettingReady {
						ProgressView()
					} else {
						Toggle(String(localized: "Ready", comment: "accessibility label"), isOn: Binding(
							get: { member.isReady },
							set: { setReady(to: $0) }
						))
						.labelsHidden()
						.tint(Color.accentColor)
					}
				} else {
					HStack(spacing: 8) {
						RankInfoView(summary: summary, size: 36)
						
						Menu {
							Button {
								onViewProfile()
							} label: {
								Label("View Profile", systemImage: "person.crop.circle")
							}
							
							if isSelfOwner && party.state == .default {
								Button {
									makeLeader()
								} label: {
									Label("Make Party Leader", systemImage: "crown")
								}
								
								Button(role: .destructive) {
									kickMember()
								} label: {
									Label("Remove from Party", systemImage: "person.badge.minus")
								}
							}
						} label: {
							Group {
								if isRunningAction {
									ProgressView()
								} else {
									Image(systemName: "ellipsis.circle")
										.font(.title3)
										.foregroundStyle(.secondary)
								}
							}
							.frame(width: 28, height: 28)
						}
					}
				}
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 10)
			.background {
				RoundedRectangle(cornerRadius: 14, style: .continuous)
					.fill(Color.tertiaryGroupedBackground)
					.overlay(
						RoundedRectangle(cornerRadius: 14, style: .continuous)
							.strokeBorder(.primary.opacity(0.05), lineWidth: 1)
					)
					.overlay {
						if member.isOwner {
							Image(systemName: "crown")
								.font(.system(size: 52, weight: .light))
								.foregroundStyle(.primary.opacity(0.08))
								.offset(x: 6)
								.allowsHitTesting(false)
						}
					}
					.clipped()
			}
			.contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
			.contextMenu {
				if member.id != userID {
					Button {
						onViewProfile()
					} label: {
						Label("View Profile", systemImage: "person.crop.circle")
					}
					
					if isSelfOwner && party.state == .default {
						Button {
							makeLeader()
						} label: {
							Label("Make Party Leader", systemImage: "crown")
						}
						
						Button(role: .destructive) {
							kickMember()
						} label: {
							Label("Remove from Party", systemImage: "person.badge.minus")
						}
					}
				}
			}
			.withLocalData($memberUser, id: member.id, shouldAutoUpdate: true)
			.withLocalData($summary, id: member.id, shouldAutoUpdate: true)
		}
		
		func setReady(to isReady: Bool) {
			Task {
				isSettingReady = true
				defer { isSettingReady = false }
				await load {
					party = try await $0.setReady(to: isReady, in: party.id)
				}
			}
		}
		
		private func makeLeader() {
			Task {
				isRunningAction = true
				defer { isRunningAction = false }
				await load {
					party = try await $0.transferPartyOwner(to: member.id, in: party.id)
				}
			}
		}
		
		private func kickMember() {
			Task {
				isRunningAction = true
				defer { isRunningAction = false }
				await load {
					try await $0.removePlayerFromParty(member.id)
				}
				await onPartyChanged()
			}
		}
	}
	
	private struct RequestPlayerRow: View {
		let request: Party.JoinRequest
		let isProcessing: Bool
		let onDecline: () -> Void
		
		@LocalData var requesterUser: User?
		
		init(request: Party.JoinRequest, isProcessing: Bool, onDecline: @escaping () -> Void) {
			self.request = request
			self.isProcessing = isProcessing
			self.onDecline = onDecline
			self._requesterUser = .init(id: request.requestedBy)
		}
		
		var body: some View {
			HStack(spacing: 10) {
				Image(systemName: "person.badge.clock")
					.foregroundStyle(Color.accentColor)
				
				VStack(alignment: .leading, spacing: 1) {
					Text(requesterUser?.name ?? "Player")
						.font(.subheadline.weight(.medium))
						.lineLimit(1)
					Text("Wants to join")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				
				Spacer()
				
				if isProcessing {
					ProgressView()
				} else {
					Button {
						onDecline()
					} label: {
						Image(systemName: "xmark")
							.font(.caption.weight(.bold))
							.foregroundStyle(.secondary)
							.frame(width: 28, height: 28)
							.background(Color.secondaryGroupedBackground, in: Circle())
					}
					.buttonStyle(.plain)
				}
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 8)
			.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
			.withLocalData($requesterUser, id: request.requestedBy, shouldAutoUpdate: true)
		}
	}
	
	private struct IncomingInviteRow: View {
		let request: Party.JoinRequest
		let isProcessing: Bool
		let onAccept: () -> Void
		let onDecline: () -> Void
		
		@LocalData var inviterUser: User?
		
		init(
			request: Party.JoinRequest,
			isProcessing: Bool,
			onAccept: @escaping () -> Void,
			onDecline: @escaping () -> Void
		) {
			self.request = request
			self.isProcessing = isProcessing
			self.onAccept = onAccept
			self.onDecline = onDecline
			self._inviterUser = .init(id: request.requestedBy)
		}
		
		var body: some View {
			HStack(spacing: 10) {
				Image(systemName: "envelope.open.fill")
					.foregroundStyle(Color.accentColor)
				
				VStack(alignment: .leading, spacing: 1) {
					Text(inviterUser?.name ?? "Party Invite")
						.font(.subheadline.weight(.medium))
						.lineLimit(1)
					Text("Invited you to join their party")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				
				Spacer()
				
				if isProcessing {
					ProgressView()
				} else {
					HStack(spacing: 6) {
						Button {
							onDecline()
						} label: {
							Image(systemName: "xmark")
								.font(.caption.weight(.bold))
								.foregroundStyle(.secondary)
								.frame(width: 28, height: 28)
								.background(Color.secondaryGroupedBackground, in: Circle())
						}
						.buttonStyle(.plain)
						
						Button {
							onAccept()
						} label: {
							Image(systemName: "checkmark")
								.font(.caption.weight(.bold))
								.foregroundStyle(.white)
								.frame(width: 28, height: 28)
								.background(Color.accentColor, in: Circle())
						}
						.buttonStyle(.plain)
					}
				}
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 8)
			.background(Color.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
			.withLocalData($inviterUser, id: request.requestedBy, shouldAutoUpdate: true)
		}
	}
}

#if DEBUG
struct PartyInfoBox_Previews: PreviewProvider {
	static var previews: some View {
		Group {
			previewBox {
				PartyInfoBox(
					userID: PreviewData.userID,
					party: .constant(PreviewData.party),
					shouldAutoShow: .constant(false)
				)
				.padding(14)
			}
			
			previewBox {
				PartyInfoBox(
					userID: PreviewData.userID,
					party: .constant(PreviewData.party <- {
						$0.members[0].isReady = false
						$0.members[1].isReady = true
						$0.queueEntryTime = .init(timeIntervalSinceNow: -35)
					}),
					shouldAutoShow: .constant(true)
				)
				.padding(14)
			}
		}
	}
	
	static func previewBox<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
		RefreshableBox(title: "Party", isExpanded: .constant(true)) {
			content()
		} refresh: { _ in }
		.forPreviews()
	}
}
#endif
