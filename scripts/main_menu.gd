extends Control

@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel


func _ready() -> void:
	status_label.text = "Valkommen! Välj ett läge."


func _on_start_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_3d.tscn")


func _on_options_button_pressed() -> void:
	status_label.text = "Options kommer snart (ljud, kamera, controls)."


func _on_multiplayer_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/horror_room.tscn")


func _on_quit_button_pressed() -> void:
	get_tree().quit()
