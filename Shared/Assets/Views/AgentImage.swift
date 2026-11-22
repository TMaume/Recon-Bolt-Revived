import SwiftUI
import ValorantAPI

typealias AgentImage = AssetImageView<_AgentImageProvider>
struct _AgentImageProvider: AssetImageProvider {
	static let assetPath = \AssetCollection.agents
}

extension AgentImage {
	static func icon(_ id: Agent.ID, outlineRadius: CGFloat? = nil) -> Self {
		Self(
			id: id,
			aspectRatio: 1,
			outlineRadius: outlineRadius,
			shouldLoadImmediately: true,
			getImage: \.displayIcon
		)
	}
	
	/// Tints the shared Gauntlet (`AbilityDraftAgent`) robot icon with the team's color while preserving any outline.
	@ViewBuilder
	static func icon(_ id: Agent.ID, outlineRadius: CGFloat? = nil, teamColor: Color?) -> some View {
		if id == .abilityDraftAgent, let teamColor {
			ZStack {
				if let outlineRadius {
					Self(
						id: id,
						renderingMode: .template,
						aspectRatio: 1,
						outlineRadius: outlineRadius,
						shouldLoadImmediately: true,
						getImage: \.displayIcon
					)
					.foregroundColor(.white)
				}
				icon(id)
					.grayscale(1)
					.contrast(1.2)
					.brightness(0.08)
					.colorMultiply(teamColor)
			}
		} else {
			icon(id, outlineRadius: outlineRadius)
		}
	}
	
	static func fullPortrait(_ id: Agent.ID) -> Self {
		Self(id: id, aspectRatio: 2048/1860, preferFullResolution: true, getImage: \.fullPortrait)
	}
	
	static func killfeedPortrait(_ id: Agent.ID) -> Self {
		Self(id: id, aspectRatio: 2, shouldLoadImmediately: true, getImage: \.killfeedPortrait)
	}
	
	@ViewBuilder
	static func killfeedPortrait(_ id: Agent.ID, teamColor: Color?) -> some View {
		if id == .abilityDraftAgent, let teamColor {
			killfeedPortrait(id)
				.grayscale(1)
				.contrast(1.2)
				.brightness(0.08)
				.colorMultiply(teamColor)
		} else {
			killfeedPortrait(id)
		}
	}
	
	static func ability(_ id: Agent.ID, slot: AgentInfo.Ability.Slot) -> Self {
		Self(id: id, renderingMode: .template, aspectRatio: 1, shouldLoadImmediately: true) { $0.ability(slot)?.displayIcon }
	}
}

#if DEBUG
struct AgentImage_Previews: PreviewProvider {
	static var previews: some View {
		Group {
			AgentImage.icon(.omen)
				.frame(height: 80)
			AgentImage.fullPortrait(.omen)
		}
		.previewLayout(.sizeThatFits)
	}
}
#endif
