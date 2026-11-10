#include "TrueSun.h"

#include "I18n/I18n.h"
#include "Utils/UI.h"

NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE_WITH_DEFAULT(
	TrueSun::Settings,
	Enabled,
	Size,
	Intensity,
	GlowIntensity,
	GlowSize,
	Reddening,
	GlareIntensity)

#define I18N_KEY_PREFIX "feature.true_sun."

void TrueSun::DrawSettings()
{
	ImGui::Checkbox(T(TKEY("enabled"), "Enabled"), (bool*)&settings.Enabled);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("enabled_tooltip"), "Replaces the vanilla sun texture with a procedural sun. Weather sun colours and cloud cover still apply."));
	}

	const Util::DisableGuard disabled(!settings.Enabled);

	ImGui::SliderFloat(T(TKEY("size"), "Size"), &settings.Size, 0.1f, 10.0f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("size_tooltip"), "Apparent diameter of the sun's disk, in degrees of sky. The real sun is about 0.5."));
	}

	ImGui::SliderFloat(T(TKEY("intensity"), "Intensity"), &settings.Intensity, 1.0f, 32.0f, "%.1f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("intensity_tooltip"), "Brightness of the disk. High values make it bloom and clip to white, like the real sun."));
	}

	ImGui::SliderFloat(T(TKEY("glow_intensity"), "Aureole Intensity"), &settings.GlowIntensity, 0.0f, 4.0f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("glow_intensity_tooltip"), "Brightness of the halo of light scattered by haze around the disk. 0 turns it off."));
	}

	ImGui::SliderFloat(T(TKEY("glow_size"), "Aureole Size"), &settings.GlowSize, 0.2f, 10.0f, "%.1f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("glow_size_tooltip"), "How far the aureole reaches beyond the disk, in degrees of sky. Hazy air spreads it wider."));
	}

	ImGui::SliderFloat(T(TKEY("reddening"), "Horizon Reddening"), &settings.Reddening, 0.0f, 2.0f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("reddening_tooltip"), "How much the air dims and reddens the sun as it nears the horizon. Weathers already tint the sun at dawn and dusk; lower this if sunsets turn too red."));
	}

	ImGui::SliderFloat(T(TKEY("glare_intensity"), "Glare Intensity"), &settings.GlareIntensity, 0.0f, 2.0f, "%.2f", ImGuiSliderFlags_AlwaysClamp);
	if (auto _tt = Util::HoverTooltipWrapper()) {
		ImGui::Text("%s", T(TKEY("glare_intensity_tooltip"), "Brightness of the game's large sun glare around the disk. It reddens with the sun near the horizon."));
	}
}

#undef I18N_KEY_PREFIX

void TrueSun::LoadSettings(json& o_json)
{
	settings = o_json;
	settings.Size = std::clamp(settings.Size, 0.1f, 10.0f);
	settings.Intensity = std::clamp(settings.Intensity, 1.0f, 32.0f);
	settings.GlowIntensity = std::clamp(settings.GlowIntensity, 0.0f, 4.0f);
	settings.GlowSize = std::clamp(settings.GlowSize, 0.2f, 10.0f);
	settings.Reddening = std::clamp(settings.Reddening, 0.0f, 2.0f);
	settings.GlareIntensity = std::clamp(settings.GlareIntensity, 0.0f, 2.0f);
}

void TrueSun::SaveSettings(json& o_json)
{
	o_json = settings;
}

void TrueSun::RestoreDefaultSettings()
{
	settings = {};
}
