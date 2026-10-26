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

	/// Extra mip bias of the blurred sample whose difference from the regular one is the detail.
	static const float SharpenMipOffset = 1.5;
	/// Mip level at which sharpening has fully faded out: minified textures would only shimmer.
	static const float SharpenFadeLod = 3.0;
	/// Detail gain at a Texture Sharpening setting of 1.
	static const float SharpenMaxGain = 1.5;
	/// Soft-knee scale: detail well below 1/SharpenKnee passes linearly, strong contrast is compressed.
	static const float SharpenKnee = 4.0;

	bool IsTextureSharpeningOn()
	{
		const SharedData::VanillaEnhancerSettings settings = SharedData::vanillaEnhancerSettings;
		return settings.Enabled && settings.TextureSharpening > 0.0;
	}

	/**
	 * Unsharp mask in texture space: the detail is the difference between the regular sample and
	 * one taken SharpenMipOffset mips blurrier. Working on the texture rather than the screen makes
	 * it perspective-correct and unable to halo at silhouettes, the two things a screen-space
	 * sharpener has to work around. Luma-only, so red and blue detail does not speckle; a log knee
	 * keeps strong contrast from crunching. `lod` is the texture's own mip level, which fades the
	 * effect out where the texture is minified and sharpening would only add shimmer under TAA.
	 */
	float3 SharpenTexture(float3 color, float3 blurred, float lod)
	{
		const float detail = dot(color - blurred, float3(0.2126, 0.7152, 0.0722));
		const float kneed = sign(detail) * log(abs(detail) * SharpenKnee + 1.0) / SharpenKnee;
		const float fade = saturate(1.0 - lod / SharpenFadeLod);
		return max(color + kneed * SharedData::vanillaEnhancerSettings.TextureSharpening * SharpenMaxGain * fade, 0.0);
	}
}

#endif  // VANILLA_ENHANCER_HLSLI
