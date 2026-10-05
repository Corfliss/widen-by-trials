@tool
extends Control

var source_code := ""

var _style: StyleBoxFlat
var _body: RichTextLabel
var _overlay: HBoxContainer
var _lang_label: Label
var _copy_btn: Button
var _copy_icon: Texture2D
var _ok_icon: Texture2D
var _copy_seq := 0


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_style = StyleBoxFlat.new()
	_style.anti_aliasing = true

	_body = RichTextLabel.new()
	_body.bbcode_enabled = false
	_body.fit_content = true
	_body.scroll_active = false
	_body.selection_enabled = true
	_body.context_menu_enabled = true
	_body.autowrap_mode = TextServer.AUTOWRAP_OFF
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.focus_mode = Control.FOCUS_CLICK
	_body.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_body)

	_overlay = HBoxContainer.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_theme_constant_override("separation", 4)
	add_child(_overlay)

	_lang_label = Label.new()
	_lang_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lang_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_lang_label)
	_lang_label.position = Vector2(10, 10)
	_lang_label.size = Vector2(200, 40)

	_copy_btn = Button.new()
	_copy_btn.flat = true
	_copy_btn.focus_mode = Control.FOCUS_NONE
	_copy_btn.tooltip_text = "Copy code"
	_copy_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_copy_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_copy_btn.pressed.connect(_on_copy_pressed)
	_overlay.add_child(_copy_btn)


func _ready() -> void:
	if not _body.minimum_size_changed.is_connected(_on_body_min_size_changed):
		_body.minimum_size_changed.connect(_on_body_min_size_changed)
	_layout_children()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAW and _style:
		draw_style_box(_style, Rect2(Vector2.ZERO, size))
	elif what == NOTIFICATION_RESIZED:
		_layout_children()


func _get_minimum_size() -> Vector2:
	if not is_instance_valid(_body) or _style == null:
		return Vector2.ZERO
	var ms := _body.get_combined_minimum_size()
	var top_extra := _header_extra_height()
	return Vector2(
		ms.x + _style.content_margin_left + _style.content_margin_right,
		ms.y + _style.content_margin_top + _style.content_margin_bottom + top_extra
	)


func set_block(code: String, lang: String) -> void:
	source_code = code
	_lang_label.text = lang
	_lang_label.visible = not lang.is_empty()
	_body.text = code.replace("\t", "    ").replace(" ", "\u00A0")
	update_minimum_size()
	queue_redraw()
	call_deferred("_layout_children")


func apply_theme(
	bg: Color,
	border: Color,
	radius: int,
	pad: int,
	mono: Font,
	mono_size: int,
	text_color: Color,
	muted: Color,
	copy_icon: Texture2D,
	ok_icon: Texture2D
) -> void:
	_style.bg_color = bg
	_style.border_color = border
	_style.set_border_width_all(1)
	_style.set_corner_radius_all(radius)
	_style.content_margin_left = pad
	_style.content_margin_right = pad
	_style.content_margin_top = pad
	_style.content_margin_bottom = pad

	_lang_label.add_theme_color_override("font_color", muted)
	_lang_label.add_theme_font_size_override("font_size", maxi(10, mono_size - 1))
	if mono:
		_lang_label.add_theme_font_override("font", mono)
		_body.add_theme_font_override("normal_font", mono)
	_body.add_theme_font_size_override("normal_font_size", mono_size)
	_body.add_theme_color_override("default_color", text_color)
	_body.add_theme_constant_override("line_separation", 3)

	var empty := StyleBoxEmpty.new()
	_body.add_theme_stylebox_override("normal", empty)
	_body.add_theme_stylebox_override("focus", empty)

	var chip := StyleBoxFlat.new()
	chip.bg_color = bg.lerp(text_color, 0.06)
	chip.border_color = border
	chip.set_border_width_all(1)
	chip.set_corner_radius_all(maxi(2, radius - 2))
	chip.content_margin_left = 5
	chip.content_margin_right = 5
	chip.content_margin_top = 3
	chip.content_margin_bottom = 3
	var chip_hover := chip.duplicate()
	chip_hover.bg_color = bg.lerp(text_color, 0.16)
	_copy_btn.add_theme_stylebox_override("normal", chip)
	_copy_btn.add_theme_stylebox_override("hover", chip_hover)
	_copy_btn.add_theme_stylebox_override("pressed", chip_hover)
	_copy_btn.add_theme_stylebox_override("focus", chip)

	_copy_icon = copy_icon
	_ok_icon = ok_icon
	_copy_btn.icon = copy_icon
	_copy_btn.visible = copy_icon != null
	if copy_icon:
		var sz := maxi(copy_icon.get_width(), copy_icon.get_height())
		_copy_btn.custom_minimum_size = Vector2(sz + 8, sz + 6)

	update_minimum_size()
	queue_redraw()
	call_deferred("_layout_children")


func _on_body_min_size_changed() -> void:
	update_minimum_size()
	_layout_children()


func _layout_children() -> void:
	if not is_instance_valid(_body) or not is_instance_valid(_overlay) or _style == null:
		return
	var l := _style.content_margin_left
	var t := _style.content_margin_top
	var r := _style.content_margin_right
	var b := _style.content_margin_bottom
	var top_extra := _header_extra_height()

	_body.position = Vector2(l, t + top_extra)
	_body.size = Vector2(maxf(0.0, size.x - l - r), maxf(0.0, size.y - t - b - top_extra))

	var inset := 4.0
	var ov := _overlay.get_combined_minimum_size()
	_overlay.size = ov
	_overlay.position = Vector2(size.x - ov.x - inset, inset)


func _header_extra_height() -> float:
	if not _lang_label.visible:
		return 0.0
	var ov := _overlay.get_combined_minimum_size()
	return ov.y + 6.0


func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(source_code)
	_copy_seq += 1
	var seq := _copy_seq
	if _ok_icon:
		_copy_btn.icon = _ok_icon
	_copy_btn.tooltip_text = "Copied!"
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(1.2).timeout
	if seq != _copy_seq or not is_instance_valid(_copy_btn):
		return
	_copy_btn.icon = _copy_icon
	_copy_btn.tooltip_text = "Copy code"
