@tool
extends EditorPlugin


func _enter_tree() -> void:
	add_custom_type("DiffusionRenderer", "CanvasLayer",
		preload("diffusion_renderer.gd"), null)


func _exit_tree() -> void:
	remove_custom_type("DiffusionRenderer")
