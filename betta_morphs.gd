extends RefCounted
## Colour morphs and fin types. All of them are modelled on varieties that exist
## in the hobby; random_look() only picks, combines and slightly varies them.

## Every colour/pattern parameter of the fish shader at its neutral value.
## Palettes only list what they change.
const COLOR_DEFAULTS := {
	"iri_strength": 1.0,
	"marble": 0.0,
	"marble_color": Color(0.7, 0.04, 0.03),
	"marble_seed": 0.0,
	"butterfly": 0.0,
	"band_pos": 0.65,
	"band_color": Color(0.92, 0.9, 0.85),
	"band_opacity": 1.0,
	"fin_opacity": 1.0,
}

## Shader side of the fin types (the mesh side is in betta_mesh.gd).
const FIN_DEFAULTS := {
	"crown": 0.0,
	"ruffle": 0.0,
	"scallop": 1.0,
}

## Fixed palettes cycled with the C key. They are shown on the default halfmoon.
const PRESETS := [
	{  # royal blue / crimson
		"body_dark": Color(0.01, 0.02, 0.10), "iri_a": Color(0.0, 0.75, 0.95), "iri_b": Color(0.45, 0.1, 0.9),
		"fin_base": Color(0.02, 0.07, 0.45), "fin_mid": Color(0.03, 0.4, 0.9), "fin_edge": Color(0.8, 0.03, 0.15),
	},
	{  # flame
		"body_dark": Color(0.12, 0.02, 0.01), "iri_a": Color(1.0, 0.45, 0.05), "iri_b": Color(1.0, 0.1, 0.3),
		"fin_base": Color(0.5, 0.05, 0.02), "fin_mid": Color(1.0, 0.35, 0.02), "fin_edge": Color(1.0, 0.85, 0.2),
	},
	{  # opal
		"body_dark": Color(0.25, 0.3, 0.35), "iri_a": Color(0.6, 1.0, 0.95), "iri_b": Color(0.9, 0.6, 1.0),
		"fin_base": Color(0.5, 0.7, 0.8), "fin_mid": Color(0.85, 0.95, 1.0), "fin_edge": Color(0.3, 0.9, 0.85),
	},
]

# Solid colour morphs. Body: dark base, two iridescent tones, scale metallicity.
# Fins: base, middle, outer edge.
const MORPHS := [
	{  # royal blue
		"body_dark": Color(0.01, 0.02, 0.10), "iri_a": Color(0.0, 0.75, 0.95), "iri_b": Color(0.45, 0.1, 0.9), "iri_strength": 1.0,
		"fin_base": Color(0.02, 0.07, 0.45), "fin_mid": Color(0.03, 0.4, 0.9), "fin_edge": Color(0.05, 0.3, 0.85),
	},
	{  # solid red: hardly any iridescence
		"body_dark": Color(0.25, 0.02, 0.02), "iri_a": Color(0.75, 0.1, 0.08), "iri_b": Color(0.55, 0.05, 0.2), "iri_strength": 0.35,
		"fin_base": Color(0.45, 0.02, 0.03), "fin_mid": Color(0.75, 0.05, 0.05), "fin_edge": Color(0.6, 0.02, 0.04),
	},
	{  # steel blue
		"body_dark": Color(0.12, 0.15, 0.2), "iri_a": Color(0.55, 0.65, 0.8), "iri_b": Color(0.45, 0.5, 0.7), "iri_strength": 1.0,
		"fin_base": Color(0.15, 0.2, 0.3), "fin_mid": Color(0.45, 0.55, 0.7), "fin_edge": Color(0.6, 0.7, 0.85),
	},
	{  # turquoise / green
		"body_dark": Color(0.0, 0.08, 0.08), "iri_a": Color(0.1, 0.85, 0.6), "iri_b": Color(0.05, 0.6, 0.8), "iri_strength": 1.1,
		"fin_base": Color(0.02, 0.2, 0.2), "fin_mid": Color(0.05, 0.6, 0.55), "fin_edge": Color(0.1, 0.8, 0.6),
	},
	{  # black orchid
		"body_dark": Color(0.01, 0.01, 0.015), "iri_a": Color(0.25, 0.15, 0.5), "iri_b": Color(0.1, 0.2, 0.5), "iri_strength": 0.5,
		"fin_base": Color(0.01, 0.01, 0.02), "fin_mid": Color(0.04, 0.02, 0.06), "fin_edge": Color(0.12, 0.05, 0.25),
	},
	{  # platinum / opaque white
		"body_dark": Color(0.75, 0.75, 0.72), "iri_a": Color(1.0, 1.0, 1.0), "iri_b": Color(0.85, 0.9, 1.0), "iri_strength": 0.8,
		"fin_base": Color(0.8, 0.8, 0.8), "fin_mid": Color(0.9, 0.9, 0.9), "fin_edge": Color(0.95, 0.95, 0.95),
	},
	{  # yellow ("pineapple")
		"body_dark": Color(0.55, 0.4, 0.05), "iri_a": Color(1.0, 0.85, 0.3), "iri_b": Color(0.9, 0.7, 0.2), "iri_strength": 0.5,
		"fin_base": Color(0.8, 0.6, 0.08), "fin_mid": Color(1.0, 0.85, 0.2), "fin_edge": Color(1.0, 0.9, 0.4),
	},
	{  # orange
		"body_dark": Color(0.5, 0.12, 0.02), "iri_a": Color(1.0, 0.45, 0.1), "iri_b": Color(0.9, 0.3, 0.05), "iri_strength": 0.4,
		"fin_base": Color(0.7, 0.2, 0.03), "fin_mid": Color(1.0, 0.45, 0.08), "fin_edge": Color(1.0, 0.55, 0.15),
	},
	{  # mustard gas: blue body, fins blue inside and yellow-orange outside
		"body_dark": Color(0.02, 0.06, 0.15), "iri_a": Color(0.1, 0.6, 0.7), "iri_b": Color(0.2, 0.3, 0.8), "iri_strength": 1.0,
		"fin_base": Color(0.05, 0.15, 0.5), "fin_mid": Color(0.1, 0.3, 0.6), "fin_edge": Color(1.0, 0.7, 0.1),
	},
	{  # cambodian: pale flesh body, red fins
		"body_dark": Color(0.85, 0.6, 0.5), "iri_a": Color(1.0, 0.85, 0.8), "iri_b": Color(0.9, 0.8, 0.9), "iri_strength": 0.3,
		"fin_base": Color(0.5, 0.02, 0.04), "fin_mid": Color(0.85, 0.08, 0.06), "fin_edge": Color(0.7, 0.04, 0.05),
	},
	{  # red dragon: thick white metallic scales over a red body
		"body_dark": Color(0.4, 0.03, 0.03), "iri_a": Color(1.0, 0.95, 0.9), "iri_b": Color(0.9, 0.9, 1.0), "iri_strength": 1.6,
		"fin_base": Color(0.45, 0.03, 0.03), "fin_mid": Color(0.8, 0.06, 0.05), "fin_edge": Color(0.7, 0.05, 0.05),
	},
	{  # copper
		"body_dark": Color(0.3, 0.15, 0.05), "iri_a": Color(1.0, 0.6, 0.3), "iri_b": Color(0.9, 0.75, 0.4), "iri_strength": 1.3,
		"fin_base": Color(0.4, 0.2, 0.08), "fin_mid": Color(0.8, 0.45, 0.2), "fin_edge": Color(0.9, 0.6, 0.3),
	},
	{  # cellophane: pale, translucent fins
		"body_dark": Color(0.8, 0.6, 0.55), "iri_a": Color(0.95, 0.85, 0.85), "iri_b": Color(0.85, 0.85, 0.95), "iri_strength": 0.2,
		"fin_base": Color(0.85, 0.75, 0.75), "fin_mid": Color(0.9, 0.85, 0.85), "fin_edge": Color(0.95, 0.9, 0.9),
		"fin_opacity": 0.4,
	},
]

# Koi are always built on a pale base: platinum, cambodian or cellophane.
const PALE_MORPHS := [5, 9, 12]
const KOI_COLORS := [Color(0.7, 0.04, 0.03), Color(0.02, 0.02, 0.02), Color(0.95, 0.35, 0.05)]

# Fin types with their relative frequency. "mesh" overrides BettaMesh.DEFAULT_SHAPE,
# the other keys override FIN_DEFAULTS.
const FIN_TYPES := [
	{"name": "halfmoon", "weight": 4.0, "mesh": {}},
	{"name": "rosetail", "weight": 1.0, "ruffle": 1.0,
		"mesh": {"caudal_spread": 1.55, "caudal_length": 0.8, "dorsal_scale": 1.1, "anal_scale": 1.05}},
	{"name": "super delta", "weight": 1.5,
		"mesh": {"caudal_spread": 1.15, "caudal_profile": "flat"}},
	{"name": "delta", "weight": 1.0,
		"mesh": {"caudal_spread": 0.85, "caudal_length": 0.7, "caudal_profile": "flat"}},
	{"name": "veiltail", "weight": 2.0,
		"mesh": {"caudal_spread": 0.8, "caudal_length": 0.95, "caudal_profile": "round",
			"caudal_sag": 0.45, "caudal_asym": 0.25, "dorsal_scale": 1.15, "dorsal_sweep": 1.25,
			"dorsal_sag": 0.2, "anal_scale": 1.15, "anal_sag": 0.15, "ventral_scale": 1.2}},
	{"name": "crowntail", "weight": 2.0, "crown": 1.0,
		"mesh": {"caudal_spread": 1.3, "caudal_length": 0.82, "caudal_profile": "round",
			"dorsal_scale": 1.1, "anal_scale": 1.1}},
	{"name": "double tail", "weight": 1.0,
		"mesh": {"caudal_spread": 1.4, "caudal_length": 0.7, "caudal_profile": "double",
			"dorsal_start": 0.36, "dorsal_scale": 1.15}},
	{"name": "plakat", "weight": 1.5, "scallop": 0.5,
		"mesh": {"caudal_spread": 1.0, "caudal_length": 0.32, "caudal_profile": "round",
			"dorsal_scale": 0.42, "anal_scale": 0.55, "ventral_scale": 0.55}},
	{"name": "halfmoon plakat", "weight": 1.0, "scallop": 0.5,
		"mesh": {"caudal_spread": 1.45, "caudal_length": 0.36, "dorsal_scale": 0.45,
			"anal_scale": 0.55, "ventral_scale": 0.6}},
	{"name": "spade tail", "weight": 0.7,
		"mesh": {"caudal_spread": 0.8, "caudal_length": 0.6, "caudal_profile": "point",
			"dorsal_scale": 0.9, "anal_scale": 0.9}},
	{"name": "round tail", "weight": 0.7,
		"mesh": {"caudal_spread": 1.0, "caudal_length": 0.65, "caudal_profile": "round"}},
]


## Fills in every shader parameter a palette leaves out.
static func with_defaults(colors: Dictionary) -> Dictionary:
	return COLOR_DEFAULTS.merged(colors, true)


## Returns {"name", "colors", "fins", "mesh"}: two sets of shader parameters and
## a mesh shape for BettaMesh.
static func random_look(rng: RandomNumberGenerator) -> Dictionary:
	var colors := _random_colors(rng)
	var fin_type := _pick_fin_type(rng)
	var fins := FIN_DEFAULTS.duplicate()
	for key: String in FIN_DEFAULTS:
		if fin_type.has(key):
			fins[key] = fin_type[key]
	return {
		"name": "%s %s" % [colors.name, fin_type.name],
		"colors": colors.params,
		"fins": fins,
		"mesh": fin_type.mesh,
	}


static func _random_colors(rng: RandomNumberGenerator) -> Dictionary:
	var params := COLOR_DEFAULTS.duplicate()
	var name := "solid"
	var body_index := rng.randi_range(0, MORPHS.size() - 1)
	var fin_index := body_index
	if rng.randf() < 0.3:
		# Bicolour: body of one morph, fins of another.
		fin_index = rng.randi_range(0, MORPHS.size() - 1)
		name = "bicolour"
	if rng.randf() < 0.18:
		# Koi: a pale fish with red, black or orange patches.
		body_index = PALE_MORPHS[rng.randi_range(0, PALE_MORPHS.size() - 1)]
		fin_index = body_index
		params.marble = 1.0
		params.marble_color = _vary(KOI_COLORS[rng.randi_range(0, KOI_COLORS.size() - 1)], rng)
		params.marble_seed = rng.randf_range(0.0, 100.0)
		name = "koi"

	var body: Dictionary = MORPHS[body_index]
	var fin: Dictionary = MORPHS[fin_index]
	for key: String in ["body_dark", "iri_a", "iri_b", "iri_strength"]:
		params[key] = body[key]
	for key: String in ["fin_base", "fin_mid", "fin_edge", "fin_opacity"]:
		if fin.has(key):
			params[key] = fin[key]

	if params.marble == 0.0 and rng.randf() < 0.25:
		# Butterfly: a sharply separated outer band on every fin, white or nearly clear.
		params.butterfly = 1.0
		params.band_pos = rng.randf_range(0.55, 0.72)
		params.fin_edge = params.fin_mid
		if rng.randf() < 0.5:
			params.band_color = Color(0.92, 0.9, 0.85)
		else:
			params.band_color = (params.fin_mid as Color).lerp(Color.WHITE, 0.7)
			params.band_opacity = 0.3
		name = "butterfly"

	for key: String in ["body_dark", "iri_a", "iri_b", "fin_base", "fin_mid", "fin_edge"]:
		params[key] = _vary(params[key], rng)
	return {"name": name, "params": params}


## Slight brightness variation so no two fish of a morph look identical.
static func _vary(c: Color, rng: RandomNumberGenerator) -> Color:
	var k := rng.randf_range(0.85, 1.15)
	return Color(minf(c.r * k, 1.0), minf(c.g * k, 1.0), minf(c.b * k, 1.0))


static func _pick_fin_type(rng: RandomNumberGenerator) -> Dictionary:
	var total := 0.0
	for fin_type: Dictionary in FIN_TYPES:
		total += fin_type.weight
	var r := rng.randf() * total
	for fin_type: Dictionary in FIN_TYPES:
		r -= fin_type.weight
		if r <= 0.0:
			return fin_type
	return FIN_TYPES[0]
