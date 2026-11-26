# Kabum! Tanks — demo de artilharia 3D (Three.js)

Demo jogável no navegador: artilharia por turnos com tanques cartunescos numa ilha destrutível.
É um único arquivo (`index.html`), sem build. O Three.js r160 é carregado do jsDelivr por import map.

## Rodar localmente

```bash
cd web/kabum-tanks
python3 -m http.server 8000   # abra http://localhost:8000
```

(Abrir o arquivo direto com `file://` também funciona na maioria dos navegadores.)

## O que tem

- **Gráficos realistas sem baixar nada**: todas as texturas (grama, terra, rocha, areia, casca, folhas,
  agulhas, fumaça, nuvens, normal maps da água e "sujeira/arranhões" dos tanques) são geradas no navegador
  com ruído fBm/Worley. Materiais PBR (`MeshStandardMaterial`) com shaders estendidos.
- **Terreno**: mistura de 4 materiais por altura e inclinação, com rocha triplanar nas encostas, normal maps,
  areia molhada na costa, fundo visível sob a água rasa, queimaduras e crateras que brilham em brasa.
- **Céu físico** (`Sky`, espalhamento de Rayleigh/Mie) usado como mapa de ambiente (PMREM) para os reflexos
  dos tanques. **Água** com reflexo do céu, Fresnel, brilho do sol, espuma na costa e ondas.
- **Vegetação**: até 70 mil tufos de grama instanciados que leem altura e queimado direto na GPU e balançam
  com o vento do turno. Árvores e pinheiros com folhas em cartões alpha (com sombra), arbustos, rochas com musgo
  e nuvens volumétricas. Árvores voam e pegam fogo nas explosões.
- **Tanques mecânicos**: corpo rígido com suspensão independente por roda (raycast mola-amortecedor),
  braços oscilantes, molas helicoidais que comprimem, esteiras articuladas (44 elos por lado contornando rodas,
  roda motriz e tensora), direção por diferença de esteiras, atrito por roda, coice do canhão que balança
  o casco, antena com mola e bandeira, faróis, fumaça do escapamento e de dano.
- **Propulsores**: segure `E` para saltar, planar ou subir rampas. Há estabilização de atitude no ar, chamas,
  sopro de poeira no chão e consumo de combustível. Quedas altas causam dano; tanques capotados se desviram.
- **Turnos por atraso**: atirar e andar acumulam atraso; quem tem o menor atraso joga primeiro.
  O vento muda a cada turno e afeta projéteis, fumaça, grama e árvores.
- **4 tanques**, cada um com 2 tiros e 1 Ultra. O Ultra carrega quando você causa ou sofre dano.

| Tanque | Tiro 1 | Tiro 2 | Ultra |
|---|---|---|---|
| Brutus | Bolão (cratera enorme) | Trinca (3 em leque) | Meteoro |
| Faísca | Choque (raios encadeados) | Pula-Pula (quica 3×) | Trovão (raio do céu) |
| Geada | Estilhaço (congela) | Granizo (divide em 5 no ar) | Avalanche (chuva de pingentes) |
| Vespa | Ferrão (míssil teleguiado) | Broca (cava túnel e explode) | Enxame (8 mini-mísseis) |

- **VFX e game juice**: bola de fogo aditiva, coluna de fumaça texturizada (ordenada por profundidade),
  saia de poeira, detritos com rastro, faíscas, brasas, anel de choque, luz dinâmica, tremor de câmera por
  trauma, hitstop, câmera lenta no abate, aberração cromática, soco de FOV, onomatopeias e números de dano.
  O áudio é sintetizado com WebAudio (motor, jato, tiros, explosões).
- **Câmera em 3ª pessoa**: fica atrás da torre, persegue o projétil, foca o impacto, desvia de morros e
  "atravessa" a folhagem próxima. Arrastar gira, a roda dá zoom e o Tab abre a visão geral.
- **Qualidade adaptativa**: se o FPS cair, o jogo reduz grama, resolução e sombras.
  Para forçar o modo leve, use `?q=low` na URL.
- **Modos**: 1×1 contra bot, todos contra todos (4) e 2 jogadores no mesmo PC. A IA mira simulando trajetórias.

## Controles

| Tecla | Ação |
|---|---|
| W / S | andar / ré |
| A / D | girar o casco |
| E | propulsores (segure) |
| ← / → | girar a torre |
| ↑ / ↓ | ângulo (Shift = ajuste fino) |
| Espaço | segurar = força, soltar = tiro |
| 1 / 2 / 3 | Tiro 1 / Tiro 2 / Ultra |
| Tab · C | visão geral · recentralizar a câmera |
| M · H | som · ajuda |

## Técnicas usadas (pesquisa)

- Laço clássico de artilharia: ângulo, força, vento variável e terreno destrutível.
- Game feel: trauma² para o tremor, hitstop curto, squash & stretch com mola, efeitos proporcionais ao impacto.
- Toon em WebGL: `MeshToonMaterial` com gradiente de 3 tons, contorno por casco invertido
  (inverted hull), bloom (`UnrealBloomPass`) e um passe final de vinheta, aberração cromática e impact frame.
