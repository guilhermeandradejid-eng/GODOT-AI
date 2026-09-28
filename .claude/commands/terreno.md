---
description: Edita o terreno (esculpir, carimbar formas, rios/estradas, erosão, pintura de camadas)
argument-hint: <o que mudar no terreno, ex. "uma montanha alta ao norte e um rio até o lago">
---
Edite o terreno da cena atual com a Vibe Suite: "$ARGUMENTS"

- Comece com `python3 tools/vibe.py terrain.info` e um `screenshot view=aerial` (abra a imagem).
- Use âncoras (`north`, `peak`, `valley`, `flat`, `beach`...) ou `terrain.height_at` para achar posições.
- Ferramentas: `terrain.stamp` (mountain/hill/crater/volcano/lake/plateau/pit), `terrain.sculpt`
  (raise/lower/smooth/flatten/set/noise/terrace; `points` para traços), `terrain.carve_path`
  (river/road), `terrain.flatten_area`, `terrain.erode`, `terrain.paint`/`terrain.auto_paint`,
  `terrain.palette`, `terrain.water`. Veja `python3 tools/vibe.py help <comando>`.
- Depois de cada mudança relevante, `screenshot` e confira. Se houver grama, rode `grass.fill`
  de novo quando o relevo mudar muito.
