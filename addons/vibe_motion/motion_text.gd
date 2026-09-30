@tool
extends RefCounted
## Text -> motion plan (Portuguese and English).
##
## "anda devagar até a esquerda, acena duas vezes e depois senta triste"
##   -> [walk (slow, left), wave (x2), sit (sad)]
##
## Sentences are split into segments ("e", "depois", "então", "e depois",
## ",", "then", "and"...); "enquanto"/"while" layers a gesture over the
## previous action ("anda enquanto acena"). Moods and styles stick until
## changed; counts ("3 vezes", "twice"), durations ("por 4 segundos"),
## speed ("devagar", "fast"), sides ("mão esquerda") and directions
## ("para trás", "em círculo", "to the left") are understood.

const Util = preload("res://addons/vibe_core/core/vibe_util.gd")

const KEYWORDS := {
	"walk": ["andar", "anda", "andando", "caminhar", "caminha", "caminhando", "passear", "passeia", "passos", "passo", "dar passos",
		"ir", "vai", "walk", "walks", "walking", "stroll", "strolls", "step", "steps", "go"],
	"run": ["correr", "corre", "correndo", "corrida", "disparar", "trotar", "trota", "run", "runs", "running", "sprint", "sprints", "jog", "jogs", "jogging"],
	"sneak": ["esgueirar", "esgueira", "se esgueira", "furtivo", "furtiva", "furtivamente", "sorrateiro", "sorrateira", "sorrateiramente",
		"pe ante pe", "na ponta dos pes", "andar agachado", "anda agachado", "agachadinho", "silenciosamente",
		"sneak", "sneaks", "sneaking", "tiptoe", "tiptoes", "stealthily"],
	"march": ["marchar", "marcha", "marchando", "march", "marches", "marching"],
	"jump": ["pular", "pula", "pulando", "pulo", "pulos", "saltar", "salta", "saltando", "salto", "saltos", "jump", "jumps", "jumping", "hop", "hops", "leap", "leaps"],
	"jumping_jacks": ["polichinelo", "polichinelos", "jumping jack", "jumping jacks", "star jumps"],
	"spin": ["girar", "gira", "girando", "rodopiar", "rodopia", "rodopiando", "pirueta", "piruetas", "rodar", "roda", "spin", "spins", "spinning", "twirl", "twirls", "pirouette"],
	"turn": ["virar", "vira", "virando", "vira-se", "se vira", "meia volta", "meia-volta", "dar meia volta", "da meia volta", "turn", "turns", "turning", "turn around", "turns around"],
	"idle": ["parado", "parada", "ficar parado", "fica parado", "ficar em pe", "esperar", "espera", "esperando", "respirar", "respira", "respirando",
		"descansar", "descansa", "idle", "stand still", "stands still", "standing", "wait", "waits", "waiting", "breathe", "breathing"],
	"wave": ["acenar", "acena", "acenando", "aceno", "dar tchau", "da tchau", "tchau", "ola", "cumprimentar", "cumprimenta", "saudar",
		"wave", "waves", "waving", "hello", "goodbye", "greet", "greets"],
	"clap": ["bater palmas", "bate palmas", "batendo palmas", "palmas", "aplaudir", "aplaude", "aplaudindo", "clap", "claps", "clapping", "applaud", "applauds"],
	"point": ["apontar", "aponta", "apontando", "point", "points", "pointing"],
	"cheer": ["comemorar", "comemora", "comemorando", "celebrar", "celebra", "celebrando", "vibrar", "vibra", "vibrando", "festejar", "festeja",
		"vitoria", "cheer", "cheers", "cheering", "celebrate", "celebrates", "victory", "hooray", "yay"],
	"dance": ["dancar", "danca", "dancando", "requebrar", "rebolar", "rebola", "dance", "dances", "dancing", "groove", "boogie", "disco"],
	"sit": ["sentar", "senta", "sentado", "sentada", "sentando", "senta-se", "se senta", "sentar na cadeira", "sit", "sits", "sitting", "sit down", "sits down", "take a seat"],
	"sit_ground": ["sentar no chao", "senta no chao", "sentado no chao", "sentada no chao", "sentar de pernas cruzadas", "sit on the ground",
		"sits on the ground", "sit on the floor", "sits on the floor", "cross legged", "cross-legged"],
	"meditate": ["meditar", "medita", "meditando", "meditacao", "posicao de lotus", "lotus", "meditate", "meditates", "meditating"],
	"stand_up": ["levantar", "levanta", "levantando", "levantar-se", "levanta-se", "se levanta", "ficar de pe", "fica de pe", "erguer-se",
		"stand up", "stands up", "get up", "gets up", "rise", "rises"],
	"crouch": ["agachar", "agacha", "agachado", "agachada", "agachando", "abaixar", "abaixa", "se abaixa", "de cocoras", "crouch", "crouches", "crouching", "squat down", "duck", "ducks"],
	"squats": ["agachamento", "agachamentos", "fazer agachamento", "squats", "doing squats"],
	"kneel": ["ajoelhar", "ajoelha", "ajoelhado", "ajoelhada", "ajoelhando", "de joelhos", "kneel", "kneels", "kneeling"],
	"lie": ["deitar", "deita", "deitado", "deitada", "deitando", "deitar-se", "deita-se", "se deita", "lie down", "lies down", "lay down", "lying down"],
	"fall": ["cair", "cai", "caindo", "tropecar", "tropeca", "tropecando", "desmaiar", "desmaia", "desmaiando", "fall", "falls", "falling", "fall down",
		"falls down", "trip", "trips", "faint", "faints"],
	"die": ["morrer", "morre", "morrendo", "morto", "morta", "die", "dies", "dying"],
	"hit": ["levar um soco", "leva um soco", "levar um golpe", "leva um golpe", "ser atingido", "e atingido", "tomar dano", "toma dano",
		"get hit", "gets hit", "is hit", "hit reaction", "take damage", "takes damage"],
	"bow": ["reverencia", "fazer reverencia", "faz reverencia", "curvar-se", "se curva", "curva-se", "bow", "bows", "bowing"],
	"salute": ["continencia", "bater continencia", "bate continencia", "prestar continencia", "presta continencia", "saudacao militar", "salute", "salutes", "saluting"],
	"nod": ["concordar", "concorda", "concordando", "assentir", "assente", "balancar a cabeca que sim", "sim com a cabeca", "fazer que sim", "faz que sim",
		"nod", "nods", "nodding"],
	"shake_head": ["negar", "nega", "negando", "nao com a cabeca", "balancar a cabeca", "balanca a cabeca", "fazer que nao", "faz que nao",
		"shake head", "shakes head", "shake his head", "shakes his head", "shake her head", "shakes her head", "shaking head"],
	"look_around": ["olhar em volta", "olha em volta", "olhando em volta", "olhar ao redor", "olha ao redor", "olhar para os lados", "olha para os lados",
		"procurar", "procura", "procurando", "look around", "looks around", "looking around", "search", "searches", "searching"],
	"shrug": ["dar de ombros", "da de ombros", "dando de ombros", "encolher os ombros", "encolhe os ombros", "shrug", "shrugs", "shrugging"],
	"stretch": ["espreguicar", "espreguica", "espreguicando", "se espreguica", "alongar", "alonga", "alongando", "alongamento", "stretch", "stretches", "stretching"],
	"talk": ["conversar", "conversa", "conversando", "falar", "fala", "falando", "gesticular", "gesticula", "gesticulando", "explicar", "explica",
		"discursar", "talk", "talks", "talking", "speak", "speaks", "speaking", "chat", "chats", "explain", "explains"],
	"think": ["pensar", "pensa", "pensando", "pensativo", "pensativa", "refletir", "reflete", "mao no queixo", "think", "thinks", "thinking", "ponder", "ponders"],
	"cross_arms": ["cruzar os bracos", "cruza os bracos", "cruzando os bracos", "bracos cruzados", "de bracos cruzados", "cross arms",
		"crosses arms", "crossed arms", "arms crossed", "crosses his arms", "crosses her arms"],
	"hands_on_hips": ["maos na cintura", "mao na cintura", "com as maos na cintura", "hands on hips", "hands on his hips", "hands on her hips"],
	"pray": ["rezar", "reza", "rezando", "orar", "ora", "orando", "pray", "prays", "praying"],
	"cry": ["chorar", "chora", "chorando", "choro", "cry", "cries", "crying", "sob", "sobs", "weep", "weeps"],
	"laugh": ["rir", "ri", "rindo", "gargalhar", "gargalha", "gargalhada", "gargalhando", "risada", "laugh", "laughs", "laughing"],
	"punch": ["socar", "soca", "socando", "soco", "socos", "murro", "murros", "esmurrar", "boxe", "boxear", "lutar boxe", "punch", "punches", "punching", "jab", "jabs", "boxing"],
	"kick": ["chutar", "chuta", "chutando", "chute", "chutes", "pontape", "voadora", "kick", "kicks", "kicking"],
	"slash": ["espada", "espadada", "espadadas", "golpe de espada", "golpear", "golpeia", "atacar", "ataca", "atacando", "ataque", "cortar", "corta",
		"sword", "slash", "slashes", "slashing", "attack", "attacks", "attacking", "strike", "strikes"],
	"cast": ["magia", "feitico", "feiticos", "conjurar", "conjura", "conjurando", "lancar magia", "lanca magia", "lancar um feitico", "lanca um feitico",
		"encantamento", "poder magico", "cast", "casts", "casting", "spell", "spells", "magic"],
	"throw": ["arremessar", "arremessa", "arremessando", "arremesso", "jogar uma pedra", "joga uma pedra", "lancar", "lanca", "atirar uma pedra",
		"throw", "throws", "throwing", "toss", "tosses"],
	"pick_up": ["pegar", "pega", "pegando", "pegar do chao", "pega do chao", "apanhar", "apanha", "recolher", "recolhe", "levantar algo",
		"pick up", "picks up", "picking up", "grab", "grabs", "collect", "collects"],
	"push": ["empurrar", "empurra", "empurrando", "push", "pushes", "pushing", "shove", "shoves"],
	"guard": ["guarda", "posicao de luta", "em guarda", "defender", "defende", "defendendo", "bloquear", "bloqueia", "lutar", "luta", "lutando",
		"guard", "block", "blocks", "fighting stance", "fight", "fights", "fighting"],
	"aim": ["mirar", "mira", "mirando", "atirar", "atira", "atirando", "disparar a arma", "dispara", "pistola", "arma",
		"aim", "aims", "aiming", "shoot", "shoots", "shooting", "gun", "pistol"],
	"fly": ["voar", "voa", "voando", "super heroi", "super-heroi", "superheroi", "fly", "flies", "flying", "superhero"],
	"pushups": ["flexao", "flexoes", "flexao de braco", "flexoes de braco", "fazer flexoes", "faz flexoes", "push up", "push ups", "pushup", "pushups", "push-ups"],
}

const MOODS := {
	"happy": ["feliz", "felizes", "alegre", "alegremente", "contente", "animado", "animada", "empolgado", "empolgada", "saltitante",
		"happy", "happily", "cheerful", "cheerfully", "excited", "joyful", "joyfully"],
	"sad": ["triste", "tristes", "tristemente", "deprimido", "deprimida", "chateado", "chateada", "cabisbaixo", "cabisbaixa", "desanimado", "desanimada",
		"sad", "sadly", "depressed", "upset", "gloomy", "unhappy"],
	"tired": ["cansado", "cansada", "exausto", "exausta", "com sono", "sonolento", "sonolenta", "tired", "exhausted", "sleepy", "weary"],
	"angry": ["bravo", "brava", "irritado", "irritada", "com raiva", "raivoso", "raivosa", "furioso", "furiosa", "zangado", "zangada", "nervoso de raiva",
		"angry", "angrily", "furious", "furiously", "mad", "annoyed"],
	"confident": ["confiante", "orgulhoso", "orgulhosa", "determinado", "determinada", "imponente", "estiloso", "estilosa", "com estilo",
		"confident", "confidently", "proud", "proudly", "boss", "swagger"],
	"scared": ["com medo", "medo", "assustado", "assustada", "amedrontado", "amedrontada", "nervoso", "nervosa", "apavorado", "apavorada",
		"scared", "afraid", "frightened", "nervous", "nervously", "fearful"],
}

const STYLES := {
	"robot": ["robo", "robotico", "robotica", "como um robo", "roboticamente", "mecanico", "mecanica", "robot", "robotic", "robotically", "like a robot"],
	"zombie": ["zumbi", "zumbis", "como um zumbi", "morto-vivo", "morto vivo", "zombie", "zombies", "like a zombie"],
	"drunk": ["bebado", "bebada", "embriagado", "embriagada", "tonto", "tonta", "cambaleando", "cambaleante", "drunk", "drunken", "dizzy", "staggering", "tipsy"],
	"ninja": ["ninja", "como um ninja", "like a ninja"],
	"cartoon": ["cartoon", "desenho animado", "exagerado", "exagerada", "exageradamente", "caricato", "caricata", "exaggerated", "cartoonish", "cartoony"],
	"elegant": ["elegante", "elegantemente", "desfilando", "desfila", "como modelo", "passarela", "gracioso", "graciosa", "elegant", "elegantly", "gracefully", "graceful", "catwalk", "runway"],
	"old": ["idoso", "idosa", "velho", "velha", "velhinho", "velhinha", "ancião", "anciao", "curvado", "curvada", "old man", "old woman", "elderly", "old person"],
	"limp": ["mancando", "manca", "mancar", "machucado", "machucada", "ferido", "ferida", "com a perna machucada", "limp", "limps", "limping", "injured", "wounded", "hurt"],
}

const NUMBERS := {
	"um": 1, "uma": 1, "dois": 2, "duas": 2, "tres": 3, "quatro": 4, "cinco": 5, "seis": 6, "sete": 7, "oito": 8, "nove": 9, "dez": 10,
	"onze": 11, "doze": 12, "quinze": 15, "vinte": 20,
	"one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "twelve": 12, "twenty": 20,
	"a": 1, "an": 1,
}

const SEPARATORS := [" e depois ", " e entao ", " e em seguida ", " em seguida ", " depois disso ", " depois ", " entao ", " logo apos ", " apos isso ",
	" e logo ", " and then ", " after that ", " afterwards ", " then ", " and ", " e ", ",", ";", ".", "!", "?", " finally ", " por fim ", " enfim "]
const OVERLAY_WORDS := [" enquanto ", " ao mesmo tempo que ", " ao mesmo tempo em que ", " while ", " at the same time as "]

## English phrases for model backends (Kimodo was trained on English text).
const EN := {
	"idle": "stands still, breathing calmly", "walk": "walks", "run": "runs", "sneak": "sneaks forward in a crouch",
	"march": "marches like a soldier", "jump": "jumps", "jumping_jacks": "does jumping jacks", "spin": "spins around in place",
	"turn": "turns around", "wave": "waves with the %s hand", "clap": "claps the hands", "point": "points with the %s hand",
	"cheer": "cheers with both arms raised", "dance": "dances energetically", "sit": "sits down on a chair",
	"sit_ground": "sits down on the ground with crossed legs", "meditate": "sits cross-legged and meditates",
	"stand_up": "stands up", "crouch": "crouches down", "squats": "does squats", "kneel": "kneels down on one knee",
	"lie": "lies down on the ground on the back", "fall": "trips and falls to the ground", "die": "gets shot and collapses to the ground",
	"hit": "gets hit and staggers back", "bow": "bows politely", "salute": "salutes like a soldier", "nod": "nods the head yes",
	"shake_head": "shakes the head no", "look_around": "looks around", "shrug": "shrugs the shoulders", "stretch": "stretches the arms above the head",
	"talk": "talks and gestures with the hands", "think": "thinks with a hand on the chin", "cross_arms": "stands with arms crossed",
	"hands_on_hips": "stands with hands on the hips", "pray": "prays with the hands together", "cry": "cries with the hands on the face",
	"laugh": "laughs out loud", "punch": "throws punches like a boxer", "kick": "kicks forward with the %s leg",
	"slash": "swings a sword", "cast": "casts a spell with both hands", "throw": "throws a ball overhand", "pick_up": "picks something up from the ground",
	"push": "pushes a heavy object", "guard": "stands in a fighting stance", "aim": "aims a pistol and shoots", "fly": "flies like a superhero",
	"pushups": "does push-ups",
}
const EN_MOOD := {"happy": "happily", "sad": "sadly", "tired": "tiredly", "angry": "angrily", "confident": "confidently", "scared": "nervously"}
const EN_STYLE := {"robot": "like a robot", "zombie": "like a zombie", "drunk": "like a drunk person", "ninja": "like a ninja",
	"cartoon": "in an exaggerated cartoon way", "elegant": "elegantly", "old": "like an old person", "limp": "with a limp"}


static func _pad(s: String) -> String:
	return " " + s + " "


static func normalize(text: String) -> String:
	var s := Util.normalize_text(text)
	for ch in ["(", ")", "\"", "'", ":", "/", "\n", "\t"]:
		s = s.replace(ch, " ")
	while s.contains("  "):
		s = s.replace("  ", " ")
	return s.strip_edges()


static func _has(seg: String, words: Array) -> String:
	# Longest phrase first, whole words only.
	var best := ""
	var p := _pad(seg)
	for w in words:
		var ww: String = w
		if ww.length() > best.length() and p.contains(_pad(ww)):
			best = ww
	return best


## Finds the clip named in a segment: [clip, matched phrase].
static func find_clip(seg: String) -> Array:
	var best_clip := ""
	var best := ""
	for clip in KEYWORDS:
		var m := _has(seg, KEYWORDS[clip])
		if m.length() > best.length():
			best = m
			best_clip = clip
	return [best_clip, best]


static func _find_in(seg: String, table: Dictionary) -> String:
	var best_key := ""
	var best := ""
	for k in table:
		var m := _has(seg, table[k])
		if m.length() > best.length():
			best = m
			best_key = k
	return best_key


static func _number_before(words: PackedStringArray, i: int) -> int:
	if i <= 0:
		return 0
	var w := words[i - 1]
	if w.is_valid_int():
		return int(w)
	if w.ends_with("x") and w.trim_suffix("x").is_valid_int():
		return int(w.trim_suffix("x"))
	return int(NUMBERS.get(w, 0))


static func _count(seg: String, keyword: String = "") -> int:
	var words := seg.split(" ", false)
	if keyword != "":
		var first := keyword.split(" ", false)[0]
		for i in words.size():
			if words[i] == first:
				var n := _number_before(words, i)
				if n > 1 and not (i + 1 < words.size() and words[i + 1] in ["segundos", "segundo", "seconds", "second", "s", "metros", "meters", "passos", "steps"]):
					return n
	for i in words.size():
		var w := words[i]
		if w in ["vezes", "vez", "times", "time", "repeticoes", "reps"]:
			var n := _number_before(words, i)
			if n > 0:
				return n
		if w == "twice":
			return 2
		if w == "thrice":
			return 3
		if w == "once":
			return 1
		if w.length() >= 2 and w.ends_with("x") and w.trim_suffix("x").is_valid_int():
			return int(w.trim_suffix("x"))
		if w.begins_with("x") and w.substr(1).is_valid_int():
			return int(w.substr(1))
	return 0


static func _steps(seg: String) -> int:
	var words := seg.split(" ", false)
	for i in words.size():
		if words[i] in ["passos", "passo", "steps", "step"]:
			return _number_before(words, i)
	return 0


static func _duration(seg: String) -> float:
	var words := seg.split(" ", false)
	for i in words.size():
		var w := words[i]
		if w in ["segundos", "segundo", "s", "seg", "seconds", "second", "secs", "sec"]:
			if i > 0:
				var v := words[i - 1].replace(",", ".")
				if v.is_valid_float():
					return float(v)
				if NUMBERS.has(v):
					return float(NUMBERS[v])
		if w.ends_with("s") and w.trim_suffix("s").replace(",", ".").is_valid_float():
			return float(w.trim_suffix("s").replace(",", "."))
	return -1.0


static func _meters(seg: String) -> float:
	var words := seg.split(" ", false)
	for i in words.size():
		if words[i] in ["metros", "metro", "m", "meters", "meter", "metres"] and i > 0:
			var v := words[i - 1].replace(",", ".")
			if v.is_valid_float():
				return float(v)
			if NUMBERS.has(v):
				return float(NUMBERS[v])
	return 0.0


static func _angle(seg: String) -> float:
	var words := seg.split(" ", false)
	for i in words.size():
		if words[i] in ["graus", "grau", "degrees", "degree", "deg"] and i > 0 and words[i - 1].is_valid_float():
			return float(words[i - 1])
	var p := _pad(seg)
	for w in [" meia volta ", " meia-volta ", " para tras ", " around ", " back "]:
		if p.contains(w):
			return 180.0
	if p.contains(" volta completa ") or p.contains(" full turn ") or p.contains(" 360 "):
		return 360.0
	return 90.0


static func _speed(seg: String) -> float:
	var p := _pad(seg)
	var slow := ["devagar", "devagarinho", "lentamente", "lento", "lenta", "calmamente", "tranquilamente", "sem pressa", "slowly", "slow", "calmly", "gently"]
	var fast := ["rapido", "rapida", "rapidamente", "depressa", "ligeiro", "ligeira", "com pressa", "apressado", "apressada", "fast", "quickly", "quick", "rapidly", "hurriedly"]
	var very := p.contains(" muito ") or p.contains(" very ") or p.contains(" bem ") or p.contains(" super ")
	for w in slow:
		if p.contains(_pad(w)):
			return 0.45 if very else 0.65
	for w in fast:
		if p.contains(_pad(w)):
			return 1.9 if very else 1.45
	return 1.0


static func _side(seg: String) -> String:
	var p := _pad(seg)
	for w in [" duas maos ", " ambas as maos ", " as duas ", " ambas ", " os dois bracos ", " both hands ", " both arms ", " both "]:
		if p.contains(w):
			return "Both"
	for w in [" esquerda ", " esquerdo ", " left "]:
		if p.contains(w):
			return "Left"
	for w in [" direita ", " direito ", " right "]:
		if p.contains(w):
			return "Right"
	return ""


static func _direction(seg: String) -> String:
	var p := _pad(seg)
	if p.contains(" circulo") or p.contains(" circle") or p.contains(" em volta de ") or p.contains(" em roda "):
		return "circle"
	if p.contains(" zigue") or p.contains(" zigzag") or p.contains(" zig zag") or p.contains(" zig-zag"):
		return "zigzag"
	for w in [" de lado ", " lateralmente ", " sideways ", " strafe ", " strafes ", " strafing "]:
		if p.contains(w):
			return "side"
	for w in [" para tras ", " pra tras ", " de costas ", " de re ", " backward ", " backwards ", " back "]:
		if p.contains(w):
			return "back"
	for w in [" para frente ", " pra frente ", " em frente ", " adiante ", " forward ", " forwards ", " ahead "]:
		if p.contains(w):
			return "forward"
	for w in [" para cima ", " pra cima ", " ao ceu ", " up ", " upward ", " upwards ", " the sky "]:
		if p.contains(w):
			return "up"
	for w in [" para baixo ", " pra baixo ", " ao chao ", " down ", " downward ", " the ground "]:
		if p.contains(w):
			return "down"
	for w in [" esquerda ", " left "]:
		if p.contains(w):
			return "left"
	for w in [" direita ", " right "]:
		if p.contains(w):
			return "right"
	return ""


## Splits text into raw segments, keeping overlays ("enquanto") attached.
static func split(text: String) -> Array:
	var s := _pad(normalize(text))
	var marker := "|"
	for sep in SEPARATORS:
		s = s.replace(sep, " " + marker + " ")
	var out: Array = []
	for part in s.split(marker, false):
		var seg: String = part.strip_edges()
		if seg == "":
			continue
		var over_txt := ""
		for w in OVERLAY_WORDS:
			var i := _pad(seg).find(w)
			if i >= 0:
				var padded := _pad(seg)
				over_txt = padded.substr(i + w.length()).strip_edges()
				seg = padded.substr(0, i).strip_edges()
				break
		out.append({"text": seg, "overlay": over_txt})
	return out


## Parses a description into a plan:
## {"segments": [{"clip", "q": {...}, "text", "overlay"?}], "unknown": [...], "mood", "style"}
static func parse(text: String, defaults: Dictionary = {}) -> Dictionary:
	var synth_moods: Dictionary = preload("res://addons/vibe_motion/motion_synth.gd").MOODS
	var mood_key := str(defaults.get("mood", ""))
	var style_key := str(defaults.get("style", ""))
	var segments: Array = []
	var unknown: Array = []
	var last_clip := ""
	for raw in split(text):
		var seg: String = raw.text
		var found := find_clip(seg)
		var clip: String = found[0]
		var m := _find_in(seg, MOODS)
		if m != "":
			mood_key = m
		var st := _find_in(seg, STYLES)
		if st != "":
			style_key = st
		# "marcha como soldado"/"anda como zumbi": style words alone imply walking.
		if clip == "" and (st != "" or m != "") and last_clip == "":
			clip = "walk"
		var dirw := _direction(seg)
		if clip == "":
			# Only modifiers ("para trás", "mais rápido"): repeat the last action.
			if last_clip != "" and (dirw != "" or _speed(seg) != 1.0 or _count(seg) > 0 or _duration(seg) > 0.0):
				clip = last_clip
			else:
				if seg.strip_edges() != "":
					unknown.append(seg)
				continue
		var q := {}
		if not mood_key.is_empty():
			q["mood"] = synth_moods.get(mood_key, {})
			q["mood_name"] = mood_key
		if style_key != "":
			q["style"] = style_key
		var sp := _speed(seg)
		if sp != 1.0:
			q["speed"] = sp
		var n := _count(seg, found[1] if found[0] == clip else "")
		if n > 0:
			q["count"] = n
		var d := _duration(seg)
		if d > 0.0:
			q["duration"] = d
		var steps := _steps(seg)
		if steps > 0 and clip in ["walk", "run", "sneak", "march"]:
			q["steps"] = steps
		var meters := _meters(seg)
		if meters > 0.0 and clip in ["walk", "run", "sneak", "march", "push"]:
			q["distance"] = meters
		var side := _side(seg)
		var hand_clips := ["wave", "point", "punch", "kick", "salute", "throw", "slash"]
		if side != "" and clip in hand_clips and (seg.contains("mao") or seg.contains("braco") or seg.contains("perna") or seg.contains("pe ")
				or seg.contains("hand") or seg.contains("arm") or seg.contains("leg") or seg.contains("foot") or side == "Both"):
			q["side"] = side
			q["side_explicit"] = true
		elif side != "" and clip in ["wave", "salute", "punch", "kick"] and dirw in ["left", "right"]:
			q["side"] = side
			q["side_explicit"] = true
		if dirw != "":
			q["dir"] = dirw
		_apply_direction(clip, q, seg)
		var entry := {"clip": clip, "q": q, "text": seg}
		if raw.overlay != "":
			var oc: Array = find_clip(raw.overlay)
			if oc[0] != "" and preload("res://addons/vibe_motion/motion_synth.gd").CLIPS.get(oc[0], {}).get("upper", false):
				var oq := {}
				var os := _side(raw.overlay)
				if os != "":
					oq["side"] = os
				var on := _count(raw.overlay)
				if on > 0:
					oq["count"] = on
				entry["overlay"] = {"clip": oc[0], "q": oq, "text": raw.overlay}
			elif oc[0] != "":
				# "acena enquanto anda": the locomotion is the base action.
				var base_entry := {"clip": oc[0], "q": q.duplicate(), "text": raw.overlay}
				base_entry.overlay = {"clip": clip, "q": {"side": q.get("side", "Right")}, "text": seg}
				entry = base_entry
		segments.append(entry)
		last_clip = entry.clip
	return {"segments": segments, "unknown": unknown, "mood": mood_key, "style": style_key}


static func _apply_direction(clip: String, q: Dictionary, seg: String) -> void:
	var d: String = q.get("dir", "")
	var loco := clip in ["walk", "run", "sneak", "march", "push"]
	if loco:
		match d:
			"back":
				q["dir_vec"] = Vector3(0, 0, -1)
			"side":
				q["dir_vec"] = Vector3(-1, 0, 0) if _side(seg) == "Right" else Vector3(1, 0, 0)
			"left", "right":
				# Curve toward that side over the first second.
				q["turn_to"] = 90.0 if d == "left" else -90.0
			"circle":
				var r := 2.2 if clip != "run" else 4.5
				q["turn"] = rad_to_deg(1.35 * float(q.get("speed", 1.0)) / r) * (-1.0 if _side(seg) == "Right" else 1.0)
			"zigzag":
				q["zigzag"] = true
	if clip == "turn":
		q["angle"] = _angle(seg)
		if d == "" and q.angle >= 180.0:
			q["dir"] = "back"
		elif d == "":
			q["dir"] = "left"
	if clip == "spin" and d == "":
		q["dir"] = "left"
	if clip == "jump" and d == "" and (seg.contains("frente") or seg.contains("forward")):
		q["dir"] = "forward"


## One English sentence per segment (for text-to-motion models).
static func english(entry: Dictionary) -> String:
	var clip: String = entry.clip
	var q: Dictionary = entry.get("q", {})
	var side := "right"
	if str(q.get("side", "")) == "Left":
		side = "left"
	var phrase: String = EN.get(clip, clip)
	if phrase.contains("%s"):
		phrase = phrase % side
	var extra := ""
	match str(q.get("dir", "")):
		"back":
			extra = " backwards" if clip in ["walk", "run", "sneak"] else ""
		"left":
			extra = " to the left"
		"right":
			extra = " to the right"
		"circle":
			extra = " in a circle"
		"forward":
			extra = " forward"
	var sp := float(q.get("speed", 1.0))
	var how := ""
	if sp < 0.9:
		how = " slowly"
	elif sp > 1.2:
		how = " quickly"
	var mood := str(q.get("mood_name", ""))
	var style := str(q.get("style", ""))
	var s := "A person " + phrase + extra + how
	if EN_MOOD.has(mood):
		s += " " + EN_MOOD[mood]
	if EN_STYLE.has(style):
		s += " " + EN_STYLE[style]
	var n := int(q.get("count", 0))
	if n > 1:
		s += ", %d times" % n
	if entry.has("overlay"):
		var oside := "left" if str(entry.overlay.get("q", {}).get("side", "")) == "Left" else "right"
		s += " while it " + (EN.get(entry.overlay.clip, "moves") as String).replace("%s", oside)
	return s + "."
