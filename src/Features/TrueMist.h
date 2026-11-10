#pragma once

#include <shared_mutex>

#include "Buffer.h"

/**
 * @brief Shading for water mist, steam and fog effects.
 *
 * Vanilla and water-mod mist (river fog skirts, waterfall spray, steam) is drawn as large effect
 * sprites shaded with one flat colour and an even opacity, so it reads as a grey sheet. True Mist
 * flags effect draws whose source or greyscale texture is a mist, steam, fog, vapor or spray texture
 * and, for those only, brightens them in sunlight (shadowed, more toward the sun), adds twinkling
 * droplet glints, tints them with the sky's ambient colour, breaks them into drifting wisps and
 * thins them when seen from above or up close.
 * Settings live in the spare FeatureData slots.
 */
struct TrueMist : Feature
{
public:
	virtual inline std::string GetName() override { return "True Mist"; }
	virtual std::string GetDisplayName() override { return T("feature.true_mist.name", "True Mist"); }
	virtual inline std::string GetShortName() override { return "TrueMist"; }
	virtual inline std::string_view GetShaderDefineName() override { return "TRUE_MIST"; }
	virtual std::string_view GetCategory() const override { return FeatureCategories::kSky; }
	virtual bool HasShaderDefine(RE::BSShader::Type a_type) override { return a_type == RE::BSShader::Type::Effect; }

	virtual std::pair<std::string, std::vector<std::string>> GetFeatureSummary() override
	{
		return { T("feature.true_mist.description", "River fog, waterfall spray and steam that glow in the sun and drift in wisps instead of hanging like grey sheets."),
			{ T("feature.true_mist.key_feature_1", "Sunlight scattering through the mist, blocked by shadows"),
				T("feature.true_mist.key_feature_2", "Sky-coloured ambient light instead of flat grey"),
				T("feature.true_mist.key_feature_3", "Drifting wisps that break up the flat sprites"),
				T("feature.true_mist.key_feature_4", "Thinner from above and up close, so water and rocks stay visible"),
				T("feature.true_mist.key_feature_5", "Only runs on mist effects: no new shader variants") } };
	}

	/// First spare FeatureData slot; must match TrueMist::SpareSlot in TrueMist.hlsli.
	static constexpr uint32_t SpareSlot = 2;

	/** @brief User settings; also the spare-slot data unpacked by TrueMist::GetSettings() in HLSL. */
	struct alignas(16) Settings
	{
		uint Enabled = true;
		float SunScattering = 1.0f;
		float AmbientTint = 0.5f;
		float Breakup = 0.5f;
		float ThinFromAbove = 0.5f;
		float NearFade = 300.0f;
		uint DebugView = false;
		float Glints = 0.5f;
	} settings;
	STATIC_ASSERT_ALIGNAS_16(Settings);

	virtual void RestoreDefaultSettings() override;
	virtual void LoadSettings(json& o_json) override;
	virtual void SaveSettings(json& o_json) override;
	virtual void DrawSettings() override;
	virtual void PostPostLoad() override;

	/**
	 * @brief Sets or clears the mist flag in the per-draw feature descriptor.
	 * @param a_pass Render pass about to be drawn by the Effect shader.
	 */
	void BSEffectShader_SetupGeometry(RE::BSRenderPass* a_pass);

private:
	struct Hooks;

	/** @brief True when an effect texture path names a mist texture (cached by path). */
	bool IsMistTexture(std::string_view a_path);

	/// Heterogeneous string hash, so per-draw lookups by string_view do not allocate.
	struct PathHash
	{
		using is_transparent = void;
		size_t operator()(std::string_view a_path) const noexcept { return std::hash<std::string_view>{}(a_path); }
	};

	std::shared_mutex textureMutex;
	std::unordered_map<std::string, bool, PathHash, std::equal_to<>> textureCache;  ///< Guarded by textureMutex.
	static constexpr uint32_t MaxLoggedTextures = 30;
	uint32_t loggedTextures = 0;  ///< Guarded by textureMutex.
};
