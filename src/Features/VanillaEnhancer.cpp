#include "VanillaEnhancer.h"

#include "I18n/I18n.h"
#include "Utils/UI.h"

NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE_WITH_DEFAULT(
	VanillaEnhancer::Settings,
	Enabled,
	SpecularEnergy,
	Fresnel,
	HorizonFix,
	NormalOcclusion)

#define I18N_KEY_PREFIX "feature.vanilla_enhancer."

void VanillaEnhancer::DrawSettings()
{
	ImGui::Checkbox(T(TKEY("enabled"), "Enabled"), (bool*)&settings.Enabled);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("enabled_tooltip"), "Applies to vanilla (non-PBR) materials. PBR materials, hair and skin keep their own shading."));
	}

	const Util::DisableGuard disabled(!settings.Enabled);

	ImGui::SliderFloat(T(TKEY("specular_energy"), "Specular Energy"), &settings.SpecularEnergy, 0.0f, 1.0f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("specular_energy_tooltip"), "Blends from vanilla specular (0) to energy-normalized specular (1).\nGlossy materials get tighter, brighter highlights and rough ones softer, dimmer highlights."));
	}

	ImGui::SliderFloat(T(TKEY("fresnel"), "Fresnel"), &settings.Fresnel, 0.0f, 1.0f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("fresnel_tooltip"), "Brightens specular highlights at grazing angles, like real surfaces do."));
	}

	ImGui::Checkbox(T(TKEY("horizon_fix"), "Specular Horizon Fix"), (bool*)&settings.HorizonFix);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("horizon_fix_tooltip"), "Removes vanilla highlights on the side of a surface facing away from the light."));
	}

	ImGui::SliderFloat(T(TKEY("normal_occlusion"), "Normal Map Occlusion"), &settings.NormalOcclusion, 0.0f, 1.0f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("normal_occlusion_tooltip"), "Darkens ambient light and reflections where the normal map implies grooves and cracks."));
	}
}

#undef I18N_KEY_PREFIX

void VanillaEnhancer::LoadSettings(json& o_json)
{
	settings = o_json;
	settings.SpecularEnergy = std::clamp(settings.SpecularEnergy, 0.0f, 1.0f);
	settings.Fresnel = std::clamp(settings.Fresnel, 0.0f, 1.0f);
	settings.NormalOcclusion = std::clamp(settings.NormalOcclusion, 0.0f, 1.0f);
}

void VanillaEnhancer::SaveSettings(json& o_json)
{
	o_json = settings;
}

void VanillaEnhancer::RestoreDefaultSettings()
{
	settings = {};
}
