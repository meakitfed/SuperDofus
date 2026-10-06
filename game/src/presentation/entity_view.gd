## Presentation of a GameEntity: owns a DofusSprite, follows the entity's position,
## maps its states to animations (AnimMap) and forwards animation labels back to
## gameplay as `visual_event` (e.g. the exact frame an attack lands).
class_name EntityView
extends Node2D

signal visual_event(entity: GameEntity, label: String)

@export var anim_map: AnimMap

var entity: GameEntity
var sprite: DofusSprite


func bind(p_entity: GameEntity) -> void:
	entity = p_entity
	if anim_map == null:
		anim_map = load("res://src/presentation/default_anim_map.tres")
	sprite = DofusSprite.new()
	add_child(sprite)
	sprite.look_string = entity.look
	sprite.preload_animations(PackedStringArray(anim_map.bases.values()))
	sprite.label_reached.connect(func(label: String, _anim: String) -> void: visual_event.emit(entity, label))
	sprite.animation_finished.connect(_on_animation_finished)
	entity.state_changed.connect(_on_state_changed)
	_sync_position()
	_on_state_changed(entity.state, entity.facing)


func _process(_delta: float) -> void:
	if entity != null:
		_sync_position()


func _sync_position() -> void:
	position = IsoGrid.cell_to_world(entity.position)


func _on_state_changed(state: GameEntity.State, facing: GameEntity.Facing) -> void:
	# GameEntity.Facing uses the same clockwise-from-east numbering as DofusAnimNames.Direction
	var ok := sprite.play_animation(anim_map.base_for(state), int(facing), not anim_map.is_one_shot(state))
	if not ok and anim_map.is_one_shot(state):
		entity.action_done()


func _on_animation_finished(_anim: String) -> void:
	if entity != null and anim_map.is_one_shot(entity.state) and entity.state != GameEntity.State.DIE:
		entity.action_done()
