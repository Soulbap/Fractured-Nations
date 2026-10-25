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

@export_group("Weapon hold (ASSET-INTEGRATION-01)")
## Weapon pieces only (slot "weapon", or a secondary weapon's held piece). The aiming eye in weapon space (Godot axes,
## origin at the pistol grip: x right, y up, z back): the sight line's x and height, and how far behind the grip the eye is
## when aiming. The default is the shared rifle hold (CHARACTER_STANDARD.md §3.1: sight line 0.172, eye relief 0.24); a
## weapon with another eye point is moved in the hands so its eye point lies where the rifle's does (InfantryGripIK) and
## first person lays its own sight line on the camera (Viewmodel).
@export var aim_eye := Vector3(0.0, 0.172, 0.24)
## Support-hand point in weapon space; ZERO = the asset's GRIP_Support marker. Set where the marker is a bipod hold
## (support hand on the butt) that does not suit a standing soldier.
@export var support_grip := Vector3.ZERO
## Extra shift of the weapon in the hands (weapon space), on top of the eye alignment.
@export var hold_shift := Vector3.ZERO
