#pragma once

#include <dxgi.h>

namespace Hooks
{

	/** @brief Hook for BSShader::BeginTechnique that intercepts shader selection to substitute custom-compiled shaders from the shader cache. */
	struct BSShader_BeginTechnique
	{
		static bool thunk(RE::BSShader* shader, uint32_t vertexDescriptor, uint32_t pixelDescriptor, bool skipPixelShader);
		static inline REL::Relocation<decltype(thunk)> func;
	};

	/** @brief Hook for BSGraphics::SetDirtyStates that triggers per-draw feature updates after the engine applies its own state changes. */
	struct BSGraphics_SetDirtyStates
	{
		static void thunk(bool isCompute);
		static inline REL::Relocation<decltype(thunk)> func;
	};

	/** @brief Hook for BSBatchRenderer::RenderPassImmediately that intercepts individual render pass dispatch. */
	struct BSBatchRenderer_RenderPassImmediately1
	{
		static void thunk(RE::BSRenderPass* pass, uint32_t technique, bool alphaTest, uint32_t renderFlags);
		static inline REL::Relocation<decltype(thunk)> func;
	};

	/** @brief Installs all hooks, detours, and memory patches for the rendering pipeline, input handling, and shader management. */
	void Install();

	/** @brief Installs early IAT hooks for D3D11 device/swapchain creation and DXGI factory, before the game initializes Direct3D. */
	void InstallEarlyHooks();

	/**
	 * @brief Imnot Shaders: rewrites an exclusive-fullscreen swap chain request into a windowed one.
	 *
	 * Skyrim enters exclusive fullscreen through SetFullscreenState on its render thread, not the
	 * thread that owns the window. That transition can stall for seconds even in vanilla, and with
	 * Community Shaders loaded it intermittently never completes, leaving a frozen topmost window.
	 * A borderless window over the monitor avoids the transition entirely; with the flip model the
	 * swap chain already uses, Windows gives it independent flip, so frame pacing and latency match
	 * exclusive fullscreen. Call before the swap chain is created; pair with ApplyBorderlessWindow.
	 *
	 * @param a_desc Swap chain description the game passed in, modified in place.
	 * @return True when the request was exclusive fullscreen and has been rewritten.
	 */
	bool ReplaceExclusiveFullscreen(DXGI_SWAP_CHAIN_DESC& a_desc);

	/** @brief Makes the game window borderless over its monitor; a no-op unless ReplaceExclusiveFullscreen rewrote the request. */
	void ApplyBorderlessWindow();
}
