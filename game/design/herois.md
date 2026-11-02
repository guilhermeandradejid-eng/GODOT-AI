# Saeli & Hulvar — "Vela e Casco"

Design final da dupla (síntese dos 3 conceitos julgados: originalidade, viabilidade no pipeline SDF e
encaixe com o gameplay). Base: conceito "Saeli & Hulvar"; enxertos de "Saeli & Grombo" e "Ziffa & Umbor".
Dados completos de construção do conceito-base: `concept[2]` em
`/tmp/.../scratchpad/char_concepts.json` (cópia resumida abaixo, com TODAS as mudanças que valem por cima dele).

## Pitch
No mar de areia de Ylvaar, Saeli é a vela sem barco e Hulvar é o casco sem vento. Sozinhos, incompletos;
juntos viram um esquife das dunas. Saeli, uma sprite-vela pequena e elétrica, adotou o maior amigo que
encontrou porque tem medo das dunas silenciosas. Hulvar é um antigo navio-guardião de porcelana esmaltada
que acorda quando ela sopra a primeira brisa: lento, literal, leal, fala só em notas graves de buzina.

**Pôster:** um navio que anda, com olhos de escotilha, e uma sprite turquesa de pé no cesto da gávea,
leques abertos e brilhando como vela.

**Emblema da dupla:** um anel com 3 pontos (o "Glifo de Rumo" na popa do Hulvar). As 3 sardas
luminosas de cada bochecha da Saeli formam o mesmo triângulo. O ponto de cima do glifo só acende quando ela
está a bordo ("juntos = completo").

## Paleta comum
| hex | papel |
|---|---|
| `#17808E` | Lagoon Teal — pele da Saeli |
| `#0E5563` | Abyss Teal — sombra/coroa da Saeli |
| `#F5ECD7` | Shell Ivory — máscara-coração, barriga, solas, rosto do Hulvar |
| `#2B3A87` | Night Indigo — botas, chevrons, quilha |
| `#2C5E86` / `#3C78A0` | Glaze Teal-Blue — casco do Hulvar (baixo/alto) |
| `#343C96` | Indigo Glaze — placas, mandíbula, punhos |
| `#D4A33F` | Brass — anéis de escotilha, punhos, borda do convés, aros |
| `#4FE3D6` / `#8FFFF2` | Glass Cyan / brilho — membranas, sardas, glifo, lanterna |
| `#FFB13B` / `#C2621E` | íris da Saeli (âmbar) |
| `#3FE6D8` / `#1E8C93` | íris do Hulvar (ciano) |
| `#CFD6E6` | Moonstone — âncora |

## Saeli (agile) — 0,93 m
Construa exatamente como o conceito-base (crânio, cara de feijão, focinho+nariz+sorriso esculpido,
máscara-coração marfim, olhos grandes âmbar, sobrancelhas índigo, sardas, orelhas-barbatana, tronco em
gota, chevrons dorsais, braços, mãos-luva, pernas/botas, cauda + prancha-folha, punhos de latão,
leques de 5 costelas), COM estas mudanças:
1. **Sem óculos** (nem tiras, nem osso `goggles`): os óculos + orelhas grandes + cauda liam como Ratchet.
   O olhar "determinado" vem da pálpebra do shader (lid ~0,35).
2. **Membranas dos leques em SDF** (nada de malha explícita de 6 mm): cada painel entre duas costelas é um
   disco fino (cylinder r 0,23, meia-espessura ≥ 0,0045) recortado pelos 2 planos das costelas, borda
   recortada (carve de esferas), dobra leve; peça própria com material `glow` (emissão 0,25 no cubo → 0,8 na
   borda). Cada metade do painel pertence ao osso da costela mais próxima (dobra suave).
3. **Materiais:** `skin` (corpo), `glow` (membranas + barbatanas das orelhas), `metal` (punhos, cubos,
   contas das costelas), `eye`. Nada de `fin`/`trim`.
4. **Surfe = "Cometa":** deitada de barriga sobre a prancha-folha, cabeça à frente, orelhas para trás como
   barbatanas, braços à frente; a cauda curva por baixo da barriga (tail_1..3). Mais legível e alcançável
   que a postura de snowboard.
5. **Sardas:** 3 por bochecha no mesmo triângulo do glifo do Hulvar (emissão 1,0).
6. Orçamento ~8k tris; espessura mínima 8 mm.

Ossos: os do conceito sem `goggles*`; incluir `earfin_L/R_1..2`, `fan_L/R_1..5`, `tail_1..3`, `board`.
Molas: `earfin_*_1→2` (2,4 / 0,30 / 0,15 / r 0,02), `tail_1→board` (1,4 / 0,35 / 0,5 / r 0,03).
Olho: sclera `#FFFDF6`, iris_outer `#C2621E`, iris_inner `#FFB13B`, pupil `#1B1530`, lid `#17808E`,
iris_size 0,60, pupil_size 0,28, base_lid 0,08.

Animações (30 fps, antecipação ≤ 2 quadros nas ações — o controle aplica a velocidade no quadro 0):
idle 3,0 s (respira, olha em volta, abre e fecha os leques, bate a prancha) · walk 0,8 · run 0,48
(16° de inclinação, braços bombeando, quique 3,5 cm) · jump 0,36 · fall 0,8 laço (leques 30% abertos) ·
land 0,30 (squash, leques fecham) · double_jump 0,42 (abre, bate, cambalhota de 0,7 volta) · glide 1,2 laço
(leques 100% abertos, braços horizontais, ±6° de inclinação lateral, tremor 6 Hz na costela 5) · spin 0,40
(giro de 720°, leques abertos) · surf 1,0 laço ("Cometa") · ride 2,0 laço (no cesto, cintura para cima,
antebraços na borda, olha em volta) · launch 0,5 laço (bola encolhida girando) · celebrate 1,6 · hurt 0,45.

## Hulvar (strong) — 1,40 m
Construa como o conceito-base (casco gordo inclinado para a frente que é corpo e cabeça, proa com 2 olhos
de escotilha, mandíbula em "underbite" com 2 presas-cabeço, braços longos com punhos-marreta, pernas
curtas de cabeço, cesto da gávea nas costas = assento + canhão, âncora em corrente como cauda), COM:
1. **Contraste com a areia:** o casco NÃO é branco. Casco em esmalte azul-petróleo (`#2C5E86` embaixo →
   `#3C78A0` em cima), quilha `#2B3A87`, placas/mandíbula/punhos `#343C96`; o marfim fica só na face da
   proa (máscara em volta dos olhos), no convés e nas solas.
2. **Ler como NAVIO, não pote/chaleira:** proa realmente afilada na frente (um "bico" de casco que avança
   sobre a mandíbula), faixa de quilha do queixo à virilha, amurada de latão contínua, cesto da gávea.
   SEM costuras de forno, faixas horizontais, rebites, parafusos de escotilha, tampas de dedo.
3. **Sem crescente na cabeça** (lê como símbolo religioso): no lugar, um gurupés curto/barbatana de proa.
4. **Sobrancelha-viseira arredondada** que nasce da linha da amurada, sem caixa.
5. **slam** = barrigada com os punhos à frente (a âncora bate por último e marca a areia).
6. **Materiais:** `stone` (casco/placas em esmalte), `metal` (latão), `glow` (lanterna do cesto,
   escotilhas laterais, glifo, runa da âncora), `glyph` (só o ponto de cima do glifo, que acende com a
   Saeli a bordo), `eye`.
7. Osso `nest` = ponto onde a Saeli fica (pés no fundo do cesto, z ≈ 1,19); cápsula r 0,48, h 1,35.
8. Orçamento ~9k tris.

Molas: `chain_1→anchor` (1,0 / 0,22 / 1,4 / r 0,06), `nest` (5,0 / 0,45 / 0 / ponta 0,22).
Olho: sclera `#F8FBFF`, iris_outer `#1E8C93`, iris_inner `#3FE6D8`, pupil `#10233A`, lid `#343C96`,
iris_size 0,55, pupil_size 0,24, base_lid 0,15.

Animações (antecipação ≤ 2 quadros em jump/ram/brace): idle 3,5 laço (respira 1,5%, punhos na areia, olha
para o cesto, âncora balança devagar) · walk 1,1 (gingado ±4°) · run 0,62 (galope com os punhos, 28° de
inclinação, cesto contra-rotacionado) · jump 0,45 · fall 0,8 laço · land 0,45 · slam (barrigada; termina na
pose de impacto) · ram 0,50 (proa abaixada, braços para trás) · brace 0,70 (pés abertos, âncora cravada,
disparo no quadro 0,25 s com recuo do cesto) · surf 1,0 laço ("Trenó de Quilha": casco deitado na areia,
pernas recolhidas, punhos como lemes) · celebrate 2,0 (bate no peito, âncora abana como rabo de cachorro) ·
hurt 0,5.

## Habilidades (UI em português)
| botão | Saeli | Hulvar |
|---|---|---|
| PULAR | pulo, **Bater de Leques** (pulo duplo), **Planar** | **Salto Pesado** |
| AÇÃO | **Rodopio** (giro) | **Aríete de Proa** (chão), **Barrigada** (no ar: pancada + onda de choque) |
| DUPLA | **Embarcar** no cesto | **Canhão do Ninho** (lança a Saeli) |
| areia | **Cometa** (surfe de barriga) | **Trenó de Quilha** |
