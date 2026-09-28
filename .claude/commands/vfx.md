---
description: Adiciona, ajusta ou cria efeitos visuais (fogo, magia, clima, água, impactos)
argument-hint: <pedido, ex. "fogueiras azuis em volta do portal e chuva leve">
---
Trabalhe nos efeitos visuais da cena atual com a Vibe Suite: "$ARGUMENTS"

- `python3 tools/vibe.py vfx.list` mostra a biblioteca (fogo, fumaça, magia, clima, água, impactos).
- Criar: `vfx.spawn preset=<nome> position=<[x,z]|âncora> color=<cor> scale=<n> intensity=<n> name=<Nome>`.
- Ajustar: `vfx.set name=<Nome> ...`; remover: `vfx.remove name=<Nome>`; reiniciar one-shots: `vfx.play`.
- Efeito novo: `vfx.describe preset=<base>` → edite o JSON → `vfx.define name=<novo> based_on=<base> definition={...}`.
- Clima e céu: `env.set preset=<day|sunset|dawn|night|overcast|foggy|stormy|alien>` + ajustes finos.
- Veja o efeito de perto: `screenshot target=<Nome>` (abra a imagem) e ajuste até ficar convincente.
