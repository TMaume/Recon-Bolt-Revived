import Foundation
import ValorantAPI

@MainActor
final class FavoritesManager: ObservableObject {
	@Published private(set) var favoritesByAccount: [User.ID: Favorites] = [:]
	@Published private(set) var inventoryByAccount: [User.ID: Inventory] = [:]
	@Published private(set) var inFlightItemIDs: Set<LowercaseUUID> = []
	@Published private(set) var isApplyingPreset = false
	
	private var itemIDsByAccount: [User.ID: Set<LowercaseUUID>] = [:]
	private var inventoryFetchTasks: [User.ID: Task<Void, Never>] = [:]
	private var prefersSkinIDOverBaseLevelID: Bool?
	
	private func setFavorites(_ favorites: Favorites?, for accountID: User.ID) {
		favoritesByAccount[accountID] = favorites
		itemIDsByAccount[accountID] = favorites?.itemIDs
	}
	
	func cacheInventory(_ inventory: Inventory, for accountID: User.ID) {
		inventoryByAccount[accountID] = inventory
	}
	
	func inventory(for accountID: User.ID?) -> Inventory? {
		guard let accountID else { return nil }
		return inventoryByAccount[accountID]
	}
	
	func refreshInventoryIfNeeded(using client: ValorantClient) async {
		let accountID = client.userID
		guard inventoryByAccount[accountID] == nil else { return }
		if let existing = inventoryFetchTasks[accountID] {
			await existing.value
			return
		}
		let task = Task { [weak self] in
			defer { self?.inventoryFetchTasks.removeValue(forKey: accountID) }
			if let loaded = try? await client.getInventory() {
				self?.inventoryByAccount[accountID] = loaded
			}
		}
		inventoryFetchTasks[accountID] = task
		await task.value
	}
	
	func favorites(for accountID: User.ID?) -> Favorites? {
		guard let accountID else { return nil }
		return favoritesByAccount[accountID]
	}
	
	func itemIDs(for accountID: User.ID?) -> Set<LowercaseUUID> {
		guard let accountID else { return [] }
		return itemIDsByAccount[accountID] ?? []
	}
	
	func isFavorited(_ itemID: LowercaseUUID, for accountID: User.ID?) -> Bool {
		guard let accountID else { return false }
		return itemIDsByAccount[accountID]?.contains(itemID) ?? false
	}
	
	func isSkinFavorited(_ skin: WeaponSkin, for accountID: User.ID?) -> Bool {
		guard let accountID, let ids = itemIDsByAccount[accountID] else { return false }
		if ids.contains(skin.id.rawID) { return true }
		return skin.levels.contains { ids.contains($0.id.rawID) }
	}
	
	func isLoading(_ itemID: LowercaseUUID) -> Bool {
		inFlightItemIDs.contains(itemID)
	}
	
	func isLoading(skin: WeaponSkin) -> Bool {
		if inFlightItemIDs.contains(skin.id.rawID) { return true }
		return skin.levels.contains { inFlightItemIDs.contains($0.id.rawID) }
	}
	
	func refresh(using client: ValorantClient) async {
		if let loaded = try? await client.getFavorites() {
			setFavorites(loaded, for: client.userID)
		}
	}
	
	func refreshIfNeeded(using client: ValorantClient) async {
		if favoritesByAccount[client.userID] == nil {
			await refresh(using: client)
		}
	}
	
	func toggleFavorite(itemID: LowercaseUUID, using client: ValorantClient) async throws {
		try await toggleFavorite(
			primaryID: itemID,
			addFallbackIDs: [],
			matchIDs: [itemID],
			using: client
		)
	}
	
	func toggleSkinFavorite(_ skin: WeaponSkin, using client: ValorantClient) async throws {
		let baseLevelID = skin.levels.first?.id.rawID
		let skinID = skin.id.rawID
		let primaryID: LowercaseUUID
		let addFallbackIDs: [LowercaseUUID]
		if prefersSkinIDOverBaseLevelID == true {
			primaryID = skinID
			addFallbackIDs = (baseLevelID != nil && baseLevelID != skinID) ? [baseLevelID!] : []
		} else {
			primaryID = baseLevelID ?? skinID
			addFallbackIDs = (baseLevelID != nil && baseLevelID != skinID) ? [skinID] : []
		}
		
		var seen = Set<LowercaseUUID>()
		let matchIDs = ([primaryID] + addFallbackIDs + skin.levels.map(\.id.rawID) + [skinID]).filter {
			seen.insert($0).inserted
		}
		
		try await toggleFavorite(
			primaryID: primaryID,
			addFallbackIDs: addFallbackIDs,
			matchIDs: matchIDs,
			using: client
		) { [weak self] usedID in
			guard let self, let baseLevelID, baseLevelID != skinID else { return }
			if usedID == skinID {
				self.prefersSkinIDOverBaseLevelID = true
			} else if usedID == baseLevelID {
				self.prefersSkinIDOverBaseLevelID = false
			}
		}
	}
	
	private func toggleFavorite(
		primaryID: LowercaseUUID,
		addFallbackIDs: [LowercaseUUID],
		matchIDs: [LowercaseUUID],
		using client: ValorantClient,
		onAdded: ((LowercaseUUID) -> Void)? = nil
	) async throws {
		guard !inFlightItemIDs.contains(primaryID) else { return }
		inFlightItemIDs.insert(primaryID)
		defer { inFlightItemIDs.remove(primaryID) }
		
		let accountID = client.userID
		let previous = favoritesByAccount[accountID]
		let matchSet = Set(matchIDs)
		let matchKeySet = Set(matchIDs.map(\.description))
		
		var matchedEntry: Favorites.FavoriteEntry?
		var matchedKey: String?
		if let current = previous {
			for candidate in matchIDs {
				if let entry = current.favoritedContent[candidate.description] {
					matchedEntry = entry
					matchedKey = candidate.description
					break
				}
				if let pair = current.favoritedContent.first(where: { $0.value.itemID == candidate }) {
					matchedEntry = pair.value
					matchedKey = pair.key
					break
				}
			}
		}
		
		let isRemoving = matchedEntry != nil
		
		// Optimistic UI update
		var optimistic = previous ?? Favorites(subject: accountID)
		if isRemoving {
			optimistic.favoritedContent = optimistic.favoritedContent.filter { key, entry in
				key != matchedKey && !matchKeySet.contains(key) && !matchSet.contains(entry.itemID)
			}
		} else {
			optimistic.favoritedContent[primaryID.description] = Favorites.FavoriteEntry(
				id: primaryID,
				itemID: primaryID
			)
		}
		setFavorites(optimistic, for: accountID)
		
		do {
			let updated: Favorites
			if isRemoving, let matchedEntry {
				updated = try await client.removeFavorite(
					itemID: matchedEntry.itemID,
					favoriteID: matchedEntry.id
				)
			} else {
				let result = try await addWithFallbacks(
					primaryID: primaryID,
					fallbackIDs: addFallbackIDs,
					using: client
				)
				updated = result.favorites
				onAdded?(result.usedID)
			}
			setFavorites(updated, for: accountID)
		} catch {
			if isRemoving {
				var rolledBack = favoritesByAccount[accountID] ?? Favorites(subject: accountID)
				if let previous {
					for (key, entry) in previous.favoritedContent where key == matchedKey || matchKeySet.contains(key) || matchSet.contains(entry.itemID) {
						rolledBack.favoritedContent[key] = entry
					}
				}
				setFavorites(rolledBack, for: accountID)
			} else if var rolledBack = favoritesByAccount[accountID] {
				rolledBack.favoritedContent.removeValue(forKey: primaryID.description)
				if let previous {
					setFavorites(previous.favoritedContent.isEmpty && rolledBack.favoritedContent.isEmpty ? previous : rolledBack, for: accountID)
				} else {
					setFavorites(rolledBack.favoritedContent.isEmpty ? nil : rolledBack, for: accountID)
				}
			} else {
				setFavorites(previous, for: accountID)
			}
			throw error
		}
	}
	
	private static func isIgnorableFavoriteMutationError(_ error: Error) -> Bool {
		switch error {
		case APIError.resourceNotFound:
			return true
		case APIError.badResponseCode(let code, _, _):
			return code == 400 || code == 404
		default:
			return false
		}
	}
	
	private func addWithFallbacks(
		primaryID: LowercaseUUID,
		fallbackIDs: [LowercaseUUID],
		using client: ValorantClient
	) async throws -> (favorites: Favorites, usedID: LowercaseUUID) {
		do {
			let updated = try await client.addFavorite(primaryID)
			return (updated, primaryID)
		} catch where Self.isIgnorableFavoriteMutationError(error) && !fallbackIDs.isEmpty {
			let firstError = error
			var seen: Set<LowercaseUUID> = [primaryID]
			for fallback in fallbackIDs where seen.insert(fallback).inserted {
				do {
					let updated = try await client.addFavorite(fallback)
					return (updated, fallback)
				} catch {
					continue
				}
			}
			throw firstError
		}
	}
	
	func applyFavoritesPreset(
		itemIDs targetList: [LowercaseUUID],
		using client: ValorantClient,
		progress: ((Int, Int) -> Void)? = nil
	) async throws {
		guard !isApplyingPreset else { return }
		isApplyingPreset = true
		defer { isApplyingPreset = false }
		
		let current = try await client.getFavorites()
		var seen = Set<LowercaseUUID>()
		let dedupedTarget = targetList.filter { seen.insert($0).inserted }
		let targetSet = Set(dedupedTarget)
		
		let currentEntries = Array(current.favoritedContent.values)
		let currentIDs = Set(currentEntries.map(\.itemID))
		let toRemove = currentEntries.filter { !targetSet.contains($0.itemID) }
		let toAdd = dedupedTarget.filter { !currentIDs.contains($0) }
		let total = toRemove.count + toAdd.count
		
		setFavorites(current, for: client.userID)
		guard total > 0 else { return }
		
		var completed = 0
		var latestFavorites: Favorites?
		progress?(0, total)
		
		do {
			for entry in toRemove {
				try Task.checkCancellation()
				do {
					latestFavorites = try await client.removeFavorite(
						itemID: entry.itemID,
						favoriteID: entry.id
					)
				} catch where Self.isIgnorableFavoriteMutationError(error) {
					// Ignore stale/missing items on the server so remaining mutations complete.
				}
				completed += 1
				progress?(completed, total)
			}
			
			for id in toAdd {
				try Task.checkCancellation()
				do {
					latestFavorites = try await client.addFavorite(id)
				} catch where Self.isIgnorableFavoriteMutationError(error) {
					// Ignore unowned items if applying across accounts.
				}
				completed += 1
				progress?(completed, total)
			}
		} catch {
			if let latestFavorites {
				setFavorites(latestFavorites, for: client.userID)
			}
			throw error
		}
		
		if let latestFavorites {
			setFavorites(latestFavorites, for: client.userID)
		} else if let finalFavs = try? await client.getFavorites() {
			setFavorites(finalFavs, for: client.userID)
		}
	}
}
