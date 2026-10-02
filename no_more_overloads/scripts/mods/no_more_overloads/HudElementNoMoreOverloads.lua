local mod = get_mod("no_more_overloads")

local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")

-- Draws the indicator from the mod._sc_* state.
local definitions = {
	scenegraph_definition = {
		screen = UIWorkspaceSettings.screen,
		nmo_area = {
			parent = "screen",
			size = { 900, 140 },
			vertical_alignment = "center",
			horizontal_alignment = "center",
			position = { 0, 0, 300 },
		},
	},
	widget_definitions = {
		indicator = UIWidget.create_definition({
			{
				pass_type = "text",
				value = "",
				value_id = "text",
				style_id = "text",
				style = {
					font_type = "machine_medium",
					font_size = 42,
					drop_shadow = true,
					text_vertical_alignment = "center",
					text_horizontal_alignment = "center",
					text_color = { 255, 255, 255, 255 },
					size = { 900, 140 },
					offset = { 0, 200, 0 },
				},
			},
		}, "nmo_area"),
	},
}

local HudElementNoMoreOverloads = class("HudElementNoMoreOverloads", "HudElementBase")

HudElementNoMoreOverloads.init = function (self, parent, draw_layer, start_scale)
	HudElementNoMoreOverloads.super.init(self, parent, draw_layer, start_scale, definitions)
end

HudElementNoMoreOverloads.update = function (self, dt, t, ui_renderer, render_settings, input_service)
	HudElementNoMoreOverloads.super.update(self, dt, t, ui_renderer, render_settings, input_service)

	local widget = self._widgets_by_name.indicator

	if mod._sc_visible and mod._sc_text then
		local style = widget.style.text
		widget.content.text = mod._sc_text
		widget.visible = true
		style.font_size = mod._sc_font_size
		style.offset[1] = mod._sc_offset_x
		style.offset[2] = mod._sc_offset_y

		local color = mod._sc_color
		if color then
			local tc = style.text_color
			tc[1], tc[2], tc[3], tc[4] = color[1], color[2], color[3], color[4]
		end
	else
		widget.content.text = ""
		widget.visible = false
	end
end

return HudElementNoMoreOverloads
