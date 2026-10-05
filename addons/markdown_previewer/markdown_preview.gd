@tool
extends Control

const PH_L := "\uFFF0"
const PH_R := "\uFFF1"
const BR_TOKEN := "\uFFF2"
const UL_BULLETS: Array[String] = ["•", "◦", "▪"]
const CodeBlockPanel := preload("res://addons/markdown_previewer/markdown_code_block.gd")
const ICON_CHECKBOX_UNCHECKED := "res://addons/markdown_previewer/icons/icon_checkbox_empty.svg"
const ICON_CHECKBOX_CHECKED := "res://addons/markdown_previewer/icons/icon_checkbox_checked.svg"

var margin_container: MarginContainer
var scroll_container: ScrollContainer
var content: VBoxContainer
var empty_hint: Label

var compact := false
var max_content_width := 960.0

var _source := ""
var _base_path := ""
var _regex_ready := false
var _ui_ready := false

var _code_bg := Color(0.12, 0.12, 0.12)
var _inline_code_bg := Color(0.16, 0.16, 0.16)
var _quote_bg := Color(0.14, 0.16, 0.2)
var _quote_bar_color: Color
var _quote_text_color: Color
var _table_border := Color(0.3, 0.3, 0.3)
var _table_header_bg := Color(0.16, 0.16, 0.16)
var _hr_color := Color(0.4, 0.4, 0.4)
var _muted_color := Color(0.6, 0.6, 0.6)
var _font_color := Color.WHITE
var _accent_color := Color(0.44, 0.62, 0.9)
var _code_border := Color(0.3, 0.3, 0.3)
var _header_sizes: Array[int] = [28, 22, 18, 16, 14, 13]
var _code_pad := 14
var _quote_pad := 12
var _cell_pad := 8
var _hr_height := 1
var _body_font_size := 14
var _mono_font: Font
var _mono_size := 14
var _code_radius := 6
var _copy_icon: Texture2D
var _ok_icon: Texture2D

var _md_pool: Array[RichTextLabel] = []
var _code_pool: Array[Control] = []

var _re_ul: RegEx
var _re_ol: RegEx
var _re_inline_code: RegEx
var _re_image: RegEx
var _re_link: RegEx
var _re_autolink: RegEx
var _re_bold_italic: RegEx
var _re_bold_star: RegEx
var _re_bold_under: RegEx
var _re_strike: RegEx
var _re_italic_star: RegEx
var _re_italic_under: RegEx
var _re_title: RegEx
var _title_map: Dictionary = {}
var _title_seq := 0
const META_SEP := "\u0001"


func _ready() -> void:
	if _is_edited_root():
		return
	_ensure_regex()
	_setup_ui()
	_apply_editor_theme()
	if Engine.is_editor_hint():
		var settings := EditorInterface.get_editor_settings()
		if not settings.settings_changed.is_connected(_on_editor_settings_changed):
			settings.settings_changed.connect(_on_editor_settings_changed)
	_render()


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		var settings := EditorInterface.get_editor_settings()
		if settings.settings_changed.is_connected(_on_editor_settings_changed):
			settings.settings_changed.disconnect(_on_editor_settings_changed)
	for rtl in _md_pool:
		if is_instance_valid(rtl):
			rtl.queue_free()
	for cb in _code_pool:
		if is_instance_valid(cb):
			cb.queue_free()
	_md_pool.clear()
	_code_pool.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		if _is_edited_root():
			_strip_for_save()
		return
	if not _ui_ready:
		return
	if what == NOTIFICATION_RESIZED:
		_update_content_width()
	elif what == NOTIFICATION_THEME_CHANGED:
		_apply_editor_theme()
		_render()


func _is_edited_root() -> bool:
	if not Engine.is_editor_hint():
		return false
	return EditorInterface.get_edited_scene_root() == self


func _strip_for_save() -> void:
	# If this scene is opened in the editor, never let runtime UI/fonts get packed.
	for child in get_children(true):
		remove_child(child)
		child.owner = null
		child.queue_free()
	_md_pool.clear()
	_code_pool.clear()
	_ui_ready = false


func _adopt(parent: Node, child: Node) -> void:
	if child.get_parent() == parent:
		return
	if child.get_parent():
		child.get_parent().remove_child(child)
	parent.add_child(child, false, Node.INTERNAL_MODE_BACK)
	child.owner = null


func update_preview(markdown_content: String, resource_path: String = "") -> void:
	_source = markdown_content
	_base_path = resource_path
	if _ui_ready:
		_render()


func set_compact(value: bool) -> void:
	compact = value
	if _ui_ready:
		_update_content_width()


func set_max_content_width(value: float) -> void:
	max_content_width = value
	if _ui_ready:
		_update_content_width()


func grab_preview_focus() -> void:
	if is_instance_valid(scroll_container):
		scroll_container.grab_focus()


func grab_focus_preview() -> void:
	grab_preview_focus()


func _setup_ui() -> void:
	if _ui_ready:
		return
	clip_contents = true

	margin_container = MarginContainer.new()
	margin_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	margin_container.grow_vertical = Control.GROW_DIRECTION_BOTH
	margin_container.add_theme_constant_override("margin_left", 16)
	margin_container.add_theme_constant_override("margin_top", 16)
	margin_container.add_theme_constant_override("margin_right", 16)
	margin_container.add_theme_constant_override("margin_bottom", 16)
	_adopt(self, margin_container)

	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.focus_mode = Control.FOCUS_ALL
	scroll_container.add_theme_constant_override("scrollbar_h_separation", 12)
	_adopt(margin_container, scroll_container)

	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_adopt(scroll_container, content)

	empty_hint = Label.new()
	empty_hint.visible = false
	empty_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	empty_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	empty_hint.grow_vertical = Control.GROW_DIRECTION_BOTH
	empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty_hint.text = "This Markdown file is empty.\n\nChoose Markdown → Edit Markdown to start writing.\nToggle views with Alt+M."
	_adopt(self, empty_hint)

	_ui_ready = true


func _on_editor_settings_changed() -> void:
	_apply_editor_theme()
	_render()


func _apply_editor_theme() -> void:
	if not Engine.is_editor_hint() or not _ui_ready:
		return
	var base := EditorInterface.get_base_control()
	if base == null:
		return

	
	var scale := EditorInterface.get_editor_scale()
	var ed_bg := _theme_color(base, "dark_color_2", Color(0.15, 0.15, 0.15))
	_font_color = _theme_color(base, "font_color", Color(0.9, 0.9, 0.9))
	_accent_color = _theme_color(base, "accent_color", Color(0.4, 0.6, 0.9))

	_code_bg = ed_bg.lerp(_font_color, 0.07)
	_inline_code_bg = ed_bg.lerp(_font_color, 0.12)
	_quote_bg = ed_bg.lerp(_font_color, 0.22)
	# Use the theme accent color (or a soft gray) for the vertical bar:
	_quote_bar_color = _accent_color.lerp(ed_bg, 0.2)
	# Soften the text color slightly relative to normal body text:
	_quote_text_color = _font_color.lerp(ed_bg, 0.18)
	_table_header_bg = ed_bg.lerp(_font_color, 0.1)
	_table_border = ed_bg.lerp(_font_color, 0.28)
	_code_border = ed_bg.lerp(_font_color, 0.32)
	_hr_color = ed_bg.lerp(_font_color, 0.35)
	_muted_color = _font_color.lerp(ed_bg, 0.45)

	_code_pad = int(round(14.0 * scale))
	_quote_pad = int(round(12.0 * scale))
	_cell_pad = int(round(8.0 * scale))
	_hr_height = maxi(1, int(round(1.0 * scale)))
	_code_radius = maxi(4, int(round(6.0 * scale)))

	var main_size := _theme_font_size(base, "doc_size")
	if main_size <= 0:
		main_size = _theme_font_size(base, "main_size")
	if main_size <= 0:
		main_size = 14
	_body_font_size = main_size
	_mono_size = _theme_font_size(base, "source_size")
	if _mono_size <= 0:
		_mono_size = main_size

	_header_sizes = [
		int(round(main_size * 2.0)),
		int(round(main_size * 1.6)),
		int(round(main_size * 1.35)),
		int(round(main_size * 1.18)),
		int(round(main_size * 1.08)),
		main_size,
	]

	_mono_font = _theme_font(base, "source")
	_copy_icon = base.get_theme_icon("ActionCopy", "EditorIcons")
	_ok_icon = base.get_theme_icon("StatusSuccess", "EditorIcons")
	if _ok_icon == null or _ok_icon.get_width() == 0:
		_ok_icon = base.get_theme_icon("ImportCheck", "EditorIcons")

	var normal_font := _theme_font(base, "doc")
	if normal_font == null:
		normal_font = _theme_font(base, "main")
	if normal_font:
		empty_hint.add_theme_font_override("font", normal_font)
	empty_hint.add_theme_font_size_override("font_size", main_size)
	empty_hint.add_theme_color_override("font_color", _muted_color)

	content.add_theme_constant_override("separation", int(round(14.0 * scale)))

	for rtl in _md_pool:
		if is_instance_valid(rtl):
			_apply_rtl_theme(rtl)
	for cb in _code_pool:
		if is_instance_valid(cb):
			_apply_code_theme(cb)
	_update_content_width()


func _theme_color(base: Control, name: String, fallback: Color) -> Color:
	if base.has_theme_color(name, "Editor"):
		return base.get_theme_color(name, "Editor")
	return fallback


func _theme_font(base: Control, name: String) -> Font:
	if base.has_theme_font(name, "EditorFonts"):
		return base.get_theme_font(name, "EditorFonts")
	return null


func _theme_font_size(base: Control, name: String) -> int:
	if base.has_theme_font_size(name, "EditorFonts"):
		return int(base.get_theme_font_size(name, "EditorFonts"))
	return 0


func _update_content_width() -> void:
	if not is_instance_valid(margin_container):
		return
	var scale := EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
	var edge := 18.0 * scale
	var v := 18.0 * scale
	var extra := 0.0
	if not compact and max_content_width > 0.0:
		var inner := size.x - edge * 2.0
		var max_w := max_content_width * scale
		if inner > max_w:
			extra = (inner - max_w) * 0.5
	var m := int(round(edge + extra))
	margin_container.add_theme_constant_override("margin_left", m)
	margin_container.add_theme_constant_override("margin_right", m)
	margin_container.add_theme_constant_override("margin_top", int(round(v)))
	margin_container.add_theme_constant_override("margin_bottom", int(round(v)))


func _configure_md_label(rtl: RichTextLabel) -> void:
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.selection_enabled = true
	rtl.context_menu_enabled = true
	rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rtl.focus_mode = Control.FOCUS_CLICK
	if not rtl.meta_clicked.is_connected(_on_meta_clicked):
		rtl.meta_clicked.connect(_on_meta_clicked)
	if not rtl.meta_hover_started.is_connected(_on_meta_hover_started):
		rtl.meta_hover_started.connect(_on_meta_hover_started.bind(rtl))
	if not rtl.meta_hover_ended.is_connected(_on_meta_hover_ended):
		rtl.meta_hover_ended.connect(_on_meta_hover_ended.bind(rtl))
	_apply_rtl_theme(rtl)


func _apply_rtl_theme(rtl: RichTextLabel) -> void:
	if not Engine.is_editor_hint():
		return
	var base := EditorInterface.get_base_control()
	if base == null:
		return
	var scale := EditorInterface.get_editor_scale()
	var normal_font := _theme_font(base, "doc")
	if normal_font == null:
		normal_font = _theme_font(base, "main")
	var bold_font := _theme_font(base, "doc_bold")
	if bold_font == null:
		bold_font = _theme_font(base, "bold")
	var italics_font := _theme_font(base, "doc_italic")
	if italics_font == null:
		italics_font = _theme_font(base, "main")
	if normal_font:
		rtl.add_theme_font_override("normal_font", normal_font)
	if bold_font:
		rtl.add_theme_font_override("bold_font", bold_font)
	if italics_font:
		rtl.add_theme_font_override("italics_font", italics_font)
	if _mono_font:
		rtl.add_theme_font_override("mono_font", _mono_font)
	rtl.add_theme_font_size_override("normal_font_size", _body_font_size)
	rtl.add_theme_font_size_override("bold_font_size", _body_font_size)
	rtl.add_theme_font_size_override("italics_font_size", _body_font_size)
	rtl.add_theme_font_size_override("mono_font_size", _mono_size)
	rtl.add_theme_color_override("default_color", _font_color)
	rtl.add_theme_constant_override("line_separation", int(round(6.0 * scale)))
	rtl.add_theme_constant_override("paragraph_separation", int(round(10.0 * scale)))
	rtl.add_theme_constant_override("table_h_separation", 0)
	rtl.add_theme_constant_override("table_v_separation", 0)
	var sb := StyleBoxEmpty.new()
	rtl.add_theme_stylebox_override("normal", sb)


func _apply_code_theme(cb: Control) -> void:
	if cb.has_method("apply_theme"):
		cb.call(
			"apply_theme",
			_code_bg,
			_code_border,
			_code_radius,
			_code_pad,
			_mono_font,
			_mono_size,
			_font_color,
			_muted_color,
			_copy_icon,
			_ok_icon
		)


func _render() -> void:
	if not is_instance_valid(content):
		return
	var is_empty := _source.strip_edges().is_empty()
	empty_hint.visible = is_empty
	content.visible = not is_empty
	if is_empty:
		_park_unused(0, 0)
		return
	_ensure_regex()
	_title_map.clear()
	_title_seq = 0
	_sync_blocks(_parse_to_blocks(_source))
	_update_content_width()


func _parse_to_blocks(markdown_text: String) -> Array[Dictionary]:
	var lines := markdown_text.replace("\r", "").split("\n")
	var blocks: Array[Dictionary] = []
	var md_lines := PackedStringArray()
	var i := 0
	while i < lines.size():
		var stripped := lines[i].strip_edges()
		if stripped.begins_with("```") or stripped.begins_with("~~~"):
			var bb := _parse_blocks("\n".join(md_lines))
			md_lines = PackedStringArray()
			if not bb.strip_edges().is_empty():
				blocks.append({"type": "md", "bbcode": bb})
			var extracted := _extract_fence(lines, i)
			i = int(extracted.next)
			blocks.append({"type": "code", "lang": extracted.lang, "code": extracted.code})
			continue
		md_lines.append(lines[i])
		i += 1
	var tail := _parse_blocks("\n".join(md_lines))
	if not tail.strip_edges().is_empty():
		blocks.append({"type": "md", "bbcode": tail})
	return blocks


func _extract_fence(lines: PackedStringArray, i: int) -> Dictionary:
	var stripped := lines[i].strip_edges()
	var fence_char := stripped[0]
	var fence_len := 0
	while fence_len < stripped.length() and stripped[fence_len] == fence_char:
		fence_len += 1
	var lang := stripped.substr(fence_len).strip_edges()
	i += 1
	var code_lines := PackedStringArray()
	while i < lines.size():
		var raw := lines[i]
		var st := raw.strip_edges()
		if st.length() >= fence_len and st.left(fence_len) == fence_char.repeat(fence_len):
			i += 1
			break
		code_lines.append(raw)
		i += 1
	return {"next": i, "lang": lang, "code": "\n".join(code_lines)}


func _sync_blocks(blocks: Array[Dictionary]) -> void:
	for child in content.get_children(true):
		content.remove_child(child)
		_adopt(self, child)
		child.hide()

	var md_i := 0
	var code_i := 0
	for block in blocks:
		if str(block.get("type", "")) == "code":
			var cb := _get_code_block(code_i)
			code_i += 1
			_adopt(content, cb)
			cb.call("set_block", str(block.get("code", "")), str(block.get("lang", "")))
			_apply_code_theme(cb)
			cb.show()
		else:
			var rtl := _get_md_label(md_i)
			md_i += 1
			_adopt(content, rtl)
			rtl.text = str(block.get("bbcode", ""))
			rtl.show()
	_park_unused(md_i, code_i)


func _get_md_label(idx: int) -> RichTextLabel:
	while _md_pool.size() <= idx:
		var rtl := RichTextLabel.new()
		_configure_md_label(rtl)
		_md_pool.append(rtl)
	return _md_pool[idx]


func _get_code_block(idx: int) -> Control:
	while _code_pool.size() <= idx:
		var cb: Control = CodeBlockPanel.new()
		_apply_code_theme(cb)
		_code_pool.append(cb)
	return _code_pool[idx]


func _park_unused(md_used: int, code_used: int) -> void:
	for i in range(md_used, _md_pool.size()):
		var rtl := _md_pool[i]
		_adopt(self, rtl)
		rtl.hide()
	for i in range(code_used, _code_pool.size()):
		var cb := _code_pool[i]
		_adopt(self, cb)
		cb.hide()


func _on_meta_hover_started(_meta: Variant, rtl: RichTextLabel) -> void:
	var parts := _split_meta(_meta)
	if not parts.url.is_empty():
		rtl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	rtl.tooltip_text = parts.title


func _on_meta_hover_ended(_meta: Variant, rtl: RichTextLabel) -> void:
	rtl.mouse_default_cursor_shape = Control.CURSOR_ARROW
	rtl.tooltip_text = ""


func _on_meta_clicked(meta: Variant) -> void:
	var parts := _split_meta(meta)
	var url = parts.url.strip_edges()
	if url.is_empty():
		return
	if url.begins_with("res://"):
		if Engine.is_editor_hint():
			if ResourceLoader.exists(url):
				var res := load(url)
				if res:
					EditorInterface.edit_resource(res)
			EditorInterface.select_file(url)
		return
	if url.begins_with("http://") or url.begins_with("https://") or url.begins_with("mailto:"):
		OS.shell_open(url)

#region Regex

func _ensure_regex() -> void:
	if _regex_ready:
		return
	_re_ul = _compile("^(\\s*)([*+-])\\s+(.*)$")
	_re_ol = _compile("^(\\s*)(\\d+)[.)]\\s+(.*)$")
	_re_inline_code = _compile("`([^`\\n]+)`")
	_re_image = _compile("!\\[([^\\]]*)\\]\\(([^)]+)\\)")
	_re_link = _compile("\\[([^\\]]+)\\]\\(([^)]+)\\)")
	_re_autolink = _compile("<(https?://[^>\\s]+)>")
	_re_bold_italic = _compile("\\*\\*\\*(.+?)\\*\\*\\*")
	_re_bold_star = _compile("\\*\\*(.+?)\\*\\*")
	_re_bold_under = _compile("__(.+?)__")
	_re_strike = _compile("~~(.+?)~~")
	_re_italic_star = _compile("(?<![*\\w])\\*(?!\\s)(.+?)(?<!\\s)\\*(?![*\\w])")
	_re_italic_under = _compile("(?<![_\\w])_(?!\\s)(.+?)(?<!\\s)_(?![_\\w])")
	_re_title = _compile("^(.*?)\\s+[\"']([^\"']*)[\"']\\s*$")
	_regex_ready = true


func _compile(pattern: String) -> RegEx:
	var regex := RegEx.new()
	regex.compile(pattern)
	return regex

#endregion

#region Parser

func _parse_blocks(markdown_text: String, hard_breaks: bool = false) -> String:
	var lines := markdown_text.split("\n")
	var output := PackedStringArray()
	var context: Array[Dictionary] = []
	var i := 0
	while i < lines.size():
		var line := lines[i]
		var stripped := line.strip_edges()

		if stripped.is_empty():
			_close_all_lists(output, context)
			i += 1
			continue

		if stripped.begins_with("```") or stripped.begins_with("~~~"):
			_close_all_lists(output, context)
			i = _consume_fence(lines, i, output)
			continue

		if _is_hr(stripped):
			_close_all_lists(output, context)
			output.append("[hr color=#%s height=%d width=100%%]" % [_hex(_hr_color), _hr_height])
			i += 1
			continue

		if _is_table_start(lines, i):
			_close_all_lists(output, context)
			i = _consume_table(lines, i, output)
			continue

		var heading_level := _heading_level(stripped)
		if heading_level > 0:
			_close_all_lists(output, context)
			output.append(_heading_bbcode(heading_level, stripped))
			i += 1
			continue

		if stripped.begins_with(">"):
			_close_all_lists(output, context)
			i = _consume_blockquote(lines, i, output)
			continue

		var ul_match := _re_ul.search(line)
		var ol_match := _re_ol.search(line)
		if ul_match or ol_match:
			i = _consume_list_item(lines, i, output, context, ul_match, ol_match)
			continue

		var indent := _get_indent_width(line)
		if not context.is_empty() and indent > int(context.back()["indent"]):
			if output.size() > 0:
				output[output.size() - 1] += "[br]" + _inline(stripped)
			i += 1
			continue

		_close_all_lists(output, context)
		i = _consume_paragraph(lines, i, output, hard_breaks)

	_close_all_lists(output, context)
	return "\n".join(output)


func _consume_fence(lines: PackedStringArray, i: int, output: PackedStringArray) -> int:
	var stripped := lines[i].strip_edges()
	var fence_char := stripped[0]
	var fence_len := 0
	while fence_len < stripped.length() and stripped[fence_len] == fence_char:
		fence_len += 1
	var lang := stripped.substr(fence_len).strip_edges()
	i += 1
	var code_lines := PackedStringArray()
	while i < lines.size():
		var raw := lines[i]
		var st := raw.strip_edges()
		if st.length() >= fence_len and st.left(fence_len) == fence_char.repeat(fence_len):
			i += 1
			break
		code_lines.append(_escape_bbcode(_preserve_code_indent(raw)))
		i += 1
	var header := ""
	if not lang.is_empty():
		header = "[color=#%s]%s[/color][br]" % [_hex(_muted_color), _escape_bbcode(lang)]
	var body := "[br]".join(code_lines)
	output.append(
		"[table=1][cell expand=1 bg=#%s border=#%s padding=%d,%d,%d,%d]%s[code]%s[/code][/cell][/table]"
		% [_hex(_code_bg), _hex(_code_border), _code_pad, _code_pad, _code_pad, _code_pad, header, body]
	)
	return i


func _preserve_code_indent(text: String) -> String:
	return text.replace("\t", "    ").replace(" ", "\u00A0")


func _consume_table(lines: PackedStringArray, i: int, output: PackedStringArray) -> int:
	var headers := _split_table_row(lines[i])
	i += 2
	var rows: Array[PackedStringArray] = []
	while i < lines.size() and lines[i].strip_edges().contains("|"):
		if _is_hr(lines[i].strip_edges()):
			break
		rows.append(_split_table_row(lines[i]))
		i += 1
	var cols := headers.size()
	if cols == 0:
		return i
	var out := "[table=%d]" % cols
	for header in headers:
		out += "[cell padding=%d,%d,%d,%d border=#%s bg=#%s][b]%s[/b][/cell]" % [
			_cell_pad, _cell_pad, _cell_pad, _cell_pad,
			_hex(_table_border), _hex(_table_header_bg), _inline(header)
		]
	for row in rows:
		for c in cols:
			var cell := row[c] if c < row.size() else ""
			out += "[cell padding=%d,%d,%d,%d border=#%s]%s[/cell]" % [
				_cell_pad, _cell_pad, _cell_pad, _cell_pad, _hex(_table_border), _inline(cell)
			]
	out += "[/table]"
	output.append(out)
	return i


func _consume_blockquote(lines: PackedStringArray, i: int, output: PackedStringArray) -> int:
	var inner_lines := PackedStringArray()
	while i < lines.size():
		var stripped := lines[i].strip_edges()
		if stripped.begins_with(">"):
			var inner := stripped.substr(1)
			if inner.begins_with(" "):
				inner = inner.substr(1)
			inner_lines.append(inner)
			i += 1
		elif stripped.is_empty() and i + 1 < lines.size() and lines[i + 1].strip_edges().begins_with(">"):
			inner_lines.append("")
			i += 1
		else:
			break

	var inner_bb := _parse_blocks("\n".join(inner_lines), true)
	var scale := EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
	
	var bar_pad := maxi(4, int(round(5.0 * scale)))
	var pad_v := int(round(12.0 * scale))
	var pad_right := int(round(16.0 * scale))
	var pad_left := int(round(14.0 * scale))

	# 2-column table forming the card:
	# - Col 1: Vibrant accent-colored left bar
	# - Col 2: Soft card container with generous padding and clean text
	output.append(
		"[table=2][cell expand=0 bg=#%s padding=3,%d,0,%d][font_size=1] [/font_size][/cell][cell expand=1 bg=#%s padding=%d,%d,%d,%d]%s[/cell][/table]"
		% [
			_hex(_accent_color),
			bar_pad, bar_pad,
			_hex(_quote_bg),
			pad_v, pad_right, pad_v, pad_left,
			inner_bb
		]
	)
	return i


func _consume_list_item(
	lines: PackedStringArray,
	i: int,
	output: PackedStringArray,
	context: Array[Dictionary],
	ul_match: RegExMatch,
	ol_match: RegExMatch
) -> int:
	var line := lines[i]
	var indent := _get_indent_width(line)
	var is_ul := ul_match != null
	var type := "ul" if is_ul else "ol"
	var item_text := (ul_match if is_ul else ol_match).get_string(3)

	while not context.is_empty() and indent < int(context.back()["indent"]):
		_close_one_list(output, context)

	if not context.is_empty() and indent == int(context.back()["indent"]) and str(context.back()["type"]) != type:
		context.back()["type"] = type

	var opened_nested := false
	if context.is_empty() or indent > int(context.back()["indent"]):
		var nested := not context.is_empty()
		context.append({"type": type, "indent": indent, "nested": nested})
		opened_nested = nested

	var depth := maxi(context.size() - 1, 0)
	var task := _parse_task(item_text)
	var marker: String
	var body: String
	if bool(task["is_task"]):
		marker = _checkbox_bbcode(bool(task["checked"]))
		body = _inline(str(task["text"]))
	elif type == "ul":
		marker = UL_BULLETS[depth % UL_BULLETS.size()]
		body = _inline(item_text)
	else:
		marker = ol_match.get_string(2) + "."
		body = _inline(item_text)

	var bb := "%s\u00A0%s" % [marker, body]
	if opened_nested:
		bb = "[indent]" + bb
	output.append(bb)
	return i + 1


func _consume_paragraph(
	lines: PackedStringArray,
	i: int,
	output: PackedStringArray,
	hard_breaks: bool = false
) -> int:
	var parts := PackedStringArray()
	while i < lines.size():
		var line := lines[i]
		var stripped := line.strip_edges()
		if stripped.is_empty():
			break
		if stripped.begins_with("```") or stripped.begins_with("~~~"):
			break
		if _is_hr(stripped) or _heading_level(stripped) > 0 or stripped.begins_with(">"):
			break
		if _re_ul.search(line) or _re_ol.search(line) or _is_table_start(lines, i):
			break
		if hard_breaks or line.ends_with("  "):
			parts.append(stripped + BR_TOKEN)
		else:
			parts.append(stripped)
		i += 1
	var joined := " ".join(parts).replace(BR_TOKEN + " ", BR_TOKEN)
	if joined.ends_with(BR_TOKEN):
		joined = joined.substr(0, joined.length() - BR_TOKEN.length())
	output.append("[p]%s[/p]" % _inline(joined).replace(BR_TOKEN, "[br]"))
	return i


func _close_all_lists(output: PackedStringArray, context: Array[Dictionary]) -> void:
	while not context.is_empty():
		_close_one_list(output, context)


func _close_one_list(output: PackedStringArray, context: Array[Dictionary]) -> void:
	var ctx: Dictionary = context.pop_back()
	if ctx.get("nested", false) and output.size() > 0:
		output[output.size() - 1] += "[/indent]"


func _heading_level(stripped: String) -> int:
	var level := 0
	while level < stripped.length() and stripped[level] == "#":
		level += 1
	if level < 1 or level > 6:
		return 0
	if level < stripped.length() and stripped[level] != " " and stripped[level] != "\t":
		return 0
	return level


func _heading_bbcode(level: int, stripped: String) -> String:
	var text := stripped.substr(level).strip_edges()
	while text.ends_with("#"):
		text = text.substr(0, text.length() - 1)
	text = text.strip_edges()
	var size := _header_sizes[level - 1]
	return "[p][b][font_size=%d]%s[/font_size][/b][/p]" % [size, _inline(text)]


func _is_hr(stripped: String) -> bool:
	var s := stripped.replace(" ", "").replace("\t", "")
	if s.length() < 3:
		return false
	var ch := s[0]
	if ch != "-" and ch != "*" and ch != "_":
		return false
	for c in s:
		if c != ch:
			return false
	return true


func _is_table_start(lines: PackedStringArray, i: int) -> bool:
	if i + 1 >= lines.size():
		return false
	var line := lines[i].strip_edges()
	if not line.contains("|"):
		return false
	return _is_table_separator(lines[i + 1].strip_edges())


func _is_table_separator(stripped: String) -> bool:
	var t := stripped.replace(" ", "").replace("\t", "")
	if t.length() < 3 or not t.contains("-"):
		return false
	for ch in t:
		if ch != "|" and ch != ":" and ch != "-":
			return false
	return true


func _split_table_row(line: String) -> PackedStringArray:
	var s := line.strip_edges()
	if s.begins_with("|"):
		s = s.substr(1)
	if s.ends_with("|"):
		s = s.substr(0, s.length() - 1)
	var cells := PackedStringArray()
	for cell in s.split("|", true):
		cells.append(cell.strip_edges())
	return cells


func _parse_task(text: String) -> Dictionary:
	var t := text.strip_edges()
	if t.begins_with("[ ]"):
		return {"is_task": true, "checked": false, "text": t.substr(3).strip_edges()}
	if t.begins_with("[x]") or t.begins_with("[X]"):
		return {"is_task": true, "checked": true, "text": t.substr(3).strip_edges()}
	return {"is_task": false, "checked": false, "text": text}


func _checkbox_bbcode(checked: bool) -> String:
	var path := ICON_CHECKBOX_CHECKED if checked else ICON_CHECKBOX_UNCHECKED
	var color := _accent_color if checked else _font_color
	var icon_size := int(round(_body_font_size * 1.05))
	
	return "[img height=%d color=#%s]%s[/img]" % [icon_size, _hex(color), path]


func _get_indent_width(line: String, tab_width: int = 4) -> int:
	var width := 0
	for ch in line:
		if ch == " ":
			width += 1
		elif ch == "\t":
			width += tab_width - (width % tab_width)
		else:
			break
	return width

#endregion

#region Inline

func _inline(text: String) -> String:
	if text.is_empty():
		return ""
	var ph: Array[String] = []
	var s := text
	s = _replace_all(_re_inline_code, s, func(m: RegExMatch) -> String:
		var code := _escape_bbcode(m.get_string(1))
		return _stash(ph, "[bgcolor=#%s][code]%s[/code][/bgcolor]" % [_hex(_inline_code_bg), code])
	)
	s = _replace_all(_re_image, s, func(m: RegExMatch) -> String:
		return _stash(ph, _image_bbcode(m.get_string(1), m.get_string(2)))
	)
	s = _replace_all(_re_link, s, func(m: RegExMatch) -> String:
		var label := _emphasis(m.get_string(1), ph)
		label = _escape_bbcode(label)
		label = _restore(label, ph)
		var link_parts := _split_url_title(m.get_string(2))
		var link_url := _sanitize_url(link_parts.url)
		return _stash(ph, "[url=%s]%s[/url]" % [_meta_with_title(link_url, link_parts.title), label])
	)
	s = _replace_all(_re_autolink, s, func(m: RegExMatch) -> String:
		var url := _sanitize_url(m.get_string(1))
		return _stash(ph, "[url=%s]%s[/url]" % [url, _escape_bbcode(url)])
	)
	s = _emphasis(s, ph)
	s = _escape_bbcode(s)
	s = _restore(s, ph)
	return s


func _emphasis(text: String, ph: Array[String]) -> String:
	var s := text
	s = _replace_all(_re_bold_italic, s, func(m: RegExMatch) -> String:
		return _stash(ph, "[b][i]%s[/i][/b]" % _escape_bbcode(m.get_string(1)))
	)
	s = _replace_all(_re_bold_star, s, func(m: RegExMatch) -> String:
		return _stash(ph, "[b]%s[/b]" % _escape_bbcode(m.get_string(1)))
	)
	s = _replace_all(_re_bold_under, s, func(m: RegExMatch) -> String:
		return _stash(ph, "[b]%s[/b]" % _escape_bbcode(m.get_string(1)))
	)
	s = _replace_all(_re_strike, s, func(m: RegExMatch) -> String:
		return _stash(ph, "[s]%s[/s]" % _escape_bbcode(m.get_string(1)))
	)
	s = _replace_all(_re_italic_star, s, func(m: RegExMatch) -> String:
		return _stash(ph, "[i]%s[/i]" % _escape_bbcode(m.get_string(1)))
	)
	s = _replace_all(_re_italic_under, s, func(m: RegExMatch) -> String:
		return _stash(ph, "[i]%s[/i]" % _escape_bbcode(m.get_string(1)))
	)
	return s


func _image_bbcode(alt: String, dest: String) -> String:
	var parts := _split_url_title(dest)
	var url := _sanitize_url(parts.url)
	var title = parts.title
	if url.begins_with("http://") or url.begins_with("https://"):
		var label := alt if not alt.is_empty() else url
		return "[url=%s]%s[/url]" % [_meta_with_title(url, title), _escape_bbcode(label)]
	var path := _resolve_local_path(url)
	if path.is_empty():
		return _escape_bbcode(alt if not alt.is_empty() else dest)
	if title.is_empty():
		return "[img]%s[/img]" % path
	return "[url=%s][img]%s[/img][/url]" % [_meta_with_title("", title), path]


func _resolve_local_path(url: String) -> String:
	if url.begins_with("res://") or url.begins_with("user://"):
		return url
	if url.begins_with("file://"):
		return url
	var base_dir := _base_path.get_base_dir() if not _base_path.is_empty() else "res://"
	if url.begins_with("/"):
		return "res:/" + url
	return base_dir.path_join(url).simplify_path()


func _split_url_title(raw: String) -> Dictionary:
	var s := raw.strip_edges()
	var m := _re_title.search(s)
	if m:
		return {"url": m.get_string(1).strip_edges(), "title": m.get_string(2)}
	return {"url": s, "title": ""}


func _meta_with_title(url: String, title: String) -> String:
	if title.is_empty():
		return url
	_title_seq += 1
	_title_map[_title_seq] = title
	return url + META_SEP + str(_title_seq)


func _split_meta(meta: Variant) -> Dictionary:
	var s := str(meta)
	var idx := s.find(META_SEP)
	if idx == -1:
		return {"url": s, "title": ""}
	var id_str := s.substr(idx + 1)
	var title := ""
	if id_str.is_valid_int() and _title_map.has(int(id_str)):
		title = str(_title_map[int(id_str)])
	return {"url": s.substr(0, idx), "title": title}


func _sanitize_url(raw: String) -> String:
	var url := raw.strip_edges()
	if url.begins_with("<") and url.ends_with(">"):
		url = url.substr(1, url.length() - 2)
	if url.contains(" "):
		url = url.split(" ")[0]
	return url.replace("[", "%5B").replace("]", "%5D")


func _stash(ph: Array[String], bbcode: String) -> String:
	ph.append(bbcode)
	return "%s%d%s" % [PH_L, ph.size() - 1, PH_R]


func _restore(text: String, ph: Array[String]) -> String:
	var s := text
	for i in range(ph.size() - 1, -1, -1):
		s = s.replace("%s%d%s" % [PH_L, i, PH_R], ph[i])
	return s


func _replace_all(regex: RegEx, text: String, handler: Callable) -> String:
	if regex == null or text.is_empty():
		return text
	var out := ""
	var pos := 0
	var m := regex.search(text, pos)
	while m:
		out += text.substr(pos, m.get_start() - pos)
		out += str(handler.call(m))
		var end := m.get_end()
		pos = end if end > pos else pos + 1
		m = regex.search(text, pos)
	out += text.substr(pos)
	return out


func _escape_bbcode(text: String) -> String:
	return text.replace("[", "\u0001").replace("]", "\u0002").replace("\u0001", "[lb]").replace("\u0002", "[rb]")


func _hex(color: Color) -> String:
	return color.to_html(false)

#endregion
