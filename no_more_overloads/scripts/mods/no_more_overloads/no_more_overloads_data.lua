local mod = get_mod("no_more_overloads")

-- Widget order is display order.
return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "group_blocking",
				type = "group",
				sub_widgets = {
					{
						setting_id = "blocking_type",
						type = "dropdown",
						default_value = "relaxed",
						options = {
							{ text = "opt_blocking_relaxed", value = "relaxed", show_widgets = { 1, 2, 3, 4, 5, 6 } },
							{ text = "opt_blocking_strict",  value = "strict",  show_widgets = { 1, 2, 3, 4, 5, 6 } },
						},
						sub_widgets = {
							{
								setting_id = "block_staffs",
								type = "checkbox",
								default_value = true,
							},
							{
								setting_id = "block_blitzes",
								type = "checkbox",
								default_value = true,
							},
							{
								setting_id = "block_force_swords",
								type = "checkbox",
								default_value = true,
							},
							{
								setting_id = "block_force_greatswords",
								type = "checkbox",
								default_value = true,
							},
							{
								setting_id = "block_duelling_swords",
								type = "checkbox",
								default_value = true,
							},
							{
								setting_id = "block_guns",
								type = "checkbox",
								default_value = true,
							},
						},
					},
					{
						setting_id = "block_plasma",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "block_crystalline",
						type = "checkbox",
						default_value = false,
					},
				},
			},
			{
				setting_id = "group_smart_triggers",
				type = "group",
				sub_widgets = {
					{
						setting_id = "auto_fire_before_unsafe",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "auto_quell",
						type = "checkbox",
						default_value = true,
						sub_widgets = {
							{
								setting_id = "auto_quell_trigger",
								type = "numeric",
								default_value = 100,
								range = { 0.1, 100 },
								decimals_number = 1,
							},
							{
								setting_id = "auto_quell_interrupt_offensive",
								type = "checkbox",
								default_value = true,
							},
							{
								setting_id = "auto_quell_interrupt_other",
								type = "checkbox",
								default_value = true,
							},
							{
								setting_id = "auto_quell_hold",
								type = "numeric",
								default_value = 0.3,
								range = { 0, 5 },
								decimals_number = 1,
							},
							{
								setting_id = "auto_quell_scriers",
								type = "checkbox",
								default_value = false,
							},
							{
								setting_id = "auto_quell_scriers_stacks",
								type = "numeric",
								default_value = 30,
								range = { 0, 30 },
								decimals_number = 0,
							},
						},
					},
					{
						setting_id = "auto_plasma_vent",
						type = "checkbox",
						default_value = true,
						sub_widgets = {
							{
								setting_id = "auto_plasma_vent_interrupt",
								type = "checkbox",
								default_value = true,
							},
							{
								setting_id = "auto_plasma_vent_hold",
								type = "numeric",
								default_value = 0.0,
								range = { 0, 5 },
								decimals_number = 1,
							},
						},
					},
					{
						setting_id = "auto_ability",
						type = "checkbox",
						default_value = true,
						sub_widgets = {
							{
								setting_id = "auto_use_scriers",
								type = "checkbox",
								default_value = true,
							},
							{
								setting_id = "auto_use_shriek",
								type = "checkbox",
								default_value = true,
							},
							{
								setting_id = "auto_use_wrath",
								type = "checkbox",
								default_value = true,
							},
							{
								setting_id = "when_to_use",
								type = "dropdown",
								default_value = "reactive",
								options = {
									{ text = "opt_when_reactive",  value = "reactive" },
									{ text = "opt_when_proactive", value = "proactive" },
								},
							},
							{
								setting_id = "min_peril",
								type = "numeric",
								default_value = 0,
								range = { 0, 100 },
								decimals_number = 0,
							},
							{
								setting_id = "recover_window",
								type = "numeric",
								default_value = 0.0,
								range = { 0, 3 },
								decimals_number = 1,
							},
						},
					},
				},
			},
			{
				setting_id = "group_indicator",
				type = "group",
				sub_widgets = {
					{
						setting_id = "show_unsafe",
						type = "checkbox",
						default_value = true,
						sub_widgets = {
							{
								setting_id = "unsafe_word",
								type = "dropdown",
								default_value = "default",
								options = {
									{ text = "opt_unsafe_default", value = "default" },
									{ text = "opt_word_blocked",   value = "BLOCKED" },
									{ text = "opt_word_danger",    value = "DANGER" },
									{ text = "opt_word_stop",      value = "STOP" },
									{ text = "opt_word_wait",      value = "WAIT" },
									{ text = "opt_word_hold",      value = "HOLD" },
									{ text = "opt_word_dontcast",  value = "DON'T CAST" },
								},
							},
							{ setting_id = "unsafe_r", type = "numeric", default_value = 235, range = { 0, 255 }, decimals_number = 0 },
							{ setting_id = "unsafe_g", type = "numeric", default_value = 45,  range = { 0, 255 }, decimals_number = 0 },
							{ setting_id = "unsafe_b", type = "numeric", default_value = 45,  range = { 0, 255 }, decimals_number = 0 },
						},
					},
					{
						setting_id = "show_safe",
						type = "checkbox",
						default_value = false,
						sub_widgets = {
							{
								setting_id = "safe_word",
								type = "dropdown",
								default_value = "default",
								options = {
									{ text = "opt_safe_default", value = "default" },
									{ text = "opt_word_go",      value = "GO" },
									{ text = "opt_word_ok",      value = "OK" },
									{ text = "opt_word_clear",   value = "CLEAR" },
									{ text = "opt_word_ready",   value = "READY" },
									{ text = "opt_word_cast",    value = "CAST" },
								},
							},
							{ setting_id = "safe_r", type = "numeric", default_value = 60,  range = { 0, 255 }, decimals_number = 0 },
							{ setting_id = "safe_g", type = "numeric", default_value = 220, range = { 0, 255 }, decimals_number = 0 },
							{ setting_id = "safe_b", type = "numeric", default_value = 70,  range = { 0, 255 }, decimals_number = 0 },
						},
					},
					{
						setting_id = "font_size",
						type = "numeric",
						default_value = 42,
						range = { 15, 90 },
						decimals_number = 0,
					},
					{
						setting_id = "pos_x",
						type = "numeric",
						default_value = 0,
						range = { -960, 960 },
						decimals_number = 0,
					},
					{
						setting_id = "pos_y",
						type = "numeric",
						default_value = 200,
						range = { -540, 540 },
						decimals_number = 0,
					},
				},
			},
		},
	},
}
