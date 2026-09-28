---
description: Cria ou transforma o mundo 3D a partir de uma descrição (terreno, grama, VFX, céu, estilo)
argument-hint: <descrição do mundo, ex. "vale nevado ao amanhecer com um rio e fogueiras">
---
Crie/transforme o mundo da cena atual do Godot com a Vibe Suite a partir desta descrição:

"$ARGUMENTS"

Passos:
1. `python3 tools/vibe.py status` para ver a cena alvo e o que já existe.
2. Veja como a descrição é interpretada: `python3 tools/vibe.py vibe "<descrição>" apply=false`.
   Se faltar algo (feições, grama, efeitos, estilo, horário), monte uma receita completa
   (veja `recipes/*.json`) e aplique com `world.build` (`--args '{"recipe": {...}}'` ou um arquivo);
   se estiver bom, aplique com `vibe "<descrição>"`.
3. Tire `screenshot view=hero` e `screenshot view=aerial`, abra os PNGs e avalie com olhar crítico
   (composição, cores, iluminação, escala, artefatos).
4. Refine com comandos pontuais (`terrain.*`, `grass.*`, `vfx.*`, `env.set`, `style.set`) até ficar
   bonito — sempre conferindo com novos screenshots.
5. Resuma o que foi criado e os comandos-chave usados (para o usuário poder repetir).
