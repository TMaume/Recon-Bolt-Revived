import SwiftUI
import ValorantAPI

struct ShootingRangeView: View {
	let userID: User.ID
	let inventory: Inventory
	let pregameInfo: LivePregameInfo?
	let liveGameInfo: LiveGameInfo?
	var onUpdatePregame: (LivePregameInfo) -> Void = { _ in }
	var onLeaveRange: () async -> Void = {}
	var onRestartRange: () async -> Void = {}
	
	@State private var selectedAgentID: Agent.ID?
	@State private var cooldownUntil: Date?
	@State private var isLeaving = false
	@State private var isRestarting = false
	@State private var statusNotice: String?
	
	@Environment(\.valorantLoad) private var load
	@Environment(\.assets) private var assets
	@Environment(\.dismiss) private var dismiss
	
	@ScaledMetric private var agentSize = 54
	private let switchCooldown: TimeInterval = 2.0
	
	private var mapID: MapID {
		pregameInfo?.mapID ?? liveGameInfo?.mapID ?? .rangeV2
	}
	
	private var currentAgentID: Agent.ID? {
		selectedAgentID
			?? pregameInfo?.team.players.firstElement(withID: userID)?.agentID
			?? liveGameInfo?.players.firstElement(withID: userID)?.agentID
	}
	
	private var ownPregameLocked: Bool {
		pregameInfo?.team.players.firstElement(withID: userID)?.isLockedIn == true
	}
	
	var body: some View {
		ScrollView {
			VStack(spacing: 0) {
				heroBanner
				
				VStack(spacing: 16) {
					cooldownOrStatusBar
					actionButtonsBar
					agentGrid
				}
				.padding(16)
			}
		}
		.background(Color.groupedBackground)
		.navigationTitle("Practice Range")
		.navigationBarTitleDisplayMode(.inline)
		.onAppear {
			syncSelectedAgentFromServer()
		}
		.onChange(of: pregameInfo?.team.players.firstElement(withID: userID)?.agentID) { _ in
			syncSelectedAgentFromServer()
		}
		.onChange(of: liveGameInfo?.players.firstElement(withID: userID)?.agentID) { _ in
			syncSelectedAgentFromServer()
		}
		.task(id: cooldownUntil) {
			guard let target = cooldownUntil else { return }
			let delay = target.timeIntervalSinceNow
			if delay > 0 {
				try? await Task.sleep(for: .seconds(delay))
			}
			cooldownUntil = nil
		}
	}
	
	private var heroBanner: some View {
		let agentInfo = currentAgentID.flatMap { assets?.agents[$0] }
		
		return ZStack(alignment: .bottomLeading) {
			MapImage.splash(mapID)
				.aspectRatio(contentMode: .fill)
				.frame(height: 170)
				.clipped()
				.overlay(
					LinearGradient(
						colors: [.black.opacity(0.15), .black.opacity(0.78)],
						startPoint: .top,
						endPoint: .bottom
					)
				)
			
			HStack(spacing: 12) {
				if let agentInfo {
					agentInfo.displayIcon.view(outlineRadius: 1.5, shouldLoadImmediately: true)
						.frame(width: 54, height: 54)
						.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
						.overlay(
							RoundedRectangle(cornerRadius: 12, style: .continuous)
								.strokeBorder(Color.accentColor, lineWidth: 2)
						)
				} else {
					Image(systemName: "scope")
						.font(.title2.weight(.semibold))
						.foregroundStyle(Color.accentColor)
						.frame(width: 54, height: 54)
						.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
				}
				
				VStack(alignment: .leading, spacing: 3) {
					Label("Practice Range", systemImage: "scope")
						.font(.caption.weight(.bold))
						.textCase(.uppercase)
						.foregroundStyle(Color.accentColor)
					
					Text(agentInfo?.displayName ?? String(localized: "Select an Agent"))
						.font(.title2.bold())
						.foregroundStyle(.white)
					
					if liveGameInfo != nil {
						Text("Solo Instance · Agent Selector")
							.font(.caption)
							.foregroundStyle(.white.opacity(0.75))
					} else if ownPregameLocked {
						Text("Agent Locked · Entering Range")
							.font(.caption)
							.foregroundStyle(.white.opacity(0.75))
					} else {
						Text("Pick an agent to train with")
							.font(.caption)
							.foregroundStyle(.white.opacity(0.75))
					}
				}
				
				Spacer()
			}
			.padding(16)
		}
	}
	
	@ViewBuilder
	private var cooldownOrStatusBar: some View {
		if let target = cooldownUntil {
			TimelineView(.periodic(from: .now, by: 0.1)) { context in
				let remaining = max(0, target.timeIntervalSince(context.date))
				let progress = max(0, min(1, remaining / switchCooldown))
				VStack(alignment: .leading, spacing: 6) {
					HStack {
						Label("Agent switch cooldown", systemImage: "timer")
							.font(.caption.weight(.semibold))
							.foregroundStyle(Color.accentColor)
						Spacer()
						Text(String(format: "%.1fs", remaining))
							.font(.caption.weight(.bold))
							.monospacedDigit()
							.foregroundStyle(.secondary)
					}
					
					GeometryReader { geo in
						Capsule()
							.fill(Color.tertiaryGroupedBackground)
							.overlay(alignment: .leading) {
								Capsule()
									.fill(Color.accentColor)
									.frame(width: geo.size.width * progress)
							}
					}
					.frame(height: 5)
				}
				.padding(12)
				.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
			}
		} else if let statusNotice {
			HStack(spacing: 10) {
				Image(systemName: "info.circle.fill")
					.foregroundStyle(Color.accentColor)
				Text(statusNotice)
					.font(.caption)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(12)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
		}
	}
	
	private var actionButtonsBar: some View {
		HStack(spacing: 10) {
			if let pregameInfo, !ownPregameLocked, let agentID = currentAgentID {
				let isOnCooldown = (cooldownUntil ?? .distantPast) > Date()
				AsyncButton {
					await load {
						let updated = try await $0.lockInAgent(agentID, in: pregameInfo.id)
						onUpdatePregame(updated)
					}
				} label: {
					HStack(spacing: 6) {
						Image(systemName: "lock.fill")
						Text("Lock In \(assets?.agents[agentID]?.displayName ?? "")")
							.lineLimit(1)
					}
					.font(.subheadline.weight(.semibold))
					.frame(maxWidth: .infinity)
					.padding(.vertical, 11)
					.background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
					.foregroundStyle(.white)
				}
				.buttonStyle(.plain)
				.disabled(isOnCooldown)
				.opacity(isOnCooldown ? 0.5 : 1)
			} else if liveGameInfo != nil {
				Button {
					restartRange()
				} label: {
					HStack(spacing: 6) {
						if isRestarting {
							ProgressView()
								.scaleEffect(0.85)
						} else {
							Image(systemName: "arrow.clockwise")
						}
						Text("Restart Range")
							.lineLimit(1)
					}
					.font(.subheadline.weight(.semibold))
					.frame(maxWidth: .infinity)
					.padding(.vertical, 11)
					.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
					.foregroundStyle(Color.accentColor)
				}
				.buttonStyle(.plain)
				.disabled(isRestarting || isLeaving)
			}
			
			Button(role: .destructive) {
				leaveRange()
			} label: {
				HStack(spacing: 6) {
					if isLeaving {
						ProgressView()
							.scaleEffect(0.85)
					} else {
						Image(systemName: "rectangle.portrait.and.arrow.right")
					}
					Text("Leave Range")
						.lineLimit(1)
				}
				.font(.subheadline.weight(.semibold))
				.frame(maxWidth: .infinity)
				.padding(.vertical, 11)
				.background(Color.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
				.foregroundStyle(.red)
			}
			.buttonStyle(.plain)
			.disabled(isLeaving || isRestarting)
		}
	}
	
	@ViewBuilder
	private var agentGrid: some View {
		if let agents = assets?.agents.values {
			let sortedAgents = agents
				.filter(\.isPlayableCharacter)
				.sorted(on: \.displayName)
				.movingToFront { inventory.owns($0.id) }
			let isOnCooldown = (cooldownUntil ?? .distantPast) > Date()
			
			let spacing = 12.0
			LazyVGrid(
				columns: [.init(.adaptive(minimum: agentSize, maximum: agentSize), spacing: spacing)],
				spacing: spacing
			) {
				ForEach(sortedAgents) { agent in
					let isOwned = inventory.owns(agent.id)
					let isSelected = agent.id == currentAgentID
					
					Button {
						selectAgent(agent.id)
					} label: {
						agentTile(isSelected: isSelected) {
							agent.displayIcon.view(outlineRadius: 1.5, shouldLoadImmediately: true)
								.compositingGroup()
								.opacity(isOwned ? 1 : 0.45)
						}
					}
					.buttonStyle(.plain)
					.disabled(!isOwned || isOnCooldown || ownPregameLocked || isLeaving || isRestarting)
				}
				
				Button {
					if let random = sortedAgents.filter({ inventory.owns($0.id) && $0.id != currentAgentID }).randomElement() {
						selectAgent(random.id)
					}
				} label: {
					agentTile(isSelected: false) {
						Image(systemName: "questionmark")
							.font(.system(size: agentSize * 0.55, weight: .bold))
							.foregroundStyle(.white)
							.frame(width: agentSize, height: agentSize)
					}
				}
				.buttonStyle(.plain)
				.disabled(isOnCooldown || ownPregameLocked || isLeaving || isRestarting)
			}
			.padding(14)
			.background(
				Color.secondaryGroupedBackground,
				in: RoundedRectangle(cornerRadius: 18, style: .continuous)
			)
			.opacity(isOnCooldown ? 0.6 : 1)
		}
	}
	
	private func agentTile<Content: View>(isSelected: Bool, @ViewBuilder content: () -> Content) -> some View {
		let lineWidth = isSelected ? 2.5 : 1.0
		let cornerRadius = 10.0
		let backgroundInset = 2.0
		return content()
			.frame(width: agentSize, height: agentSize)
			.cornerRadius(cornerRadius)
			.background(
				RoundedRectangle(cornerRadius: cornerRadius - backgroundInset, style: .continuous)
					.fill(Color.tertiaryGroupedBackground)
					.padding(backgroundInset)
			)
			.overlay(
				RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
					.strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: lineWidth)
			)
	}
	
	private func syncSelectedAgentFromServer() {
		if let serverAgent = pregameInfo?.team.players.firstElement(withID: userID)?.agentID
			?? liveGameInfo?.players.firstElement(withID: userID)?.agentID {
			selectedAgentID = serverAgent
		}
	}
	
	private func selectAgent(_ agentID: Agent.ID) {
		guard (cooldownUntil ?? .distantPast) <= Date() else { return }
		cooldownUntil = Date().addingTimeInterval(switchCooldown)
		selectedAgentID = agentID
		
		Task {
			if let pregameInfo {
				await load {
					let updated = try await $0.pickAgent(agentID, in: pregameInfo.id)
					onUpdatePregame(updated)
					statusNotice = nil
				}
			} else if let liveGameInfo {
				do {
					let updated = try await loadSwitchingAgentInLiveRange(agentID: agentID, matchID: liveGameInfo.id)
					if let updated {
						onUpdatePregame(updated)
					}
					statusNotice = nil
				} catch {
					statusNotice = String(localized: "In-game Range swaps happen directly inside the game (F2), or tap Restart Range to respawn with the selected agent.")
				}
			}
		}
	}
	
	private func loadSwitchingAgentInLiveRange(agentID: Agent.ID, matchID: Match.ID) async throws -> LivePregameInfo? {
		var result: LivePregameInfo?
		var caughtError: Error?
		await load { client in
			do {
				result = try await client.pickAgent(agentID, in: matchID)
			} catch {
				caughtError = error
			}
		}
		if let caughtError { throw caughtError }
		return result
	}
	
	private func leaveRange() {
		Task {
			isLeaving = true
			defer { isLeaving = false }
			await load { client in
				if let pregameInfo {
					try? await client.quitPregameMatch(pregameInfo.id)
				} else if let liveGameInfo {
					try? await client.disassociateFromLiveGame(liveGameInfo.id)
				}
			}
			await onLeaveRange()
			dismiss()
		}
	}
	
	private func restartRange() {
		Task {
			isRestarting = true
			defer { isRestarting = false }
			await load { client in
				if let liveGameInfo {
					try? await client.disassociateFromLiveGame(liveGameInfo.id)
				} else if let pregameInfo {
					try? await client.quitPregameMatch(pregameInfo.id)
				}
				try? await Task.sleep(for: .milliseconds(350))
				try await client.startSoloExperience()
			}
			await onRestartRange()
		}
	}
}
