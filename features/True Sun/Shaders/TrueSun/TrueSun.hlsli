#ifndef TRUE_SUN_HLSLI
#define TRUE_SUN_HLSLI

#include "Common/Color.hlsli"
#include "Common/SharedData.hlsli"

/**
 * True Sun: replaces the vanilla sun texture, a pale flat disk, with a procedural photosphere.
 * The disk is far brighter than the sky so it blooms and its core clips to white; its limb darkens
 * and warms like the real sun's; a forward-scattering aureole surrounds it; and the air between the
 * camera and the sun dims and reddens it toward the horizon. The weather's sun colour and visibility
 * still drive it, so weather mods and cloudy days keep working.
 */
namespace TrueSun
{
	/// Limb darkening exponents per channel, I(mu) = mu^a: the limb loses blue fastest, so the edge warms.
	static const float3 LimbExponent = float3(0.397, 0.503, 0.652);
	/// Optical depth of a clear atmosphere at the zenith per channel (Rayleigh plus light aerosol).
	static const float3 ZenithOpticalDepth = float3(0.05, 0.10, 0.21);
	/// Fraction of the quad radius where the aureole has faded out, so the quad's square never shows.
	static const float QuadFadeStart = 0.6;

	bool IsOn()
	{
		return SharedData::trueSunSettings.Enabled != 0;
	}

	/** @brief Relative air mass toward a direction (Rozenberg), 1 at the zenith and 40 at the horizon. */
	float AirMass(float elevationSin)
	{
		float cosZenith = max(elevationSin, 0.0);
		return rcp(cosZenith + 0.025 * exp(-11.0 * cosZenith));
	}

	/**
	 * @brief Colour and brightness the atmosphere leaves of sunlight seen toward a direction.
	 * Hue follows the physical transmittance; the dimming is compressed (square root) the way the eye
	 * adapts, so a setting sun stays a vivid orange-red instead of fading to near black.
	 */
	float3 Extinction(float3 viewDirection)
	{
		float reddening = SharedData::trueSunSettings.Reddening;
		if (reddening <= 0.0)
			return 1.0;
		float3 transmittance = exp(-ZenithOpticalDepth * AirMass(viewDirection.z) * reddening);
		float luminance = max(Color::RGBToLuminance(transmittance), 1e-4);
		return transmittance * rsqrt(luminance);
	}

	/**
	 * @brief Procedural sun for the vanilla sun quad.
	 * @param uv Quad texture coordinate, 0..1 with the sun centred.
	 * @param viewDirection World-space direction from the camera to this pixel.
	 * @return Emitted colour before the weather's sun colour multiplies it.
	 */
	float3 Shade(float2 uv, float3 viewDirection)
	{
		float2 p = uv * 2.0 - 1.0;
		float r = length(p);

		// The game's sun quad spans tens of degrees, and weather mods resize it, so the disk is sized in
		// degrees of sky: the quad faces the camera, so sky angle per quad unit is the ratio of the
		// view direction's and the quad coordinate's screen derivatives.
		float3 dirX = ddx(viewDirection);
		float3 dirY = ddy(viewDirection);
		float2 pX = ddx(p);
		float2 pY = ddy(p);
		float degreesPerUnit = sqrt((dot(dirX, dirX) + dot(dirY, dirY)) / max(dot(pX, pX) + dot(pY, pY), 1e-12)) * (180.0 / 3.14159265);
		float angle = r * degreesPerUnit;
		float angularRadius = 0.5 * SharedData::trueSunSettings.Size;

		// Antialiased disk edge, one pixel wide whatever the sun's size on screen
		float edgeWidth = max(fwidth(angle), 1e-5);
		float disk = saturate((angularRadius - angle) / edgeWidth + 0.5);

		float rho = saturate(angle / angularRadius);
		float mu = sqrt(max(1.0 - rho * rho, 0.0));
		float3 photosphere = pow(max(mu, 0.02), LimbExponent) * (disk * SharedData::trueSunSettings.Intensity);

		// Aureole: light scattered forward by haze, falling off with angular distance from the limb
		float outside = max(angle - angularRadius, 0.0);
		float aureole = SharedData::trueSunSettings.GlowIntensity * exp(-outside / max(SharedData::trueSunSettings.GlowSize, 0.05));
		aureole *= 1.0 - smoothstep(QuadFadeStart, 1.0, r);

		return (photosphere + aureole * (1.0 - disk)) * Extinction(viewDirection);
	}
}

#endif  // TRUE_SUN_HLSLI
