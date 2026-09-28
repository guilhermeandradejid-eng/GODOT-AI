---
description: Troca o estilo de arte da cena (realistic, stylized, toon, cel, lowpoly) e compara
argument-hint: <estilo ou "comparar">
---
Estilo pedido: "$ARGUMENTS"

- Estilos: `realistic` (texturas PBR), `stylized` (pintado), `toon`, `cel` (anime, 2 tons), `lowpoly` (facetado).
- Se for "comparar": para cada estilo rode `style.set` + `screenshot view=hero path=res://.vibe/screenshots/estilo_<nome>.png`,
  abra as imagens e recomende o melhor para a cena. Depois volte ao estilo escolhido.
- Caso contrário: `python3 tools/vibe.py style.set style=<estilo>`, `screenshot view=hero`, avalie e,
  se necessário, ajuste `env.set` (horário/névoa) para combinar com o estilo.
