# Chamado Urgente!

Jogo cooperativo de **suporte técnico** em Three.js, no espírito de *Overcooked* / *Moving Out*:
você e seus colegas são o time de TI do escritório e precisam atender os chamados antes de estourar o **SLA**.

![gameplay](docs/gameplay.jpg)

## Rodar

```bash
cd games/chamado-urgente
npm install
npm run dev        # abre em http://localhost:5173
```

`npm run build` gera a versão estática em `dist/` (dá para hospedar em qualquer lugar).

## Como jogar (1 a 4 técnicos, coop local)

No menu, cada dispositivo entra apertando o botão de pegar; **Espaço**/**Start** começa.

| | Mover | Pegar/soltar | Consertar · borrifar · arremessar | Correr (empurra colegas!) |
|---|---|---|---|---|
| Teclado 1 | WASD | E | F (segurar) | Shift esq. |
| Teclado 2 | Setas | Enter | Shift dir. | Ctrl dir. |
| Controle | analógico | A | X / RT | B / RB |

**Esc** pausa · **M** liga/desliga a música.

### Chamados do cenário 1 (7º andar — Contabilidade)

| Chamado | O que fazer |
|---|---|
| Cabo de rede partido | pegar cabo na **Sala de TI** e segurar F na mesa |
| Vírus no computador | levar o **pendrive antivírus** da bancada e escanear — se demorar, **espalha para o PC vizinho** |
| Impressora sem papel | buscar **resma** no **Almoxarifado** |
| Impressora emperrada | segurar F (dois técnicos juntos = 2x mais rápido) |
| Impressora pegando fogo | pegar um **extintor** e borrifar de longe |
| Internet caiu | reiniciar o **rack** — enquanto estiver fora, o SLA de todos os chamados corre 1,6x mais rápido |

Extras: **chamados VIP** do diretor (SLA menor, vale 1,5x), **combo** por chamados seguidos,
**café** dá velocidade por 10 s, itens podem ser **arremessados** e o colega pega no ar.
Expediente de 3 min (09:00 → 18:00), metas de 1 a 3 estrelas ajustadas ao tamanho da equipe.

## Código

| Arquivo | Conteúdo |
|---|---|
| `src/config.js` | **balanceamento**: SLA, tempo de conserto, recompensa, ritmo dos chamados, metas |
| `src/level.js` | montagem do cenário (paredes, salas, mesas, estações) |
| `src/stations.js` | mesas, impressoras, rack, prateleiras, café e os visuais de cada problema |
| `src/tickets.js` | geração de chamados, SLA, vírus espalhando, internet fora |
| `src/player.js` · `src/items.js` | técnicos (movimento, dash, interação) e itens (física, arremesso) |
| `src/models.js` · `src/textures.js` · `src/fx.js` | modelos procedurais, texturas em canvas, partículas |
| `src/ui.js` · `src/icons.js` · `src/audio.js` | HUD/marcadores, ícones SVG, sons e música sintetizados |

Tudo é procedural (sem arquivos de modelo/áudio externos).

## Testes

```bash
npm run build && npx vite preview --port 4173 &
npm test           # menu → entrar 2 jogadores → cabo → fogo → arremesso → vírus/internet → relatório
```
