class_name BoardSurfaces
extends RefCounted

## Authored surface textures for the isometric board.
##
## The board used to be flat-shaded boxes: one albedo colour per material and
## nothing else, so a concrete barrier and a steel plate differed only in hue.
## Each profile now uses a generated, game-ready source texture. The committed
## images are greyscale modulation maps: the board still owns the colour, while
## the art supplies recognisable plate, grate, rubble, grain and corrosion.
##
## Every texture is deliberately quiet. It multiplies over the colour the board
## already chose, in a narrow band around white, so it adds grain without
## changing what a surface reads as. The tokens are not textured at all: side
## colour is the one thing on the board that has to stay instantly legible, and
## grain on top of it would only make it harder to read.

## Textures are square, seamless and power-of-two so mipmaps stay inexpensive.
const SIZE := 512

## The profile each cover material draws with. A material with no entry here
## falls back to [constant DEFAULT_PROFILE].
const MATERIAL_PROFILES := {
	"Concrete": "concrete",
	"Steel Plate": "brushed",
	"Glass": "glass",
	"Sheet Metal": "brushed",
	"Wood Crate": "grain",
	"Vehicle Hulk": "corroded",
}

## The location editor exposes these five floor types. Keep the visual mapping
## here, beside the object-material mapping, so saved boards immediately regain
## the right finish when they are loaded.
const TILE_PROFILES := {
	"deck": "deck",
	"grate": "grate",
	"rubble": "rubble",
	"ramp": "ramp",
	"water": "water",
}

const DEFAULT_PROFILE := "concrete"

## Generated source art, normalized into quiet greyscale modulation maps. Keeping
## the paths here makes the complete board texture set auditable in one place.
const TEXTURES := {
	"deck": preload("res://assets/textures/board/deck.png"),
	"concrete": preload("res://assets/textures/board/concrete.png"),
	"brushed": preload("res://assets/textures/board/brushed.png"),
	"glass": preload("res://assets/textures/board/glass.png"),
	"grain": preload("res://assets/textures/board/grain.png"),
	"corroded": preload("res://assets/textures/board/corroded.png"),
	"grate": preload("res://assets/textures/board/grate.png"),
	"rubble": preload("res://assets/textures/board/rubble.png"),
	"ramp": preload("res://assets/textures/board/ramp.png"),
	"water": preload("res://assets/textures/board/water.png"),
}

## Physical response remains explicit in code, independent of the albedo art.
const PROFILES := {
	"deck": {"roughness": 0.82, "metallic": 0.12},
	"concrete": {"roughness": 0.88, "metallic": 0.04},
	"brushed": {"roughness": 0.42, "metallic": 0.62},
	"glass": {"roughness": 0.16, "metallic": 0.30},
	"grain": {"roughness": 0.90, "metallic": 0.02},
	"corroded": {"roughness": 0.78, "metallic": 0.35},
	"grate": {"roughness": 0.58, "metallic": 0.48},
	"rubble": {"roughness": 0.96, "metallic": 0.02},
	"ramp": {"roughness": 0.72, "metallic": 0.28},
	"water": {"roughness": 0.08, "metallic": 0.18},
}


static func profile_for_material(material_name: String) -> String:
	return String(MATERIAL_PROFILES.get(material_name, DEFAULT_PROFILE))


static func profile_for_tile(tile_id: String) -> String:
	return String(TILE_PROFILES.get(tile_id, "deck"))


static func color_for_tile(tile_id: String, alternate := false) -> Color:
	var colors := {
		"deck": [Color("2b3a4d"), Color("25323f")],
		"grate": [Color("38414a"), Color("303840")],
		"rubble": [Color("4a4642"), Color("403d3a")],
		"ramp": [Color("414956"), Color("38404b")],
		"water": [Color("173f52"), Color("123747")],
	}
	var pair: Array = colors.get(tile_id, colors["deck"])
	return pair[1] if alternate else pair[0]


## The generated texture for [param profile].
static func texture_for(profile: String) -> Texture2D:
	return TEXTURES.get(profile, TEXTURES[DEFAULT_PROFILE]) as Texture2D


## A lit material carrying the profile's texture and surface response.
##
## [param color] stays the albedo: the texture only modulates it, so callers keep
## deciding what colour a thing is.
static func material_for(profile: String, color: Color) -> StandardMaterial3D:
	var spec: Dictionary = PROFILES.get(profile, PROFILES[DEFAULT_PROFILE])
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.albedo_texture = texture_for(profile)
	material.roughness = float(spec["roughness"])
	material.metallic = float(spec["metallic"])
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.texture_repeat = true
	return material


## Slide the pattern along by a fixed amount for this key.
##
## Two crates of the same material would otherwise be pixel-identical. The offset
## is derived from the key rather than randomised so that a board rebuilt by undo
## comes back looking the way it went in.
static func offset_for(key: String) -> Vector3:
	var hashed := key.hash()
	return Vector3(float(hashed % 97) / 97.0, float((hashed / 97) % 89) / 89.0, 0.0)


## How far a single deck tile's tint drifts from its neighbours, either way.
const DECK_DRIFT := 0.10

## How many tiles a patch of deck wear spans. Larger than one tile on purpose:
## every tile carries the same texture patch, so variation between tiles is the
## only thing that stops a deck reading as one repeated stamp.
const DECK_WEAR_SCALE := 0.14

static var _deck_noise: FastNoiseLite


## A per-tile brightness multiplier, so the deck weathers unevenly across its
## span rather than tiling one identical patch.
##
## Sampled off the grid position, so a rebuilt board weathers the same way.
static func deck_variation(x: int, z: int) -> float:
	if _deck_noise == null:
		_deck_noise = FastNoiseLite.new()
		_deck_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_deck_noise.seed = 90210
		_deck_noise.frequency = DECK_WEAR_SCALE
	return 1.0 + _deck_noise.get_noise_2d(float(x), float(z)) * DECK_DRIFT
