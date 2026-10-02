return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`no_more_overloads` encountered an error loading the Darktide Mod Framework.")

		new_mod("no_more_overloads", {
			mod_script       = "no_more_overloads/scripts/mods/no_more_overloads/no_more_overloads",
			mod_data         = "no_more_overloads/scripts/mods/no_more_overloads/no_more_overloads_data",
			mod_localization = "no_more_overloads/scripts/mods/no_more_overloads/no_more_overloads_localization",
		})
	end,
	packages = {},
}
