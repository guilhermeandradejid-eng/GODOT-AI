@tool
extends RefCounted
## "Vibe" prompt interpreter: turns a free-form description in Portuguese or
## English into a world recipe (see vibe_world.gd).
##
## It is deliberately simple and deterministic (keyword tables, no network),
## so it works offline and gives the same world for the same prompt. Claude
## Code (or any user) can refine the returned recipe and run `world.build`.

const Util = preload("res://addons/vibe_core/core/vibe_util.gd")

const TERRAIN_WORDS := {
	"volcano": ["vulcao", "vulcoes", "volcano", "volcanoes", "vulcanico", "vulcanica", "volcanic"],
	"archipelago": ["arquipelago", "archipelago", "ilhas", "islands"],
	"island": ["ilha", "island", "isle", "ilhota", "atol", "atoll"],
	"canyon": ["canion", "canions", "canyon", "canyons", "mesa", "mesas", "planalto", "plateau", "desfiladeiro", "gorge", "badlands"],
	"dunes": ["deserto", "desert", "duna", "dunas", "dune", "dunes", "saara", "sahara"],
	"crater": ["cratera", "crateras", "crater", "craters", "lunar"],
	"valley": ["vale", "vales", "valley", "valleys", "ravina", "fiorde", "fjord"],
	"mountains": ["montanha", "montanhas", "mountain", "mountains", "serra", "serras", "cordilheira", "pico", "picos", "peak", "peaks", "alpes", "alps", "alpino", "alpine", "montanhoso", "mountainous"],
	"hills": ["colina", "colinas", "hill", "hills", "morro", "morros", "coxilha", "coxilhas", "ondulado", "rolling", "hilly"],
	"plains": ["planicie", "planicies", "plain", "plains", "campo", "campos", "pradaria", "prairie", "prado", "savana", "savanna", "estepe", "steppe", "fazenda", "farm", "pasto", "pasture"],
	"flat": ["plano", "plana", "flat", "arena"],
}

const TERRAIN_PRIORITY := ["volcano", "archipelago", "island", "canyon", "dunes", "crater", "valley", "mountains", "hills", "plains", "flat"]

const PALETTE_WORDS := {
	"alien": ["alien", "alienigena", "extraterrestre", "planeta", "planet", "scifi", "sci-fi", "fantasia", "fantasy", "magico", "magica", "magical", "encantado", "encantada", "enchanted", "mistico", "mistica", "mystic"],
	"volcanic": ["vulcao", "volcano", "vulcanico", "vulcanica", "volcanic", "lava", "magma", "cinzas", "ash", "inferno", "hell"],
	"snowy": ["neve", "nevado", "nevada", "nevados", "nevadas", "snow", "snowy", "gelo", "ice", "icy", "gelado", "gelada", "artico", "arctic", "inverno", "winter", "congelado", "frozen", "tundra", "polar"],
	"desert": ["deserto", "desert", "duna", "dunas", "dunes", "saara", "sahara", "arido", "arida", "arid", "sertao"],
	"canyon": ["canion", "canyon", "canyons", "mesa", "mesas", "badlands", "arenito", "sandstone"],
	"tropical": ["tropical", "tropicais", "selva", "jungle", "rainforest", "paraiso", "paradise", "caribe", "caribbean", "havai", "hawaii"],
	"autumn": ["outono", "autumn", "fall", "outonal"],
	"swamp": ["pantano", "swamp", "brejo", "mangue", "marsh", "bog", "charco"],
	"lunar": ["lunar", "moonscape"],
	"savanna": ["savana", "savanna", "cerrado", "seco", "seca", "dry"],
}

const PALETTE_PRIORITY := ["alien", "lunar", "volcanic", "snowy", "desert", "canyon", "swamp", "tropical", "autumn", "savanna"]

const GRASS_WORDS := {
	"flowers": ["flores", "flor", "flowers", "flower", "florido", "florida", "floridos", "floral", "primavera", "spring", "jardim", "garden"],
	"wheat": ["trigo", "wheat", "plantacao", "lavoura", "crop", "crops", "cevada", "barley"],
	"tall": ["capim", "capinzal", "mato", "matagal", "tall grass", "grama alta", "grass tall", "long grass"],
	"dry": ["grama seca", "capim seco", "dry grass", "palha", "straw", "feno", "hay"],
	"lush": ["exuberante", "lush", "denso", "densa", "dense", "verdejante", "vicejante"],
	"meadow": ["grama", "gramado", "grass", "relva", "lawn", "campina", "pasto", "meadow"],
}

const VFX_WORDS := {
	"campfire": ["fogueira", "fogueiras", "campfire", "campfires", "bonfire", "acampamento", "camp"],
	"torch": ["tocha", "tochas", "torch", "torches", "archote", "archotes"],
	"fire": ["fogo", "fire", "chama", "chamas", "flame", "flames", "incendio", "queimando", "burning"],
	"smoke": ["fumaca", "smoke", "fumegante", "smoking"],
	"steam": ["vapor", "steam", "geiser", "geyser", "geysers", "geiseres"],
	"sparks": ["faisca", "faiscas", "fagulha", "fagulhas", "spark", "sparks"],
	"embers": ["brasa", "brasas", "ember", "embers"],
	"explosion": ["explosao", "explosoes", "explosion", "explosions", "bomba", "bomb", "boom"],
	"magic_aura": ["magia", "magic", "feitico", "spell", "aura", "encantamento", "arcano", "arcane"],
	"portal": ["portal", "portais", "portals", "vortex", "vortice", "teleporte", "teleport"],
	"fireflies": ["vagalume", "vagalumes", "firefly", "fireflies", "pirilampo", "pirilampos"],
	"rain": ["chuva", "chuvoso", "chuvosa", "chovendo", "rain", "rainy", "raining", "garoa", "drizzle"],
	"snowfall": ["nevando", "nevasca", "snowfall", "snowing", "blizzard", "flocos", "neve caindo", "caindo neve",
		"flocos de neve", "neva", "nevar", "falling snow", "snow falling"],
	"dust": ["poeira", "dust", "dusty", "poeirento", "sandstorm"],
	"leaves": ["folhas", "leaves", "falling leaves", "folhas caindo"],
	"fountain": ["fonte", "fountain", "chafariz"],
	"waterfall": ["cachoeira", "cachoeiras", "waterfall", "waterfalls", "cascata", "cascatas"],
	"lightning": ["raio", "raios", "relampago", "relampagos", "lightning", "trovao", "thunder", "trovoada"],
	"heal": ["cura", "curar", "heal", "healing"],
	"bubbles": ["bolha", "bolhas", "bubble", "bubbles"],
	"shockwave": ["onda de choque", "shockwave", "impacto", "impact"],
	"force_field": ["campo de forca", "escudo", "shield", "force field", "forcefield", "barreira", "barrier"],
	"mist": ["nevoa rasteira", "ground fog", "ground mist", "bruma"],
}

const ENV_WORDS := {
	"stormy": ["tempestade", "tempestades", "storm", "stormy", "tempestuoso", "trovoada", "thunderstorm"],
	"night": ["noite", "night", "noturno", "noturna", "nighttime", "madrugada", "luar", "moonlight", "meia noite", "midnight", "escuro", "escura", "dark"],
	"sunset": ["por do sol", "entardecer", "sunset", "crepusculo", "dusk", "fim de tarde", "golden hour", "hora dourada", "anoitecer", "poente"],
	"dawn": ["amanhecer", "alvorada", "dawn", "sunrise", "nascer do sol", "madrugada clara", "manha", "morning"],
	"foggy": ["neblina", "nevoa", "nevoeiro", "fog", "foggy", "mist", "misty", "bruma", "sombrio", "sombria", "gloomy", "misterioso", "misteriosa", "mysterious", "assombrado", "haunted"],
	"overcast": ["nublado", "nublada", "overcast", "cloudy", "nuvens", "clouds", "cinzento", "cinzenta"],
	"alien": ["alien", "alienigena", "extraterrestre", "planeta", "planet"],
	"day": ["dia", "day", "daytime", "ensolarado", "ensolarada", "sunny", "meio dia", "noon", "claro", "bright"],
}

const ENV_PRIORITY := ["stormy", "night", "sunset", "dawn", "foggy", "overcast", "alien", "day"]

const NUMBER_WORDS := {
	"um": 1, "uma": 1, "one": 1, "a": 1, "an": 1,
	"dois": 2, "duas": 2, "two": 2, "par": 2, "pair": 2,
	"tres": 3, "three": 3, "quatro": 4, "four": 4, "cinco": 5, "five": 5,
	"seis": 6, "six": 6, "sete": 7, "seven": 7, "oito": 8, "eight": 8,
	"nove": 9, "nine": 9, "dez": 10, "ten": 10, "doze": 12, "twelve": 12,
	"varias": 5, "varios": 5, "muitas": 8, "muitos": 8, "several": 5, "many": 8, "lots": 8,
	"algumas": 3, "alguns": 3, "some": 3, "few": 3, "poucas": 2, "poucos": 2,
}

const NEGATIONS := ["sem", "no", "without", "nenhum", "nenhuma", "nada"]

const STYLE_WORDS := {
	"cel": ["cel", "celshaded", "cel shading", "cel shaded", "anime", "manga", "mangá"],
	"lowpoly": ["lowpoly", "low poly", "poligonal", "facetado", "facetada", "polygonal"],
	"toon": ["toon", "cartoon", "desenho", "cartunesco", "cartunesca", "infantil", "fofo", "fofa", "cute"],
	"stylized": ["estilizado", "estilizada", "stylized", "pintado", "pintada", "painterly", "ghibli", "aquarela", "watercolor"],
	"realistic": ["realista", "realistic", "fotorealista", "photorealistic", "realismo", "realism", "pbr"],
}

## Characters (needs the vibe_motion plugin): noun -> outfit preset.
const CHARACTER_WORDS := {
	"knight": ["cavaleiro", "cavaleiros", "knight", "knights", "paladino", "paladinos", "paladin"],
	"wizard": ["mago", "magos", "maga", "magas", "bruxo", "bruxos", "bruxa", "bruxas", "feiticeiro", "feiticeira", "wizard", "wizards", "mage", "mages", "witch", "sorcerer"],
	"ninja": ["ninja", "ninjas", "samurai", "samurais"],
	"robot": ["robo", "robos", "robot", "robots", "androide", "androides", "android", "ciborgue", "cyborg"],
	"soldier": ["soldado", "soldados", "soldier", "soldiers", "militar", "militares", "guarda", "guardas", "guard", "guards"],
	"zombie": ["zumbi", "zumbis", "zombie", "zombies"],
	"astronaut": ["astronauta", "astronautas", "astronaut", "astronauts"],
	"king": ["rei", "reis", "rainha", "rainhas", "king", "queen", "principe", "princesa", "prince", "princess"],
	"athlete": ["atleta", "atletas", "athlete", "athletes", "corredor", "corredora", "corredores", "runner", "runners", "jogador", "jogadora"],
	"adventurer": ["aventureiro", "aventureira", "aventureiros", "explorador", "exploradora", "exploradores", "heroi", "heroina", "herois",
		"adventurer", "adventurers", "explorer", "explorers", "hero", "heroes", "heroine", "cacador", "cacadora", "hunter", "viajante", "traveler"],
	"mannequin": ["manequim", "manequins", "boneco", "bonecos", "mannequin", "mannequins", "dummy"],
	"casual": ["personagem", "personagens", "pessoa", "pessoas", "homem", "homens", "mulher", "mulheres", "menino", "meninos", "menina", "meninas",
		"garoto", "garotos", "garota", "garotas", "crianca", "criancas", "aldeao", "aldeoes", "campones", "turista", "turistas", "dancarino",
		"dancarina", "dancarinos", "character", "characters", "person", "people", "man", "men", "woman", "women", "boy", "boys", "girl", "girls",
		"kid", "kids", "villager", "villagers", "dancer", "dancers", "tourist", "tourists"],
}
const CHARACTER_PRIORITY := ["zombie", "knight", "wizard", "ninja", "robot", "soldier", "astronaut", "king", "athlete", "adventurer", "mannequin", "casual"]

var _text := ""
var _padded := ""
var _tokens: PackedStringArray = []
var notes: Array = []


func parse(prompt: String) -> Dictionary:
	notes.clear()
	_text = Util.normalize_text(prompt)
	var cleaned := ""
	for i in _text.length():
		var ch := _text[i]
		var code := ch.unicode_at(0)
		var is_alnum := (code >= 97 and code <= 122) or (code >= 48 and code <= 57)
		cleaned += ch if is_alnum else " "
	_tokens = cleaned.split(" ", false)
	_padded = " " + " ".join(_tokens) + " "

	var recipe := {}
	var seed_value := _find_seed()
	if seed_value < 0:
		seed_value = absi(prompt.strip_edges().to_lower().hash()) % 100000

	# --- Terrain ------------------------------------------------------------
	var preset := _first_match(TERRAIN_WORDS, TERRAIN_PRIORITY)
	var palette := _first_match(PALETTE_WORDS, PALETTE_PRIORITY)
	var wants_water := _has_any(["mar", "oceano", "ocean", "sea", "praia", "praias", "beach", "beaches", "costa", "litoral", "coast", "baia", "bay", "enseada", "agua", "water"]) and not _negated(["agua", "water", "mar", "sea"])
	var wants_river := _has_any(["rio", "rios", "river", "rivers", "riacho", "corrego", "stream", "creek"])
	var wants_lake := _has_any(["lago", "lagos", "lake", "lakes", "lagoa", "lagoas", "pond"])
	var wants_road := _has_any(["estrada", "estradas", "road", "roads", "caminho", "trilha", "trail", "path"])
	if preset == "" and palette == "snowy":
		preset = "mountains"
	if preset == "" and palette == "desert":
		preset = "dunes"
	if preset == "" and palette == "lunar":
		preset = "crater"
	if preset == "":
		preset = "island" if wants_water else "hills"
		notes.append("terreno padrão / default terrain: %s" % preset)
	if palette == "":
		palette = {"dunes": "desert", "canyon": "canyon", "volcano": "volcanic", "crater": "lunar", "island": "tropical", "archipelago": "tropical"}.get(preset, "temperate")

	var size := 256.0
	if _has_any(["pequeno", "pequena", "pequenos", "small", "tiny", "mini", "minusculo"]):
		size = 128.0
	elif _has_any(["enorme", "gigante", "gigantesco", "gigantesca", "huge", "giant", "massive", "imenso", "imensa", "vasto", "vasta", "vast"]):
		size = 1024.0
	elif _has_any(["grande", "big", "large", "amplo", "ampla", "wide"]):
		size = 512.0

	var height_mul := 1.0
	if _has_any(["altas", "altos", "alta", "alto", "altissimas", "altissimos", "tall", "high", "towering", "imponente", "imponentes", "ingreme", "ingremes", "steep", "dramatico", "dramatica", "dramatic", "epico", "epica", "epic"]):
		height_mul = 1.6
	elif _has_any(["suave", "suaves", "gentle", "leve", "leves", "baixo", "baixa", "baixas", "baixos", "low", "calmo", "calma"]):
		height_mul = 0.6

	var terrain := {
		"preset": preset,
		"size": size,
		"seed": seed_value,
		"height_multiplier": height_mul,
		"palette": palette,
		"auto_paint": true,
	}
	if preset in ["island", "archipelago", "volcano"] or wants_water:
		terrain["water"] = true
	var features: Array = []
	if wants_river and preset != "archipelago":
		features.append({"type": "river"})
		notes.append("rio / river")
	if wants_lake:
		features.append({"type": "lake", "at": "center" if preset in ["valley", "plains", "hills"] else "valley"})
		notes.append("lago / lake")
	if wants_road:
		features.append({"type": "road"})
		notes.append("estrada / road")
	if preset in ["canyon", "mountains", "valley", "hills"] and _has_any(["erosao", "erodido", "eroded", "erosion", "realista", "realistic"]):
		terrain["erosion"] = {"type": "hydraulic", "iterations": 20000}
	if not features.is_empty():
		terrain["features"] = features
	recipe["terrain"] = terrain
	notes.append("terreno / terrain: %s, %dm, paleta/palette %s, seed %d" % [preset, int(size), palette, seed_value])

	# --- Grass --------------------------------------------------------------
	var grass: Array = []
	var no_grass := _negated(["grama", "grass", "vegetacao", "vegetation", "mato", "plantas", "plants"]) or _has_any(["arido", "arida", "arid", "barren", "esteril", "morto", "morta", "dead"])
	if not no_grass:
		var grass_preset := _first_match(GRASS_WORDS, ["wheat", "tall", "dry", "lush", "meadow"])
		if grass_preset == "":
			grass_preset = {"temperate": "meadow", "tropical": "lush", "autumn": "dry", "savanna": "savanna", "swamp": "reeds", "alien": "alien", "snowy": "tundra"}.get(palette, "")
		if grass_preset == "" and _has_any(GRASS_WORDS["flowers"]):
			grass_preset = "meadow"
		if grass_preset != "":
			grass.append({"preset": grass_preset})
			notes.append("grama / grass: %s" % grass_preset)
		if _has_any(GRASS_WORDS["flowers"]) and not _negated(GRASS_WORDS["flowers"]):
			grass.append({"preset": "flowers", "name": "Flowers", "density": 0.5})
			notes.append("flores / flowers")
	if not grass.is_empty():
		recipe["grass"] = grass

	# --- Trees, bushes, rocks (vibe_scatter) --------------------------------
	var scatter := _scatter(palette)
	if not scatter.is_empty():
		recipe["scatter"] = scatter[0] if scatter.size() == 1 and scatter[0] is String else scatter

	# --- VFX ----------------------------------------------------------------
	var vfx: Array = []
	for key in VFX_WORDS:
		var hit := _find_word(VFX_WORDS[key])
		if hit < 0:
			continue
		if key == "fire" and (_find_word(VFX_WORDS["campfire"]) >= 0 or _find_word(VFX_WORDS["torch"]) >= 0) \
				and _color_near(hit) == null and _count_before(hit) == 0:
			continue
		if _negated(VFX_WORDS[key]):
			continue
		var entry := {"preset": key}
		var count := _count_before(hit)
		if count == 0:
			count = 3 if _tokens[hit].ends_with("s") and not key in ["rain", "snowfall", "dust", "leaves", "fireflies", "embers", "sparks", "bubbles", "mist", "lightning", "portal"] else 1
		if key in ["rain", "snowfall", "dust", "leaves", "mist", "lightning"]:
			count = 1
		if count > 1:
			entry["count"] = count
		var color = _color_near(hit)
		if color != null:
			entry["color"] = "#" + (color as Color).to_html(false)
		var where := _location_near(hit)
		if where != "":
			entry["at"] = where
		vfx.append(entry)
		notes.append("vfx: %s%s%s" % [key, " x%d" % count if count > 1 else "", " (%s)" % entry.color if entry.has("color") else ""])
	if preset == "volcano" and not _negated(["fumaca", "smoke"]):
		vfx.append({"preset": "volcano_plume", "at": "peak"})
		notes.append("vfx: volcano_plume (pico/peak)")

	# --- Environment ----------------------------------------------------------
	var env := _first_match(ENV_WORDS, ENV_PRIORITY)
	if env == "" and palette == "alien":
		env = "alien"
	if env == "":
		env = "day"
	var environment := {"preset": env}
	if env == "stormy":
		if not _has_vfx(vfx, "rain") and palette != "snowy":
			vfx.append({"preset": "rain"})
		if not _has_vfx(vfx, "lightning"):
			vfx.append({"preset": "lightning", "at": "random"})
	if palette == "snowy" and env == "stormy" and not _has_vfx(vfx, "snowfall"):
		vfx.append({"preset": "snowfall"})
	recipe["environment"] = environment
	notes.append("ambiente / environment: %s" % env)
	if not vfx.is_empty():
		recipe["vfx"] = vfx
	var style := _first_match(STYLE_WORDS, ["cel", "lowpoly", "toon", "stylized", "realistic"])
	if style != "":
		recipe["style"] = style
		notes.append("estilo / style: %s" % style)
	recipe["camera"] = {"type": "fly", "view": "hero"}
	var characters := _characters()
	if not characters.is_empty():
		recipe["characters"] = characters
	return recipe


## "com um cavaleiro acenando", "two zombies walking", "pessoas dançando
## perto da fogueira": outfit, count and the action phrase (parsed later by
## motion.character).
func _characters() -> Array:
	var out: Array = []
	var used := {}
	for key in CHARACTER_PRIORITY:
		var words: Array = CHARACTER_WORDS[key]
		for i in _tokens.size():
			if used.has(i) or not words.has(_tokens[i]):
				continue
			used[i] = true
			var count := _count_before(i)
			if count == 0:
				count = 3 if _tokens[i].ends_with("s") and not _tokens[i] in ["ninjas", "samurais"] or _tokens[i] in ["people", "men", "women", "kids", "gente"] else 1
			# The action: the clause right after the noun.
			var action: Array = []
			for j in range(i + 1, mini(i + 9, _tokens.size())):
				var w: String = _tokens[j]
				if w in ["com", "with", "numa", "num", "sob", "under", "ao", "during", "durante"]:
					break
				action.append(w)
			var entry := {"outfit": key, "at": "flat"}
			if count > 1:
				entry["count"] = count
			var text := " ".join(action).strip_edges()
			if text != "":
				entry["motion"] = text + (" como um zumbi" if key == "zombie" and not text.contains("zumbi") and not text.contains("zombie") else "")
			var where := _location_near(i)
			if where != "":
				entry["at"] = where
			for fire in ["fogueira", "campfire", "bonfire", "fogo", "fire"]:
				if action.has(fire) or (i > 0 and _tokens[i - 1] == fire):
					entry["at"] = "near:campfire"
			for portal in ["portal"]:
				if action.has(portal):
					entry["at"] = "near:portal"
			out.append(entry)
			notes.append("personagem / character: %s%s%s" % [key, " x%d" % count if count > 1 else "", (" (" + text + ")") if text != "" else ""])
			if out.size() >= 4:
				return out
	return out


const SCATTER_WORDS := {
	"pines": ["pinheiro", "pinheiros", "pinhal", "conifera", "coniferas", "abeto", "abetos", "pine", "pines", "fir", "firs", "conifer", "conifers"],
	"palms": ["palmeira", "palmeiras", "coqueiro", "coqueiros", "palm", "palms", "coconut"],
	"jungle": ["selva", "jungle", "rainforest"],
	"birches": ["betula", "betulas", "birch", "birches"],
	"acacias": ["acacia", "acacias"],
	"dead_trees": ["arvores secas", "arvore seca", "arvores mortas", "galhos secos", "dead trees", "dead tree", "assombrada", "assombrado", "haunted", "spooky"],
	"forest": ["floresta", "florestas", "arvores", "arvore", "bosque", "bosques", "mata", "forest", "forests", "trees", "tree", "woods", "woodland"],
	"bushes": ["arbusto", "arbustos", "moita", "moitas", "bush", "bushes", "shrub", "shrubs"],
	"ferns": ["samambaia", "samambaias", "fern", "ferns"],
	"cacti": ["cacto", "cactos", "cactus", "cacti", "cactuses"],
	"rocks": ["rocha", "rochas", "pedra", "pedras", "rochoso", "rochosa", "rock", "rocks", "rocky", "stone", "stones"],
	"boulders": ["matacao", "matacoes", "pedregulho", "pedregulhos", "rochedo", "rochedos", "boulder", "boulders"],
	"mushrooms": ["cogumelo", "cogumelos", "fungo", "fungos", "mushroom", "mushrooms"],
	"crystals": ["cristal", "cristais", "crystal", "crystals"],
	"logs": ["tronco caido", "troncos caidos", "troncos", "toras", "logs", "log"],
}


## Vegetation: named presets, or "auto" (the palette's natural vegetation)
## unless the prompt says there is none ("sem árvores", "barren"...).
func _scatter(palette: String) -> Array:
	if _negated(["arvore", "arvores", "vegetacao", "floresta", "tree", "trees", "vegetation", "forest", "plantas", "plants"]) \
			or _has_any(["arido", "arida", "arid", "barren", "esteril", "deserto de sal", "vazio", "vazia", "empty", "bare", "limpo", "limpa"]):
		return []
	var named: Array = []
	for key in SCATTER_WORDS:
		var words: Array = SCATTER_WORDS[key]
		var hit := false
		for w in words:
			if (" " + w + " ") in _padded:
				hit = true
				break
		if hit and not _negated(words):
			if key == "forest" and not named.is_empty():
				continue  # "floresta de pinheiros" = pines
			var entry := {"preset": key}
			var dense := _has_any(["densa", "denso", "dense", "fechada", "cerrada", "thick", "lush", "exuberante"])
			var sparse := _has_any(["esparsa", "esparso", "sparse", "poucas", "poucos", "few", "rala", "ralo"])
			if dense:
				entry["density"] = 1.8
			elif sparse:
				entry["density"] = 0.4
			named.append(entry)
			notes.append("vegetação / scatter: %s" % key)
	if named.is_empty():
		notes.append("vegetação automática / auto scatter (%s)" % palette)
		return ["auto"]
	# Named trees still get some rocks around them.
	var has_rocks := false
	for e in named:
		if e.preset in ["rocks", "boulders"]:
			has_rocks = true
	if not has_rocks:
		named.append({"preset": "rocks", "density": 0.5})
	return named


func _has_vfx(list: Array, preset: String) -> bool:
	for v in list:
		if v.get("preset", "") == preset:
			return true
	return false


func _find_seed() -> int:
	for i in _tokens.size() - 1:
		if _tokens[i] in ["seed", "semente"] and _tokens[i + 1].is_valid_int():
			return _tokens[i + 1].to_int()
	return -1


func _has_any(words: Array) -> bool:
	return _find_word(words) >= 0


## Returns the token index of the first matching word (or phrase start), -1 otherwise.
func _find_word(words: Array) -> int:
	var best := -1
	for w in words:
		var idx := -1
		if (w as String).contains(" "):
			var pos := _padded.find(" " + w + " ")
			if pos >= 0:
				idx = _padded.substr(0, pos + 1).strip_edges().split(" ", false).size()
		else:
			idx = _tokens.find(w)
		if idx >= 0 and (best < 0 or idx < best):
			best = idx
	return best


func _negated(words: Array) -> bool:
	var idx := _find_word(words)
	if idx <= 0:
		return false
	# "no" is "in the" in Portuguese ("no outono", "no deserto"): it only
	# negates in English prompts.
	var english := _has_any(["the", "a", "an", "with", "and", "of", "in", "at", "on", "near", "without", "some", "is", "are"])
	for back in range(1, 3):
		if idx - back >= 0 and _tokens[idx - back] in NEGATIONS:
			if _tokens[idx - back] == "no" and not english:
				continue
			return true
	return false


func _first_match(table: Dictionary, priority: Array) -> String:
	for key in priority:
		if table.has(key) and _has_any(table[key]) and not _negated(table[key]):
			return key
	return ""


const COUNT_ADJECTIVES := ["grandes", "pequenas", "pequenos", "enormes", "lindas", "lindos", "belas", "belos",
	"magicas", "magicos", "brilhantes", "big", "small", "large", "huge", "little", "tiny", "bright", "glowing"]


func _count_before(idx: int) -> int:
	for back in range(1, 3):
		var j := idx - back
		if j < 0:
			break
		var t := _tokens[j]
		if t.is_valid_int():
			return clampi(t.to_int(), 1, 50)
		if NUMBER_WORDS.has(t) and not (t in ["a", "an", "um", "uma"]):
			return NUMBER_WORDS[t]
		if not (t in COUNT_ADJECTIVES):
			break
	return 0


func _color_near(idx: int) -> Variant:
	for j in [idx + 1, idx + 2, idx - 1]:
		if j >= 0 and j < _tokens.size():
			var c = Util.find_color_word(_tokens[j])
			if c != null:
				return c
	return null


func _location_near(idx: int) -> String:
	var table := {
		"center": ["centro", "center", "centre", "meio", "middle"],
		"peak": ["topo", "pico", "cume", "peak", "summit", "top", "cratera", "crater"],
		"beach": ["praia", "beach", "shore", "costa", "margem", "litoral"],
		"valley": ["vale", "valley", "baixada"],
		"north": ["norte", "north"], "south": ["sul", "south"],
		"east": ["leste", "east", "oriente"], "west": ["oeste", "west"],
	}
	for j in range(idx + 1, mini(idx + 6, _tokens.size())):
		for key in table:
			if _tokens[j] in table[key]:
				return key
	return ""
