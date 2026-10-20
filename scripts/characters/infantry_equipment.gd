## One interchangeable piece of infantry equipment (uniform part, vest, helmet, weapon...).
##
## A piece is a glTF scene exported by tools/blender/character/build_infantry.py containing
## <id>_LOD0/1/2 meshes. Skinned pieces are bound to the shared infantry skeleton by bone
## name; rigid pieces ride on an attachment bone (ATT_*) or on a mount node of another
## piece (attach = "<slot>:<node>", e.g. "weapon:ATT_Optic"). See docs/CHARACTER_STANDARD.md.
class_name InfantryEquipment
extends Resource

enum Mode { SKINNED, RIGID }

@export var id := ""
@export var scene: PackedScene
@export var mode := Mode.SKINNED
## Rigid pieces: skeleton attachment bone, or "<slot>:<mount node>" on another piece.
@export var attach := ""
## Logical slot (uniform, head, eyes, chest, belt, back, weapon, weapon_accessory).
@export var slot := ""
## Base-body regions this piece covers and therefore hides (Torso, Arms, Hands, Legs, Feet, Head).
@export var hides_body: PackedStringArray = []
