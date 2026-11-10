#pragma once

#include "Buffer.h"

/**
 * @brief Light inside the game's cloud layers.
 *
 * Vanilla clouds are flat cut-outs tinted by the weather colour: no light comes through them. True
 * Clouds uses the cloud texture's opacity as thickness to add a silver lining on edges in front of
 * the sun or moon, a glow through thin cloud near the light, darker dense cloud, and light-coloured
 * edges at sunrise and sunset. It runs in the game's cloud shaders only; settings live in the spare
 * FeatureData slots.
 */
struct TrueClouds : Feature
{
public:
	virtual inline std::string GetName() override { return "True Clouds"; }
	virtual std::string GetDisplayName() override { return T("feature.true_clouds.name", "True Clouds"); }
	virtual inline std::string GetShortName() override { return "TrueClouds"; }
	virtual inline std::string_view GetShaderDefineName() override { return "TRUE_CLOUDS"; }
	virtual std::string_view GetCategory() const override { return FeatureCategories::kSky; }
	virtual bool HasShaderDefine(RE::BSShader::Type a_type) override { return a_type == RE::BSShader::Type::Sky; }

	virtual std::pair<std::string, std::vector<std::string>> GetFeatureSummary() override
	{
		return { T("feature.true_clouds.description", "Clouds that let the sun and moon through: silver linings, glowing thin cloud and darker, deeper storm clouds."),
			{ T("feature.true_clouds.key_feature_1", "Silver lining on cloud edges in front of the sun and moon"),
				T("feature.true_clouds.key_feature_2", "Sunlight glowing through thin cloud"),
				T("feature.true_clouds.key_feature_3", "Thick clouds darker and deeper"),
				T("feature.true_clouds.key_feature_4", "Warm lit edges at sunrise and sunset"),
				T("feature.true_clouds.key_feature_5", "Only compiled into cloud shaders: no cost elsewhere") } };
	}

	/// First spare FeatureData slot; must match TrueClouds::SpareSlot in TrueClouds.hlsli.
	static constexpr uint32_t SpareSlot = 4;

	/** @brief User settings; also the spare-slot data unpacked by TrueClouds::GetSettings() in HLSL. */
	struct alignas(16) Settings
	{
		uint Enabled = true;
		float SilverLining = 0.2f;
		float SunGlow = 0.15f;
		float Depth = 0.5f;
		float SunTint = 0.5f;
		uint DebugView = false;
		float pad0 = 0.0f;
		float pad1 = 0.0f;
	} settings;
	STATIC_ASSERT_ALIGNAS_16(Settings);

	virtual void RestoreDefaultSettings() override;
	virtual void LoadSettings(json& o_json) override;
	virtual void SaveSettings(json& o_json) override;
	virtual void DrawSettings() override;
};
