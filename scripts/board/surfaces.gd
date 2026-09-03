class_name BoardSurfaces
extends RefCounted

## Procedural surface textures for the isometric board.
##
## The board used to be flat-shaded boxes: one albedo colour per material and
## nothing else, so a concrete barrier and a steel plate differed only in hue.
## These are generated from noise at runtime rather than shipped as image files,
## which keeps them out of the export, out of Git, and reviewable as code.
##
## Every texture is deliberately quiet. It multiplies over the colour the board
## already chose, in a narrow band around white, so it adds grain without
## changing what a surface reads as. The tokens are not textured at all: side
## colour is the one thing on the board that has to stay instantly legible, and
## grain on top of it would only make it harder to read.

## Textures are square, seamless, and generated once per profile per run.
const SIZE := 96

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

const DEFAULT_PROFILE := "concrete"

## How each profile is built.
##
## "contrast" is the half-width of the band the noise is remapped into: 0.10
## means the texture runs from 0.90 to 1.10, so it modulates the underlying
## colour by at most ten per cent either way. "stretch" squashes the noise on one
## axis, which is what turns isotropic noise into a brushed or grained look.
const PROFILES := {
	"deck": {
		"frequency": 0.09,
		"octaves": 3,
		"contrast": 0.075,
		"stretch": 1.0,
		"roughness": 0.82,
		"metallic": 0.12,
	},
	"concrete": {
		"frequency": 0.07,
		"octaves": 4,
		"contrast": 0.10,
		"stretch": 1.0,
		"roughness": 0.88,
		"metallic": 0.04,
	},
	"brushed": {
		"frequency": 0.16,
		"octaves": 2,
		"contrast": 0.07,
		"stretch": 7.0,
		"roughness": 0.42,
		"metallic": 0.62,
	},
	"glass": {
		"frequency": 0.05,
		"octaves": 2,
		"contrast": 0.035,
		"stretch": 2.0,
		"roughness": 0.16,
		"metallic": 0.30,
	},
	"grain": {
		"frequency": 0.10,
		"octaves": 3,
		"contrast": 0.13,
		"stretch": 5.0,
		"roughness": 0.90,
		"metallic": 0.02,
	},
	"corroded": {
		"frequency": 0.12,
		"octaves": 5,
		"contrast": 0.16,
		"stretch": 1.0,
		"roughness": 0.78,
		"metallic": 0.35,
	},
}

## Built textures, keyed by profile. Static so a board rebuilt by undo does not
## pay for them twice, and so the two boards that can be on screen at once — the
## GM's and the player display's — share one set.
static var _cache: Dictionary = {}


static func profile_for_material(material_name: String) -> String:
	return String(MATERIAL_PROFILES.get(material_name, DEFAULT_PROFILE))


## The texture for [param profile], generated on first use.
static func texture_for(profile: String) -> Texture2D:
	if _cache.has(profile):
		return _cache[profile]
	var spec: Dictionary = PROFILES.get(profile, PROFILES[DEFAULT_PROFILE])
	var texture := _build(spec)
	_cache[profile] = texture
	return texture


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


static func _build(spec: Dictionary) -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	# Fixed seed: the board looks the same every run, which matters because the
	# screenshot suite compares renders.
	noise.seed = 1312
	noise.frequency = float(spec["frequency"])
	noise.fractal_octaves = int(spec["octaves"])

	var image := noise.get_seamless_image(SIZE, SIZE)
	image.convert(Image.FORMAT_RGB8)
	# Read the noise from an untouched copy: the loop below both samples and
	# writes, and sampling a pixel it had already remapped would compound the
	# remap into a much harder contrast than the profile asked for.
	var source: Image = image.duplicate()

	var contrast := float(spec["contrast"])
	var stretch := maxf(1.0, float(spec["stretch"]))
	for y in SIZE:
		for x in SIZE:
			# Sampling a squashed row turns the same isotropic noise into a
			# directional one, which is what reads as brushing or wood grain.
			var level: float = source.get_pixel(int(float(x) / stretch) % SIZE, y).r
			var scale: float = 1.0 + (level - 0.5) * 2.0 * contrast
			image.set_pixel(x, y, Color(scale, scale, scale))

	return ImageTexture.create_from_image(image)
