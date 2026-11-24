import SwiftUI
import PhotosUI
import UIKit
import ValorantAPI

struct PresetThumbnailView: View {
	var bannerCardID: PlayerCard.ID?
	var bannerImageData: Data?
	var fallbackIcon: String
	var size: CGFloat = 46
	var cornerRadius: CGFloat = 10
	
	var body: some View {
		Group {
			if let bannerImageData, let uiImage = UIImage(data: bannerImageData) {
				Image(uiImage: uiImage)
					.resizable()
					.aspectRatio(contentMode: .fill)
			} else if let bannerCardID {
				PlayerCardImage.small(bannerCardID)
			} else {
				ZStack {
					Color.accentColor.opacity(0.18)
					Image(systemName: fallbackIcon)
						.font(.system(size: size * 0.44, weight: .semibold))
						.foregroundStyle(Color.accentColor)
				}
			}
		}
		.frame(width: size, height: size)
		.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
	}
}

struct PresetBannerPickerSheet: View {
	@Binding var selectedCardID: PlayerCard.ID?
	@Binding var selectedImageData: Data?
	var equippedCardID: PlayerCard.ID?
	var inventory: Inventory
	
	@Environment(\.assets) private var assets
	@Environment(\.dismiss) private var dismiss
	
	@State private var search = ""
	@State private var pickedPhotoItem: PhotosPickerItem?
	@State private var isProcessingPhoto = false
	@State private var photoError: String?
	
	private var filteredCards: [PlayerCardInfo] {
		guard let assets else { return [] }
		let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
		let allCards = Array(assets.playerCards.values)
		let matching: [PlayerCardInfo] = query.isEmpty
			? allCards
			: allCards.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
		
		return matching.sorted { lhs, rhs in
			let lhsOwned = inventory.cards.contains(lhs.id)
			let rhsOwned = inventory.cards.contains(rhs.id)
			if lhsOwned != rhsOwned {
				return lhsOwned
			}
			return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
		}
	}
	
	var body: some View {
		NavigationStack {
			ScrollView {
				LazyVStack(alignment: .leading, spacing: 16) {
					optionsCard
					
					if assets != nil {
						VStack(alignment: .leading, spacing: 10) {
							Text("Player Cards")
								.font(.subheadline.weight(.medium))
								.foregroundStyle(.secondary)
								.padding(.horizontal, 4)
							
							LazyVGrid(
								columns: [
									GridItem(.flexible(), spacing: 10),
									GridItem(.flexible(), spacing: 10),
									GridItem(.flexible(), spacing: 10),
								],
								spacing: 10
							) {
								ForEach(filteredCards, id: \.id) { card in
									let isSelected = selectedCardID == card.id && selectedImageData == nil
									Button {
										selectedCardID = card.id
										selectedImageData = nil
										dismiss()
									} label: {
										VStack(spacing: 6) {
											PlayerCardImage.small(card.id)
												.aspectRatio(1, contentMode: .fill)
												.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
												.overlay {
													if isSelected {
														RoundedRectangle(cornerRadius: 10, style: .continuous)
															.stroke(Color.accentColor, lineWidth: 2.5)
													}
												}
											
											Text(card.displayName)
												.font(.caption2)
												.foregroundStyle(isSelected ? Color.accentColor : .secondary)
												.lineLimit(1)
										}
									}
									.buttonStyle(.plain)
								}
							}
						}
					}
				}
				.padding(16)
			}
			.background(Color.groupedBackground.ignoresSafeArea())
			.searchable(text: $search, prompt: "Search player cards")
			.navigationTitle("Choose Banner")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") { dismiss() }
				}
			}
			.onChange(of: pickedPhotoItem) { newItem in
				guard let newItem else { return }
				Task {
					await loadCustomPhoto(from: newItem)
				}
			}
			.alert(
				"Could Not Load Image",
				isPresented: Binding(
					get: { photoError != nil },
					set: { if !$0 { photoError = nil } }
				)
			) {
				Button("OK", role: .cancel) {}
			} message: {
				if let photoError {
					Text(photoError)
				}
			}
		}
	}
	
	private var optionsCard: some View {
		VStack(spacing: 0) {
			Button {
				selectedCardID = nil
				selectedImageData = nil
				dismiss()
			} label: {
				optionRow(
					icon: "nosign",
					tint: .secondary,
					title: "No Banner (Default Icon)",
					isSelected: selectedCardID == nil && selectedImageData == nil
				)
			}
			.buttonStyle(.plain)
			
			Divider().padding(.leading, 48).opacity(0.25)
			
			PhotosPicker(selection: $pickedPhotoItem, matching: .images) {
				HStack(spacing: 12) {
					Image(systemName: "photo.on.rectangle")
						.font(.body.weight(.semibold))
						.foregroundStyle(Color.accentColor)
						.frame(width: 24)
					Text("Choose Custom Photo")
						.font(.body)
						.foregroundStyle(.primary)
					Spacer()
					if isProcessingPhoto {
						ProgressView()
							.controlSize(.small)
					} else if selectedImageData != nil {
						Image(systemName: "checkmark")
							.font(.subheadline.weight(.semibold))
							.foregroundStyle(Color.accentColor)
					}
				}
				.padding(.horizontal, 14)
				.padding(.vertical, 13)
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			
			if let equippedCardID {
				Divider().padding(.leading, 48).opacity(0.25)
				
				Button {
					selectedCardID = equippedCardID
					selectedImageData = nil
					dismiss()
				} label: {
					optionRow(
						icon: "person.crop.rectangle",
						tint: .accentColor,
						title: "Use Equipped Player Card",
						isSelected: selectedCardID == equippedCardID && selectedImageData == nil
					)
				}
				.buttonStyle(.plain)
			}
		}
		.background(Color.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}
	
	private func optionRow(
		icon: String,
		tint: Color,
		title: LocalizedStringKey,
		isSelected: Bool
	) -> some View {
		HStack(spacing: 12) {
			Image(systemName: icon)
				.font(.body.weight(.semibold))
				.foregroundStyle(tint)
				.frame(width: 24)
			Text(title)
				.font(.body)
				.foregroundStyle(.primary)
			Spacer()
			if isSelected {
				Image(systemName: "checkmark")
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(Color.accentColor)
			}
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 13)
		.contentShape(Rectangle())
	}
	
	@MainActor
	private func loadCustomPhoto(from item: PhotosPickerItem) async {
		isProcessingPhoto = true
		defer {
			isProcessingPhoto = false
			pickedPhotoItem = nil
		}
		do {
			guard let rawData = try await item.loadTransferable(type: Data.self),
				  let source = UIImage(data: rawData),
				  let compressed = Self.downscaledJPEGData(from: source) else {
				photoError = "Unsupported image format."
				return
			}
			selectedImageData = compressed
			selectedCardID = nil
			dismiss()
		} catch {
			photoError = error.localizedDescription
		}
	}
	
	private static func downscaledJPEGData(from image: UIImage) -> Data? {
		let maxDimension: CGFloat = 256
		let originalSize = image.size
		guard originalSize.width > 0, originalSize.height > 0 else { return nil }
		
		let scale = min(1, maxDimension / max(originalSize.width, originalSize.height))
		let targetSize = CGSize(
			width: max(1, (originalSize.width * scale).rounded()),
			height: max(1, (originalSize.height * scale).rounded())
		)
		
		let format = UIGraphicsImageRendererFormat.default()
		format.scale = 1
		let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
		let resized = renderer.image { _ in
			image.draw(in: CGRect(origin: .zero, size: targetSize))
		}
		return resized.jpegData(compressionQuality: 0.78)
	}
}
