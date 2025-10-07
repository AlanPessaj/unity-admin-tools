-- Unity Admin Tools - custom fonts (client-side)
-- This file registers fonts that use the "Circular Std Medium" family for
-- all addon UI elements. It does not change global game fonts.

if CLIENT then
    -- Helper to (re)create a font for the addon UI.
    local function CreateUATFont(name, size, weight)
        weight = weight or 500
        surface.CreateFont(name, {
            font = "Circular Std Medium",
            size = size,
            weight = weight,
            antialias = true,
            extended = true,
        })
    end

    -- Public function to ensure fonts exist. Call this before creating any UI that uses the fonts.
    function UAT_EnsureFonts()
        -- Recreate fonts unconditionally; CreateFont is cheap and idempotent for our use.
        CreateUATFont("UAT_Circular_13", 13, 500)
        CreateUATFont("UAT_Circular_14", 14, 600)
        CreateUATFont("UAT_Circular_16", 16, 600)
        CreateUATFont("UAT_Circular_20", 20, 600)
        CreateUATFont("UAT_Circular_24", 24, 600)
        CreateUATFont("UAT_Circular_32", 32, 700)
    end
    
    -- Optionally call once early (best-effort). UI modules will call UAT_EnsureFonts() again before use.
    timer.Simple(0.1, function()
        if UAT_EnsureFonts then UAT_EnsureFonts() end
    end)
end
