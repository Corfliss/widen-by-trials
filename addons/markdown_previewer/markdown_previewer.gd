@tool
extends EditorPlugin

const MD_EXTENSIONS := ["md", "markdown", "mdown", "mkd", "mdwn"]
const MENU_PREVIEW := 0
const MENU_EDIT := 1
const MENU_SPLIT := 2
const MODE_NONE := -1
const MODE_PREVIEW := 0
const MODE_EDIT := 1
const MODE_SPLIT := 2

const SETTING_DEFAULT_VIEW := "markdown_previewer/default_view"
const SETTING_REMEMBER_VIEW := "markdown_previewer/remember_view_per_file"
const SETTING_MAX_WIDTH := "markdown_previewer/max_content_width"
const SETTING_LIVE_PREVIEW := "markdown_previewer/live_preview"

const MarkdownPreview := preload("res://addons/markdown_previewer/markdown_preview.gd")
var preview_panel: Control

var markdown_menu: MenuButton
var menu_popup: PopupMenu
var menubar_popup: PopupMenu
var menu_host: Control = null
var used_toolbar_fallback := false
var _place_tries := 0
var _logged_placement := false

var active_code_edit: CodeEdit = null
var _watched_edit: CodeEdit = null
var _bound_code: CodeEdit = null
var current_path := ""
var current_mode := MODE_NONE
var file_state: Dictionary = {}
var split_container: HSplitContainer = null
var _code_flags_h := 0
var _code_flags_v := 0
var _path_tick := 0
var _applying_mode := false


func _enter_tree() -> void:
	_register_project_settings()
	if not ProjectSettings.settings_changed.is_connected(_on_project_settings_changed):
		ProjectSettings.settings_changed.connect(_on_project_settings_changed)

	set_process(true)
	set_process_unhandled_key_input(true)

	preview_panel = MarkdownPreview.new()
	preview_panel.name = "MarkdownPreviewOverlay"
	preview_panel.hide()
	_apply_preview_settings()

	markdown_menu = MenuButton.new()
	markdown_menu.name = "MarkdownMenu"
	markdown_menu.text = "Markdown"
	markdown_menu.flat = true
	markdown_menu.switch_on_hover = true
	markdown_menu.focus_mode = Control.FOCUS_NONE
	markdown_menu.tooltip_text = "Preview, edit, or split this Markdown file.\nAlt+M cycles views. Alt+Shift+M opens split view."
	markdown_menu.hide()

	menu_popup = markdown_menu.get_popup()
	_fill_popup(menu_popup)
	call_deferred("_try_place_menu")


func _exit_tree() -> void:
	if ProjectSettings.settings_changed.is_connected(_on_project_settings_changed):
		ProjectSettings.settings_changed.disconnect(_on_project_settings_changed)

	_teardown_view()
	_unbind_code_edit()
	_unplace_menu()

	if is_instance_valid(markdown_menu):
		markdown_menu.queue_free()
	markdown_menu = null
	menu_popup = null

	if is_instance_valid(preview_panel):
		if preview_panel.get_parent():
			preview_panel.get_parent().remove_child(preview_panel)
		preview_panel.queue_free()
		preview_panel = null


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	if key.keycode != KEY_M or not key.alt_pressed or key.ctrl_pressed or key.meta_pressed:
		return
	if not _is_script_editor_visible() or not _is_markdown_path(current_path):
		return
	if key.shift_pressed:
		_set_mode(MODE_SPLIT)
	else:
		_cycle_mode()
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not is_instance_valid(menu_host):
		_try_place_menu()
	_sync_with_script_editor()


#region Settings

func _register_project_settings() -> void:
	_add_project_setting(
		SETTING_DEFAULT_VIEW,
		MODE_PREVIEW,
		TYPE_INT,
		PROPERTY_HINT_ENUM,
		"Preview,Edit Markdown,Split View"
	)
	_add_project_setting(SETTING_REMEMBER_VIEW, true, TYPE_BOOL)
	_add_project_setting(
		SETTING_MAX_WIDTH,
		960,
		TYPE_INT,
		PROPERTY_HINT_RANGE,
		"0,1920,10"
	)
	_add_project_setting(SETTING_LIVE_PREVIEW, true, TYPE_BOOL)


func _add_project_setting(
	path: String,
	default_value: Variant,
	type: int,
	hint: int = PROPERTY_HINT_NONE,
	hint_string: String = ""
) -> void:
	if not ProjectSettings.has_setting(path):
		ProjectSettings.set_setting(path, default_value)
	ProjectSettings.set_initial_value(path, default_value)
	ProjectSettings.add_property_info({
		"name": path,
		"type": type,
		"hint": hint,
		"hint_string": hint_string,
	})
	ProjectSettings.set_as_basic(path, true)


func _get_setting(path: String, fallback: Variant) -> Variant:
	return ProjectSettings.get_setting(path, fallback)


func _default_mode() -> int:
	return clampi(int(_get_setting(SETTING_DEFAULT_VIEW, MODE_PREVIEW)), MODE_PREVIEW, MODE_SPLIT)


func _remember_view_per_file() -> bool:
	return bool(_get_setting(SETTING_REMEMBER_VIEW, true))


func _on_project_settings_changed() -> void:
	_apply_preview_settings()


func _apply_preview_settings() -> void:
	if not is_instance_valid(preview_panel):
		return
	preview_panel.set_max_content_width(float(_get_setting(SETTING_MAX_WIDTH, 960)))

#endregion


func _fill_popup(popup: PopupMenu) -> void:
	popup.clear()
	popup.add_radio_check_item("Preview", MENU_PREVIEW)
	popup.add_radio_check_item("Edit Markdown", MENU_EDIT)
	popup.add_radio_check_item("Split View", MENU_SPLIT)
	if not popup.id_pressed.is_connected(_on_menu_id_pressed):
		popup.id_pressed.connect(_on_menu_id_pressed)
	if not popup.about_to_popup.is_connected(_update_menu_checks):
		popup.about_to_popup.connect(_update_menu_checks)
	_update_menu_checks()


func _try_place_menu() -> void:
	if used_toolbar_fallback or not is_instance_valid(markdown_menu):
		return
	if is_instance_valid(menu_host) and markdown_menu.get_parent() == menu_host:
		return

	var se := EditorInterface.get_script_editor()
	if not is_instance_valid(se):
		return

	var vbox := _get_script_editor_vbox(se)
	if vbox and vbox.get_child_count() > 0:
		var first := vbox.get_child(0)
		if first is MenuBar:
			_place_on_menubar(first)
			return
		var hbox := _as_menu_hbox(first)
		if hbox == null:
			hbox = _find_hbox_with_menus(vbox)
		if hbox:
			_place_on_hbox(hbox)
			return

	_place_tries += 1
	if _place_tries > 120:
		if markdown_menu.get_parent():
			markdown_menu.get_parent().remove_child(markdown_menu)
		add_control_to_container(CONTAINER_TOOLBAR, markdown_menu)
		used_toolbar_fallback = true
		menu_host = markdown_menu.get_parent()


func _place_on_hbox(hbox: HBoxContainer) -> void:
	_strip_stale_markdown_menus(hbox)
	if markdown_menu.get_parent() != hbox:
		if markdown_menu.get_parent():
			markdown_menu.get_parent().remove_child(markdown_menu)
		hbox.add_child(markdown_menu)

	var last_mb := -1
	for i in hbox.get_child_count():
		var child := hbox.get_child(i)
		if child is MenuButton and child != markdown_menu:
			last_mb = i
			markdown_menu.flat = child.flat
			markdown_menu.switch_on_hover = child.switch_on_hover
			markdown_menu.focus_mode = child.focus_mode
			markdown_menu.theme_type_variation = child.theme_type_variation
	if last_mb >= 0:
		hbox.move_child(markdown_menu, last_mb + 1)

	menu_host = hbox
	menu_popup = markdown_menu.get_popup()
	_fill_popup(menu_popup)
	if not _logged_placement:
		_logged_placement = true


func _place_on_menubar(bar: MenuBar) -> void:
	if not is_instance_valid(menubar_popup):
		menubar_popup = PopupMenu.new()
		menubar_popup.name = "Markdown"
		_fill_popup(menubar_popup)
	if menubar_popup.get_parent() != bar:
		if menubar_popup.get_parent():
			menubar_popup.get_parent().remove_child(menubar_popup)
		bar.add_child(menubar_popup)
	menu_host = bar
	menu_popup = menubar_popup
	if is_instance_valid(markdown_menu):
		markdown_menu.hide()
	if not _logged_placement:
		_logged_placement = true


func _unplace_menu() -> void:
	if is_instance_valid(markdown_menu):
		if used_toolbar_fallback:
			remove_control_from_container(CONTAINER_TOOLBAR, markdown_menu)
			used_toolbar_fallback = false
		elif markdown_menu.get_parent():
			markdown_menu.get_parent().remove_child(markdown_menu)
	if is_instance_valid(menubar_popup):
		if menubar_popup.get_parent():
			menubar_popup.get_parent().remove_child(menubar_popup)
		menubar_popup.queue_free()
		menubar_popup = null
	menu_host = null


func _on_menu_id_pressed(id: int) -> void:
	match id:
		MENU_PREVIEW:
			_set_mode(MODE_PREVIEW)
		MENU_EDIT:
			_set_mode(MODE_EDIT)
		MENU_SPLIT:
			_set_mode(MODE_SPLIT)


func _cycle_mode() -> void:
	match current_mode:
		MODE_PREVIEW:
			_set_mode(MODE_EDIT)
		MODE_EDIT:
			_set_mode(MODE_SPLIT)
		MODE_SPLIT:
			_set_mode(MODE_PREVIEW)
		_:
			_set_mode(MODE_PREVIEW)


func _set_mode(mode: int) -> void:
	if not is_instance_valid(_get_current_code_edit()):
		return
	_state_for(current_path).mode = mode
	_apply_mode(mode)


func _update_menu_checks() -> void:
	if not is_instance_valid(menu_popup):
		return
	var preview_idx := menu_popup.get_item_index(MENU_PREVIEW)
	var edit_idx := menu_popup.get_item_index(MENU_EDIT)
	var split_idx := menu_popup.get_item_index(MENU_SPLIT)
	if preview_idx >= 0:
		menu_popup.set_item_checked(preview_idx, current_mode == MODE_PREVIEW)
	if edit_idx >= 0:
		menu_popup.set_item_checked(edit_idx, current_mode == MODE_EDIT)
	if split_idx >= 0:
		menu_popup.set_item_checked(split_idx, current_mode == MODE_SPLIT)


func _sync_with_script_editor() -> void:
	var se := EditorInterface.get_script_editor()
	var code_edit := _get_current_code_edit()
	var editor_visible := is_instance_valid(se) and se.is_visible_in_tree()

	var editor_changed := code_edit != _watched_edit
	if editor_changed:
		_watched_edit = code_edit
		current_path = _get_current_file_path() if code_edit else ""
		_path_tick = 0
	else:
		_path_tick += 1
		if _path_tick >= 45:
			_path_tick = 0
			var path := _get_current_file_path() if code_edit else ""
			if path != current_path:
				current_path = path
				editor_changed = true

	var is_md := editor_visible and _is_markdown_path(current_path)
	if is_instance_valid(markdown_menu):
		markdown_menu.visible = is_md and (menu_host is HBoxContainer or used_toolbar_fallback)
	if is_instance_valid(menubar_popup):
		menubar_popup.visible = is_md

	if not is_md or not is_instance_valid(code_edit):
		if current_mode != MODE_NONE:
			_teardown_view()
			_unbind_code_edit()
			active_code_edit = null
			current_mode = MODE_NONE
		return

	if editor_changed or code_edit != active_code_edit:
		_teardown_view()
		active_code_edit = code_edit
		_bind_code_edit(code_edit)
		var mode := _default_mode()
		if _remember_view_per_file():
			mode = int(_state_for(current_path).mode)
		_apply_mode(mode)
		return

	if current_mode == MODE_PREVIEW and is_instance_valid(code_edit) and code_edit.visible:
		code_edit.hide()
	if current_mode == MODE_SPLIT and not is_instance_valid(split_container):
		_apply_mode(MODE_SPLIT)


func _apply_mode(mode: int) -> void:
	if _applying_mode:
		return
	var code := _get_current_code_edit()
	if not is_instance_valid(code) or not is_instance_valid(preview_panel):
		return

	_applying_mode = true
	_exit_split()
	if preview_panel.get_parent():
		preview_panel.get_parent().remove_child(preview_panel)
	preview_panel.hide()
	preview_panel.set_compact(false)
	preview_panel.custom_minimum_size = Vector2.ZERO
	code.show()

	active_code_edit = code
	current_mode = mode
	_state_for(current_path).mode = mode

	match mode:
		MODE_EDIT:
			code.grab_focus()
		MODE_PREVIEW:
			_embed_preview_over(code)
			code.hide()
			preview_panel.grab_preview_focus()
		MODE_SPLIT:
			_enter_split(code)
			code.grab_focus()

	_refresh_preview()
	_update_menu_checks()
	_applying_mode = false


func _reset_container_layout(ctrl: Control) -> void:
	# Root preview scene uses uncontrolled / full-rect anchors. Those fight
	# HSplitContainer and VBoxContainer layout, so force container sizing.
	ctrl.set_anchors_preset(Control.PRESET_TOP_LEFT)
	ctrl.anchor_right = 0.0
	ctrl.anchor_bottom = 0.0
	ctrl.offset_left = 0.0
	ctrl.offset_top = 0.0
	ctrl.offset_right = 0.0
	ctrl.offset_bottom = 0.0
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctrl.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _embed_preview_over(code: CodeEdit) -> void:
	var host := code.get_parent()
	if host == null:
		return
	if preview_panel.get_parent() != host:
		if preview_panel.get_parent():
			preview_panel.get_parent().remove_child(preview_panel)
		host.add_child(preview_panel)
		host.move_child(preview_panel, code.get_index())
	_reset_container_layout(preview_panel)
	preview_panel.custom_minimum_size = Vector2.ZERO
	preview_panel.set_compact(false)
	preview_panel.show()


func _enter_split(code: CodeEdit) -> void:
	var host := code.get_parent()
	if host == null:
		return
	if preview_panel.get_parent():
		preview_panel.get_parent().remove_child(preview_panel)

	_code_flags_h = code.size_flags_horizontal
	_code_flags_v = code.size_flags_vertical

	var scale := EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
	var min_side := 120.0 * scale

	split_container = HSplitContainer.new()
	split_container.name = "MarkdownSplit"
	split_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_container.add_theme_constant_override("separation", maxi(6, int(round(8.0 * scale))))

	var idx := code.get_index()
	host.add_child(split_container)
	host.move_child(split_container, idx)
	host.remove_child(code)

	split_container.add_child(code)
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	code.show()

	_reset_container_layout(preview_panel)
	preview_panel.custom_minimum_size = Vector2(min_side, 0)
	split_container.add_child(preview_panel)
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_panel.set_compact(true)
	preview_panel.show()

	if not split_container.dragged.is_connected(_on_split_dragged):
		split_container.dragged.connect(_on_split_dragged)
	call_deferred("_apply_split_offset")


func _is_split_offset_from_center() -> bool:
	# Godot 4.4+ measures split_offset from the stretch-ratio position (center
	# when both sides expand equally). 4.2–4.3 add it to the first child's min size.
	var info := Engine.get_version_info()
	return int(info.get("major", 4)) > 4 or int(info.get("minor", 0)) >= 4


func _apply_split_offset() -> void:
	if not is_instance_valid(split_container):
		return
	if split_container.size.x < 16.0:
		if not split_container.resized.is_connected(_apply_split_offset):
			split_container.resized.connect(_apply_split_offset, CONNECT_ONE_SHOT)
		return

	var saved := int(_state_for(current_path).split)
	if saved >= 0:
		split_container.split_offset = saved
		return

	var total := split_container.size.x
	var first := split_container.get_child(0) as Control
	var first_min := first.get_combined_minimum_size().x if first else 0.0
	if _is_split_offset_from_center():
		split_container.split_offset = 0
	else:
		split_container.split_offset = int(total * 0.5 - first_min)


func _on_split_dragged(offset: int) -> void:
	_state_for(current_path).split = offset


func _exit_split() -> void:
	if not is_instance_valid(split_container):
		split_container = null
		return

	var host := split_container.get_parent()
	var idx := split_container.get_index()
	var code := active_code_edit

	if is_instance_valid(code) and code.get_parent() == split_container:
		split_container.remove_child(code)
	if is_instance_valid(preview_panel) and preview_panel.get_parent() == split_container:
		split_container.remove_child(preview_panel)

	if is_instance_valid(preview_panel):
		preview_panel.custom_minimum_size = Vector2.ZERO

	if is_instance_valid(host):
		host.remove_child(split_container)
		if is_instance_valid(code):
			host.add_child(code)
			host.move_child(code, clampi(idx, 0, host.get_child_count() - 1))
			code.size_flags_horizontal = _code_flags_h
			code.size_flags_vertical = _code_flags_v
			code.show()

	split_container.queue_free()
	split_container = null


func _teardown_view() -> void:
	if current_mode == MODE_SPLIT and is_instance_valid(split_container):
		_state_for(current_path).split = split_container.split_offset
	_exit_split()
	if is_instance_valid(preview_panel):
		if preview_panel.get_parent():
			preview_panel.get_parent().remove_child(preview_panel)
		preview_panel.hide()
		preview_panel.set_compact(false)
		preview_panel.custom_minimum_size = Vector2.ZERO
	if is_instance_valid(active_code_edit):
		active_code_edit.show()
	current_mode = MODE_NONE
	_update_menu_checks()


func _bind_code_edit(code: CodeEdit) -> void:
	_unbind_code_edit()
	_bound_code = code
	if is_instance_valid(code) and not code.text_changed.is_connected(_on_code_text_changed):
		code.text_changed.connect(_on_code_text_changed)


func _unbind_code_edit() -> void:
	if is_instance_valid(_bound_code) and _bound_code.text_changed.is_connected(_on_code_text_changed):
		_bound_code.text_changed.disconnect(_on_code_text_changed)
	_bound_code = null


func _on_code_text_changed() -> void:
	if not bool(_get_setting(SETTING_LIVE_PREVIEW, true)):
		return
	if current_mode == MODE_PREVIEW or current_mode == MODE_SPLIT:
		_refresh_preview()


func _refresh_preview() -> void:
	if not is_instance_valid(preview_panel) or not is_instance_valid(active_code_edit):
		return
	preview_panel.update_preview(active_code_edit.text, current_path)


func _state_for(path: String) -> Dictionary:
	var key := path if not path.is_empty() else "_none"
	if not file_state.has(key):
		file_state[key] = {"mode": _default_mode(), "split": -1}
	return file_state[key]


func _get_current_code_edit() -> CodeEdit:
	var se := EditorInterface.get_script_editor()
	if not is_instance_valid(se):
		return null
	var current := se.get_current_editor()
	if not is_instance_valid(current):
		return null
	if current.has_method("get_base_editor"):
		var base := current.get_base_editor()
		if base is CodeEdit:
			return base
	var nested := current.find_children("", "CodeEdit", true, false)
	return nested[0] if nested.size() > 0 else null


func _is_script_editor_visible() -> bool:
	var se := EditorInterface.get_script_editor()
	return is_instance_valid(se) and se.is_visible_in_tree()


func _is_markdown_path(path: String) -> bool:
	if path.is_empty():
		return false
	var file := path.get_file().to_lower().replace("(*)", "").replace("*", "").strip_edges()
	return file.get_extension() in MD_EXTENSIONS


func _get_current_file_path() -> String:
	var se := EditorInterface.get_script_editor()
	if not is_instance_valid(se):
		return ""

	var script := se.get_current_script()
	if script and not script.resource_path.is_empty():
		return script.resource_path

	var ed := se.get_current_editor()
	if is_instance_valid(ed):
		if ed.has_method("get_edited_resource"):
			var res: Variant = ed.get_edited_resource()
			if res is Resource and not String(res.resource_path).is_empty():
				return res.resource_path
		var ed_name := String(ed.name).replace("(*)", "").strip_edges()
		if _is_markdown_path(ed_name):
			return ed_name

	return _find_path_from_ui(se)


func _find_path_from_ui(se: Node) -> String:
	var lists := se.find_children("", "ItemList", true, false)
	for node in lists:
		var lst := node as ItemList
		if lst == null:
			continue
		var selected := lst.get_selected_items()
		if selected.is_empty():
			continue
		var tip := lst.get_item_tooltip(selected[0]).strip_edges()
		if _is_markdown_path(tip):
			return tip
		var text := lst.get_item_text(selected[0]).replace("(*)", "").replace("*", "").strip_edges()
		if _is_markdown_path(text):
			return text

	var vbox := _get_script_editor_vbox(se)
	if vbox:
		for child in vbox.get_children():
			if child is HBoxContainer:
				for sub in child.get_children():
					if sub is Label:
						var t: String = sub.text.replace("(*)", "").replace("*", "").strip_edges()
						if _is_markdown_path(t):
							return t
	return ""


func _as_menu_hbox(node: Node) -> HBoxContainer:
	if node is HBoxContainer and _count_menu_buttons(node) >= 2:
		return node
	if node is Control:
		for child in node.get_children():
			if child is HBoxContainer and _count_menu_buttons(child) >= 2:
				return child
	return null


func _find_hbox_with_menus(root: Node) -> HBoxContainer:
	if root is HBoxContainer and _count_menu_buttons(root) >= 2:
		return root
	for child in root.get_children():
		var found := _find_hbox_with_menus(child)
		if found:
			return found
	return null


func _count_menu_buttons(node: Node) -> int:
	var n := 0
	for child in node.get_children():
		if child is MenuButton:
			n += 1
	return n


func _strip_stale_markdown_menus(hbox: HBoxContainer) -> void:
	for child in hbox.get_children():
		if child is MenuButton and child != markdown_menu and child.text == "Markdown":
			hbox.remove_child(child)
			child.queue_free()


func _get_script_editor_vbox(se: Node) -> VBoxContainer:
	if se is VBoxContainer:
		return se
	for child in se.get_children():
		if child is VBoxContainer:
			return child
	var nested := se.find_children("", "VBoxContainer", true, false)
	return nested[0] if nested.size() > 0 else null
