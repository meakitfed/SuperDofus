## Entry point of the headless game server run from the project (roadmap S.01):
##   godot --headless --path game -s res://src/server/main.gd -- --port=7777 --world=incarnam
## All the logic, and the list of options, is in ServerApp (server_app.gd): an exported server
## (X.01) ignores -s and runs the same node from scenes/server/server.tscn.
extends SceneTree


func _initialize() -> void:
	root.add_child(ServerApp.new())
