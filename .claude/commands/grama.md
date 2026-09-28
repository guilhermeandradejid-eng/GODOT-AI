---
description: Adiciona ou ajusta grama, flores, trigo e vegetação rasteira
argument-hint: <pedido, ex. "flores só perto do lago e capim alto nas colinas">
---
Ajuste a vegetação da cena atual com a Vibe Suite: "$ARGUMENTS"

- `python3 tools/vibe.py status` para ver as camadas de grama existentes.
- Nova camada: `grass.create preset=<meadow|lush|tall|dry|flowers|wheat|tundra|savanna|reeds|alien> name=<Nome>`.
- Distribuição: `grass.fill grass=<Nome> density=.. min_height=.. max_height=.. max_slope=.. layer=.. patchiness=..`
  ou pincel `grass.paint grass=<Nome> position=.. radius=.. density=..` / `erase=true` (use `points` para faixas).
- Aparência: `grass.set grass=<Nome> color_base=.. color_tip=.. blade_height=.. wind_strength=.. view_distance=..`.
- Confira com `screenshot view=hero` e `screenshot view=ground` (abra as imagens).
