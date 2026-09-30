---
description: Cria personagens e gera animações a partir de texto (andar, dançar, lutar, sentar, acenar...)
argument-hint: <pedido, ex. "um cavaleiro acena e depois dança perto da fogueira">
---
Crie personagens e animações por texto na cena atual com a Vibe Suite (vibe_motion): "$ARGUMENTS"

1. `python3 tools/vibe.py motion.list` mostra as ações entendidas (andar, correr, pular, dançar,
   acenar, sentar, meditar, chutar, golpe de espada, feitiço, reverência...), humores, estilos e
   roupas (casual, adventurer, athlete, ninja, robot, soldier, knight, wizard, zombie, astronaut, king).
2. Veja como o texto será entendido: `motion.describe text="anda devagar, acena duas vezes e depois senta triste"`.
   Entende PT/EN, sequências ("e depois", "then"), sobreposição ("anda enquanto acena"), contagens,
   durações, velocidade, lado e direção.
3. Personagem + animação: `motion.character outfit=<roupa> name=<Nome> position=<[x,z]|âncora|near:<nó>>
   facing=<graus|posição|camera> text="<ação>"`. Para outro personagem existente:
   `motion.generate character=<Nome> text="<ação>"` (salva em `res://animations/<nome>.res`).
4. Confira o movimento: `motion.render character=<Nome> animation=<nome> mode=sheet` (ou `trail`) e
   abra o PNG. Na cena: `motion.play character=<Nome> fraction=0.5` congela a pose e
   `screenshot target=<Nome>` mostra de perto. Volte a animar com `motion.play character=<Nome> time=-1`.
5. Opcional: `motion.backend url=http://127.0.0.1:8090` usa o servidor Kimodo (kimodo.cpp) para gerar
   movimento por IA; `motion.import path=res://mocap/pulo.bvh character=<Nome>` traz mocap (BVH/glTF/FBX).
6. Resuma os personagens, animações e comandos usados.
