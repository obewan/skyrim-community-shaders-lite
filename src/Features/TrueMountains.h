#pragma once

#include <shared_mutex>

#include "Buffer.h"

/**
 * @brief Rock shading for mountains, cliffs and boulders.
 *
 * Vanilla mountains are lit like cardboard: a soft normal map, washed-out grey albedo, and no
 * self-shadowing. True Mountains flags draws whose diffuse texture is a landscape rock texture and,
 * for those only, casts relief self-shadows from a height guessed from the texture, darkens cavities
 * and restores the rock's contrast and colour. The check is a runtime branch in the existing
 * Lighting permutations, so it adds no shader variants. Settings live in the spare FeatureData slots.
 */
struct TrueMountains : Feature
{
public:
	virtual inline std::string GetName() override { return "True Mountains"; }
	virtual std::string GetDisplayName() override { return T("feature.true_mountains.name", "True Mountains"); }
	virtual inline std::string GetShortName() override { return "TrueMountains"; }
	virtual inline std::string_view GetShaderDefineName() override { return "TRUE_MOUNTAINS"; }
	virtual std::string_view GetCategory() const override { return FeatureCategories::kMaterials; }
	virtual bool HasShaderDefine(RE::BSShader::Type a_type) override { return a_type == RE::BSShader::Type::Lighting; }

	virtual std::pair<std::string, std::vector<std::string>> GetFeatureSummary() override
	{
		return { T("feature.true_mountains.description", "Mountains, cliffs and boulders with real relief instead of flat grey cardboard."),
			{ T("feature.true_mountains.key_feature_1", "Relief self-shadows in cracks and under ledges, following the sun"),
				T("feature.true_mountains.key_feature_2", "Darker cavities and restored rock contrast"),
				T("feature.true_mountains.key_feature_3", "Subtle colour variation across large rock faces"),
				T("feature.true_mountains.key_feature_4", "Only runs on rock surfaces: no new shader variants") } };
	}

	/// First spare FeatureData slot; must match TrueMountains::SpareSlot in TrueMountains.hlsli.
	static constexpr uint32_t SpareSlot = 0;

	/** @brief User settings; also the spare-slot data unpacked by TrueMountains::GetSettings() in HLSL. */
	struct alignas(16) Settings
	{
		uint Enabled = true;
		float ReliefShadows = 0.8f;
		float ReliefDepth = 0.5f;
		float Cavity = 0.5f;
		float Contrast = 0.4f;
		float ColorVariation = 0.5f;
		uint DebugView = false;
		float pad0 = 0.0f;
	} settings;
	STATIC_ASSERT_ALIGNAS_16(Settings);

	virtual void RestoreDefaultSettings() override;
	virtual void LoadSettings(json& o_json) override;
	virtual void SaveSettings(json& o_json) override;
	virtual void DrawSettings() override;
	virtual void PostPostLoad() override;

	/**
	 * @brief Sets or clears the mountain flag in the per-draw feature descriptor.
	 * @param a_pass Render pass about to be drawn by the Lighting shader.
	 */
	void BSLightingShader_SetupGeometry(RE::BSRenderPass* a_pass);

private:
	struct Hooks;

	/** @brief True when a diffuse texture path is a landscape rock texture (cached by path). */
	bool IsRockTexture(std::string_view a_path);

	/** @brief Logs (once per texture, capped) a rock texture whose draw an exclusion rejected. */
	void LogRejectedRock(std::string_view a_path, bool a_alphaTested, uint64_t a_flags);

	/// Heterogeneous string hash, so per-draw lookups by string_view do not allocate.
	struct PathHash
	{
		using is_transparent = void;
		size_t operator()(std::string_view a_path) const noexcept { return std::hash<std::string_view>{}(a_path); }
	};

	std::shared_mutex textureMutex;
	/// Keyed by path content: texture-set paths are plain strings whose addresses can be reused.
	std::unordered_map<std::string, bool, PathHash, std::equal_to<>> textureCache;

	static constexpr uint32_t MaxLoggedRockTextures = 20;
	uint32_t loggedRockTextures = 0;     ///< Guarded by textureMutex.
	uint32_t loggedMissedTextures = 0;   ///< Guarded by textureMutex.
	uint32_t loggedRejections = 0;       ///< Guarded by textureMutex.
	std::unordered_set<std::string, PathHash, std::equal_to<>> rejectedLogged;  ///< Guarded by textureMutex.
};
