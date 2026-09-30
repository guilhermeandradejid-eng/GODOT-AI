---
description: Espalha árvores, arbustos, rochas e props pelo terreno (florestas, pinheiros, palmeiras, cactos, cristais...)
argument-hint: <pedido, ex. "floresta de pinheiros nas encostas e rochas perto do rio">
---
Trabalhe na vegetação e nos props da cena atual com a Vibe Suite (vibe_scatter): "$ARGUMENTS"

- `python3 tools/vibe.py scatter.list` mostra os presets (forest, autumn, pines, palms, jungle, birches,
  acacias, dead_trees, bushes, ferns, cacti, rocks, boulders, mushrooms, crystals, logs, alien_trees),
  a vegetação padrão de cada paleta e as camadas já existentes.
- Rápido: `scatter.auto` coloca a vegetação natural da paleta do terreno.
- Controle: `scatter.add preset=<nome> density=<0.2..2> rules={"max_slope": 30, "max_height_frac": 0.6,
  "cluster": 0.5, "min_above_water": 1, "clearing": 8}` e cores com `colors={"leaves": ["#c33", "#e83"]}`.
- Clareiras e caminhos: `scatter.paint name=<Camada> position=<[x,z]|âncora> radius=15 erase=true`.
  Efeitos e personagens já ganham uma clareira em volta ao construir a camada.
- Ajustes: `scatter.set name=<Camada> ...`, remover: `scatter.clear name=<Camada>` (ou `all=true`).
- Confira com `screenshot view=hero` e `view=aerial` (abra os PNGs): densidade, escala, onde cresce.
