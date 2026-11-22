# Referências e bíblia de arte — Valebrisa

Pesquisa feita para orientar a direção de arte e o design de combate. A regra geral: **parecer feito à mão**
— decisões de cor, forma e ritmo intencionais, nada de "3D genérico com filtro".

## 1. Jogo-base: *Secrets of Grindea* (Pixel Ferrets)

- Ação em tempo real com vista de cima, combos curtos, **golpes carregados** e magias com níveis de carga.
  O próprio dev descreve que cada habilidade começa com 2 níveis de carga e ganha mais com pontos
  ([devlog oficial](https://www.secretsofgrindea.com/?p=890)).
- Chefes com padrões que dão uma **janela de reação** clara; jogadores reclamam quando o aviso não é legível
  ([comentários no itch.io](https://itch.io/post/9617430)).
- **O que levamos**: combo de 3 golpes com avanço, giro carregado (segurar ataque), rolamento com
  invulnerabilidade, magia que custa energia, chefe em padrões alternados com avisos que **enchem até o impacto**
  e uma janela de punição (atordoado após a pancada). Inimigos comuns também telegrafam (gosma treme, fungão
  infla, besouro mostra a faixa da investida).

## 2. "Pixel art 3D" (t3ssel8r e seguidores)

- Contornos procedurais **perfeitos em pixel**, com brilho só nas **arestas convexas**
  ([David Holland, "3D pixel art rendering"](https://davidholland.netlify.app/articles/3d-pixel-art-rendering)).
- **Câmera presa ao grid** para os pixels não "nadarem"; o tranco do snap é compensado por um deslocamento
  suave na ampliação ([artigo *Texel Splatting*, 2026](https://arxiv.org/html/2603.14587v1)).
- Grama em tufos iluminados como o chão; um cuidado conhecido é **não contornar a grama**, senão cada tufo
  ganha borda ([mesmo artigo do David Holland](https://davidholland.netlify.app/articles/3d-pixel-art-rendering)).
- Outras leituras: [Blender Studio — 3D pixel art](https://studio.blender.org/blog/3d-pixel-art-in-blender),
  [80.lv — animação convincente em 3D pixel art](https://80.lv/articles/tips-on-convincing-animations-for-3d-pixel-art-games),
  [Smartly Dressed Games — Pixel Graphics Experiment](https://blog.smartlydressedgames.com/2020/04/20/pixel-graphics-01/).
- **O que levamos**: resolução interna ~300 px, contorno na cor do próprio objeto (escurecida e esfriada),
  brilho de aresta, grama e efeitos fora do passe de contorno, poses a 12 quadros/s e direção em 8 lados.

## 3. JRPG "diorama": HD-2D (*Octopath Traveler*, *Triangle Strategy*, *Live A Live*)

- A sensação de maquete vem de luz dinâmica, sombras e pós-processamento sobre um mundo 3D com sprites
  ([HD-2D na Wikipédia](https://en.wikipedia.org/wiki/HD-2D);
  [Unreal — entrevista Octopath Traveler II](https://www.unrealengine.com/en-US/developer-interviews/octopath-traveler-ii-builds-a-bigger-bolder-world-in-its-stunning-hd-2d-style)).
- **O que levamos**: luz de fim de tarde com sombras duras, vinheta em degraus, partículas ambientes (pólen,
  folhas, fumaça de chaminé, vagalumes), lampiões quentes e sombras de nuvens — mundo pequeno, denso e "vivo".
  Não usamos tilt-shift/desfoque: brigaria com a leitura em pixel.

## 4. Cor: hue shifting e paleta curta

- Rampas de cor que mudam de **matiz**, não só de brilho; sombras mais frias/azuladas e luzes mais quentes
  ([Gamedev.net — Color Palettes](https://www.gamedev.net/articles/visual-arts/color-palettes-r4964/);
  [Pixel Grimoire #6](https://medium.com/pixel-grimoire/how-to-start-making-pixel-art-6-a74f562a4056);
  [Lospec — paletas com hue shift](https://lospec.com/palette-list/tag/hue%20shift)).
- Paletas restritas guiam o olhar (ex.: tons contidos com destaques estratégicos)
  ([itch.io — escolhendo a paleta](https://itch.io/blog/1039646/picking-the-perfect-color-palette-for-your-game)).
- **O que levamos**: 3 faixas por material — sombra = cor × (0,56; 0,60; 0,86) + lilás, meio = hex exato,
  luz = cor × (1,10; 1,07; 0,94) + amarelo. Gestão de cor desligada para o hex escolhido aparecer tal qual.

## 5. Indie 2D de referência (linguagem, não cópia)

| Jogo | O que observar |
|---|---|
| *Secrets of Grindea* | escala chibi, ritmo de combate, telegrafia de chefes, humor nos NPCs |
| *CrossCode* | vista isométrica 16-bit, leitura de altura dos penhascos, interface limpa |
| *Eastward* | densidade de detalhes em vilas, luz quente, objetos com personalidade |
| *Sea of Stars* | luz dinâmica sobre pixel art, cores saturadas mas controladas |
| *Hyper Light Drifter* / *Tunic* / *Death's Door* | silhuetas fortes, paleta curta, avisos de ataque claros |
| *Stardew Valley* / *Moonlighter* | vila acolhedora, rotina dos NPCs, loop de loja e masmorra |

## 6. Regras práticas usadas no projeto

1. Toda cor nova entra como hex pensado para a faixa "meio"; conferir a sombra (lilás) e a luz (amarela).
2. Silhueta primeiro: personagens com cabeça grande e cores de contraste com a grama (gosmas azuis/rosa, não verdes).
3. Detalhe só onde o olho vai: telhados com fileiras de telha, floreiras, varal, poço; o resto é forma simples.
4. Nada de borda preta pura; contorno é a própria cor escurecida.
5. Todo ataque inimigo tem aviso legível ≥ 0,45 s e uma janela de punição depois.
6. Movimento suave, pose em degraus (12 fps); números e efeitos em pixels inteiros.
