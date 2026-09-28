# Third-party notices / Créditos de terceiros

## Assets

| Arquivo(s) | Origem | Licença |
|---|---|---|
| `addons/vibe_terrain/textures/grass_ground_*` (ambientCG **Ground037**) | via demo do [Terrain3D](https://github.com/TokisanGames/Terrain3D) — <https://ambientcg.com/view?id=Ground037> | CC0 1.0 |
| `addons/vibe_terrain/textures/rock_*` (ambientCG **Rock023**) | via demo do Terrain3D — <https://ambientcg.com/view?id=Rock023> | CC0 1.0 |
| `addons/vibe_terrain/textures/sandstone_*` | [godot-demo-projects](https://github.com/godotengine/godot-demo-projects) (`3d/material_testers`), reempacotada (altura → normal) | MIT — © Godot Engine contributors |
| Demais texturas de terreno (`sand`, `snow`, `dirt`, `gravel`, `mud`, `ash`, `lava`, `ice`, `moss`, `crystal`, `regolith`) e todos os sprites de `addons/vibe_vfx/textures/` | Gerados proceduralmente por `tools/texture_gen/generate_textures.py` | CC0 1.0 (domínio público) |

As texturas foram reempacotadas em WebP no formato esperado pelos shaders
(`albedo_height`: RGB = cor, A = altura; `normal_rough`: RGB = normal, A = rugosidade).

## Técnicas adaptadas (código reescrito, créditos nos cabeçalhos dos shaders)

| Técnica | Projeto de referência | Licença |
|---|---|---|
| Mistura de camadas por altura, detiling por rotação aleatória, macro-variação | [Terrain3D](https://github.com/TokisanGames/Terrain3D) — Cory Petkovsek, Roope Palmroos e colaboradores | MIT |
| Vento por ruído, aglomerados (clumping), luz com subsurface na grama | [GodotGrass](https://github.com/2Retr0/GodotGrass) — Ethan Truong | MIT |
| Iluminação toon em bandas, rim light | [FlexibleToonShaderGD](https://github.com/CaptainProton42/FlexibleToonShaderGD) — CaptainProton42 | MIT |
| Água estilizada, campo de força, dissolve/erosão de partículas | [godot-shaders](https://github.com/gdquest-demos/godot-shaders) — GDQuest | MIT (código) |
| Normais triplanares "UDN" / whiteout | Ben Golus — *Normal Mapping for a Triplanar Shader* (artigo) | — (técnica) |

Nenhum arquivo de código desses projetos foi copiado: as ideias foram reimplementadas
nos shaders da suíte. Os avisos de licença MIT abaixo cobrem os assets MIT redistribuídos
(`sandstone_*`) e reconhecem os projetos cujas técnicas serviram de referência.

## MIT License (godot-demo-projects, Terrain3D, GodotGrass, FlexibleToonShaderGD, godot-shaders)

```
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## CC0 1.0 Universal (ambientCG e texturas procedurais)

Dedicado ao domínio público — <https://creativecommons.org/publicdomain/zero/1.0/>.
