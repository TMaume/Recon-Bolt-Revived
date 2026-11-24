import SwiftUI
import ValorantAPI
import HandyOperators
import UserDefault

struct MatchListView: View {
	let userID: User.ID
	
	@LocalData var user: User?
	@LocalData var matchList: MatchList?
	@LocalData var summary: CareerSummary?
	@LocalData var identity: Player.Identity?
	@State var isEditingFilter = false
	@State private var agentMastery: AgentMastery? = nil
	@State private var showingProfileShare = false
	@State private var masteryFetchTick = 0
	@State private var matchCacheTick = 0
	@State private var cachedDetailsSnapshot: [MatchDetails] = []
	@State private var computedMastery: [AgentMasterySummary] = []
	@State private var computedAccolades = AccoladesReport(
		totalEarned: 0,
		earnedTypesCount: 0,
		totalTypesCount: AccoladeType.allCases.count,
		scannedMatchesCount: 0,
		allItems: [],
		earnedItems: []
	)
	@State private var computedLatestSession: SessionRecapBuilder.LatestSessionPreview? = nil
	@State private var computedGoalTrajectory: SeasonGoalTrajectory? = nil
	@ObservedObject private var filterStore = MatchListFilterStore.shared
	
	@Environment(\.valorantLoad) private var load
	@Environment(\.shouldAnonymize) private var shouldAnonymize
	@Environment(\.location) private var location
	@Environment(\.assets) private var assets
	@Environment(\.seasons) private var seasons
	@EnvironmentObject private var bookmarkList: BookmarkList
	@EnvironmentObject private var goalStore: SeasonGoalStore
	@EnvironmentObject private var accountManager: AccountManager
	@EnvironmentObject private var settings: AppSettings
	
	private var shownMatches: [CompetitiveUpdate] {
		matchList?.matches ?? []
	}
	
	private struct CareerComputeKey: Equatable {
		var userID: User.ID
		var matchIDs: [Match.ID]
		var totalMatchCount: Int
		var cacheTick: Int
		var masteryTick: Int
		var currentActID: Act.ID?
		var summarySeasonCount: Int
		var summaryLatestID: Match.ID?
		var activeGoal: SeasonGoal?
		var assetsVersion: AssetVersion?
	}
	
	var body: some View {
		let currentAct = seasons?.currentAct()
		let prevAct = assets?.seasons.actBefore(currentAct)
		let activeGoal: SeasonGoal? = {
			guard userID == accountManager.activeAccount?.id else { return nil }
			let goal = goalStore.goal(for: userID, actID: currentAct?.id)
			return (goal?.showsOnProfile == true) ? goal : nil
		}()
		let computeKey = CareerComputeKey(
			userID: userID,
			matchIDs: shownMatches.prefix(40).map(\.id),
			totalMatchCount: shownMatches.count,
			cacheTick: matchCacheTick,
			masteryTick: masteryFetchTick,
			currentActID: currentAct?.id,
			summarySeasonCount: summary?.competitiveInfo?.bySeason?.count ?? 0,
			summaryLatestID: summary?.latestUpdate?.id,
			activeGoal: activeGoal,
			assetsVersion: assets?.version
		)
		
		ScrollView {
			LazyVStack(spacing: settings.isCompactListStyle ? 4 : 12) {
				VStack(spacing: 14) {
					VStack(spacing: 0) {
						PlayerIdentityCell(user: user, identity: identity)
						CompetitiveSummaryCell(summary: summary, showThisActFooter: false)
							.padding(.horizontal, 12)
							.buttonStyle(.plain)
					}
					.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
					.clipped()
					
					CareerSummaryCollapsibleCard(summary: summary)
					
					AgentMasterySummaryBox(summaries: computedMastery, actEndDate: currentAct?.timeSpan.end)
					
					AccoladesSummaryBox(userID: userID, matches: cachedDetailsSnapshot, report: computedAccolades)
					
					if let activeGoal, let trajectory = computedGoalTrajectory {
						SeasonGoalProgressModule(goal: activeGoal, trajectory: trajectory, currentAct: currentAct)
					}
					
					HStack(spacing: 12) {
						NavigationLink {
							SessionRecapView(
								userID: userID,
								matches: shownMatches,
								detailsByID: Dictionary(uniqueKeysWithValues: cachedDetailsSnapshot.map { ($0.id, $0) })
							)
						} label: {
							VStack(alignment: .leading, spacing: 6) {
								HStack(spacing: 6) {
									Image(systemName: "clock.badge.checkmark")
										.foregroundStyle(Color.accentColor)
									Text("Session Recap")
										.font(.subheadline.weight(.semibold))
								}
								if let latest = computedLatestSession {
									Text(latest.startTime.formatted(.dateTime.day().month(.abbreviated)))
										.font(.caption)
										.foregroundStyle(.secondary)
									HStack(spacing: 4) {
										Text("\(latest.matchCount) matches")
											.foregroundStyle(.secondary)
										if latest.netRRDelta != 0 {
											Text("• \(latest.netRRDelta > 0 ? "+\(latest.netRRDelta)" : "\(latest.netRRDelta)") RR")
												.foregroundStyle(latest.netRRDelta > 0 ? Color.green : Color.red)
										}
									}
									.font(.caption.monospacedDigit())
								} else {
									Text("Open matches to build")
										.font(.caption)
										.foregroundStyle(.secondary)
								}
							}
							.frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
							.padding(12)
							.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
						}
						.buttonStyle(.plain)
						
						NavigationLink {
							if let user, let matchList {
								StatisticsContainer(user: user, matchList: matchList)
							}
						} label: {
							VStack(alignment: .leading, spacing: 6) {
								HStack(spacing: 6) {
									Image(systemName: "chart.line.uptrend.xyaxis")
										.foregroundStyle(Color.accentColor)
									Text("View Stats")
										.font(.subheadline.weight(.semibold))
								}
								Text("Win rate, K/D & more")
									.font(.caption)
									.foregroundStyle(.secondary)
								Spacer(minLength: 0)
							}
							.frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
							.padding(12)
							.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
						}
						.buttonStyle(.plain)
						.disabled(user == nil || matchList == nil)
					}
				}
				.padding(.bottom, 6)
				
				Text("Matches", comment: "Match List: section")
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(.leading, 4)
					.padding(.top, 4)
				
				ForEach(shownMatches) { match in
					MatchCell(
						match: match,
						userID: userID,
						filter: filterStore.filter,
						inList: false,
						isCompact: settings.isCompactListStyle
					)
				}
				
				if matchList?.canLoadOlderMatches == true {
					AsyncButton {
						await updateMatchList(update: ValorantClient.loadOlderMatches)
					} label: {
						Label(
							String(localized: "Load Older Matches", comment: "Match List"),
							systemImage: "ellipsis"
						)
						.font(.subheadline.weight(.medium))
						.frame(maxWidth: .infinity)
						.padding(.vertical, 12)
						.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
					}
					.buttonStyle(.plain)
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		}
		.background(Color.groupedBackground)
		.toolbar {
			ToolbarItemGroup(placement: .navigationBarTrailing) {
				if !shouldAnonymize(userID) {
					Button {
						bookmarkList.toggleBookmark(for: userID, location: location!)
					} label: {
						if bookmarkList.hasBookmark(for: userID) {
							Label(
								String(localized: "Remove Bookmark", comment: "Match List: accessibility label"),
								systemImage: "bookmark.fill"
							)
						} else {
							Label(
								String(localized: "Add Bookmark", comment: "Match List: accessibility label"),
								systemImage: "bookmark"
							)
						}
					}
				}
				
				Button {
					isEditingFilter = true
				} label: {
					Label(
						String(localized: "Edit Filter", comment: "Match List: accessibility label"),
						systemImage: "line.horizontal.3.decrease.circle"
					)
					.symbolVariant(filterStore.filter.isActive ? .fill : .none)
				}
				
				Button {
					showingProfileShare = true
				} label: {
					Label(
						String(localized: "Share Profile", comment: "Match List: accessibility label"),
						systemImage: "square.and.arrow.up"
					)
				}
			}
		}
		.refreshable { await refresh() }
		.sheet(isPresented: $isEditingFilter) {
			MatchListFilterEditor(filter: $filterStore.filter)
		}
		.sheet(isPresented: $showingProfileShare) {
			ShareProfileCardSheet(
				user: user,
				cardID: identity?.cardID,
				titleID: identity?.titleID,
				accountLevel: identity?.accountLevel ?? 0,
				summary: summary
			)
		}
		.withLocalData($user, id: userID, shouldAutoUpdate: true)
		.withLocalData($matchList, id: userID, shouldAutoUpdate: true)
		.withLocalData($summary, id: userID, shouldAutoUpdate: true)
		.withLocalData($identity, id: userID, shouldAutoUpdate: true)
		.valorantLoadTask(id: userID) { client in
			agentMastery = try? await client.getAgentMastery(userID: userID)
			masteryFetchTick += 1
		}
		.onReceive(
			LocalDataProvider.shared.matchDetailsManager.changePublisher
				.debounce(for: .milliseconds(250), scheduler: RunLoop.main)
		) { _ in
			matchCacheTick += 1
		}
		.task(id: computeKey) {
			let manager = LocalDataProvider.shared.matchDetailsManager
			let details = shownMatches.prefix(40).compactMap {
				manager.loadedObject(for: $0.id)
			}
			let uid = userID
			let allUpdates = shownMatches
			let masterySnapshot = agentMastery
			let assetsSnapshot = assets
			let seasonsSnapshot = seasons
			let currentActSnapshot = currentAct
			let prevActSnapshot = prevAct
			let goalSnapshot = activeGoal
			let summarySnapshot = summary
			let matchListSnapshot = matchList
			
			let computed = await Task.detached(priority: .userInitiated) {
				PerfMonitor.measure("CareerModules.compute", warnOverMs: 2.0) {
					let detailsMap = Dictionary(uniqueKeysWithValues: details.map { ($0.id, $0) })
					let mastery = AgentMasteryCalculator.buildFromRiot(
						masterySnapshot,
						userID: uid,
						matches: details,
						assets: assetsSnapshot,
						contractsDetails: nil,
						currentAct: currentActSnapshot,
						previousAct: prevActSnapshot
					)
					let accolades = AccoladesCalculator.compute(
						userID: uid,
						matches: details,
						act: currentActSnapshot,
						seasons: seasonsSnapshot
					)
					let latestSession = SessionRecapBuilder.latestSessionPreview(
						matches: allUpdates,
						detailsByID: detailsMap
					)
					let trajectory = goalSnapshot.map { goal in
						SeasonGoalStore.compute(
							goal: goal,
							summary: summarySnapshot,
							matchList: matchListSnapshot,
							currentAct: currentActSnapshot,
							seasons: seasonsSnapshot
						)
					}
					return (mastery, accolades, latestSession, trajectory)
				}
			}.value
			
			guard !Task.isCancelled else { return }
			cachedDetailsSnapshot = details
			computedMastery = computed.0
			computedAccolades = computed.1
			computedLatestSession = computed.2
			computedGoalTrajectory = computed.3
		}
		.onAppear {
			cacheLoadedIdentityToSocial()
		}
		.onChange(of: identity?.cardID) { _ in
			cacheLoadedIdentityToSocial()
		}
		.onChange(of: cachedDetailsSnapshot.count) { _ in
			cacheLoadedIdentityToSocial()
		}
		.onChange(of: summary?.competitiveInfo?.bySeason?.count ?? 0) { _ in
			cacheLoadedIdentityToSocial()
		}
		.anonymizing(additionally: shouldAnonymize(userID) ? .all : .none)
		.navigationTitle(title)
	}
	
	private func cacheLoadedIdentityToSocial() {
		let fallbackMatch = cachedDetailsSnapshot.lazy.compactMap { match -> (Player.Identity, Date)? in
			guard let pIdentity = match.players.first(where: { $0.id == userID })?.identity else { return nil }
			return (pIdentity, match.matchInfo.gameStart)
		}.first
		guard let resolvedIdentity = identity ?? fallbackMatch?.0 else { return }
		let updateTime = identity != nil ? Date() : (fallbackMatch?.1 ?? .distantPast)
		let currentActID = seasons?.currentAct()?.id
		let tier = summary?.competitiveInfo?.inSeason(currentActID)?.competitiveTier
			?? summary?.competitiveInfo?.bySeason?.values.first(where: { $0.competitiveTier >= 3 })?.competitiveTier
		LocalDataProvider.onIdentityAndTierResolved?(resolvedIdentity, tier, updateTime)
	}
	
	var title: Text {
		if !shouldAnonymize(userID), let user {
			return Text(user.gameName)
		} else {
			return Text("Matches", comment: "Match List: title if name unknown/hidden")
		}
	}
	
	func refresh() async {
		async let matchListUpdate: Void = updateMatchList(update: ValorantClient.loadMatches)
		async let summaryUpdate: Void = load {
			try await $0.fetchCareerSummary(for: userID, forceFetch: true)
		}
		async let identityUpdate: Void = load {
			try await $0.fetchIdentity(for: userID, forceFetch: true)
		}
		async let masteryUpdate: Void = load {
			agentMastery = try? await $0.getAgentMastery(userID: userID)
			masteryFetchTick += 1
		}
		_ = await (matchListUpdate, summaryUpdate, identityUpdate, masteryUpdate)
	}
	
	func updateMatchList(update: @escaping (ValorantClient) -> (inout MatchList) async throws -> Void) async {
		await load { try await $0.updateMatchList(for: userID, update: update($0)) }
	}
}

extension MatchListView {
	init(userID: User.ID) {
		self.init(
			userID: userID,
			user: .init(id: userID),
			matchList: .init(id: userID),
			summary: .init(id: userID),
			identity: .init(id: userID)
		)
	}
}

extension MatchListFilter: DefaultsValueConvertible {}

private struct CareerSummaryCollapsibleCard: View {
	let summary: CareerSummary?
	
	@Environment(\.assets) private var assets
	@Environment(\.seasons) private var seasons
	@State private var isExpanded = false
	
	var body: some View {
		let bySeason = summary?.competitiveInfo?.bySeason ?? [:]
		let currentAct = seasons?.currentAct()
		let pastOrCurrentActs: [Act] = (assets?.seasons.actsInOrder ?? [])
			.filter { act in
				if let current = currentAct {
					return act.timeSpan.start <= current.timeSpan.start
				}
				return act.timeSpan.start <= Date()
			}
			.reversed()
		let previewActs = Array(pastOrCurrentActs.prefix(3))
		let expandedActs = Array(pastOrCurrentActs.prefix(10))
		let playedActsCount = bySeason.values.filter { $0.gameCount > 0 || $0.competitiveTier > 0 }.count
		
		let thisActInfo = currentAct.flatMap { bySeason[$0.id] }
		let thisActWins = thisActInfo?.winCountIncludingPlacements ?? 0
		let thisActGames = thisActInfo?.gameCount ?? 0
		
		let allTotals = bySeason.values.reduce((wins: 0, games: 0)) { acc, item in
			(acc.wins + item.winCountIncludingPlacements, acc.games + item.gameCount)
		}
		
		VStack(alignment: .leading, spacing: 14) {
			HStack {
				Button {
					withAnimation(.easeInOut(duration: 0.2)) {
						isExpanded.toggle()
					}
				} label: {
					HStack(spacing: 8) {
						Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
							.font(.caption.bold())
							.foregroundStyle(Color.accentColor)
						Text("Career Summary")
							.font(.headline)
							.foregroundStyle(.primary)
					}
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				
				Spacer()
				
				TransparentNavigationLink {
					if let summary {
						CareerSummaryView(summary: summary)
					}
				} label: {
					HStack(spacing: 6) {
						if playedActsCount > 0 {
							Text("\(playedActsCount) Acts")
								.font(.subheadline)
								.foregroundStyle(.secondary)
						}
						Image(systemName: "chevron.right")
							.font(.caption.weight(.semibold))
							.foregroundStyle(.secondary)
					}
					.padding(.leading, 8)
				}
				.buttonStyle(.plain)
				.disabled(summary == nil)
			}
			
			if !isExpanded {
				if !previewActs.isEmpty {
					HStack(spacing: 12) {
						ForEach(previewActs) { act in
							actBadgeColumn(act: act, info: bySeason[act.id])
								.frame(maxWidth: .infinity)
						}
					}
				}
				
				if thisActGames > 0 {
					let pct = Double(thisActWins) * Double(100) / Double(thisActGames)
					HStack {
						Text("This Act")
							.font(.subheadline)
							.foregroundStyle(.secondary)
						Spacer()
						Text(String(format: "%.1f %%", pct))
							.font(.subheadline.weight(.bold).monospacedDigit())
							.foregroundStyle(Color.valorantBlue)
						Text("\(thisActWins) / \(thisActGames)")
							.font(.subheadline.monospacedDigit())
							.foregroundStyle(.secondary)
					}
				}
			} else {
				if !expandedActs.isEmpty {
					ScrollView(.horizontal, showsIndicators: false) {
						HStack(spacing: 16) {
							ForEach(expandedActs) { act in
								actBadgeColumn(act: act, info: bySeason[act.id])
									.frame(minWidth: 74)
							}
						}
						.padding(.vertical, 2)
					}
				}
				
				if thisActGames > 0 || allTotals.games > 0 {
					Divider()
						.opacity(0.4)
				}
				
				if thisActGames > 0 {
					winRateProgressBlock(
						title: "This Act",
						wins: thisActWins,
						games: thisActGames,
						highlightColor: Color.valorantBlue
					)
				}
				
				if allTotals.games > 0 {
					winRateProgressBlock(
						title: "All Acts",
						wins: allTotals.wins,
						games: allTotals.games,
						highlightColor: .primary
					)
				}
			}
		}
		.padding(14)
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
	}
	
	private func actBadgeColumn(act: Act, info: CareerSummary.SeasonInfo?) -> some View {
		VStack(spacing: 8) {
			Group {
				if let info, info.competitiveTier > 0 {
					RankInfoView(
						summary: nil,
						dataOverride: info,
						size: 44,
						lineWidth: 2.5,
						shouldShowProgress: false
					)
				} else if let info, info.gameCount > 0 {
					ZStack {
						Circle()
							.fill(Color.tertiaryGroupedBackground)
						Circle()
							.stroke(Color.secondary.opacity(0.4), lineWidth: 1.5)
						Image(systemName: "questionmark")
							.font(.subheadline.bold())
							.foregroundStyle(.secondary)
					}
					.frame(width: 40, height: 40)
				} else {
					Circle()
						.strokeBorder(
							Color.secondary.opacity(0.35),
							style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])
						)
						.frame(width: 40, height: 40)
				}
			}
			.frame(height: 44)
			
			Text(shortActLabel(for: act))
				.font(.system(size: 10, weight: .medium))
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.minimumScaleFactor(0.75)
		}
	}
	
	private func winRateProgressBlock(
		title: LocalizedStringKey,
		wins: Int,
		games: Int,
		highlightColor: Color
	) -> some View {
		let ratio = games > 0 ? min(1, max(0, Double(wins) / Double(games))) : Double(0)
		let pct = ratio * Double(100)
		return VStack(alignment: .leading, spacing: 6) {
			HStack {
				Text(title)
					.font(.subheadline)
					.foregroundStyle(.secondary)
				Spacer()
				Text(String(format: "%.1f %%", pct))
					.font(.headline.weight(.bold).monospacedDigit())
					.foregroundStyle(highlightColor)
			}
			
			GeometryReader { geo in
				ZStack(alignment: .leading) {
					Capsule()
						.fill(Color.valorantRed.opacity(0.9))
					if wins > 0 {
						Capsule()
							.fill(Color.valorantBlue)
							.frame(width: max(8, geo.size.width * CGFloat(ratio)))
					}
				}
			}
			.frame(height: 7)
			
			Text("\(wins) / \(games)")
				.font(.caption.monospacedDigit())
				.foregroundStyle(.secondary)
		}
	}
	
	private func shortActLabel(for act: Act) -> String {
		if let episode = act.episode {
			let epShort = episode.name
				.replacingOccurrences(of: "Episode ", with: "EP ", options: .caseInsensitive)
				.replacingOccurrences(of: "Season ", with: "V", options: .caseInsensitive)
				.replacingOccurrences(of: "20", with: "")
			return "\(epShort.uppercased()) // \(act.name.uppercased())"
		}
		return act.name.uppercased()
	}
}

#if DEBUG
struct MatchListView_Previews: PreviewProvider {
	static var previews: some View {
		MatchListView(
			userID: PreviewData.userID,
			user: .init(preview: PreviewData.user),
			matchList: .init(preview: PreviewData.matchList),
			summary: .init(preview: PreviewData.summary),
			identity: .init(preview: PreviewData.userIdentity)
		)
		.withToolbar()
		.environmentObject(BookmarkList())
		.environmentObject(SeasonGoalStore())
		.environmentObject(AccountManager.mocked)
		.environmentObject(AppSettings())
	}
}
#endif
