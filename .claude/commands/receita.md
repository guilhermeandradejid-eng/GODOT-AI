---
description: Constrói um mundo a partir de uma receita JSON (recipes/) ou cria uma nova receita
argument-hint: <nome da receita em recipes/ ou descrição de uma nova>
---
Receita: "$ARGUMENTS"

- Se existir `recipes/<nome>.json`: `python3 tools/vibe.py world.build path=res://recipes/<nome>.json`,
  depois `screenshot view=hero` e avalie.
- Se for uma descrição nova: escreva `recipes/<nome_curto>.json` seguindo o formato das receitas
  existentes (scene, style, environment, terrain + features, grass, vfx, camera, commands), construa,
  confira com screenshots e itere no arquivo até ficar bom.
- Para virar demo navegável: adicione o nome em `ORDER` de `tools/build_demos.py` e rode
  `python3 tools/build_demos.py <nome>`.
