## WorldConfig for a world generated from a geographic reference layout
## (WORLD-TERRAIN-01, tools/terrain_ref/generate.py).
##
## The relief, control map, colour map, vegetation maps, roads and water are produced
## offline from a layout JSON and stored in source_directory; ReferenceWorldBuilder
## imports them into the usual Terrain3D / vegetation chunk / Road Generator pipeline.
## The inherited procedural relief fields are unused. base_sites only mark the CORE demo
## spawn points (natural plateaus); nothing is flattened or built there, and main_road
## is a sample of the first primary road used by benchmarks and diagnostics.
@tool
class_name ReferenceWorldConfig
extends WorldConfig

## Output directory of tools/terrain_ref/generate.py (height.r32, control.r32,
## color.rgba8, vegetation.png, info.png, roads.json, water.json, sites.json).
@export_dir var source_directory := "res://worlds/ref_20km/source"
## Vegetation library with the WORLD-TERRAIN-01 Nordic assets.
@export_file("*.tres") var vegetation_library_path := "res://assets/environment/nordic_library.tres"
## Size of the generated maps in vertices per side (must match the layout's full_res).
@export var source_resolution := 10240


func create_builder() -> WorldBuilder:
	return ReferenceWorldBuilder.new()
