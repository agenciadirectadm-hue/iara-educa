// Textos sobre mensagens no modo demonstração. Dependem do WhatsApp de teste estar ligado:
// com a ponte ligada, quem conversa com ela recebe respostas de verdade — então nenhuma tela
// pode afirmar "nenhuma mensagem real é enviada" (ajuste 6.3-1 do documento do portal).

/** Frase geral para as telas de entrada e de ajuda. */
export function avisoMensagens(canalAtivo?: boolean): string {
  return canalAtivo
    ? 'As famílias desta demonstração são fictícias e os avisos para elas são simulados. O WhatsApp de teste está ligado agora: quem conversa com ele recebe as respostas de verdade.'
    : 'As famílias desta demonstração são fictícias e os avisos para elas são simulados. O WhatsApp de teste está desligado: nenhuma mensagem sai agora.';
}

/** Explicação da bandeirinha ao lado de "a família foi avisada". */
export const AVISO_FAMILIA_FICTICIA =
  'Aviso simulado para família fictícia. Só quem conversa pelo WhatsApp de teste, quando ele está ligado, recebe a mensagem de verdade.';
