# Ylvaar — A Última Hora

Design final do mundo (síntese de "Ylvaar, o Mar de Maré de Areia" e "Aurelith — As Horas de Vael",
com os cortes de MVP e as correções dos jurados).

## Premissa
Ylvaar é um mar de areia viva que corria como maré, regido pela **Agulha de Vael**: um relógio de sol
gigante, inclinado para o sol, cuja sombra girava as horas do mundo. Os **Silentes** — poeira que ganhou
forma onde a areia parou — arrancaram as três **Pedras das Horas** e o tempo congelou uma hora antes do
pôr do sol. Saeli e Hulvar acordam na Proa, a duna mais alta, quando a primeira brisa volta.
Devolvam as três pedras à Agulha e deixem o sol, enfim, se pôr.

Subtítulo da UI: **"A Última Hora"**.

## Princípio de fluxo
**Sobe pelo vento e pela pedra, desce pela areia.** A bacia central é o ponto mais baixo; as três zonas
são elevadas. Urnas-canhão na borda da bacia lançam a dupla em direção às zonas; de cada zona se volta
surfando (ou pelo trilho de areia do cânion).

## Zonas (mapa jogável ~800 m; x leste, z sul; sol baixo a noroeste)
| zona | centro | altura | terreno | marcos | mecânica |
|---|---|---|---|---|---|
| **A Proa** (partida) | (70, 300) | 52 m | duna-estrela alta, terraço plano | Pedra-Guia, vista da Agulha contra o sol | tutorial: andar, pular, planar; **Primeira Descida** surfando até a bacia |
| **O Berço** (hub) | (0, 0) | fundo -18 m | bacia-funil r 120 com paredes surfáveis 18-28° | **Agulha de Vael** (lâmina de 130 m inclinada para o sol), **Portão de Vael** com 3 encaixes | 3 urnas-canhão na borda (uma por zona); final |
| **Tolvaren** (colosso adormecido) | (-250, -20) | corcunda 34 m | montes (costas) + crista do braço apontando para o Berço | cabeça-gaiola com olho de brasa, mão aberta na areia | **Balança de Tolvaren**: placa pesada na palma + placa leve no ombro → a gaiola abre |
| **Véu de Saryth** (mesa das cascatas) | (-120, -265) | topo 48 m | platô com penhascos de arenito voltados para o Berço | 4 cascatas de areia contra o sol, colunata | respiros de vento (Saeli plana para cima), urna pesada (Hulvar), **arena de 5 Silentes** → relíquia; volta pelo cânion com trilho de areia |
| **Kesrin** (cratera de vidro) | (250, -40) | borda 16 m, fundo -6 m | cratera de areia vitrificada (lilás) | monólitos de cristal, geodo | **Fendas** até uma plataforma de cristal + 2 placas (pesada + leve) → o geodo abre |
| **Dunas de Oruun** | (-190, 220) e (200, -290) | — | campos de dunas gigantes (λ 200 m) | ossos de um leviatã (COULD) | surfe livre, trilhas de centelhas nas cristas |

## Caminho principal
Proa → Primeira Descida (surfe) → Berço → (qualquer ordem) Tolvaren / Saryth / Kesrin → volta surfando
→ Portão de Vael com as 3 pedras → final.

## Quebra-cabeças co-op (só tipos existentes)
1. **Balança de Tolvaren** — `plates` grupo `tolvaren`: pesada na palma (só o Hulvar desce), leve no
   ombro (a Saeli chega por respiro/trilho do braço). `gates` grupo `tolvaren` = gaiola da cabeça → relíquia.
2. **Véu de Saryth** — `updrafts` na face do penhasco (a Saeli plana até o topo), `launchers` na base
   (urna pesada; o Hulvar também sobe, e pode lançar a Saeli), `enemies` com `arena: "saryth"` no topo;
   vencer os 5 revela a relíquia. Descida: `rails` (correnteza de areia) pelo cânion até o Berço.
3. **Olho de Kesrin** — `rifts` em cadeia da borda até a plataforma de cristal; `plates` grupo `kesrin`
   (pesada no fundo da cratera, leve na plataforma); `gates` = geodo → relíquia.

## Progressão das horas (enxerto)
Cada pedra devolvida… (no MVP: cada pedra COLETADA) avança o sol uma hora: elevação 22° → 17° → 13° e
luz dourada → rosa → violeta (sol, céu, névoa e areia). O final leva ao crepúsculo/noite com a areia
brilhando como céu estrelado.

## Final — "A Última Hora"
As 3 pedras se encaixam no Portão de Vael; a costura dourada da Agulha acende; o sol finalmente se move
(time-lapse de ~10 s), uma onda de brilho atravessa as dunas, a noite cai, câmera orbitando; tela de fim.
Sem escalar a Agulha e sem feixe de luz vertical (nada de "montanha com luz").

## Inimigo
**Silentes**: diabretes de vidro escuro em forma de ampulheta, um olho âmbar, ~1 m (IA de vagar/perseguir
existente). Vencidos por pisão, Rodopio, Aríete ou Barrigada; viram brilho e centelhas.

## Props (prioridade)
MUST: agulha (lâmina-relógio), portao_vael, pedra_guia (checkpoint), urna (canhão), tambor (trampolim de
bronze), placa / placa_pesada, portao (porta de pedra com glifo), cabeca_colosso, mao_colosso, cristal
(2 variantes), geodo, pilar/arco de ruína, rochas de arenito (2), pedra_hora (relíquia: gema facetada,
SEM anéis cruzados — evitar a esfera armilar), silente (inimigo).
SHOULD: colunata da mesa, respiro (anel de pedra). COULD: ossos do leviatã, casco naufragado.

## Coletáveis
**Centelhas** (~250) em linhas, arcos e círculos ao longo das linhas de surfe e dos saltos.
