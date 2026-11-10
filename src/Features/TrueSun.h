#pragma once

#include "Buffer.h"

/**
 * @brief A realistic sun in place of the vanilla pale flat disk.
 *
 * Replaces the sun texture with a procedural photosphere: far brighter than the sky so it blooms and
 * clips to white, with a darker, warmer limb, a forward-scattering aureole, and the dimming and
 * reddening of the air it is seen through near the horizon. The weather's sun colour and visibility
 * still drive it. Code is only compiled into the sky shader's sun permutations.
 */
struct TrueSun : Feature
{
public:
	virtual inline std::string GetName() override { return "True Sun"; }
	virtual std::string GetDisplayName() override { return T("feature.true_sun.name", "True Sun"); }
	virtual inline std::string GetShortName() override { return "TrueSun"; }
	virtual inline std::string_view GetShaderDefineName() override { return "TRUE_SUN"; }
	virtual std::string_view GetCategory() const override { return FeatureCategories::kSky; }
	virtual bool HasShaderDefine(RE::BSShader::Type a_type) override { return a_type == RE::BSShader::Type::Sky; }

	virtual std::pair<std::string, std::vector<std::string>> GetFeatureSummary() override
	{
		return { T("feature.true_sun.description", "A realistic sun instead of the vanilla pale flat disk."),
			{ T("feature.true_sun.key_feature_1", "A blinding disk that blooms and clips to white"),
				T("feature.true_sun.key_feature_2", "Limb darkening: the edge of the disk is dimmer and warmer"),
				T("feature.true_sun.key_feature_3", "A soft aureole of light scattered by haze"),
				T("feature.true_sun.key_feature_4", "Dims and turns orange-red toward the horizon"),
				T("feature.true_sun.key_feature_5", "Only compiled into the sun's sky shaders: no cost elsewhere") } };
	}

	/** @brief User settings; also the feature buffer data, matching TrueSunSettings in SharedData.hlsli. */
	struct alignas(16) Settings
	{
		uint Enabled = true;
		float Size = 5.0f;
		float Intensity = 12.0f;
		float GlowIntensity = 0.8f;
		float GlowSize = 3.0f;
		float Reddening = 0.5f;
		float GlareIntensity = 1.0f;
		float pad0 = 0.0f;
	} settings;
	STATIC_ASSERT_ALIGNAS_16(Settings);

	virtual void RestoreDefaultSettings() override;
	virtual void LoadSettings(json& o_json) override;
	virtual void SaveSettings(json& o_json) override;
	virtual void DrawSettings() override;
};
