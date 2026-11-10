#ifndef TRUE_CLOUDS_HLSLI
#define TRUE_CLOUDS_HLSLI

#include "Common/Color.hlsli"
#include "Common/SharedData.hlsli"

/**
 * True Clouds: light inside the game's cloud layers. The cloud texture's opacity stands in for
 * optical thickness: thin edges in front of the sun or moon get a forward-scattered silver lining,
 * thin cloud near the light glows through, thick cloud darkens toward its base, and lit edges take
 * the light's colour at sunrise and sunset. Settings come from the spare FeatureData slots.
 */
namespace TrueClouds
{
	/// First spare slot; must match TrueClouds::SpareSlot in src/Features/TrueClouds.h.
	static const uint SpareSlot = 4;

	/// Henyey-Greenstein asymmetry of cloud droplets: strongly forward scattering.
	static const float Anisotropy = 0.7;
	/// Scales the forward lobe (above isotropic) into silver lining light.
	static const float LiningScale = 0.02;
	/// Width of the glow through thin cloud around the light (cosine exponent).
	static const float GlowExponent = 64.0;
	/// Brightness of the glow through thin cloud at Sun Glow 1.
	static const float GlowScale = 0.35;
	/// Darkening of fully dense cloud at Depth 1.
	static const float MaxDarkening = 0.45;

	struct Settings
	{
		bool Enabled;
		float SilverLining;
		float SunGlow;
		float Depth;
		float SunTint;
		bool DebugView;
	};

	Settings GetSettings()
	{
		const float4 s0 = SharedData::SpareSlots[SpareSlot];
		const float4 s1 = SharedData::SpareSlots[SpareSlot + 1];
		Settings s;
		s.Enabled = asuint(s0.x) != 0;
		s.SilverLining = s0.y;
		s.SunGlow = s0.z;
		s.Depth = s0.w;
		s.SunTint = s1.x;
		s.DebugView = asuint(s1.y) != 0;
		return s;
	}

	bool IsOn()
	{
		return asuint(SharedData::SpareSlots[SpareSlot].x) != 0;
	}

	float Luma(float3 color)
	{
		return dot(color, float3(0.2126, 0.7152, 0.0722));
	}

	/// Henyey-Greenstein phase function, scaled so isotropic scattering is 1.
	float Phase(float cosTheta, float g)
	{
		const float g2 = g * g;
		return (1.0 - g2) / pow(max(1.0 + g2 - 2.0 * g * cosTheta, 1e-4), 1.5);
	}

	/**
	 * Lit cloud colour.
	 * @param color Vanilla cloud colour (vertex colour x texture + sky scale).
	 * @param density Cloud texture opacity, used as optical thickness, 0..1.
	 * @param viewDirection Normalized direction from the camera.
	 */
	float3 Shade(float3 color, float density, float3 viewDirection, Settings s)
	{
		// The directional light is the sun by day and the moon by night
		const float3 light = max(Color::DirectionalLight(SharedData::DirLightColor.xyz), 0.0);
		const float lightLuma = Luma(light);
		const float cosTheta = dot(viewDirection, SharedData::DirLightDirection.xyz);
		const float thin = 1.0 - density;
		// Partly transparent texels are cloud edges: the silver lining lives there
		const float edge = 4.0 * density * thin;

		// Thick cloud is darker, less so when looking toward the light, which it transmits
		const float towardLight = saturate(cosTheta);
		float3 shaded = color * (1.0 - MaxDarkening * s.Depth * density * (1.0 - 0.5 * towardLight));

		// Thin, lit parts take the light's hue: warm at sunrise and sunset
		const float3 lightHue = lightLuma > 1e-4 ? clamp(light / lightLuma, 0.0, 2.0) : 1.0.xxx;
		shaded *= lerp(1.0.xxx, lightHue, 0.5 * s.SunTint * thin);

		const float forward = max(Phase(cosTheta, Anisotropy) - 1.0, 0.0);
		const float glow = pow(towardLight, GlowExponent);
		shaded += light * (forward * edge * LiningScale * s.SilverLining + glow * thin * GlowScale * s.SunGlow);

		[flatten] if (s.DebugView)
			shaded = float3(edge, glow * thin, density);
		return shaded;
	}
}

#endif  // TRUE_CLOUDS_HLSLI
