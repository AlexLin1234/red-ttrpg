class_name MapAsset
extends RefCounted

const MAX_BYTES := 32 * 1024 * 1024
const MAX_PIXELS := 40_000_000
const EXTERNAL_PATH := "res://data/maps/night_city_2045.png"


static func from_file(path: String) -> Dictionary:
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return {"ok": false, "error": "Map image could not be read"}
	if image.get_width() * image.get_height() > MAX_PIXELS:
		return {"ok": false, "error": "Map exceeds the 40 megapixel limit"}
	image.convert(Image.FORMAT_RGBA8)
	var png := image.save_png_to_buffer()
	if png.size() > MAX_BYTES:
		return {"ok": false, "error": "Normalized map exceeds the 32 MB limit"}
	return {
		"ok": true,
		"map":
		{
			"name": path.get_file(),
			"width": image.get_width(),
			"height": image.get_height(),
			"png_base64": Marshalls.raw_to_base64(png),
			"zones": [],
		},
	}


static func decode(data: Dictionary) -> Image:
	var image := Image.new()
	var encoded := String(data.get("png_base64", ""))
	if encoded == "" or image.load_png_from_buffer(Marshalls.base64_to_raw(encoded)) != OK:
		return null
	return image


static func load_external(path: String = EXTERNAL_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "Night City map is not installed. Extract it into data/maps/night_city_2045.png."}
	var loaded := from_file(path)
	if not bool(loaded.get("ok", false)):
		return loaded
	return {"ok": true, "image": decode(loaded["map"]), "path": path}
