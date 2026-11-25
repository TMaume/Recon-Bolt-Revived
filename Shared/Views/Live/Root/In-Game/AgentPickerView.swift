import SwiftUI
import ValorantAPI

struct AgentPickerView: View {
	@Binding var pregameInfo: LivePregameInfo
	let userID: User.ID
	let inventory: Inventory
	var cooldownDuration: TimeInterval = 0
	var showsDodgeButton: Bool = true
	var onDodge: () -> Void = {}
	
	@State private var isConfirmingDodge = false
	@State private var isDodging = false
	@State private var cooldownUntil: Date?
	
	@Environment(\.valorantLoad) private var load
	@Environment(\.assets) private var assets
	
	@ScaledMetric private var agentSize = 50
	
	private var isCoolingDown: Bool {
		cooldownUntil.map { $0 > Date() } ?? false
	}
	
	var body: some View {
		let ownPlayer = pregameInfo.team.players.firstElement(withID: userID)!
		let gameModeInfo = assets?.gameModes[pregameInfo.modeID]
		let isVotingBased = gameModeInfo?.gameRuleOverride(for: .majorityVoteAgents) == true
		let takenAgents = isVotingBased ? [] : Set(
			pregameInfo.team.players
				.filter(\.isLockedIn)
				.filter { $0.id != userID }
				.map { $0.agentID! }
		)
		
		let hasSelectedAgent = ownPlayer.isLockedIn
		
		VStack(spacing: 24) {
			let selectedAgentID = ownPlayer.agentID
			
			HStack(spacing: 12) {
				AsyncButton {
					await load {
						pregameInfo = try await $0.lockInAgent(selectedAgentID!, in: pregameInfo.id)
					}
					ReviewManager.registerUsage(points: 10)
					ReviewManager.requestReviewIfAppropriate()
				} label: {
					let agentName = selectedAgentID
						.flatMap { assets?.agents[$0] }?
						.displayName
					
					Text(agentName.map { "Lock In \($0)" } ?? "Lock In")
						.bold()
						.lineLimit(1)
				}
				.buttonStyle(.borderedProminent)
				.disabled(selectedAgentID == nil || takenAgents.contains(selectedAgentID!))
				.disabled(hasSelectedAgent || isCoolingDown) // can't move this out because then it'd affect the relock gesture too
				
				if showsDodgeButton {
					Button(role: .destructive) {
						isConfirmingDodge = true
					} label: {
						Label("Dodge", systemImage: "rectangle.portrait.and.arrow.right")
							.bold()
							.lineLimit(1)
							.opacity(isDodging ? 0.25 : 1)
							.overlay {
								if isDodging {
									ProgressView()
								}
							}
					}
					.buttonStyle(.bordered)
					.tint(.red)
					.disabled(isDodging)
					.confirmationDialog(
						"Dodge Match?",
						isPresented: $isConfirmingDodge,
						titleVisibility: .visible
					) {
						Button("Dodge Match", role: .destructive) {
							isDodging = true
							Task {
								defer { isDodging = false }
								await load {
									try await $0.quitPregameMatch(pregameInfo.id)
									onDodge()
								}
							}
						}
					} message: {
						Text("Quitting during agent select may result in a queue penalty or RR loss.")
					}
				}
			}
			
			if let cooldownUntil, cooldownDuration > 0 {
				TimelineView(.periodic(from: .now, by: 0.1)) { context in
					let remaining = max(0, cooldownUntil.timeIntervalSince(context.date))
					let progress = max(0, min(1, remaining / cooldownDuration))
					VStack(spacing: 4) {
						HStack {
							Label("Cooldown", systemImage: "timer")
								.font(.caption.weight(.semibold))
								.foregroundStyle(Color.accentColor)
							Spacer()
							Text(String(format: "%.1fs", remaining))
								.font(.caption.weight(.bold))
								.monospacedDigit()
								.foregroundStyle(.secondary)
						}
						ProgressView(value: progress)
							.tint(Color.accentColor)
					}
					.padding(.horizontal, 8)
				}
			}
			
			if let agents = assets?.agents.values {
				let sortedAgents = agents
					.filter(\.isPlayableCharacter)
					.sorted(on: \.displayName)
					.movingToFront { inventory.owns($0.id) }
				
				let gridSpacing = 12.0
				LazyVGrid(columns: [.init(
					.adaptive(minimum: agentSize, maximum: agentSize),
					spacing: gridSpacing, alignment: .center
				)], spacing: gridSpacing) {
					ForEach(sortedAgents) { agent in
						agentButton(
							for: agent,
							selectedAgentID: selectedAgentID,
							isTaken: takenAgents.contains(agent.id)
						)
					}
					
					// random agent
					AsyncButton {
						startCooldownIfNeeded()
						await load {
							guard let agent = inventory.agents.subtracting(takenAgents).randomElement() else { return }
							pregameInfo = try await $0.pickAgent(agent, in: pregameInfo.id)
						}
					} label: {
						gridButton(isSelected: false) {
							Image(systemName: "questionmark")
								.font(.system(size: agentSize * 0.65, weight: .bold))
								.foregroundColor(.white)
								.frame(width: agentSize, height: agentSize)
						}
					}
				}
				.padding(4)
				.disabled(hasSelectedAgent || isCoolingDown)
			}
		}
		.disabled(pregameInfo.state != .agentSelectActive)
		.padding()
		.task(id: cooldownUntil) {
			guard let cooldownUntil else { return }
			let delay = cooldownUntil.timeIntervalSinceNow
			if delay > 0 {
				try? await Task.sleep(for: .seconds(delay))
			}
			self.cooldownUntil = nil
		}
	}
	
	private func startCooldownIfNeeded() {
		guard cooldownDuration > 0 else { return }
		cooldownUntil = Date().addingTimeInterval(cooldownDuration)
	}
	
	@ViewBuilder
	func agentButton(for agent: AgentInfo, selectedAgentID: Agent.ID?, isTaken: Bool) -> some View {
		let ownsAgent = inventory.owns(agent.id)
		AsyncButton {
			startCooldownIfNeeded()
			await load {
				pregameInfo = try await $0.pickAgent(agent.id, in: pregameInfo.id)
			}
		} label: {
			gridButton(isSelected: agent.id == selectedAgentID) {
				agent.displayIcon.view(outlineRadius: 1.5, shouldLoadImmediately: true)
					.compositingGroup()
					.opacity(ownsAgent ? 1 : 0.5)
					.opacity(isTaken ? 0.8 : 1)
			}
		}
		.disabled(!ownsAgent || isTaken)
	}
	
	@ViewBuilder
	func gridButton<Content: View>(isSelected: Bool, @ViewBuilder content: () -> Content) -> some View {
		let lineWidth = isSelected ? 2.0 : 1.0
		let cornerRadius = 8.0
		let backgroundInset = 2.0
		content()
			.cornerRadius(cornerRadius)
			.background(
				RoundedRectangle(cornerRadius: cornerRadius - backgroundInset)
					.fill(.secondary)
					.padding(backgroundInset)
			)
			.overlay(
				RoundedRectangle(cornerRadius: cornerRadius + lineWidth)
					.strokeBorder(lineWidth: lineWidth)
					.padding(-lineWidth)
			)
			.foregroundStyle(isSelected ? Color.valorantSelf : Color.accentColor)
	}
}

#if DEBUG
struct AgentPickerView_Previews: PreviewProvider, PreviewProviderWithAssets {
	static func previews(assets: AssetCollection) -> some View {
		AgentPickerView(
			pregameInfo: .constant(PreviewData.pregameInfo),
			userID: PreviewData.userID,
			inventory: PreviewData.inventory
		)
		.previewLayout(.sizeThatFits)
	}
}
#endif
