# Ylvaar — Itens, Ferramentas e Quebra-cabeças

Este é o design final dos itens do **Sael**. Ele junta dois designs que foram avaliados: "Quebra-cabeça + Co-op"
(design **A**) e "Game-feel + Travessia" (design **B**). O escopo é de MVP:

- **4 itens**;
- **8 tipos de elemento** de quebra-cabeça;
- **1 tutorial de item** (A Proa);
- **1 quebra-cabeça por zona**: Berço, Tolvaren, Véu de Saryth e Kesrin.

Todas as coordenadas foram conferidas com `measure.py`, `place.py` e `linecheck.py`. Os pontos de interação
ficam em chão com inclinação abaixo de 12°, sem colidir com props, e as linhas de corda e de cabo estão livres.
O script de verificação está em
`/tmp/claude-0/-home-user-GODOT-AI/bf279d27-9655-57b3-af78-106934686db9/scratchpad/items_design/verify_final.py`.

---

## 0. Julgamento e síntese

| critério (1–10) | A · Quebra-cabeça + Co-op | B · Game-feel + Travessia | **Síntese** |
|---|---|---|---|
| Diversão | 8 | 9 | 9 |
| Clareza no celular | 5 | 8 | 8 |
| Valor co-op | 9 | 5 | 9 |
| Encaixe no mundo | 8 | 8 | 9 |
| Risco de implementação (10 = baixo) | 4 | 5 | 6 |
| **Total** | **34** | **35** | **41** |

**A — pontos fortes**
- Cadeia ao estilo Zelda: cada zona dá um item e cobra os anteriores.
- Combos entre itens: Lançar a Luz, Eco, Lufada.
- Toda zona tem um momento de dupla.
- Descobriu que a **Balança de Tolvaren não tem solução no solo**. A IA só procura placa a até 18 m (`_find_plate`) e
  se teleporta para o líder quando passa de 42 m, mas as duas placas ficam a 145 m uma da outra.

**A — pontos fracos**
- São 6 verbos de arpéu, mais o Reboque (regra escondida), 3 chips, um gesto de deslizar e o USAR do Hulvar (Âncora). É regra
  contextual demais para uma tela de celular.
- O hit-stop usa `Engine.time_scale`, o que congela o parceiro e dessincroniza a rede.
- O atalho `L` para a Lanterna conflita com o `L` que gira a câmera no kb1 quando o kb2 está ativo (`poll_look`).
- O "platô de Kesrin a 8,7 m" na verdade fica a **12,1 m** do fundo (6,07 contra -6,0). Além disso, dá para chegar
  nele andando pela parede norte, então a tirolesa não é uma trava de verdade.
- A relíquia no nicho do penhasco: a borda bloqueia a linha de visão (B mediu 0,67 m).

**B — pontos fortes**
- Sensação de jogo: cadeia de balanço simulada, carona de planeio, Ricochete e passos de 30 s.
- USAR contextual: o arpéu vence quando há alvo destacado.
- Travas que entram no grupo `plates`, então o `StoneGate` não muda.
- Aviso em cada trava.
- Relíquia de Saryth puxada do topo do Véu, com linha de visão verificada.
- Hit-stop local, seguro para a rede.

**B — pontos fracos**
- Mantém a Balança de 145 m: sem solução no solo e ruim para a câmera compartilhada no co-op local.
- Muitas peças novas: blindado, Clarão, respiro adormecido, emboscada, crosta, latch e véu.
- O fim do cabo, em (276,-15.29), fica sobre uma beirada de 23,8° com chão a -2,6 m.
- A linha até os olhos de Tolvaren passa pela AABB da cabeça. É preciso excluir o colisor do próprio prop.

**Síntese.** O núcleo é a progressão e o co-op do A, com a interface, a sensação de jogo e a arquitetura de travas do B.

| | |
|---|---|
| **Fica** | USAR contextual (o arpéu vence); a Lanterna vira um *estado* com um chip próprio (zero troca de ferramenta); números do balanço, da carona de planeio, do combo, do hit-stop local e do Ricochete vindos do B; Embarque Relâmpago (o arpéu no Hulvar); Lançar a Luz; Reboque como regra existente ("o Sael no cesto é pesado", `is_heavy()`); Eco como **sino** de duas mãos; Silentes velados; véu + relíquia puxada; correções de IA no solo (Segurar Posto, placa única, sinos, busca de placas em 40 m) |
| **Sai** | Âncora e tirolesa ancorada; Clarão; respiro adormecido; Silente blindado; emboscada; Crosta (o Eco virou sino); TACADA/Martelo; quarto float no pacote; troca de ferramenta |

---

## 1. Visão geral

| item | onde | botão | verbos |
|---|---|---|---|
| **Arpéu de Rumo** | A Proa (grátis, 1º item) | **USAR** (contextual) | argola de balanço, argola de puxar-se, puxar (relíquia, Silente, aro pesado do cesto), Embarque Relâmpago no Hulvar, Cabo de Vidro; com a lanterna acesa, **Lançar a Luz** |
| **Bastão de Quilha** | O Berço (Sinos Gêmeos) | **AÇÃO** (melhora o Rodopio) | combo de 3 golpes, Rodopio de bastão, **Ricochete** (pogo), sinos `staff` |
| **Lanterna de Brasa** | Tolvaren (palma do colosso) | **chip da Lanterna** (liga/desliga) | expõe Silentes velados, acende Olhos de Brasa, faz o Cristal-Eco ressoar; **Farol** no cesto |
| **Concha dos Ventos** | Véu de Saryth (arena) | **USAR** (quando não há alvo de arpéu) | rajada (empurra Silentes, desfaz Dunas-tampão, abre o Véu de areia); no ar, **Lufada** |

Regra de ouro na tela: o **USAR faz uma ação** (arpéu ou concha), o **chip liga um estado** (lanterna) e o
**bastão vive na AÇÃO**. Nunca é preciso trocar de ferramenta.

---

## 2. Itens

Constantes do herói usadas nas contas (`hero.gd` CONFIG agile):

| constante | valor |
|---|---|
| velocidade | 8,2 m/s |
| gravidade | 30 (×1,6 na queda) |
| pulo / pulo duplo | 11,6 / 10,4 |
| planeio | -2,3 m/s de queda, 9,2 m/s de velocidade |
| Rodopio | r 1,45 |
| Barrigada do Hulvar | onda de 3,4 m e golpe de 2,2 m |

Alturas do Sael: pulo 2,2 m; com o pulo duplo, 4,2 m.

### 2.1 Arpéu de Rumo (`arpeu`)

**Fantasia.** Um arpéu de latão de três garras num rolo de corda de vela trançada, achado no toco de mastro da Proa.
A corda acende em ciano quando há um alvo ao alcance: é o mesmo brilho do Glifo de Rumo do Hulvar. "O rumo puxa a vela."
Fica guardado no cinto direito (`belt_R`).

**Mira (comum a todos os verbos)**

| parâmetro | valor |
|---|---|
| Cone de mira (meia-abertura) | 45° no teclado e no controle; **60° no toque** |
| Centro do cone | direção do analógico (ou da câmera, se o analógico estiver abaixo de 0,2) |
| Elevação | argolas e cabo: 15° a 85°; puxar, Hulvar e braseiro: -30° a 85° |
| Linha de visão | raio do peito (y +0,6) na `LAYER_WORLD`. Bater a até 0,6 m do alvo conta como livre. O colisor do **prop anfitrião** do alvo (cabeça do colosso, geodo) é excluído |
| Pontuação | `ângulo/meia_abertura + 0,6·dist/alcance − bônus`. Bônus: argola `chain_next` da argola atual 0,4; alvo na direção da velocidade 0,2 |
| Classes de prioridade | argola > aro de puxar ou braseiro > relíquia > Hulvar > Silente |
| Trava "grudenta" | troca de alvo só se outro tiver pontuação 0,15 melhor, ou se o atual sair do cone por mais de 0,25 s |
| Buffer de USAR | 0,20 s (o toque vale se um alvo ficar válido logo depois) |
| Pré-destaque no ar | argola que vai ficar válida em ≤ 0,25 s pela velocidade atual |

**Arremesso**
- Clipe `grapple_throw` de 0,18 s. O gancho visual voa a 60 m/s e prende em `max(0,08, d/60)` s.
- No ar, durante o arremesso: gravidade ×0,5 e a velocidade horizontal se mantém.
- **Sem alvo:** arremesso vazio de 8 m à frente, que volta em 0,35 s.
- Recarga de 0,25 s. É 0 quando se encadeia para a `chain_next`.

**Verbos**

| verbo | alcance | comportamento |
|---|---|---|
| **Balanço** (argola `swing`) | 14 m | Pêndulo plano (modelo `swing3.py`): corda `L = clamp(d, 6, 10)` m, recolhida em 0,15 s; g = 30; velocidade de entrada entre 8 e 22 m/s; ω até ±22/L; o analógico gira o plano em ±35°/s. Solta sozinho a θ = +45° depois do ponto baixo, a menos que USAR esteja segurado (máx. 3,0 s). PULAR solta a qualquer hora. Se colidir (`move_and_collide`), vai para AIR com a velocidade atual |
| Soltura | — | `v × 1,08 + 4,0 m/s` para cima. **Perfeita** (θ entre 35° e 55°): +2,0 m/s ao longo de v, brilho dourado e "ding" que sobe 1 semitom por argola encadeada (máx. +4). Recarrega pulo duplo, Rodopio e Lufada |
| **Puxar-se** (argola `zip`) | **20 m** | Acelera até 24 m/s a 60 m/s² e para a 1,2 m da argola. Pulo final: horizontal ×14 + 9 para cima (ápice ≈ 1,6 m acima da argola). Uma linha de 18 m leva ≈ 0,85 s |
| **Puxar** objeto leve | 12 m | Clipe `pull` de 0,45 s. A relíquia ou o objeto vem até 1,0 m na frente do Sael em 0,4 s (ease-out); a relíquia é coletada na chegada. **Silente:** é arrastado 3 m na direção do Sael e fica atordoado 0,6 s |
| **Reboque** (aro `heavy`) | 12 m | Só funciona se quem puxa for `is_heavy()`, ou seja, **o Sael no cesto do Hulvar** (regra que já existe para as placas). Leva 1,2 s: o Hulvar toca `brace` e recua 0,6 m. Fora do cesto aparece o aviso "Pesado demais... puxe do cesto do Hulvar!" |
| **Embarque Relâmpago** (alvo: o Hulvar) | 4–16 m | Zip a 22 m/s até o osso `nest`; `mount_on()` a menos de 1,0 m. Só vale se o Hulvar estiver em GROUND, SWIM ou SURF e sem passageiro. A IA do Hulvar para por 0,4 s quando é mirada |
| **Cabo de Vidro** (tirolesa) | USAR a até 6 m do poste inicial, ou no ar a até 2,0 m do cabo nos primeiros 70% dele | O Sael fica pendurado com os pés 1,15 m abaixo do cabo (pose `swing` com as pernas recolhidas). Velocidade: começa em `max(entrada, 10)`, ganha `30·sinθ·0,78` por s, perde 4%/s, entre 10 e 19 m/s. Nos últimos 8 m freia até 6 m/s. PULAR solta com v + 4 para cima (pulo duplo recarregado). No fim: `launch(tangente×v + 6 para cima, 0,2)` |
| Pegar argola no **Canhão do Ninho** | — | Em LAUNCH, depois de 0,25 s, o USAR pode prender numa argola: canhão → balanço → planeio |
| **Lançar a Luz** (combo com a Lanterna) | 14 m | Com a lanterna acesa, um Olho de Brasa apagado vira alvo de arpéu. Ao prender, a chama corre pela corda em 0,4 s e acende o olho |

**Carona de planeio** (regra nova, vale para todos os verbos)
- Gatilho: entrar em GLIDE até 1,5 s depois de soltar o arpéu ou o cabo, com velocidade horizontal acima de 9,2 m/s.
- Efeito: o teto do planeio vira essa velocidade e decai 2,5 m/s² até 9,2.
- Ganho: ≈ +18 m de planeio a partir de uma soltura de 18,7 m/s.

**Medido na Proa** (cadeia B2→B3, design B, `swing3.py`):

| entrada no surfe | soltura | duração de cada balanço | folga mínima do chão |
|---|---|---|---|
| 12 / 16 / 20 m/s | 17,5 / 18,7 / 18,7 m/s | 0,73–1,02 s | 2,97 m |

O planeio depois da cadeia chega à bacia do Berço.

### 2.2 Bastão de Quilha (`bastao`)

**Fantasia.** Bastão entalhado na madeira da quilha de um barco de areia, com ponteira de latão. É uma "quilha afinada": canta
quando bate em vidro e cristal. Por isso toca os Sinos de Cristal e racha a casca dos Silentes. Fica nas costas (`back_slot`),
na diagonal sobre a prancha.

**Habilidade.** Assim que o Sael tem o bastão, **AÇÃO no chão vira um combo de 3 golpes**. No ar continua sendo o Rodopio, agora com
o bastão e alcance maior, e acertar algo no ar dá o **Ricochete**.

**Golpes**

| golpe | clipe | quadros ativos | área de acerto | dano | empurrão | avanço | hit-stop | tremida | vibração |
|---|---|---|---|---|---|---|---|---|---|
| `attack_1` (de frente) | 0,32 s | 0,06–0,14 s | esfera r 0,95 a 0,95 m à frente, y +0,55 | 1 | 4,5 + 2,0 para cima | 4,0 m/s por 0,08 s | 0,05 s | 0,06 | 15 ms |
| `attack_2` (revés) | 0,34 s | 0,07–0,15 s | r 1,0 a 1,0 m | 1 | 5,5 + 2,5 | 4,5 m/s | 0,06 s | 0,08 | — |
| `attack_3` (pancada com as duas mãos) | 0,50 s | 0,18–0,24 s | círculo no chão r 1,9 a 1,1 m à frente + anel de cambaleio r 2,4 | **2** | 9,0 + 6,0 | 6,0 m/s por 0,10 s | 0,10 s | 0,22 | 35 ms |

- **Buffer:** o próximo toque vale a partir de 0,10 s do golpe até o fim do clipe + 0,15 s. O combo zera 0,45 s depois do fim.
- **Durante o golpe:** velocidade ×0,30 e giro ×0,5.
- **Mira suave:** ao iniciar um golpe, se houver Silente ou sino a até 3,5 m num cone de 70°, o Sael vira para ele em 0,08 s.
- **Hit-stop LOCAL.** Atacante e vítima pulam a física e o `AnimationTree` vai a velocidade 0. **Nunca** `Engine.time_scale`.
- **Rodopio com bastão:** raio 1,45 → **1,9**, dano 1, uma vez por voo (como hoje).
- **Ricochete:** quando o Rodopio no ar acerta um Silente ou um sino, `vy = 9,5`, `air_jumps = 1` e `air_spin = true`. Encadeia sem limite.
- **Tipos de golpe** enviados em `_attack`: `staff1`, `staff2`, `staff3` e `staff_spin`. Os sinos `staff` aceitam só esses.

### 2.3 Lanterna de Brasa (`lanterna`)

**Fantasia.** Lanterna de vidro âmbar com gaiola de latão. Guarda uma brasa viva que caiu do olho do colosso Tolvaren. É "a hora que
ainda corre": os Silentes, poeira congelada no tempo, racham diante dela. Quanto mais o sol desce, mais ela brilha.
Fica no cinto esquerdo (`belt_L`); acesa, vai para a mão esquerda (`grip_L`).

**Habilidade.** É um **estado** (liga/desliga) e não ocupa as mãos para os outros itens.

**Luz**

| parâmetro | valor |
|---|---|
| Raio de jogo | **7 m** |
| Raio "erguida" | **9 m** (no cesto do Hulvar ou parado por 0,6 s) |
| `OmniLight3D` | `omni_range` = raio + 2 m, energia `1,8 × (1 + 0,6 × horas/3)` (1,8 → 2,16 → 2,52 → 2,88), cor `#FFB45A`, atenuação 1,2, **sem sombra**, cintila ±6% a 3 Hz |
| Consulta | `Game.lantern_pos` + `Game.lantern_radius`. `INF` quando apagada |

**Verbos**
1. **Expor**: Silentes velados dentro do raio ficam vulneráveis (seção 5.7).
2. **Acender**: com a lanterna a até **1,6 m** de um Olho de Brasa por 0,15 s ("a chama pula"), ou de longe com Lançar a Luz (14 m).
3. **Ressoar**: o Cristal-Eco (`dark`) só aceita golpes dentro da luz.
4. **Farol** (co-op): no cesto, a lanterna sobe (raio de 9 m) e o Hulvar vira um farol que anda.

### 2.4 Concha dos Ventos (`concha`)

**Fantasia.** Concha espiral de nácar rosado com bocal de latão. "Lembra o vento da maré": um sopro e o ar parado de Ylvaar
volta a correr.

O nome é Concha, e não "Búzio", porque "búzios" remete a uma prática real de adivinhação.

Fica pendurada por um cordão no cinto esquerdo, na frente da lanterna (`belt_L`, deslocada +0,09 m para a frente).

**Rajada (USAR quando não há alvo de arpéu destacado)**
- Clipe `horn_blow` de 0,6 s. O vento fica ativo de 0,12 a 0,47 s. No chão, o Sael fica parado 0,45 s.
- Cone de **10 m** de comprimento e **25°** de meia-abertura, na direção do analógico ou da câmera.
- Mira automática para o Véu, Duna-tampão ou Silente mais próximo dentro do cone.
- Recarga de **0,9 s**.

**Efeitos**

| alvo | efeito |
|---|---|
| Silente | empurrão de 10 m/s + 2 para cima e atordoamento de 0,8 s, sem dano |
| **Duna-tampão** | some com um sopro (0,8 s de animação) |
| **Véu de areia** | se a linha do topo da cascata estiver a até 10 m: abre por **6,0 s** e fecha em 1,0 s |
| Hulvar dentro do cone | **Vento de Popa**: 3,0 s de velocidade ×1,4 (enfeite de co-op; o Hulvar continua correndo). É barato porque é só um multiplicador em `_horizontal` |

**Lufada (USAR no ar ou planando, sem alvo de arpéu)**
- `vy = max(vy, 9,0)` e +4,0 m/s no teto horizontal ou do planeio, decaindo em 1,2 s.
- Uma vez por voo. Recarrega ao pousar, ao entrar numa corrente de ar, ao soltar o arpéu, no Ricochete ou no trampolim.
- Medido no `glidesim` (planeio a partir de y 50, Lufada aos 0,5 s): +2,8 m de altura relativa e +2,5 m à frente aos 2,0 s;
  numa queda de 10 m, o alcance passa de 37,0 para **50,7 m**.

---

## 3. Controles

### 3.1 Toque (celular, paisagem)

Posições relativas ao canto inferior direito, na escala do `TouchControls._scale()`:

| controle | `BTN` | posição | raio | cor | aparece quando |
|---|---|---|---|---|---|
| PULAR / AÇÃO / DUPLA / TROCAR | (existentes) | (-120,-120) / (-280,-86) / (-236,-236) / (-96,-290) | 74 / 58 / 50 / 40 | — | — |
| **USAR** | `"use"` | **(-392,-196)** | **52** | `Color(0.98, 0.78, 0.36)` | o Sael tem o Arpéu |
| **chip da Lanterna** | `"lamp"` | **(-470,-262)** | **28** | `Color(1.0, 0.71, 0.35)` | o Sael tem a Lanterna |

**Folgas verificadas** (distância entre centros contra 1,15 × soma dos raios):

| par | distância | mínimo |
|---|---|---|
| USAR–AÇÃO | 157 px | 126 |
| USAR–DUPLA | 161 px | 117 |
| USAR–PULAR | 282 px | 145 |
| chip–USAR | 102 px | 92 |
| chip–DUPLA | 235 px | 90 |

Em 960×720, a borda esquerda do chip fica em x = 458, fora da zona do analógico (x < 403).

**USAR (multitoque, rastreado por dedo como os outros botões)**
- Toque = ação contextual.
- Segurar = manter o balanço (até 3,0 s).
- O ícone muda conforme o contexto: losango de latão (alvo de arpéu destacado), concha (se o Sael a tiver) ou arpéu cinza (arremesso vazio).
- Pulsa como o hint do DUPLA quando há um alvo de quebra-cabeça válido a até 10 m.

**Chip da Lanterna:** toque = liga/desliga. Aceso, mostra o halo âmbar. Ele é o "seletor de ferramenta" do MVP: não existe troca de
ferramenta.

**Soprar com um alvo de arpéu à vista:** vire o analógico para longe do alvo. O destaque some e o USAR vira Concha.

**Jogando de Hulvar no solo:** o USAR e o chip continuam visíveis e **mandam o Sael da IA** usar o item (seção 7.2, "Pedido").
No co-op, o jogador do Hulvar não vê esses botões.

### 3.2 Teclado

| ação | kb1 (P1, sempre o Sael) | kb2 (P2 = Hulvar no co-op local) |
|---|---|---|
| USAR | **F** (ou botão lateral do mouse `XBUTTON1`) | — (o Hulvar não tem itens) |
| Lanterna | **G** | — |

O resto não muda: Espaço pula, J/clique = AÇÃO (com bastão = combo), K/E = DUPLA, Tab/Q = TROCAR.
`L` e `H` **não** são usados, porque giram a câmera no kb1 quando o kb2 está ativo.

### 3.3 Controle

- **RB** = USAR. **LB** = Lanterna. **Y** = TROCAR (o **RB deixa de trocar**).
- A pula, X/RT = AÇÃO (combo), B = DUPLA.
- O P2 (Hulvar) não usa RB nem LB.

### 3.4 HUD
- **Retículo:** losango de latão de 24 px projetado no alvo travado (`camera.unproject_position`), com um arco fino de alcance.
  Pisca dourado na janela de soltura perfeita.
- **Faixa de item novo** (4 s): "Você encontrou: Arpéu de Rumo" + 2 linhas de dica. Os dois heróis tocam `celebrate`.
- **Ícones dos itens obtidos** ao lado das Pedras das Horas.
- **Avisos de trava** (`hints`, seção 5.9).

### 3.5 Entrada e rede (`PlayerInput`)

| novo | tipo | flag do pacote |
|---|---|---|
| `use` | bool segurado | 128 |
| `_use_pressed` | press/take/peek | 32 |
| `_lamp_pressed` | press/take/peek | 64 |

O pacote continua com 3 floats; não há índice de ferramenta.

---

## 4. Progressão (trava ao estilo Zelda; nada fica bloqueado para sempre)

1. **A PROA → Arpéu de Rumo** (grátis, no 1º quadro). Tutorial: Puxar-se (B1), cadeia de Balanço (B2→B3) e Embarque Relâmpago.
2. **O BERÇO → Sinos Gêmeos → Bastão de Quilha.** Primeiro golpe sincronizado da dupla. Treino do combo com os 2 Silentes do hub.
3. **TOLVAREN** (urna (-98,46) ou trilho do braço):
   - a **Palma** dá a **Lanterna** (peso do Hulvar);
   - o **Olhar** acende os 2 Olhos de Brasa (Lançar a Luz = Arpéu + Lanterna);
   - o **Reboque** da mandíbula (Arpéu + cesto do Hulvar) dá a **Brasa de Tolvaren** (pedra 1: o sol desce uma hora).
4. **VÉU DE SARYTH** (urna (-44,-102) ou respiro (-84,-188)):
   - a **Névoa do Silêncio** (Silentes velados: Lanterna + Bastão/Hulvar; Farol no cesto) dá a **Concha dos Ventos**;
   - o **Véu Partido** (Concha + Arpéu) dá a **Lágrima de Saryth** (pedra 2).
5. **KESRIN** (urna (104,-20) ou fenda do hub), o calabouço final com os 4 itens:
   - Cabo de Vidro (Arpéu);
   - Duna-tampão (Concha);
   - placas em dupla com trava;
   - **Cristal-Eco** (Lanterna + Bastão + Barrigada do Hulvar), que dá o **Olho de Kesrin** (pedra 3).
6. **Portão de Vael** → final, sem mudanças.

**Travas suaves.** Dá para chegar a qualquer zona antes da hora e **ver** a trava, com o aviso do que falta:
- Silentes velados invulneráveis: "uma luz os revelaria";
- olhos apagados: "Os olhos de Tolvaren estão apagados...";
- duna sobre a placa: "precisa de vento";
- Cristal-Eco: "só ressoa na luz... e com dois golpes".

A Lanterna vem de Tolvaren e é exigida em Saryth. A Concha vem de Saryth e é exigida em Kesrin. O Bastão é exigido em Kesrin.
O Arpéu é exigido em Tolvaren e em Saryth.

**Duração estimada:** Proa 1,5 min · Berço 2 min · Tolvaren 5 min · Saryth 5 min · Kesrin 5 min.
O estado (`Game.items` + travas) **não é salvo** no MVP, como o resto do jogo.

---

## 5. Elementos de quebra-cabeça (8 tipos)

**Regra de grupo única.** Toda trava nova entra no grupo de nós `plates` com:
- `group_id`, `pressed`, `heavy := false` e `occupied_by(h) -> false`;
- `signal changed(pressed)`;
- `is_plate := false`. Só o `PressurePlate` tem `is_plate = true`.

Consequências:
- O `StoneGate` não muda: abre quando **todos** os membros do grupo estão `pressed` ao mesmo tempo.
- Travas novas **ficam travadas** depois de feitas.
- Placas com `"latch": true` travam juntas quando todas as **placas** do grupo descem ao mesmo tempo.
- Itens e relíquias com `group` aparecem quando o grupo fica resolvido (`PuzzleGroups.solved`).

**Atenção.** O `CompanionAI._find_plate` e o `playtest._t_plates` passam a filtrar `is_plate`. Sem isso, a IA andaria até braseiros e sinos.

### 5.1 `items` — Relicário de Ferramenta
- **Comportamento:** pedestal de arenito com o item flutuando. Só o **Sael** pega: o inventário (`Game.items: Array[String]`) é da dupla, mas
  as ferramentas são dele. Se o Hulvar tocar, aparece o aviso "Isso é do Sael!".
- **Ao pegar:**
  - os dois tocam `celebrate` (1,2 s), aparece a faixa e o item é equipado no osso;
  - USAR ou o chip aparecem.
- **Escondido até ser revelado:** com `group`, até o grupo ser resolvido; com `arena`, até a arena ser limpa. Aparece como a relíquia
  (escala elástica 0,8 s), subindo 1,5 m em 1,2 s.
- **Parâmetros:** `{id: arpeu|bastao|lanterna|concha, at: [x,z] | [x,y,z], h = 1.0, group?: string, arena?: string}`. Raio de coleta 1,2 m.
- **Rede:** RPC confiável `_item_taken(id)`.

### 5.2 `hook_rings` — Argola
- **Comportamento:** alvo no grupo de nós `hook_targets`.
  - `mode: "swing"`: âncora de pêndulo.
  - `mode: "zip"`: puxa-se e salta por cima.
  - `mode: "pull"`: aro de puxar preso num objeto. Ao ser puxado, desliza `travel` m e fica `pressed` (trava); é membro do grupo.
    Com `heavy`, exige `is_heavy()` (Reboque). Com `last`, fica apagado e não pode ser mirado até os outros membros do grupo estarem feitos.
  - `chain_next` dá bônus de 0,4 para a próxima argola na mira enquanto se balança.
  - `ai: true`: o Sael da IA pode usar.
- **Parâmetros:** `{id, mode: swing|zip|pull, at: [x,y,z] (absoluta), chain_next?, ai = false, heavy = false, group?, last = false, travel = 0.6}`.
  Alcances: swing 14 m, zip 20 m, pull 12 m.

### 5.3 `ziplines` — Cabo de Vidro
- **Comportamento:** cabo reto entre dois postes que só o Arpéu agarra (seção 2.1). O Hulvar não usa ("O cabo é fino demais para o Hulvar").
  É uma variante do `SandRail`: `hang = 1.15`, `requires = "arpeu"`, freio nos últimos `brake` m.
- **Parâmetros:** `{id, from: [x,z], from_h: altura do cabo no poste inicial, to: [x,z], to_h, min_speed = 10, max_speed = 19, brake = 8}`.

### 5.4 `braziers` — Olho de Brasa
- **Comportamento:** trava acesa pela lanterna:
  - a até 1,6 m por 0,15 s;
  - ou por Lançar a Luz (arpéu com a lanterna acesa, 14 m).

  Fica acesa para sempre (`pressed = true`).
- **Montagem:** `mount: "wall"` registra o colisor do prop mais próximo (até 6 m) como exceção da linha de visão. Os olhos ficam **sobre**
  a cabeça do colosso.
- **Luz:** só emissivo (sem `OmniLight`), para caber no orçamento do celular.
- **Parâmetros:** `{at: [x,y,z], group, mount: "floor" | "wall"}`.

### 5.5 `chimes` — Sino de Cristal (e Cristal-Eco)
- **Comportamento:** recebe `on_attack(center, r, by, kind)` e `on_pound(p, by)`.
  - Cada tipo em `need` é marcado por `window` s.
  - Com todos os tipos de `need` marcados, o sino **toca**: fica `pressed` por `window` s ou, com `latch`, para sempre.
  - Os sinos do grupo **travam** quando o grupo é resolvido.
- **Tipos de golpe:**
  - `"any"`: Rodopio, bastão, Aríete, Barrigada, pisão;
  - `"staff"`: `staff1`, `staff2`, `staff3`, `staff_spin`;
  - `"slam"`: Barrigada a até `slam_radius` (via `pound_listeners`) ou Aríete (`bump`).
- **Variantes:** com `dark`, só aceita golpes enquanto está dentro da luz da lanterna. Com `last`, fica inerte até os outros membros do grupo estarem feitos.
- **Feedback:** se a janela vence sem tocar, nota descendente e brilho apagando.
- **Parâmetros:** `{at: [x,z], group, need = ["any"], window = 1.2, slam_radius = 9.0, dark = false, latch = false, last = false, size = 1.0}`.
  Raio de acerto 1,2 m × `size` (somado ao raio do golpe).

### 5.6 `drifts` — Duna-tampão
- **Comportamento:** domo de areia com colisão por cima de uma placa ou passagem. É uma trava do grupo e cobre a placa de verdade: quem
  está em cima fica 1,2 m acima, e a placa não desce porque `d.y > 0,9`.
- **Concha:** um sopro no cone desfaz o domo em 0,8 s (faixas de areia na direção da rajada). Depois fica `pressed = true` e a colisão sai.
- **Outros golpes:** Rodopio, Barrigada e bastão só levantam poeira, com o aviso "A areia volta a cobrir... precisa de vento".
- **Parâmetros:** `{at: [x,z], group, radius = 1.6, height = 1.2}`.

### 5.7 Silente Velado — flag `enemies[].veiled`
- **Fora da luz:** vulto meio transparente (`dissolve` 0,55, olho apagado).
  - Invulnerável: golpes e pisões fazem "tink" e o herói quica; aparece o aviso "Os Silentes se escondem na névoa... uma luz os revelaria".
  - Não persegue: velocidade ×0,6 e só vaga.
  - O contato ainda machuca.
- **Dentro da luz** (`Game.lantern_pos` a ≤ raio):
  - fica **exposto**: opaco, olho âmbar aceso, persegue normalmente;
  - na 1ª exposição, atordoa 1,2 s e recua a 3 m/s por 0,5 s.
- **PV:**

  | Silente | PV |
  |---|---|
  | comum | 1 (como hoje) |
  | velado exposto | 2 |

- **Dano por golpe:**

  | golpe | dano |
  |---|---|
  | Rodopio | 1 |
  | bastão | 1 / 1 / 2 |
  | pisão | 1 |
  | Aríete | 2 |
  | onda da Barrigada | 2 |

- **Rede:** RPC `_enemy_hit(name, dmg)`.

### 5.8 Véu de Areia — flags `sandfalls[].veil` + `relics[].veil` / `relics[].pull`
- **Cascata:** uma cascata com `veil: true` abre em V a partir do topo por `part_time` s quando recebe uma rajada da Concha a até 10 m do topo.
  Enquanto está aberta, as partículas param.
- **Relíquia:** a relíquia com `veil: <índice>` fica **visível** (silhueta brilhando através da areia), mas **não pode ser pega**: o toque é
  bloqueado e o aviso "Algo brilha dentro do véu de areia..." aparece.
  - Com o véu aberto, vira alvo de **puxar** do arpéu (`pull: true`, 12 m) e também pode ser tocada.
- **Parâmetros:** `sandfalls[i].veil = true`, `part_time = 6.0`; `relics[].veil = i`, `pull = true`.

### 5.9 (UI, não é trava) `hints` — Aviso de trava
- **Comportamento:** um herói dentro de `r` mostra o texto se faltar o item `needs` **e** o `group` (se houver) ainda não estiver resolvido.
  No máximo 1 vez a cada 20 s por aviso.
- **Parâmetros:** `{at: [x,z], r, needs, group?, text}`.

---

## 6. Quebra-cabeças por zona (JSON pronto para `game/world/world.json` → `content`)

As chaves novas (`items`, `hook_rings`, `ziplines`, `braziers`, `chimes`, `drifts`, `hints`) são listas novas em `content`.
As mudanças em entradas existentes aparecem como **"substitui"**, com a entrada antiga citada.
As alturas citadas vêm de `measure.py` (chão / inclinação máxima num raio de 1 m).

### 6.1 A Proa — tutorial: "Primeira Descida com Arpéu" (~1,5 min, opcional e rápido)

1. O **Arpéu** está no toco de mastro em (62,262): chão 51,00, inclinação 0,0°, sem colisão. Fica a 6 m do spawn e a 6 m da Pedra-Guia.
   Aviso ao pegar: "USAR: puxe-se até a argola!".
2. **B1** (`zip`) em (57,5, 61,0, 247), 14,8 m acima da encosta:
   - do pedestal: 18,3 m, dentro do alcance de 20 m, com 31° de elevação;
   - da beira do terraço (60,255): 12,6 m;
   - as duas linhas estão livres (folga ≥ 0,6 m, sem props).

   O Sael sobe, salta por cima, faz o pulo duplo e plana direto para a Primeira Descida.
3. Surfando, **B2 → B3** (`swing`, com `chain_next`) ficam sobre a linha de surfe: é a cadeia medida da seção 2.1.
   Errar só vira surfe normal.
4. **Embarque Relâmpago:** quando o Hulvar fica a mais de 8 m na descida, aparece o aviso "USAR no Hulvar: embarque relâmpago!".

```json
"items": [
  {"id": "arpeu", "at": [62, 262], "h": 1.0}
],
"hook_rings": [
  {"id": "proa_b1", "mode": "zip",   "at": [57.5, 61.0, 247.0], "ai": true},
  {"id": "proa_b2", "mode": "swing", "at": [27.1, 22.9, 150.4], "chain_next": "proa_b3", "ai": true},
  {"id": "proa_b3", "mode": "swing", "at": [20.2, 22.9, 127.4], "ai": true}
]
```

### 6.2 O Berço (hub) — "Sinos Gêmeos" → Bastão de Quilha (~2 min)

Dois Sinos de Cristal `any`, com janela de **1,2 s**, em lados opostos do mostrador da Agulha (disco de r 23,5 em (0,-8)):

| sino | chão | inclinação |
|---|---|---|
| **Leste** (25,0) | -22,04 | 7,8° |
| **Oeste** (-25,0) | -21,76 | 5,5° |

Eles ficam a 50 m um do outro, e a volta ao redor do mostrador leva ≈ 10 s (79 m a 8,2 m/s). Um herói sozinho não consegue: é preciso a dupla.

- **Co-op:** cada um num sino.
  - O Sael usa o Rodopio (ainda não tem o bastão); o Hulvar, o Aríete ou a Barrigada.
  - O primeiro sino tocado brilha 1,2 s (contagem implícita).
- **Solo:** ao chegar a 8 m de um sino, o parceiro da IA vai ao outro (rastro de luz se estiver a mais de 20 m) e mostra o ícone
  "pronto". Ele toca **0,3 s** depois do seu golpe (seção 7.2).
- **Resolvido:** nota em acorde, a costura da Agulha pisca e o **Bastão** surge em (15,13). O chão ali é -22,00 e plano,
  a 8,5 m da borda do Portão de Vael.

Os 2 Silentes que já existem, em (30,-40) e (-40,30), servem de treino do combo ("AÇÃO, AÇÃO, AÇÃO!").

```json
"chimes": [
  {"at": [25, 0],  "group": "berco", "need": ["any"], "window": 1.2},
  {"at": [-25, 0], "group": "berco", "need": ["any"], "window": 1.2}
],
"items": [
  {"id": "bastao", "at": [15, 13], "h": 1.0, "group": "berco"}
],
"hints": [
  {"at": [0, 0], "r": 30, "needs": "bastao", "group": "berco", "text": "Dois sinos, um de cada lado... toquem juntos!"}
]
```

### 6.3 Tolvaren — "A Palma" → Lanterna; "O Olhar de Tolvaren" → Brasa de Tolvaren (~5 min)

**A) A Palma** (borda oeste do Berço)
- A placa pesada que já existe na palma (-98,18), com h 0,82, muda do grupo `tolvaren` para o grupo `palma`.
- Quando o Hulvar pisa nela, os dedos se abrem e a **Lanterna** aparece na palma em (-99,18, 7,61, 20,07). O chão ali é 6,01, a lanterna
  fica 0,8 m acima da palma e a 2,38 m da placa.
- **Solo (de Sael):** espere a até 4 m da placa por 1,0 s e o Hulvar da IA sobe nela (seção 7.2).

**B) O Olhar** (cabeça do colosso, terraço a 27,0 m)
- **Como chegar:**
  - **Sael:** trilho do braço ou respiro (-232,-48);
  - **Hulvar:** urna (-98,46) → corcunda (-232,-16) → descida surfando (28–37°) até o terraço.
- **Mirante** (-247,-57): chão 27,01, inclinação 3,1°.
  - Olhos de Brasa: **esquerdo** (-256,54, 32,28, -59,16) a 10,8 m; **direito** (-254,68, 32,31, -64,20) a 11,5 m.
  - Os dois ficam 5,3 m acima do terraço. O Sael alcança 4,2 m com o pulo duplo, por isso o normal é usar **Lançar a Luz**.
  - O terreno está livre; a linha passa pela AABB da cabeça, por isso o colisor da cabeça é excluído no `mount: "wall"`.
- **Rotas de dupla:**
  - **Mola** (Barrigada do Hulvar perto do Sael: ≈ 6,35 m com pulo duplo e Rodopio). Passe a até 1,6 m de cada olho com a lanterna acesa.
  - **Canhão do Ninho** (≈ 7,3 m).

**C) A Mandíbula** (aro de puxar `heavy` com `last`, em (-252,77, 29,1, -60,68) sobre o portão-gaiola)
- Acende quando os 2 olhos estão acesos.
- **Reboque:**
  1. O Hulvar para no ponto (-246,5, -60): chão 27,00, inclinação 5,4°, a 6,3 m do aro, com linha livre do cesto (y ≈ 28,9).
  2. O Sael, no cesto (DUPLA), aperta USAR. O Hulvar faz `brace` e a gaiola abre.
- **Brasa de Tolvaren:** a relíquia que já existe aparece pelo portão.
- **Solo:**
  - de Sael: embarque no Hulvar perto do aro e aperte USAR;
  - de Hulvar: com o Sael da IA no cesto, o USAR faz o Pedido.

A placa leve do ombro (-238,-22) **sai**. Isso acaba com o racha de 145 m sem solução no solo, e a dupla fica junta na cabeça (boa
para a câmera compartilhada).

```json
"plates": [
  {"at": [-98, 18], "h": 0.82, "group": "palma", "heavy": true}
],
"items": [
  {"id": "lanterna", "at": [-99.18, 7.61, 20.07], "group": "palma"}
],
"braziers": [
  {"at": [-256.54, 32.28, -59.16], "group": "tolvaren", "mount": "wall"},
  {"at": [-254.68, 32.31, -64.2],  "group": "tolvaren", "mount": "wall"}
],
"hook_rings": [
  {"id": "tolv_mandibula", "mode": "pull", "at": [-252.77, 29.1, -60.68], "heavy": true,
   "group": "tolvaren", "last": true, "travel": 0.6}
],
"hints": [
  {"at": [-247, -57], "r": 9, "needs": "lanterna", "group": "tolvaren", "text": "Os olhos de Tolvaren estão apagados..."},
  {"at": [-98, 18],   "r": 5, "needs": "lanterna", "group": "palma",    "text": "A palma cede só a um peso grande..."}
]
```

**Mudanças em `plates`:**

| ação | entrada antiga | entrada nova |
|---|---|---|
| substitui | `{"at": [-98, 18], "h": 0.82, "group": "tolvaren", "heavy": true}` | a do bloco acima |
| remove | `{"at": [-238, -22], "group": "tolvaren", "heavy": false}` | — |

`gates` e `relics` de Tolvaren ficam como estão.

### 6.4 Véu de Saryth — "A Névoa do Silêncio" → Concha; "O Véu Partido" → Lágrima de Saryth (~5 min)

**A) Névoa do Silêncio** (arena no topo da mesa, 48 m)
- Os 5 Silentes da arena passam a ser **velados**. Sem lanterna, aparece o aviso "uma luz os revelaria".
- **Formas de vencer:**
  - **Co-op — Farol:** o Sael embarca e ergue a lanterna (9 m); o Hulvar anda esmagando com a Barrigada (onda de 3,4 m, dano 2) e o Aríete.
  - **Sael sozinho:** luz de 7 m e o combo do bastão (`attack_3` mata um exposto).
- **Arena limpa:** a **Concha dos Ventos** surge no antigo lugar da relíquia, em (-132,-286): chão 47,91, inclinação 0,6°, fora da caixa
  da colunata.

**B) O Véu Partido**
- A **Lágrima de Saryth** passa a flutuar no topo da cascata nº 0, em (-64,4, 49,5, -221,6). Fica 1,6 m acima do topo da areia e 1,47 m
  acima da borda.
- **Na borda** (-67,-225), com chão 48,03 e inclinação 0,9°:
  1. Sopre a Concha: o topo da cascata fica a 4,4 m, dentro do cone de 10 m.
  2. O véu abre por 6 s.
  3. USAR puxa a relíquia por uma linha de 4,4 m, livre de terreno e de props.
- O antigo nicho do penhasco foi rejeitado: a borda bloqueia a linha de visão.
- **Volta:** trilho ou planeio que já existem.

```json
"enemies": [
  {"at": [-110, -268], "arena": "saryth", "wander": 6, "veiled": true},
  {"at": [-134, -258], "arena": "saryth", "wander": 6, "veiled": true},
  {"at": [-120, -290], "arena": "saryth", "wander": 6, "veiled": true},
  {"at": [-100, -280], "arena": "saryth", "wander": 6, "veiled": true},
  {"at": [-146, -280], "arena": "saryth", "wander": 6, "veiled": true}
],
"items": [
  {"id": "concha", "at": [-132, -286], "h": 1.2, "arena": "saryth"}
],
"relics": [
  {"id": "saryth", "at": [-64.4, 49.5, -221.6], "veil": 0, "pull": true}
],
"sandfalls": [
  {"top": [-64.4, 47.9, -221.6], "height": 20.0, "width": 7, "facing": 52.0, "veil": true, "part_time": 6.0}
],
"hints": [
  {"at": [-120, -262], "r": 16, "needs": "lanterna", "text": "Os Silentes se escondem na névoa... uma luz os revelaria."},
  {"at": [-67, -225],  "r": 7,  "needs": "concha",   "text": "Algo brilha dentro do véu de areia..."}
]
```

**Mudanças em entradas existentes** (as outras 3 cascatas não mudam):

| lista | entrada antiga | ação |
|---|---|---|
| `enemies` | as 5 entradas de arena `saryth` | substituídas pelas do bloco acima |
| `relics` | `{"id": "saryth", "at": [-132, -286], "h": 1.2, "arena": "saryth"}` | substituída |
| `sandfalls` | `sandfalls[0]` | substituída |

### 6.5 Kesrin — "O Olho do Geodo" (os 4 itens) → Olho de Kesrin (~5 min)

**Geometria medida**

| ponto | altura |
|---|---|
| Borda oeste | 24,0 m |
| Fundo da cratera | -6,0 |
| Prateleira da placa leve (288,-14) | 6,07, ou seja, **12,1 m** acima do fundo. Fora do alcance da Mola (6,35) e do Canhão (7,3) |

Dá para chegar à prateleira andando pela parede norte, uma volta de ≈ 130 m. O cabo é o caminho rápido.

**Passos**
1. **Cabo de Vidro (Arpéu).**
   - Poste inicial em (177,-26): chão 24,02, inclinação 1,0°, ao lado do checkpoint (173,7,-34,5). Cabo a 2,2 m.
   - Poste final na prateleira em (283,-15): chão 6,10, inclinação 0,5°. Cabo a 3,0 m.
   - Linha de 107,9 m, sem props; folga mínima de 1,93 m do cabo e de 0,81 m dos pés.
   - Descida de ≈ 6,6 s, chegando a 6 m/s com o freio. O Sael para a 5 m da placa leve.
2. **Duna-tampão (Concha).** A placa leve (288,-14) está enterrada sob um domo (r 1,6, h 1,2). Um sopro a descobre.
3. **Placas em dupla, com trava.** O Sael fica na placa leve e o Hulvar desce surfando a parede oeste até a pesada (262,-40).
   - As placas estão a 36,8 m uma da outra. A busca de placas da IA passa a 40 m, então em solo o parceiro da IA vai sozinho.
   - As duas descem juntas, **travam** (`latch`) e soltam um "clunk"; a cratera zune.
4. **Cristal-Eco (Lanterna + Bastão + Hulvar).**
   - Fica em (250,-40): chão -6,00, plano, 8 m à frente da porta do geodo.
   - É `dark` e `last`: só se acende depois das placas e da duna, e só ressoa na luz.
   - Precisa da Barrigada do Hulvar (a até 9 m) **e** de um golpe de bastão do Sael em até **2,0 s**, em qualquer ordem.
   - Resolvido, o grupo `kesrin` se completa: o geodo se abre (o portão que já existe em (250,-48)) e o **Olho de Kesrin** aparece.
   - Como a relíquia só surge quando o portão abre, atravessar as paredes do geodo (`collide: none`) não adianta.
5. **Saída** pela fenda que já existe (238,-24).

**Solo**
- **De Sael:** cabo → duna → placa leve; o Hulvar da IA vai à pesada. Depois, no cristal, a IA do Hulvar faz a Barrigada 0,4 s depois do
  seu golpe.
- **De Hulvar:** use o Pedido para o Sael da IA soprar a duna e bater no cristal (com a lanterna acesa automaticamente).

```json
"ziplines": [
  {"id": "kesrin_cabo", "from": [177, -26], "from_h": 2.2, "to": [283, -15], "to_h": 3.0,
   "min_speed": 10, "max_speed": 19, "brake": 8}
],
"drifts": [
  {"at": [288, -14], "group": "kesrin", "radius": 1.6, "height": 1.2}
],
"plates": [
  {"at": [262, -40], "group": "kesrin", "heavy": true,  "latch": true},
  {"at": [288, -14], "group": "kesrin", "heavy": false, "latch": true}
],
"chimes": [
  {"at": [250, -40], "group": "kesrin", "need": ["slam", "staff"], "window": 2.0, "slam_radius": 9.0,
   "dark": true, "latch": true, "last": true, "size": 1.4}
],
"hints": [
  {"at": [288, -14], "r": 5,  "needs": "concha",   "group": "kesrin", "text": "Areia demais sobre a placa... precisa de vento."},
  {"at": [250, -40], "r": 10, "needs": "lanterna", "group": "kesrin", "text": "O cristal dorme no escuro..."},
  {"at": [250, -36], "r": 10, "needs": "bastao",   "group": "kesrin", "text": "O cristal só canta com dois golpes: o peso e a quilha."}
]
```

**Mudanças em `plates`:** as 2 entradas de `kesrin` ganham `"latch": true`.

O trampolim (266,-26), os portões, a relíquia e as fendas ficam.
O cabo e a duna não colidem com nada além da placa que a duna cobre de propósito (`place.clash` = só `plateL`).

---

## 7. Co-op e IA do companheiro

### 7.1 Momentos de dupla (um por zona)

| zona | momento | o que cada um faz |
|---|---|---|
| Proa | Embarque Relâmpago | o Sael se puxa até o cesto do Hulvar a até 16 m, inclusive com o Hulvar em trenó; depois, Canhão → argola |
| Berço | Sinos Gêmeos | um em cada sino, golpe em até 1,2 s |
| Tolvaren | Palma + Reboque | o peso do Hulvar dá a lanterna; o Sael mira do cesto e o Hulvar faz a força (`brace`) |
| Saryth | Farol | o Sael ergue a luz no cesto (9 m); o Hulvar esmaga os Silentes expostos |
| Kesrin | Placas + Eco | separam-se (cabo e placas) e se reencontram para o golpe duplo no cristal |

Enfeite em todas as zonas: **Vento de Popa**, a Concha no Hulvar (3 s com velocidade ×1,4).

### 7.2 IA (solo)

1. **Segurar Posto** — a correção de segurança do design A.
   - TROCAR com o herói ativo sobre uma placa (`occupied_by`) ou a até 2 m de um sino faz o herói deixado **segurar**: ícone de âncora,
     sem seguir e sem se teleportar.
   - Dura até você chamar (DUPLA como Hulvar, que já existe; ou DUPLA como Sael a até 9 m) ou até o grupo ser resolvido.
   - Em `HeroParty.swap()`: `old_ai.hold_at(pos)`.
2. **Busca de placas.**
   - `_find_plate` filtra `is_plate` e procura até **40 m**, contra 18 m hoje.
   - Com um posto ativo, a regra de teleporte por distância (> 42 m) fica desligada.
   - Se o posto estiver a mais de 20 m, a IA vai até ele em rastro de luz.
3. **Placa única pesada** (palma): se o líder é o Sael e fica a até 4 m de uma placa pesada cujo grupo só tem essa placa, por 1,0 s,
   o Hulvar da IA sobe nela e segura até o grupo ser resolvido.
4. **Sinos:**
   - quando o líder chega a 8 m de um sino de um grupo não resolvido, a IA vai ao sino **não tocado** mais distante que ela consegue
     tocar e espera (ícone "pronto");
   - ela toca **0,3 s** depois de qualquer golpe do líder num sino do mesmo grupo;
   - no Cristal-Eco: o parceiro a até 9 m faz a sua parte (Hulvar: pulo + Barrigada; Sael: `attack_1`) 0,4 s depois do golpe do líder.
5. **Lanterna da IA:** o Sael da IA (com o item) acende a lanterna a até 12 m de um Silente velado, de um Olho de Brasa apagado ou de um
   sino `dark` de grupo não resolvido. Apaga depois de 5 s sem nenhum. No cesto, a lanterna fica erguida (Farol).
6. **Pedido (jogando de Hulvar):** USAR e o chip mandam o Sael da IA agir do lugar onde ele está:
   - Reboque, se estiver no cesto;
   - Lançar a Luz;
   - soprar a duna ou o véu;
   - puxar a relíquia.

   Usa a mesma mira, com origem no Sael e direção da câmera.
7. **Combate leve:** o Hulvar da IA dá Aríete (≤ 2 m) ou pulo + Barrigada (≤ 3,4 m) em Silentes **expostos** a até 6 m do líder.
   Recarga de 1,5 s.
8. **Sael da IA e argolas:** usa só argolas `ai: true` (a cadeia da Proa) quando o líder já passou por elas. Fora disso, continua o
   teleporte em rastro de luz.

### 7.3 Rede (Wi-Fi)

O anfitrião é sempre o Sael (`NetCoop.start_game`), então eventos de ferramenta nascem no anfitrião.

**RPCs novos, confiáveis e idempotentes**

| RPC | quando |
|---|---|
| `_item_taken(id)` | ao pegar um item |
| `_puzzle_event(path, kind)` | `lit`, `rung`, `mark_slam`, `blown`, `pulled`, `parted`, `latched` |
| `_enemy_hit(name, dmg)` | a cada golpe num Silente com PV |

**Janela do Eco:** a Barrigada do cliente envia `mark_slam` e o anfitrião marca no próprio relógio, com tolerância de +0,15 s na janela.

**Estado do Sael** (`_hero_state`) ganha:
- `tool_bits` (1 = lanterna acesa, 2 = erguida, 4 = corda ativa);
- `rope_to: Vector3`.

Assim o par remoto desenha a corda e a luz.

**Estados novos do herói** entram **no fim** do `enum S` (HOOK, SWING, ZIPLINE), para não mudar os inteiros que já são enviados.

---

## 8. Animações, VFX, SFX e props

### 8.1 Clipes do Sael (30 fps) e ossos

| clipe | duração | uso / mão |
|---|---|---|
| `attack_1` | 0,32 s | bastão em `grip_R`, golpe de frente |
| `attack_2` | 0,34 s | revés, `grip_R` |
| `attack_3` | 0,50 s | pancada com as duas mãos, `grip_R` + `grip_L` |
| `grapple_throw` | 0,18 s | o arpéu sai de `belt_R` para `grip_R` no quadro 0 |
| `swing` | laço de 1,0 s | as duas mãos na corda; o cachecol segue a velocidade (mola do cachecol ×0,5 no balanço). Também a pose do cabo, com as pernas recolhidas |
| `pull` | 0,45 s | puxão para trás; no Reboque, laço de 1,2 s |
| `lantern_hold` | camada de tronco (máscara a partir de `spine_2`), mistura de 0,15 s | lanterna em `grip_L`. Sai em 0,1 s durante golpe, arremesso ou sopro (a lanterna volta a `belt_L`) e volta 0,8 s depois |
| `horn_blow` | 0,6 s | concha de `belt_L` para `grip_L`, bochechas cheias, cachecol esticado para a frente |

**Equipamento** (`BoneAttachment3D`):
- `belt_R`: rolo do arpéu;
- `belt_L`: lanterna (-0,04, -0,02, -0,08) e concha (0,02, -0,04, 0,09);
- `back_slot`: bastão na diagonal sobre a prancha. Na volta à locomoção, o bastão vai para as costas em 0,15 s.

Mola da lanterna pendurada: 3,0 / 0,35.

**Hulvar:** reaproveita `brace` (Reboque) e `slam` (Eco). Não precisa de clipe novo.

### 8.2 VFX (reusar `Fx.burst` sempre que der)
- **Arpéu:**
  - corda: faixa de 2 segmentos, 2,5 cm, marrom-avermelhada, brilho ciano 0,4 presa;
  - faísca dourada ao prender (`sparkle`);
  - na soltura perfeita: `ring_light` 1,0;
  - FOV +6° no balanço (0,2 s).
- **Bastão:** rastro de 0,12 s, de marfim para ciano; no acerto, `hit_spark` + 3 a 6 faíscas de latão; no `attack_3`, `dust_ring` 0,9 e
  rachadura no chão (2 s).
- **Lanterna:** halo aditivo em billboard (r 0,9) + 6 brasas. Olho de Brasa acendendo: emissivo de 0 a 2,0 em 0,6 s, `fire` pequeno e
  brasas ocasionais. Silente exposto: `dissolve` de 0,55 para 0 e olho âmbar acendendo.
- **Concha:** cone de traços (`streak.png`, 12 partículas, 0,4 s) + anel de poeira. A duna some em `dust` 2,0 + faixas de areia.
  O véu se abre em V. Na Lufada, `ring_light` 0,6 sob os pés.
- **Sinos:** onda de luz ciano no toque, brilho 1,5 durante a janela e fixo quando resolvido. O Cristal-Eco tem rachaduras ciano quando ressoa.

### 8.3 SFX (`game/tools/gen_audio.py`, CC0)

| fonte | sons |
|---|---|
| Arpéu | `hook_throw` (chicote), `hook_lock` (clank), `swing_wind` (laço com volume pela velocidade), `zip_reel` (zunido subindo), `rope_creak` (Reboque), `cable_hum` |
| Bastão | `staff_swing_1/2/3` (o tom sobe), `staff_hit` (madeira em vidro), `tink` (velado), `crack` |
| Lanterna | `lantern_on`, `lantern_loop` (crepitar a -22 dB), `ember_ignite` |
| Concha | `horn_blow` (nota grave e redonda, uma quinta acima da buzina do Hulvar), `gust_whoosh`, `sand_scatter`, `veil_part`, `veil_close` |
| Sinos | `chime_high`, `chime_low` (mesmo acorde), `chime_fail` (nota descendente), `chord_solved` |
| Itens | `item_get` (fanfarra curta) |

### 8.4 Props para o kit SDF (`game/blender/build_world_props.py`)

| prop | tamanho | descrição visual |
|---|---|---|
| `item_arpeu` | 0,30 m | três garras curvas de latão `#D4A33F` + rolo de corda de vela marrom-avermelhada com 4 voltas |
| `item_bastao` | 0,95 m | haste de madeira clara com veios da quilha, ponteira de latão e 3 anéis entalhados perto da empunhadura |
| `item_lanterna` | 0,22 m | gaiola de latão de 4 hastes, vidro âmbar `#FFB45A` (glow) e alça de arco |
| `item_concha` | 0,24 m | espiral de nácar rosado com 3 voltas, borda aberta e bocal de latão |
| `relicario` | 0,9 m | pedestal de arenito com pano índigo `#2B3A87` e aro de latão |
| `argola` | 1,1 m de Ø | aro de latão com 3 bandeirolas de pano de vela e 3 contas de vidro ciano `#4FE3D6` (glow 0,25 → 1,0) |
| `aro_puxar` | 0,6 m | aro grosso de latão com 2 elos de corrente, cravado numa placa índigo |
| `sino_cristal` | 1,6 m | prisma lilás facetado (material de cristal de Kesrin) num tripé de bronze |
| `cristal_eco` | `size` 1,4 | sino maior e mais escuro, com veios ciano |
| `cabeco` | 2,2 / 3,0 m | poste do cabo: coluna de bronze com aro de latão no topo |
| `braseiro` | — | tigela-gema de vidro âmbar apagada para o fundo do olho; o resto é a cabeça que já existe |

Peças que **não** são SDF:
- **Duna-tampão:** domo procedural com o material da areia.
- **Cabo:** faixa trançada de 3 cm com contas de vidro a cada 4 m.

---

## 9. Plano de implementação (≈ 6 h de código + 1 h de assets)

As etapas abaixo podem ser jogadas uma a uma.

### 1. Inventário e entrada (45 min)
- **`game/scripts/systems/game.gd`:**
  - `items: Array[String]`;
  - `has_item(id)`, `give_item(id)` e o sinal `item_collected(id)`;
  - `lantern_pos: Vector3` (`INF`) e `lantern_radius`.
- **`player_input.gd`:** `use` (segurado), `_use_pressed`, `_lamp_pressed` em press/take/peek/clear e as flags 32/64/128.
- **`input_sources.gd`:**
  - kb1: `F` ou `XBUTTON1` = use, `G` = lamp;
  - pad: `RB` = use, `LB` = lamp, `Y` = swap (tirar o `RB` do swap);
  - toque: `touch_use` (segurado) + eventos `use` e `lamp`.

### 2. UI (45 min)
- **`touch_controls.gd`:**
  - `BTN.use` e `BTN.lamp`; `show_use`, `show_lamp`, `use_icon`, `lamp_on`, `use_hint`;
  - USAR segurado define `touch_use`.
- **`hud.gd`:** retículo (`unproject_position` do alvo do `HeroTools`), faixa de item, ícones de item e `hints` (pelo `Game.toast`).

### 3. `HeroTools` (novo `game/scripts/player/hero_tools.gd`, `class_name HeroTools`, `RefCounted`, um por herói ágil) (75 min)
- `find_target(origin, dir, touch: bool) -> Dictionary`, sobre o grupo `hook_targets` + braseiros (com a lanterna acesa) + relíquias
  `pull` + o Hulvar + `enemies`.
- `use_pressed(hero)`: despacha para arpéu, concha ou Lufada.
- Lanterna: `OmniLight3D` + `BoneAttachment3D` em `belt_L`/`grip_L`; atualiza `Game.lantern_pos`.
- `gust(origin, dir)`: `call_group("wind_listeners", "on_gust", origin, dir, 10.0, 25.0, hero)`.
- Corda: `MeshInstance3D` com faixa de 2 segmentos, atualizada por quadro.

### 4. `hero.gd` (75 min)
- `enum S` ganha **no fim** `HOOK`, `SWING` e `ZIPLINE`.
- Funções novas:
  - `_st_hook` (arremesso, zip, Embarque e puxar);
  - `_st_swing` (pêndulo do `swing3.py` com `move_and_collide`);
  - `_st_zipline` (modelo de velocidade + freio; reaproveita a matemática de `_st_grind`).
- **USAR:** `intent.take("use")` → `tools.use_pressed(self)` em `_st_ground`, `_st_air`, `_st_glide`, `_st_surf`, `_st_ride` (Reboque)
  e `_st_launch` (depois de 0,25 s). `intent.take("lamp")` → `tools.toggle_lamp()` em todos os estados controláveis.
- **Bastão:**
  - `_action_ground()` do ágil vira `_staff_combo()` quando `Game.has_item("bastao")` (`combo_step`, `combo_t`, buffer);
  - `_attack(center, r, kind, dmg := 1) -> int` devolve o número de acertos;
  - `_spin()` usa r 1,9 e o kind `staff_spin`; o Ricochete acontece quando `_attack` acerta no ar.
- **Hit-stop local:** `_freeze_t` pula `_physics_process` e define `visual.anim_speed(0)`.
- **Carona de planeio:** em `_st_glide`, `_glide_cap = max(9.2, carry)` decaindo 2,5/s², usando `_carry_t` definido na soltura.
- **Lufada:** `_lufada_ready`, recarregada em `_land`, `bounce`, `add_updraft` e na soltura.
- `is_heavy()` não muda (RIDE já conta).

### 5. Travas e mundo (90 min)
- **Novo `game/scripts/world/tool_puzzles.gd`** (`class_name ToolPuzzles`), com as classes internas `ToolPedestal`, `HookRing`, `Zipline`
  (estende `Interactables.SandRail`), `Brazier`, `Chime`, `SandDrift` e `HintZone`.
- **`PuzzleGroups`** (estático): `members(group)`, `done_except(node)` para `last`, `solved(group)` e o sinal `group_solved(group)`.
  Revela itens e relíquias com `group`.
- **`interactables.gd`:**
  - `PressurePlate`: `is_plate := true`, `latch` / `latched`;
  - `Relic`: `veil_index`, `pull`, `can_take()`, alvo de puxar;
  - o `StoneGate` não muda.
- **`sand_fx.gd`:** o nó da cascata ganha `part(t)` / `close()` e entra em `wind_listeners` quando tem `veil`.
- **`silente.gd`:**
  - `hp`, `veiled`, `_exposed` (`Game.lantern_pos`), `on_attack(..., dmg := 1)`;
  - `on_gust`, `on_hook_pull`, empurrão e `stun_t`;
  - "tink" quando velado.
- **`world_content.gd`:**
  - `_items()`, `_hook_rings()`, `_ziplines()`, `_braziers()`, `_chimes()`, `_drifts()` e `_hints()`, chamados **depois** de
    `_plates_and_gates()` e de `_relics()` e **antes** de `_enemies()`;
  - `_enemies()` lê `veiled`; `_sandfalls()` guarda `sandfall_nodes[i]`; `_relics()` lê `veil` e `pull`;
  - `_arenas[aid]` passa a ter uma lista de `reveal` (relíquia e/ou item).

### 6. IA e dupla (45 min)
- **`companion_ai.gd`:** as regras da seção 7.2, mais `hold_at(pos)` e `release_hold()`.
- **`party.gd`:**
  - `swap()` chama `hold_at` quando o herói deixado está numa placa ou num sino;
  - no solo, como Hulvar, repassa o USAR e o chip ao Sael da IA (Pedido).

### 7. Rede (30 min)
- **`net_coop.gd`:**
  - `_hero_state` com `tool_bits` e `rope_to`;
  - os RPCs `_item_taken`, `_puzzle_event` e `_enemy_hit`;
  - conectar `Game.item_collected` e os sinais `changed` das travas novas (como `_on_local_seed`).

### 8. Conteúdo
Aplicar os blocos JSON da seção 6 em `game/world/world.json`. Só o conteúdo muda: **não** é preciso rodar o `gen_terrain`.

### 9. Assets (≈ 1 h, em paralelo)
- Props da seção 8.4 em `build_world_props.py`.
- Clipes e ossos no `build_sael` (o script do menino).
- SFX em `gen_audio.py`.
- Captura com `capture.tscn` na hora 3 (lanterna em Kesrin) e na Proa (cadeia de argolas).

**Lista de cortes** (se faltar tempo, nesta ordem):
1. O balanço vira só zip: B2 e B3 viram `zip`.
2. Sai a carona de planeio.
3. Sai o Ricochete.
4. Sai o Vento de Popa.
5. O Farol vira só a luz de 7 m.

Nenhum corte quebra a progressão.

---

## 10. Testes (`game/tools/playtest.gd`; rodar `python3 tests/run_tests.py --game-only` e `godot --headless --path . --import`)

### Novos testes
- `items` — tocar os 4 pedestais: `Game.items` tem 4, e o Hulvar não pega.
- `hook_zip` — o Sael em (60,255) com o arpéu e USAR: chega a ≤ 1,5 m de B1 em ≤ 1,2 s e termina em AIR com `air_jumps == 1`.
- `hook_swing` — surfe a 16 m/s antes de B2 com USAR segurado e solto: solta acima de 15 m/s sem tocar o chão, e prende B3.
- `embarque` — o Hulvar a 12 m em GROUND, com USAR no Hulvar: o Sael entra em RIDE em ≤ 1,0 s.
- `staff_combo` — com o bastão, 3 AÇÕES em 0,25 s: `combo_step` vai de 1 a 3 e um Silente comum a 1 m morre no 1º golpe.
  `Engine.time_scale` continua 1,0.
- `chimes_sync`:
  - golpes nos sinos `berco` com 0,3 s de diferença: o Bastão aparece;
  - com 2,0 s de diferença, ele **não** aparece.
- `palma` — o Hulvar na placa (-98,18): a Lanterna aparece. Com o Sael na placa, não aparece.
- `tolvaren`:
  - sem lanterna, o arpéu não prende nos olhos;
  - com lanterna, Lançar a Luz acende os 2 olhos;
  - o Reboque fora do cesto falha; no cesto funciona, o portão abre e a relíquia aparece.
- `veiled` — sem luz, 3 golpes não matam; com luz, `attack_3` mata, e o Rodopio + Rodopio também.
- `veu` — antes do sopro a relíquia não é pega; Concha na borda e USAR: `Game.relics` contém `saryth`.
- `kesrin`:
  - Cabo: o Sael sai do poste e chega a ≤ 6 m de (283,-15).
  - Duna: o sopro libera a placa.
  - Placas: com as duas placas, `latched`; ao tirar os heróis, continuam `pressed`.
  - Cristal: só a Barrigada não resolve; Barrigada + `staff1` em ≤ 2,0 s resolvem e o portão `kesrin` abre.
- `ai_hold` — TROCAR com o Sael na placa leve: ele continua nela por 10 s, mesmo a 40 m do líder.
- `ai_chime` — no solo, o líder chega a 8 m do sino Leste: a IA toca o Oeste e o grupo resolve.
- `lan` (`tests/run_tests.py`) — duas instâncias: o anfitrião acende um olho e o cliente vê `pressed`; o cliente faz a Barrigada no
  cristal e o anfitrião bate em ≤ 2,0 s, e os dois veem o portão aberto.

### Testes que já existem e precisam de ajuste
- `_t_plates`:
  - filtrar `is_plate`;
  - antes de pisar, chamar `force_done()` nas travas não-placa do grupo;
  - a `palma` não tem portão: verificar a revelação da Lanterna.
- `_t_relics`: a relíquia de Saryth precisa de `veil`, então o teste chama `part()` antes de tocar.
- `_t_enemy`: veja se o inimigo testado não é velado.

---

## 11. Riscos

| risco | mitigação |
|---|---|
| Balanço cinemático atravessar penhascos ou o trimesh do colosso | `move_and_collide` a cada passo e abortar para AIR; argolas autoradas com ≥ 2,97 m de folga (medido) |
| Mira errada no toque (argola × Hulvar × Silente perto) | classes de prioridade, trava grudenta, `chain_next`, retículo sempre visível; nunca disparar sem USAR |
| Carona de planeio e Lufada desafinarem a escalada da mesa e o playtest | carona só até 1,5 s depois da soltura; Lufada 1×/voo; rodar `--game-only` |
| Câmera compartilhada no co-op local com a dupla separada | os maiores rachas agora: Sinos (50 m) e placas de Kesrin (36,8 m); a Balança de 145 m saiu |
| Rede: janelas de 1,2–2,0 s | o anfitrião mede com o próprio relógio, +0,15 s de tolerância; eventos idempotentes; hit-stop local |
| Custo no celular | uma `OmniLight` extra (lanterna, sem sombra, ≤ 11 m); olhos e sinos só com emissivo; corda de 2 segmentos; limitar partículas de vento na qualidade *Baixa* |
| Mudanças em conteúdo existente quebrarem testes (`palma`, ombro, Saryth) | os ajustes de teste estão listados na seção 10 e são feitos junto |
| Legibilidade do Silente velado contra a areia dourada | contorno escuro + névoa lilás local; conferir com `capture.tscn` antes de fechar |
| Geodo `collide: none` | a relíquia só aparece com o portão aberto, então atravessar a parede não dá nada; uma colisão por pedaço fica para depois do MVP |

**Fora do MVP** (ideias boas que ficaram de fora): Âncora do Hulvar + tirolesa ancorada, Clarão da lanterna, respiro adormecido,
Silente blindado, emboscada do bastão, TACADA/Martelo e Bigorna, argolas `dark`.
