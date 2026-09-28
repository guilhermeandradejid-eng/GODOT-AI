---
description: Renderiza a cena e analisa o resultado visual
argument-hint: [hero|aerial|ground|top|camera|<nome de nó>]
---
Renderize a cena atual e analise: `python3 tools/vibe.py screenshot view=<vista>` — use a vista
"$ARGUMENTS" (padrão `hero`; se for o nome de um nó, use `target=<nome>`).

Abra o PNG retornado com a ferramenta de leitura de imagens e descreva objetivamente: composição,
iluminação, cores, escala, artefatos (bordas, ladrilhamento, efeitos estranhos). Sugira (ou aplique,
se o usuário pediu) os comandos que corrigem cada problema.
