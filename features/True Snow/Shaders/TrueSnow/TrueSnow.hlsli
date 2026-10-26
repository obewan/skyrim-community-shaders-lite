#ifndef TRUE_SNOW_HLSLI
#define TRUE_SNOW_HLSLI

#include "Common/Math.hlsli"
#include "Common/Random.hlsli"
#include "Common/SharedData.hlsli"

/**
 * True Snow: snow shading for the fraction of a pixel the game marks as snow (landscape snow
 * layers, projected snow, snow objects), on vanilla and PBR materials alike. Every function is a
 * no-op while the feature is disabled or the snow mask is zero.
 */
namespace TrueSnow
{
	/// Fresh snow reflects 80-90% of light; the cap keeps it below clipped white.
	static const float MaxAlbedo = 0.9;
	/// How much of the texture's colour is kept: snow is near-neutral, but not grey.
	static const float Saturation = 0.4;
	/// Scattered light leaves snow bluish: red is absorbed most on the long paths through ice.
	static const float3 ScatterTint = float3(0.55, 0.75, 1.0);
	/// Fraction of world-space cells that hold a sparkling crystal.
	static const float SparkleCoverage = 0.35;
	/// Spread of crystal facet orientations around the surface normal.
	static const float FacetSpread = 0.9;
	/// Facet alignment exponent: higher gives smaller, sharper sparkles.
	static const float SparkleSharpness = 128.0;
	static const float SparkleGain = 120.0;
	/// Radius of a crystal inside its cell, as a fraction of the cell: glints are points, not squares.
	static const float CrystalRadius = 0.12;
	/// Back-lit transmission falloff around the direction toward the light.
	static const float TranslucencyFocus = 4.0;
	/// Blinn-Phong exponent of the melt-layer sheen: broad and soft next to the crystal glints.
	static const float WetShininess = 96.0;
	/// Reflectance of the thin water layer at normal incidence.
	static const float WetF0 = 0.02;

	bool IsOn()
	{
		return SharedData::trueSnowSettings.Enabled != 0;
	}

	/**
	 * How much a texture's average colour looks like snow: bright for the scene and nearly
	 * colourless. Meant for a whole texture (its smallest mip), not individual texels, whose grains
	 * and stones would fail one by one and leave the snow speckled.
	 */
	float LooksLikeSnow(float3 averageAlbedo)
	{
		const float luma = dot(averageAlbedo, float3(0.2126, 0.7152, 0.0722));
		const float maxChannel = max(max(averageAlbedo.r, averageAlbedo.g), averageAlbedo.b);
		const float saturation = (maxChannel - min(min(averageAlbedo.r, averageAlbedo.g), averageAlbedo.b)) / max(maxChannel, 1e-4);
		const float bright = smoothstep(0.06, 0.14, luma);
		const float neutral = 1 - smoothstep(0.08, 0.20, saturation);
		return bright * neutral;
	}

	/**
	 * Snow lies on flat to moderate slopes, rock dominates cliffs. `upness` is the geometric
	 * normal's up component, so normal-map detail does not break the mask up.
	 */
	float SlopeFactor(float upness)
	{
		return smoothstep(0.45, 0.75, upness);
	}

	/// Snow brightness reached at a Brightness setting of 1; the setting scales it, capped at MaxAlbedo.
	static const float TargetLuma = 0.45;
	/// How much of the texture's own brightness variation survives the lift (1 keeps all of it).
	static const float DetailKept = 0.15;

	/**
	 * Lifts the texture toward fresh-snow reflectance: partly desaturated, slightly cool, and raised
	 * toward a target brightness set by the Brightness setting. Vanilla snow is so grey that scaling
	 * alone stays grey; the soft power curve keeps part of the texture's detail.
	 */
	float3 AdjustAlbedo(float3 albedo, float snowMask)
	{
		if (!IsOn() || snowMask <= 0)
			return albedo;
		const float luma = max(dot(albedo, float3(0.2126, 0.7152, 0.0722)), 1e-3);
		const float3 neutral = lerp(luma.xxx, albedo, Saturation);
		const float target = min(TargetLuma * SharedData::trueSnowSettings.Brightness, MaxAlbedo);
		const float lift = pow(target / luma, 1 - DetailKept);
		const float3 snow = min(neutral * lift * float3(0.96, 0.98, 1.0), MaxAlbedo);
		return lerp(albedo, snow, snowMask);
	}

	/**
	 * Light scattered through the snowpack, added to the lighting path's own diffuse: wrapped
	 * lighting reaching past the shadow terminator (only the part beyond plain N.L), plus ice
	 * translucence, light transmitted through thin ridges and edges when the light is behind them.
	 * Both tinted blue. Multiply by the lighting path's own diffuse scale.
	 */
	float3 Scatter(float3 N, float3 V, float3 L, float3 lightColor, float softShadow, float snowMask)
	{
		const SharedData::TrueSnowSettings settings = SharedData::trueSnowSettings;
		if (!settings.Enabled || snowMask <= 0)
			return 0;
		const float NdotL = dot(N, L);
		const float wrap = settings.Subsurface;
		const float wrapped = saturate((NdotL + wrap) / (1 + wrap));
		const float wrapExtra = max(wrapped - saturate(NdotL), 0);

		// Looking toward the light, at surfaces seen edge-on: where the snow is thinnest to the eye
		const float towardLight = pow(saturate(dot(V, -L)), TranslucencyFocus);
		const float edge = 1 - saturate(dot(N, V));
		const float transmission = towardLight * edge * edge * settings.Translucency;

		return (wrapExtra + transmission) * ScatterTint * lightColor * softShadow * snowMask;
	}

	/**
	 * Sheen of a thin melt layer: a broad energy-normalized Blinn-Phong lobe with Schlick Fresnel
	 * for water, so it shows most at grazing angles. Added as specular, like the sparkles.
	 */
	float3 WetSheen(float3 N, float3 V, float3 L, float3 lightColor, float shadow, float snowMask)
	{
		const SharedData::TrueSnowSettings settings = SharedData::trueSnowSettings;
		const float NdotL = dot(N, L);
		if (!settings.Enabled || settings.Wetness <= 0 || snowMask <= 0 || NdotL <= 0)
			return 0;
		const float3 H = normalize(L + V);
		const float lobe = pow(saturate(dot(N, H)), WetShininess) * (WetShininess + 8) / (8 * Math::PI);
		const float fresnel = WetF0 + (1 - WetF0) * pow(1 - saturate(dot(V, H)), 5);
		return lobe * fresnel * NdotL * settings.Wetness * lightColor * shadow * snowMask;
	}

	/**
	 * Sun and moon glints from ice crystals. Each world-space cell may hold one crystal facet with a
	 * random orientation; it flashes when it reflects the light into the eye. Anchored in world
	 * space, so the pattern is stable without TAA and shifts as the viewer moves, like real snow.
	 * Cells smaller than a pixel fade out, which keeps distant snow from turning to noise.
	 */
	float3 Sparkle(float3 worldPosition, float3 N, float3 V, float3 L, float3 lightColor, float shadow, float snowMask)
	{
		const SharedData::TrueSnowSettings settings = SharedData::trueSnowSettings;
		if (!settings.Enabled || settings.SparkleIntensity <= 0 || snowMask <= 0 || dot(N, L) <= 0)
			return 0;

		const float3 position = worldPosition * settings.SparkleDensity;
		// Cells per pixel, from the pixel's true area: the geometric mean of its two axes. A plain
		// fwidth length is dominated by the axis stretched along the view at grazing angles, which
		// faded mid-range ground out far too early. A distant crystal stays visible as a pixel-sized
		// point, its brightness scaled by the area it really covers; only when several share a pixel
		// does it fade out.
		const float footprint = sqrt(length(ddx(position)) * length(ddy(position)));
		const float distanceFade = saturate(1.5 - footprint);
		if (distanceFade <= 0)
			return 0;
		const float crystalRadius = max(CrystalRadius, footprint * 0.5);
		const float areaScale = min(1, 1.5 * CrystalRadius / crystalRadius);

		const uint3 hash = Random::pcg3d(asuint(int3(floor(position))));
		const float3 random = float3(hash & 0xFFFF) / 65535.0;
		if (frac(random.z * 7.31) > SparkleCoverage)
			return 0;

		// One crystal per cell, at a random spot inside it, so the glint is a point
		const float3 crystalCenter = 0.2 + 0.6 * frac(random * float3(3.17, 5.71, 9.43));
		const float crystal = (1 - smoothstep(crystalRadius * 0.5, crystalRadius, length(frac(position) - crystalCenter))) * areaScale;
		if (crystal <= 0)
			return 0;

		const float3 facet = normalize(N + (random - 0.5) * FacetSpread);
		const float3 H = normalize(L + V);
		const float glint = pow(saturate(dot(facet, H)), SparkleSharpness);
		return glint * crystal * SparkleGain * settings.SparkleIntensity * lightColor * shadow * snowMask * distanceFade;
	}
}

#endif  // TRUE_SNOW_HLSLI
