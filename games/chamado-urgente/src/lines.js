// Falas dos personagens (balões). Mantenha curtas: aparecem por ~2,5 s.
export const LINES = {
  cable: ['Minha internet sumiu!', 'O cabo fez TZZZT!', 'Tô offline!', 'Cadê meu e-mail?!'],
  virus: ['Apareceu uma caveira!', 'Só cliquei no link do prêmio...', 'Meu PC tá rindo de mim!', 'Ganhei um iPhone?'],
  paper: ['BIP! SEM PAPEL', 'BIP BIP! BANDEJA 2 VAZIA'],
  jam: ['CRRRK-KRRRK!', 'ERRO 0x4E: PAPEL ATOLADO', 'NHAC NHAC NHAC'],
  fire: ['FOGO!!!', 'A impressora tá pegando fogo!', 'Alguém chama a TI!!', 'Cheiro de queimado...'],
  router: ['Caiu a internet!', 'O Wi-Fi sumiu!', 'Eu tava em reunião!', 'Sem rede de novo?!'],
  urgent: ['Já reiniciei 3 vezes!', 'E aí, TI?!', 'ALÔ?! ALGUÉM?!', 'Abri o chamado faz HORAS!', 'Vou ligar pro ramal!'],
  vip: ['EU SOU O DIRETOR!', 'Resolve isso AGORA!', 'Tenho reunião com o CEO!'],
  thanks: ['Valeu, TI!', 'Vocês são demais!', 'Salvou meu dia!', 'Nossa, que rápido!', 'Amo a TI!', 'Funcionou!'],
  fail: ['Vou abrir reclamação...', 'Ninguém me ajuda...', 'Vou falar com o diretor!', 'Vou trabalhar no papel então.'],
  tech: ['Desliga e liga de novo...', 'Deixa comigo!', 'É rapidinho!', 'Já resolvo!', 'Hmm, interessante...'],
  techDone: ['Resolvido!', 'Próximo!', 'Fácil!', 'Chamado fechado!'],
  techFire: ['Sai da frente!', 'Extintor na mão!', 'Calma, calma!'],
};

export function pick(list) { return list[Math.floor(Math.random() * list.length)]; }
