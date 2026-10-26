#ifndef VANILLA_ENHANCER_HLSLI
#define VANILLA_ENHANCER_HLSLI

#include "Common/SharedData.hlsli"

/**
 * Vanilla Enhancer: better shading for vanilla (non-PBR) materials from the textures they
 * already have. Every function returns its input unchanged while the feature is disabled.
 */
namespace VanillaEnhancer
{
	/// Shininess at which energy normalization leaves vanilla brightness unchanged.
	static const float ReferenceShininess = 30.0;
	/// Fresnel boost at a fully grazing angle when the Fresnel setting is 1.
	static const float MaxFresnelBoost = 4.0;

	/**
	 * Corrects a vanilla Blinn-Phong specular term.
	 *
	 * Energy: vanilla's lobe peaks at 1 whatever its shininess, so tight highlights are as dim as
	 * broad ones. Normalized Blinn-Phong scales with (s + 8); dividing by the reference keeps the
	 * average material at its authored brightness while glossy ones brighten and rough ones dim.
	 * Fresnel: Schlick's (1 - V.H)^5 term, applied as a boost so the authored value stays the
	 * normal-incidence reflectance. Horizon: vanilla omits N.L, which lets highlights appear on
	 * the side facing away from the light.
	 */
	float3 AdjustSpecular(float3 vanillaSpecular, float shininess, float3 N, float3 V, float3 L, float3 H)
	{
		const SharedData::VanillaEnhancerSettings settings = SharedData::vanillaEnhancerSettings;
		if (!settings.Enabled)
			return vanillaSpecular;

		const float energy = clamp((shininess + 8.0) / (ReferenceShininess + 8.0), 0.25, 4.0);
		float3 specular = vanillaSpecular * lerp(1.0, energy, settings.SpecularEnergy);

		const float fresnel = pow(1.0 - saturate(dot(V, H)), 5.0);
		specular *= 1.0 + settings.Fresnel * MaxFresnelBoost * fresnel;

		if (settings.HorizonFix)
			specular *= saturate(dot(N, L) * 4.0);

		return specular;
	}

	/**
	 * Occlusion implied by the normal map: where the mapped normal bends away from the surface,
	 * the texel sits in a groove or crack that sees less of the environment.
	 */
	float NormalMapOcclusion(float3 mappedNormal, float3 vertexNormal)
	{
		const SharedData::VanillaEnhancerSettings settings = SharedData::vanillaEnhancerSettings;
		if (!settings.Enabled)
			return 1.0;

		const float alignment = saturate(dot(normalize(mappedNormal), normalize(vertexNormal)));
		return lerp(1.0, alignment * alignment, settings.NormalOcclusion);
	}
}

#endif  // VANILLA_ENHANCER_HLSLI
