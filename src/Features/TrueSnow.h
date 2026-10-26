#pragma once

#include "Buffer.h"

/**
 * @brief Snow shading for the fraction of each pixel the game draws as snow.
 *
 * Vanilla snow is lit like plaster: plain Lambert diffuse, a grey albedo, and its specular moved to a
 * blurry post-process. True Snow takes the game's own snow sources (landscape snow layers, projected
 * snow, snow objects) and, for that fraction only, brightens the albedo toward fresh snow, adds
 * subsurface scattering and ice translucence, and sun and moon crystal sparkles plus a melt-layer
 * sheen. Code is only compiled into the game's snow shader permutations.
 */
struct TrueSnow : Feature
{
public:
	virtual inline std::string GetName() override { return "True Snow"; }
	virtual std::string GetDisplayName() override { return T("feature.true_snow.name", "True Snow"); }
	virtual inline std::string GetShortName() override { return "TrueSnow"; }
	virtual inline std::string_view GetShaderDefineName() override { return "TRUE_SNOW"; }
	virtual std::string_view GetCategory() const override { return FeatureCategories::kMaterials; }
	virtual bool HasShaderDefine(RE::BSShader::Type a_type) override { return a_type == RE::BSShader::Type::Lighting; }

	virtual std::pair<std::string, std::vector<std::string>> GetFeatureSummary() override
	{
		return { T("feature.true_snow.description", "Realistic snow on vanilla and PBR materials: brighter, softly scattering, translucent at its edges and sparkling in the sun."),
			{ T("feature.true_snow.key_feature_1", "Fresh-snow brightness that keeps the texture's detail"),
				T("feature.true_snow.key_feature_2", "Subsurface scattering: soft, bluish shading past the shadow edge"),
				T("feature.true_snow.key_feature_3", "Ice translucence on ridges and edges lit from behind"),
				T("feature.true_snow.key_feature_4", "Stable sun and moon crystal sparkles, and a melt-layer sheen"),
				T("feature.true_snow.key_feature_5", "Only compiled into snow shaders: no cost elsewhere") } };
	}

	/** @brief User settings; also the feature buffer data, matching TrueSnowSettings in SharedData.hlsli. */
	struct alignas(16) Settings
	{
		uint Enabled = true;
		float Brightness = 1.75f;
		float Subsurface = 0.5f;
		float SparkleIntensity = 1.0f;
		float SparkleDensity = 0.5f;
		float Translucency = 0.5f;
		float Wetness = 0.2f;
		uint DebugView = false;
	} settings;
	STATIC_ASSERT_ALIGNAS_16(Settings);

	virtual void RestoreDefaultSettings() override;
	virtual void LoadSettings(json& o_json) override;
	virtual void SaveSettings(json& o_json) override;
	virtual void DrawSettings() override;
};
