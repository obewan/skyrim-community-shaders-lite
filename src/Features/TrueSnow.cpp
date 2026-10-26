#include "TrueSnow.h"

#include "I18n/I18n.h"
#include "Utils/UI.h"

NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE_WITH_DEFAULT(
	TrueSnow::Settings,
	Enabled,
	Brightness,
	Subsurface,
	SparkleIntensity,
	SparkleDensity,
	Translucency,
	Wetness)

#define I18N_KEY_PREFIX "feature.true_snow."

void TrueSnow::DrawSettings()
{
	ImGui::Checkbox(T(TKEY("enabled"), "Enabled"), (bool*)&settings.Enabled);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("enabled_tooltip"), "Applies to landscape snow, projected snow on rocks and roofs, and snow objects."));
	}

	const Util::DisableGuard disabled(!settings.Enabled);

	ImGui::SliderFloat(T(TKEY("brightness"), "Brightness"), &settings.Brightness, 1.0f, 2.0f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("brightness_tooltip"), "Lifts grey snow textures toward fresh-snow reflectance, keeping their detail. Capped below pure white."));
	}

	ImGui::SliderFloat(T(TKEY("subsurface"), "Subsurface"), &settings.Subsurface, 0.0f, 1.0f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("subsurface_tooltip"), "Light scattered inside the snow: softens the shadow edge with a cool blue tint."));
	}

	ImGui::SliderFloat(T(TKEY("translucency"), "Ice Translucency"), &settings.Translucency, 0.0f, 1.0f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("translucency_tooltip"), "Light passing through thin ridges and edges when the sun is behind them."));
	}

	ImGui::SliderFloat(T(TKEY("wetness"), "Wetness"), &settings.Wetness, 0.0f, 1.0f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("wetness_tooltip"), "Soft glossy sheen of a thin melt layer, strongest at grazing angles."));
	}

	ImGui::SliderFloat(T(TKEY("sparkle_intensity"), "Sparkle Intensity"), &settings.SparkleIntensity, 0.0f, 2.0f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("sparkle_intensity_tooltip"), "Brightness of the ice crystal glints in sunlight and moonlight. 0 turns them off."));
	}

	ImGui::SliderFloat(T(TKEY("sparkle_density"), "Sparkle Density"), &settings.SparkleDensity, 0.1f, 2.0f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("sparkle_density_tooltip"), "How fine the crystals are. Higher values give smaller, more numerous sparkles."));
	}
}

#undef I18N_KEY_PREFIX

void TrueSnow::LoadSettings(json& o_json)
{
	settings = o_json;
	settings.Brightness = std::clamp(settings.Brightness, 1.0f, 2.0f);
	settings.Subsurface = std::clamp(settings.Subsurface, 0.0f, 1.0f);
	settings.Translucency = std::clamp(settings.Translucency, 0.0f, 1.0f);
	settings.Wetness = std::clamp(settings.Wetness, 0.0f, 1.0f);
	settings.SparkleIntensity = std::clamp(settings.SparkleIntensity, 0.0f, 2.0f);
	settings.SparkleDensity = std::clamp(settings.SparkleDensity, 0.1f, 2.0f);
}

void TrueSnow::SaveSettings(json& o_json)
{
	o_json = settings;
}

void TrueSnow::RestoreDefaultSettings()
{
	settings = {};
}
