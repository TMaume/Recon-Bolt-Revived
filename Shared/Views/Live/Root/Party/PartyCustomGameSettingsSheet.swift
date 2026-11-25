import SwiftUI
import ValorantAPI

struct PartyCustomGameSettingsSheet: View {
	@Binding var party: Party
	let userID: User.ID
	var onPartyChanged: () async -> Void = {}
	
	@State private var settings: Party.CustomGameData.Settings
	@State private var rules: Party.CustomGameData.GameRules
	@State private var configs: CustomGameConfigs?
	@State private var isSaving = false
	@State private var isReturningToStandard = false
	
	@Environment(\.valorantLoad) private var load
	@Environment(\.assets) private var assets
	@Environment(\.dismiss) private var dismiss
	
	init(
		party: Binding<Party>,
		userID: User.ID,
		onPartyChanged: @escaping () async -> Void = {}
	) {
		self._party = party
		self.userID = userID
		self.onPartyChanged = onPartyChanged
		let current = party.wrappedValue.customGameData?.settings ?? .init()
		self._settings = State(initialValue: current)
		self._rules = State(initialValue: current.gameRules ?? .init())
	}
	
	private var isOwner: Bool {
		(party.members.firstElement(withID: userID) ?? party.members.first)?.isOwner == true
	}
	
	private var canEdit: Bool {
		isOwner && party.state == .customGameSetup && !isSaving && !isReturningToStandard
	}
	
	private var selfPings: [Party.Member.ServerPing] {
		let member = party.members.firstElement(withID: userID) ?? party.members.first
		return (member?.pings ?? []).sorted { lhs, rhs in
			if lhs.ping != rhs.ping { return lhs.ping < rhs.ping }
			return serverDisplayName(lhs.serverID) < serverDisplayName(rhs.serverID)
		}
	}
	
	private var selectableMapPaths: [String] {
		var paths: [String] = []
		if let enabled = configs?.enabledMaps, !enabled.isEmpty {
			paths = enabled.filter { path in
				let lower = path.lowercased()
				return !lower.contains("range") && !lower.contains("poveglia") && !lower.contains("npe")
			}
		} else if let assetMaps = assets?.maps.values {
			paths = assetMaps
				.filter { map in
					if map.id == .range || map.id == .rangeV2 || map.id == .gauntlet { return false }
					let raw = map.id.rawValue.lowercased()
					return !(map.callouts ?? []).isEmpty
						&& !raw.contains("skirmish")
						&& !raw.contains("hurm")
						&& !raw.contains("npe")
				}
				.map(\.id.rawValue)
		}
		if !settings.map.isEmpty && !paths.contains(settings.map) {
			paths.insert(settings.map, at: 0)
		}
		return paths.sorted { mapDisplayName($0) < mapDisplayName($1) }
	}
	
	private static let fallbackModes: [String] = [
		"/Game/GameModes/Bomb/BombGameMode.BombGameMode_C",
		"/Game/GameModes/QuickBomb/QuickBombGameMode.QuickBombGameMode_C",
		"/Game/GameModes/_Development/Swiftplay_EndOfRoundCredits/SwiftPlay_GameMode_PrimaryAsset",
		"/Game/GameModes/Deathmatch/DeathmatchGameMode.DeathmatchGameMode_C",
		"/Game/GameModes/GunGame/GunGameTeamsGameMode.GunGameTeamsGameMode_C",
		"/Game/GameModes/HURM/HURM.HURM_C",
	]
	
	private var selectableModePaths: [String] {
		var modes = (configs?.enabledModes.isEmpty == false) ? configs!.enabledModes : Self.fallbackModes
		modes = modes.filter { !$0.localizedCaseInsensitiveContains("NewPlayerExperience") && !$0.localizedCaseInsensitiveContains("NPE") }
		if !settings.mode.isEmpty && !modes.contains(settings.mode) {
			modes.insert(settings.mode, at: 0)
		}
		return modes
	}
	
	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 18) {
					mapPreviewCard
					matchSetupCard
					gameRulesCard
					
					if isOwner {
						exitCustomLobbyButton
					}
				}
				.padding(.horizontal, 16)
				.padding(.vertical, 14)
			}
			.background(Color.groupedBackground)
			.navigationTitle("Custom Game Settings")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .navigationBarLeading) {
					Button("Cancel") {
						dismiss()
					}
				}
				
				ToolbarItem(placement: .navigationBarTrailing) {
					Button {
						saveSettings()
					} label: {
						if isSaving {
							ProgressView()
								.tint(.white)
						} else {
							Image(systemName: "checkmark")
								.fontWeight(.semibold)
						}
					}
					.buttonStyle(.borderedProminent)
					.tint(Color.accentColor)
					.disabled(!canEdit)
				}
			}
			.valorantLoadTask { client in
				configs = try? await client.getCustomGameConfigs()
			}
		}
	}
	
	private var mapPreviewCard: some View {
		let mapID = MapID(settings.map.isEmpty ? MapID.ascent.rawValue : settings.map)
		return ZStack(alignment: .bottomLeading) {
			MapImage.splash(mapID)
				.aspectRatio(contentMode: .fill)
				.frame(height: 120)
				.clipped()
				.overlay(
					LinearGradient(
						colors: [.black.opacity(0.15), .black.opacity(0.82)],
						startPoint: .top,
						endPoint: .bottom
					)
				)
			
			VStack(alignment: .leading, spacing: 3) {
				Text("CUSTOM GAME")
					.font(.caption2.weight(.bold))
					.tracking(0.8)
					.foregroundStyle(Color.accentColor)
				
				Text(mapDisplayName(settings.map))
					.font(.title2.bold())
					.foregroundStyle(.white)
				
				Text("\(modeDisplayName(settings.mode)) · \(serverDisplayName(settings.gamePod))")
					.font(.caption)
					.foregroundStyle(.white.opacity(0.8))
			}
			.padding(14)
		}
		.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	private var matchSetupCard: some View {
		VStack(spacing: 0) {
			HStack(spacing: 14) {
				Image(systemName: "map")
					.font(.body.weight(.medium))
					.foregroundStyle(Color.accentColor)
					.frame(width: 24)
				
				Text("Map")
				
				Spacer()
				
				Menu {
					ForEach(selectableMapPaths, id: \.self) { mapPath in
						Button {
							settings.map = mapPath
						} label: {
							HStack {
								Text(mapDisplayName(mapPath))
								if mapPath == settings.map { Image(systemName: "checkmark") }
							}
						}
					}
				} label: {
					HStack(spacing: 6) {
						Text(mapDisplayName(settings.map))
						Image(systemName: "chevron.up.chevron.down")
							.font(.caption.weight(.semibold))
					}
					.foregroundStyle(Color.accentColor)
				}
				.disabled(!canEdit)
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 14)
			
			Divider()
				.padding(.leading, 54)
			
			HStack(spacing: 14) {
				Image(systemName: "flag.2.crossed")
					.font(.body.weight(.medium))
					.foregroundStyle(Color.accentColor)
					.frame(width: 24)
				
				Text("Mode")
				
				Spacer()
				
				Menu {
					ForEach(selectableModePaths, id: \.self) { modePath in
						Button {
							settings.mode = modePath
						} label: {
							HStack {
								Text(modeDisplayName(modePath))
								if modePath == settings.mode { Image(systemName: "checkmark") }
							}
						}
					}
				} label: {
					HStack(spacing: 6) {
						Text(modeDisplayName(settings.mode))
						Image(systemName: "chevron.up.chevron.down")
							.font(.caption.weight(.semibold))
					}
					.foregroundStyle(Color.accentColor)
				}
				.disabled(!canEdit)
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 14)
			
			if !selfPings.isEmpty {
				Divider()
					.padding(.leading, 54)
				
				HStack(spacing: 14) {
					Image(systemName: "server.rack")
						.font(.body.weight(.medium))
						.foregroundStyle(Color.accentColor)
						.frame(width: 24)
					
					Text("Server")
					
					Spacer()
					
					Menu {
						ForEach(selfPings) { ping in
							Button {
								settings.gamePod = ping.serverID
							} label: {
								HStack {
									Text("\(serverDisplayName(ping.serverID)) (\(ping.ping) ms)")
									if ping.serverID == settings.gamePod { Image(systemName: "checkmark") }
								}
							}
						}
					} label: {
						HStack(spacing: 6) {
							Text(serverDisplayName(settings.gamePod))
							Image(systemName: "chevron.up.chevron.down")
								.font(.caption.weight(.semibold))
						}
						.foregroundStyle(Color.accentColor)
					}
					.disabled(!canEdit)
				}
				.padding(.horizontal, 16)
				.padding(.vertical, 14)
			}
		}
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
	
	private var gameRulesCard: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Game Options")
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 6)
			
			VStack(spacing: 0) {
				ruleToggle(title: "Allow Cheats", icon: "wand.and.stars", isOn: $rules.allowCheats)
				Divider().padding(.leading, 54)
				ruleToggle(title: "Tournament Mode", icon: "trophy", isOn: $rules.tournamentModeEnabled)
				Divider().padding(.leading, 54)
				ruleToggle(title: "Overtime: Win by Two", icon: "arrow.triangle.2.circlepath", isOn: $rules.overtimeWinByTwo)
				Divider().padding(.leading, 54)
				ruleToggle(title: "Play Out All Rounds", icon: "repeat", isOn: $rules.playOutAllRoundsEnabled)
				Divider().padding(.leading, 54)
				ruleToggle(title: "Hide Match History", icon: "eye.slash", isOn: $rules.hideMatchHistory)
			}
			.disabled(!canEdit)
			.opacity(canEdit ? 1 : 0.65)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
	}
	
	private func ruleToggle(title: LocalizedStringKey, icon: String, isOn: Binding<Bool>) -> some View {
		Toggle(isOn: isOn) {
			HStack(spacing: 14) {
				Image(systemName: icon)
					.font(.body.weight(.medium))
					.foregroundStyle(Color.accentColor)
					.frame(width: 24)
				Text(title)
			}
		}
		.tint(Color.accentColor)
		.padding(.horizontal, 16)
		.padding(.vertical, 10)
	}
	
	private var exitCustomLobbyButton: some View {
		Button {
			returnToStandardLobby()
		} label: {
			HStack {
				Spacer()
				if isReturningToStandard {
					ProgressView()
				} else {
					Label("Switch to Standard Queue", systemImage: "arrow.uturn.backward")
						.font(.body.weight(.semibold))
						.foregroundStyle(Color.accentColor)
				}
				Spacer()
			}
			.padding(.vertical, 14)
			.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
		.buttonStyle(.plain)
		.disabled(!canEdit)
	}
	
	private func mapDisplayName(_ path: String) -> String {
		guard !path.isEmpty else { return String(localized: "Select Map") }
		let id = MapID(path)
		if let info = assets?.maps[id] {
			return info.displayName
		}
		return path.split(separator: "/").last.map(String.init) ?? path
	}
	
	private func modeDisplayName(_ path: String) -> String {
		guard !path.isEmpty else { return String(localized: "Standard") }
		let lower = path.lowercased()
		if lower.contains("quickbomb") { return String(localized: "Spike Rush") }
		if lower.contains("swiftplay") { return String(localized: "Swiftplay") }
		if lower.contains("deathmatch") { return String(localized: "Deathmatch") }
		if lower.contains("gungame") { return String(localized: "Escalation") }
		if lower.contains("oneforall") { return String(localized: "Replication") }
		if lower.contains("hurm") { return String(localized: "Team Deathmatch") }
		if lower.contains("snowball") { return String(localized: "Snowball Fight") }
		if lower.contains("shootingrange") { return String(localized: "Practice Range") }
		if lower.contains("skirmishascension") { return "Skirmish: Ascension" }
		if lower.contains("skirmish") { return "Skirmish" }
		if lower.contains("bomb") { return String(localized: "Standard") }
		return path.split(separator: "/").dropFirst(3).first.map(String.init) ?? path
	}
	
	private func serverDisplayName(_ podID: String) -> String {
		guard !podID.isEmpty else { return String(localized: "Default") }
		return assets?.serverDisplayName(for: podID)
			?? MatchAnalytics.parseServerName(from: podID)
			?? podID
	}
	
	private func saveSettings() {
		var updated = settings
		updated.gameRules = rules
		if updated.map.isEmpty {
			updated.map = selectableMapPaths.first ?? MapID.ascent.rawValue
		}
		if updated.mode.isEmpty {
			updated.mode = Self.fallbackModes[0]
		}
		if updated.gamePod.isEmpty, let bestPod = selfPings.first?.serverID {
			updated.gamePod = bestPod
		}
		
		Task {
			isSaving = true
			defer { isSaving = false }
			var saved = false
			await load {
				party = try await $0.setCustomGameSettings(updated, in: party.id)
				saved = true
			}
			if saved {
				await onPartyChanged()
				dismiss()
			}
		}
	}
	
	private func returnToStandardLobby() {
		Task {
			isReturningToStandard = true
			defer { isReturningToStandard = false }
			var didReset = false
			await load {
				party = try await $0.makeDefaultQueue(.unrated, in: party.id)
				didReset = true
			}
			if didReset {
				await onPartyChanged()
				dismiss()
			}
		}
	}
}
