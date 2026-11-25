import SwiftUI
import ValorantAPI
import HandyOperators

struct LiveGameContainer: View {
	var userID: User.ID
	var playersInParty: Set<Player.ID>
	var party: Party? = nil
	@State var activeMatch: ActiveMatch?
	var isShootingRangeHint: Bool = false
	@State var details: Details?
	
	@State private var hasEnded = false
	
	@Environment(\.valorantLoad) private var load
	@Environment(\.scenePhase) private var scenePhase
	@Environment(\.dismiss) private var dismiss
	
	var body: some View {
		content
			.onSceneActivation(perform: refreshActiveMatch)
			.valorantLoadTask(id: details?.playerIDs) {
				guard let playerIDs = details?.playerIDs else { return }
				try await $0.fetchUsers(for: playerIDs)
			}
			.task {
				while !Task.isCancelled {
					await refreshActiveMatch()
					await Task.sleep(seconds: 5, tolerance: 1)
				}
			}
			.task(id: activeMatch) {
				await fetchDetails()
			}
			.task(id: hasEnded) {
				if hasEnded { dismiss() }
			}
	}
	
	@ViewBuilder
	var content: some View {
		switch details {
		case .shootingRangePregame(let pregameInfo, let inventory)?:
			ShootingRangeView(
				userID: userID,
				inventory: inventory,
				pregameInfo: pregameInfo,
				liveGameInfo: nil,
				onUpdatePregame: { updated in
					details = .shootingRangePregame(updated, inventory)
				},
				onLeaveRange: {
					hasEnded = true
				},
				onRestartRange: {
					await refreshAfterRangeRestart()
				}
			)
		case .shootingRangeLive(let liveGameInfo, let inventory)?:
			ShootingRangeView(
				userID: userID,
				inventory: inventory,
				pregameInfo: nil,
				liveGameInfo: liveGameInfo,
				onLeaveRange: {
					hasEnded = true
				},
				onRestartRange: {
					await refreshAfterRangeRestart()
				}
			)
		case .pregame(let pregameInfo, let inventory)?:
			AgentSelectView(
				userID: userID,
				inventory: inventory,
				pregameInfo: pregameInfo
			)
			.id(pregameInfo.id)
		case .liveGame(let liveGameInfo)?:
			LiveMatchView(gameInfo: liveGameInfo, userID: userID)
		case nil:
			ProgressView()
		}
	}
	
	func fetchDetails() async {
		await load {
			guard let activeMatch else { return }
			if activeMatch.inPregame {
				async let inventory = $0.getInventory()
				let pregameInfo = try await $0.getLivePregameInfo(activeMatch.id) <- LocalDataProvider.dataFetched
				let loadedInventory = try await inventory
				if pregameInfo.isShootingRange || isShootingRangeHint {
					details = .shootingRangePregame(pregameInfo, loadedInventory)
				} else {
					details = .pregame(pregameInfo, loadedInventory)
				}
			} else {
				let gameInfo = try await $0.getLiveGameInfo(activeMatch.id) <- LocalDataProvider.dataFetched
				if gameInfo.isShootingRange || isShootingRangeHint {
					let loadedInventory = try await $0.getInventory()
					details = .shootingRangeLive(gameInfo, loadedInventory)
				} else {
					details = .liveGame(gameInfo)
				}
			}
		}
	}
	
	func refreshActiveMatch() async {
		await load {
			if let newMatch = try await $0.getActiveMatch() {
				hasEnded = false
				activeMatch = newMatch
			} else {
				hasEnded = true
				activeMatch = nil
			}
		}
	}
	
	private func refreshAfterRangeRestart() async {
		await load { client in
			for _ in 0..<8 {
				if let match = try await client.getActiveMatch() {
					hasEnded = false
					activeMatch = match
					await fetchDetails()
					return
				}
				try? await Task.sleep(for: .milliseconds(400))
			}
			await refreshActiveMatch()
		}
	}
	
	enum Details {
		case shootingRangePregame(LivePregameInfo, Inventory)
		case shootingRangeLive(LiveGameInfo, Inventory)
		case pregame(LivePregameInfo, Inventory)
		case liveGame(LiveGameInfo)
		
		var playerIDs: [Player.ID] {
			switch self {
			case .shootingRangePregame(let info, _), .pregame(let info, _):
				return info.team.players.map(\.id)
			case .shootingRangeLive(let info, _), .liveGame(let info):
				return info.players.map(\.id)
			}
		}
	}
}

#if DEBUG
struct LiveGameContainer_Previews: PreviewProvider {
	static var previews: some View {
		LiveGameContainer(
			userID: PreviewData.userID,
			playersInParty: [],
			activeMatch: .init(id: PreviewData.liveGameInfo.id, inPregame: false),
			details: .liveGame(PreviewData.liveGameInfo)
		)
		.withToolbar()
	}
}
#endif
