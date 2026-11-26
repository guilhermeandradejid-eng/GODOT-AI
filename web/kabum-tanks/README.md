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

- **Turnos por atraso**: cada tiro e cada metro andado somam "atraso"; quem tem o menor atraso joga em seguida.
  Tiros fortes custam mais turno.
- **Mira 3D**: casco e torre giram separados, o ângulo vai de −5° a 88° e a força é carregada segurando Espaço.
  Uma prévia curta da trajetória mostra o começo do arco, e um traço branco marca a força do último tiro.
- **Vento** que muda a cada turno e empurra projéteis, fumaça, nuvens e o pólen do ar.
- **Terreno destrutível** (heightmap 161×161): crateras, túneis da broca e queimaduras.
  Tanques caem nos buracos (dano de queda), escorregam em encostas íngremes e afundam no mar.
- **Física dos tanques**: alinhamento ao relevo, limite de subida, combustível, empurrão das explosões,
  pouso com squash & stretch.
- **4 tanques**, cada um com 2 tiros e 1 Ultra. O Ultra carrega quando você causa ou sofre dano.

| Tanque | Tiro 1 | Tiro 2 | Ultra |
|---|---|---|---|
| Brutus | Bolão (cratera enorme) | Trinca (3 em leque) | Meteoro |
| Faísca | Choque (raios encadeados) | Pula-Pula (quica 3×) | Trovão (raio do céu) |
| Geada | Estilhaço (congela) | Granizo (divide em 5 no ar) | Avalanche (chuva de pingentes) |
| Vespa | Ferrão (míssil teleguiado) | Broca (cava túnel e explode) | Enxame (8 mini-mísseis) |

- **VFX e game juice**: bolas de fogo toon que viram fumaça, faíscas, detritos com física, anéis de choque,
  flashes de luz, raios, árvores que voam, tremor de câmera por "trauma", hitstop, câmera lenta no abate,
  "impact frame" em 2 tons, aberração cromática, soco de FOV, onomatopeias e números de dano.
  O áudio é todo sintetizado com WebAudio.
- **Câmera em 3ª pessoa**: fica atrás da torre, persegue o projétil, foca o impacto e desvia de morros.
  Arrastar gira a câmera, a roda do mouse dá zoom e o Tab abre a visão geral.
- **Modos**: 1×1 contra bot, todos contra todos (4 tanques) e 2 jogadores no mesmo PC.
  A IA tem 3 níveis e mira simulando trajetórias com o vento.
- **Celular**: controles de toque e layouts para retrato e paisagem.

## Controles

| Tecla | Ação |
|---|---|
| W / S | andar / ré |
| A / D | girar o casco |
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
