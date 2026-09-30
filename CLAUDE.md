# Godot Vibe Suite — guia para o Claude Code

Este repositório é um projeto Godot 4.3+ com uma suíte de plugins para criar mundos 3D
("vibecoding") pelo terminal: **terreno** (esculpir/pintar/gerar), **grama** (densidade
pintada, vento, flores), **vegetação** (árvores, arbustos, rochas), **VFX** (partículas, céu,
atmosfera, água) e **personagens com animação gerada por texto**, em 5 estilos de arte.
Tudo que dá para fazer no editor também dá para fazer por comandos.

| Pasta | Conteúdo |
|---|---|
| `addons/vibe_core/` | registro de comandos, ponte HTTP do editor, CLI headless, intérprete de prompts (`vibe`), receitas (`world.build`), estilos |
| `addons/vibe_terrain/` | `VibeTerrain3D` (heightmap em chunks + LOD + colisão + água), geradores, pincéis, paletas, shaders por estilo |
| `addons/vibe_grass/` | `VibeGrass3D` (MultiMesh em chunks, densidade pintada, vento, flores/trigo) |
| `addons/vibe_vfx/` | `VibeVFX3D` (biblioteca de efeitos em dados), ambientes/céu/pós-processamento (`env.set`) |
| `addons/vibe_scatter/` | `VibeScatter3D` (árvores, arbustos, rochas, cactos, cristais... instanciados com LOD, vento e colisão) |
| `addons/vibe_motion/` | `VibeCharacter3D` (humanoide procedural com esqueleto), texto → animação, backend Kimodo, import de mocap |
| `tools/` | `vibe.py` (CLI), `vibe_client.py`, `vibe_mcp.py` (servidor MCP), `build_demos.py`, `install.py` |
| `recipes/` | receitas JSON dos mundos de demonstração (bons exemplos para copiar) |
| `demos/` | cenas de demonstração geradas + hub (`demo_hub.tscn` é a cena principal) |
| `tests/` | `run_tests.py` (testes headless), `render_gallery.py` (galeria de estilos) |

## Como executar comandos

Sempre pela ferramenta — não edite à mão os `.tscn`/`.res` gerados.

```bash
python3 tools/vibe.py status                          # onde os comandos rodam + o que existe na cena
python3 tools/vibe.py help                            # todos os comandos
python3 tools/vibe.py help terrain.sculpt             # argumentos de um comando
python3 tools/vibe.py <comando> chave=valor ...       # valores em JSON: 12, true, [10,-5], {"a":1}
python3 tools/vibe.py batch passos.json               # [{"cmd": ..., "args": {...}}, ...]
```

Se o servidor MCP `godot-vibe` estiver ativo (`.mcp.json`), os mesmos comandos existem como
ferramentas (`terrain.sculpt` → `terrain_sculpt`; `screenshot` devolve a imagem).

- **Modo live**: com o editor Godot aberto e os plugins ativos, os comandos vão pela ponte HTTP
  (127.0.0.1, token em `.godot/vibe_bridge.json`), aparecem na hora e aceitam Ctrl+Z.
- **Modo headless**: sem editor, o Godot roda em segundo plano, abre a cena alvo, aplica e
  salva. A cena alvo fica em `.vibe/state.json` (troque com `scene.open`/`scene.new` ou `--scene`).
- Binário: `GODOT_BIN=/caminho/godot` (4.3+); depois do primeiro uso fica lembrado em `.vibe/state.json`
  (o MCP também usa). `screenshot` precisa de janela (ou `xvfb-run` no Linux).

## Fluxo de vibecoding

1. `status` — entender o estado atual.
2. Mundo rápido: `vibe "ilha tropical ao pôr do sol com fogueira e vagalumes"` (PT/EN) ou
   `world.build path=res://recipes/<nome>.json` para controle total. `vibe apply=false` só
   devolve a receita interpretada (bom ponto de partida para editar).
3. **Olhe o resultado**: `screenshot view=hero` (também `aerial`, `ground`, `top`, `camera`,
   `target=<nó>`) e abra o PNG com a ferramenta de leitura de imagens. Não declare algo pronto
   sem ver a imagem.
4. Refine com comandos pontuais (abaixo) e repita o screenshot.
5. `scene.save` (headless já salva ao fim de cada chamada).

## Referência rápida

- **Posições**: `[x, z]` (encaixa na superfície), `[x, y, z]` (absoluta), âncoras
  `center`, `north|south|east|west`, `northeast`…, `peak`, `valley`, `flat`, `beach`, `water`, `random`,
  ou o nome de um nó (`near:Fogueira`, `Portal`) — ex.: `grass.paint grass=Grass position=near:Fogueira radius=5 erase=true`.
- **Estilos** (`style.set style=...`, afeta terreno, água, grama, VFX e pós-processamento):
  `realistic` (texturas PBR), `stylized` (pintado), `toon`, `cel` (anime 2 tons), `lowpoly`.
- **Terreno**: `terrain.create preset=<flat|plains|hills|mountains|island|archipelago|dunes|canyon|crater|volcano|valley> size=256 seed=7 palette=<temperate|tropical|snowy|desert|canyon|volcanic|autumn|alien|lunar|swamp|savanna> water=true`
  - `terrain.sculpt op=<raise|lower|smooth|flatten|set|noise|terrace> position=[x,z] radius=20 strength=10` (ou `points=[[x,z],...]` para traçar)
  - `terrain.stamp shape=<mountain|hill|crater|volcano|lake|plateau|pit> position=... radius=... height=...`
  - `terrain.carve_path mode=<river|road>` (caminho automático ou `points`), `terrain.flatten_area`, `terrain.erode type=<hydraulic|thermal>`
  - `terrain.paint layer=<0-3|nome> position=... radius=...`, `terrain.auto_paint`, `terrain.palette name=...`, `terrain.set_layer`
  - `terrain.water enabled=true level=2`, `terrain.height_at position=...`, `terrain.info`, import/export de heightmap
- **Grama**: `grass.create preset=<meadow|lush|tall|dry|flowers|wheat|tundra|savanna|reeds|alien> name=Flores`
  → `grass.fill grass=Flores density=0.4 max_slope=30 layer=0` (regras) ou `grass.paint position=... radius=... density=1|erase=true`;
  `grass.set` (cores, altura, vento, `view_distance`).
- **VFX**: `vfx.spawn preset=<fire|campfire|torch|embers|sparks|smoke|steam|explosion|volcano_plume|magic_aura|portal|heal|fireflies|rain|snowfall|dust|leaves|mist|fountain|waterfall|bubbles|lightning|shockwave|force_field|confetti> position=... color=blue scale=2`;
  `vfx.set`, `vfx.remove`, `vfx.play`; efeitos próprios com `vfx.describe` → `vfx.define` (salva em `res://vfx_presets/`).
- **Vegetação**: `scatter.auto` (vegetação natural da paleta) ou `scatter.add preset=<forest|autumn|pines|palms|jungle|birches|acacias|dead_trees|bushes|ferns|cacti|rocks|boulders|mushrooms|crystals|logs|alien_trees> density=1 rules={"max_slope":30,"clearing":8}`;
  clareiras com `scatter.paint name=<Camada> position=... radius=15 erase=true`; `scatter.set`, `scatter.clear`, `scatter.list`.
- **Personagens e animação por texto**: `motion.character outfit=<casual|adventurer|athlete|ninja|robot|soldier|knight|wizard|zombie|astronaut|king|mannequin> position=near:Fogueira text="senta no chão e depois acena"`;
  `motion.generate character=<Nome> text="anda devagar, acena duas vezes e depois senta triste"` (PT/EN, sequências, "enquanto", contagens, humor);
  `motion.describe text=...` (como foi entendido), `motion.render animation=<nome> mode=sheet` (abra o PNG para ver o movimento),
  `motion.play character=<Nome> fraction=0.5` (congela a pose; `time=-1` volta a animar), `motion.import path=...bvh|glb|fbx`,
  `motion.backend url=http://127.0.0.1:8090` (IA Kimodo/kimodo.cpp; sem servidor usa o sintetizador embutido).
- **Atmosfera**: `env.set preset=<day|sunset|dawn|night|overcast|foggy|stormy|alien>` (+ `sun_elevation`, `fog_density`, `clouds`,
  `cloud_shade`, `cirrus`, `sky_mid`, `volumetric`, `fog_height`, `tonemap=aces|agx|filmic`...). Sem `preset` mantém o atual e os ajustes.
  `quality=<low|medium|high|ultra>`: SSAO, SSIL, névoa volumétrica (raios de sol), sombras suaves e, em `ultra`, SDFGI (Forward+).
- **Genéricos**: `node.add type=OmniLight3D position=[0,5,0] properties={...}`, `node.set`, `node.get`, `node.remove`,
  `scene.tree`, `camera.add type=fly view=hero`, `undo`/`redo` (editor).

## Receitas (`world.build`)

JSON declarativo — veja `recipes/*.json` e `world.example`:
`scene`, `style`, `environment`, `terrain` (+ `features`: river/road/lake/mountain/crater/flatten…,
`erosion`, `auto_paint`), `grass` (lista, com `rules` do `grass.fill`), `vfx` (lista com `at`,
`count`, `color`, `scale`), `characters` (lista com `outfit`, `at` — inclusive `near:<nó>` —, `motion`,
`facing`, `count`), `scatter` (`"auto"` ou lista de presets com `density`/`rules`; é montado depois dos
efeitos e personagens, abrindo clareiras em volta deles), `camera` e `commands` (comandos extras, rodados no fim).

## Regras do projeto

- Mudanças visuais: confirme com `screenshot` antes de concluir.
- Dados gerados ficam ao lado da cena: `res://pasta/<cena>_data/*.res` (versione junto com a cena).
- Lógica de jogo é GDScript normal. Em runtime: `VibeVFX3D.spawn(parent, "explosion", pos)`,
  `terrain.get_height_at_world(p)`, `terrain.raycast(...)`, `grass.paint(...)`, `character.play("danca")`,
  `character.generate("pula e comemora")` (gera a animação em jogo).
- Animações geradas ficam em `res://animations/<nome>.res` (versione as que a cena usa).
- Novos comandos: crie/edite `addons/<plugin>/vibe_commands.gd` (descoberta automática) e rode
  `godot --headless --path . --script res://addons/vibe_core/cli/vibe_cli.gd -- --write-schema res://addons/vibe_core/commands.schema.json`.
- Validação antes de commitar: `godot --headless --path . --import` (sem erros de script/shader)
  e `python3 tests/run_tests.py`. Visual: `python3 tests/render_gallery.py`, `python3 tools/build_demos.py <demo>`.
