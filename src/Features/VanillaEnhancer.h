#pragma once

#include "Buffer.h"

/**
 * @brief Improves the shading of vanilla (non-PBR) materials using only the textures they already have.
 *
 * Corrects vanilla Blinn-Phong specular (energy, Fresnel, highlights behind the surface) and darkens
 * ambient light where the normal map implies grooves and cracks. Meant for players who cannot afford
 * parallax or PBR texture packs: a few instructions per pixel, no extra textures. PBR materials, hair
 * and skin keep their own shading models.
 */
struct VanillaEnhancer : Feature
{
public:
	virtual inline std::string GetName() override { return "Vanilla Enhancer"; }
	virtual std::string GetDisplayName() override { return T("feature.vanilla_enhancer.name", "Vanilla Enhancer"); }
	virtual inline std::string GetShortName() override { return "VanillaEnhancer"; }
	virtual inline std::string_view GetShaderDefineName() override { return "VANILLA_ENHANCER"; }
	virtual std::string_view GetCategory() const override { return FeatureCategories::kMaterials; }
	virtual bool HasShaderDefine(RE::BSShader::Type a_type) override { return a_type == RE::BSShader::Type::Lighting; }

	virtual std::pair<std::string, std::vector<std::string>> GetFeatureSummary() override
	{
		return { T("feature.vanilla_enhancer.description", "Better shading for vanilla materials from the textures they already have, for setups without parallax or PBR textures."),
			{ T("feature.vanilla_enhancer.key_feature_1", "Energy-normalized specular: glossy highlights get tight and bright, rough ones soft and wide"),
				T("feature.vanilla_enhancer.key_feature_2", "Fresnel brightening at grazing angles"),
				T("feature.vanilla_enhancer.key_feature_3", "No more highlights on the side facing away from the light"),
				T("feature.vanilla_enhancer.key_feature_4", "Normal map occlusion: grooves and cracks receive less ambient light"),
				T("feature.vanilla_enhancer.key_feature_5", "No extra textures, a few instructions per pixel") } };
	}

	/** @brief User settings; also the feature buffer data, matching VanillaEnhancerSettings in SharedData.hlsli. */
	struct alignas(16) Settings
	{
		uint Enabled = true;
		float SpecularEnergy = 1.0f;
		float Fresnel = 0.5f;
		uint HorizonFix = true;
		float NormalOcclusion = 0.5f;
		float pad0[3]{};
	} settings;
	STATIC_ASSERT_ALIGNAS_16(Settings);

	virtual void RestoreDefaultSettings() override;
	virtual void LoadSettings(json& o_json) override;
	virtual void SaveSettings(json& o_json) override;
	virtual void DrawSettings() override;
};
