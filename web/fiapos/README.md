# Fiapos — Capítulo I: O Ateliê

Horror atmosférico em 2,5D para um ou dois jogadores, feito com Three.js e física cannon-es.
Duas crianças minúsculas atravessam uma casa gigante e precisam escapar da Costureira, uma figura curvada
com uma gaiola no lugar da cabeça e uma vela acesa dentro.

Personagens, monstro, cenários e sons são originais. O jogo é um único arquivo (`index.html`), sem build;
texturas e áudio são gerados no navegador.

## Rodar localmente

```bash
cd web/fiapos
python3 -m http.server 8000   # abra http://localhost:8000
```

- `?q=low` força o modo leve.
- `?mockroom` simula o co-op online entre duas abas do mesmo navegador (usado nos testes).

## Modos

- **Sozinho**: todos os quebra-cabeças têm uma solução com objetos (caixas, carretel).
- **Co-op local**: mesmo teclado ou dois controles. Lume usa WASD, Espaço, Shift, C, E e Q.
  Traça usa setas, Enter, Shift direito, Ctrl direito, ponto e barra.
- **Co-op online**: usa a sala em tempo real do Artifact (capacidade `room`, só presença).
  Um jogador cria a sala, o outro digita o código de 4 letras. O anfitrião simula a física do mundo e a
  Costureira; o convidado simula a própria criança, e o anfitrião aplica os empurrões e puxões dele.
  Só funciona dentro do Claude, com o jogo publicado e compartilhado com o parceiro.

## O que tem

- **Animação procedural**: esqueletos de juntas para as crianças e para a Costureira.
  As crianças andam, correm, andam agachadas, rastejam em dutos, pulam, caem se debatendo, se penduram em
  bordas e escalam, pulam obstáculos baixos, empurram, puxam, carregam, ajudam o parceiro a subir,
  tremem de medo e viram a cabeça para o perigo.
  A Costureira patrulha, escuta inclinando a gaiola, procura embaixo da mesa varrendo com o braço,
  persegue, grita, agarra (braço com IK de dois ossos) e mexe os dedos longos o tempo todo.
  O vestido e as roupas no varal balançam por shader.
- **Física (cannon-es)**: caixas, carretel, banquinho, xícaras e boneca de porcelana que quebram.
  Também há uma lâmpada pendurada balançando numa corda, uma porta arrancada que voa pelo corredor,
  uma placa de pressão que abre um alçapão e crianças que podem subir uma na cabeça da outra.
- **Furtividade**: a Costureira vê em cone, com linha de visão bloqueada por móveis, e ouve passos de
  corrida e objetos caindo. Embaixo da mesa você fica escondido, mas ela pode varrer a borda.
- **Sustos**:
  - a boneca que cai do armário e se espatifa;
  - batidas dentro do duto;
  - a silhueta atrás do vidro fosco durante um relâmpago;
  - o rosto na janela da porta do corredor;
  - a porta arrancada no início da perseguição;
  - o braço que tenta te alcançar por baixo da porta;
  - a captura em close.
- **Clima**:
  - luar com sombras das grades, fachos de luz volumétricos e lâmpadas que piscam;
  - a vela da Costureira projetando sombras das barras da gaiola;
  - neblina, poeira no ar e teias;
  - pós-processamento com granulação, vinheta, aberração e faixas de cinema;
  - pulsação da tela quando ela está perto.
- **Áudio sintetizado com reverberação**:
  - drone grave, vento, gotas, rangidos, tique-taque e sussurros;
  - batimento cardíaco que acelera com o medo;
  - passos pesados posicionados no espaço, grito e acordes dissonantes;
  - caixinha de música no menu.

## Controles

| Ação | Jogador 1 | Jogador 2 | Controle |
|---|---|---|---|
| Andar / profundidade | A D / W S | setas | analógico |
| Pular / subir na borda | Espaço | Enter | A |
| Correr (faz barulho) | Shift | Shift dir. | RT / RB |
| Agachar, rastejar, esconder | C ou Ctrl | Ctrl dir. ou vírgula | B |
| Segurar, empurrar, puxar, carregar | E (segure) | ponto | X |
| Ajudar o parceiro a subir | Q | barra | Y |
| Pausa | Esc | | Start |
