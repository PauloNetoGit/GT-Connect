# Publicar o Pedal Ponte na Play Store

## Antes de começar

- **Conta de desenvolvedor Google Play**: taxa única de US$ 25.
- **Conta pessoal criada depois de 13/11/2023**: antes de liberar para todo mundo, o Google exige um **teste fechado com pelo menos 12 testadores, inscritos por 14 dias seguidos**. Chame amigos músicos (cada um precisa de uma conta Google e de um Android). Contas de empresa (com D-U-N-S) não têm essa exigência.
- **Versão do Android alvo**: desde 31/08/2026, apps novos precisam mirar o Android 16 (API 36). O build usa o padrão do Flutter estável atual. Se a Play Console reclamar do "target API", atualize o Flutter e gere de novo.

## Passo a passo na Play Console

1. **Criar app** → nome: *Pedal Ponte* · idioma padrão: Português (Brasil) · App · Gratuito.
2. **Política de privacidade**: publique `docs/privacidade.html` (por exemplo pelo GitHub Pages ou pelo Google Sites) e cole o link. Antes, troque `[seu e-mail]` pelo seu contato.
3. **Acesso ao app**: "Todas as funcionalidades estão disponíveis sem restrições".
4. **Anúncios**: Não.
5. **Classificação do conteúdo**: categoria *Utilitário/Produtividade*; responda "não" para violência, sexo, apostas etc.
6. **Público-alvo**: 18+ (ou 13+); não é voltado a crianças.
7. **Segurança dos dados** (respostas):
   - O app coleta ou compartilha dados? **Não**.
   - Explicação: as configurações ficam só no celular; o Bluetooth é usado apenas para falar com o pedal MIDI, sem localização.
8. **Permissões de Bluetooth**: o app declara `BLUETOOTH_SCAN` com `neverForLocation`, então não precisa justificar localização.
9. **Ficha da loja**: textos abaixo, o ícone 512×512 já pronto em `docs/icone-play-store-512.png`, uma imagem de destaque 1024×500 e pelo menos 2 capturas de tela (tire do próprio celular).
10. **Teste fechado** → crie uma faixa, envie o `app-release.aab`, adicione os e-mails dos testadores e compartilhe o link de inscrição. Depois dos 14 dias, peça **acesso à produção**.

## Textos da loja

**Nome (até 30 caracteres):** Pedal Ponte

**Descrição curta (até 80):** Controle a BOSS GT-1 com seu pedal MIDI Bluetooth, usando o celular como ponte.

**Descrição completa:**

> O Pedal Ponte liga um controlador MIDI (como o M-Vave Chocolate Plus) à pedaleira BOSS GT-1, que não aceita comandos MIDI comuns.
>
> Ligue a GT-1 no celular com um cabo USB OTG, conecte o pedal pelo Bluetooth e escolha o que cada botão faz:
> • ir direto para um patch (U01–U99, P01–P99)
> • avançar ou voltar patch, dentro da faixa que você escolher
> • alternar entre dois patches
> • ligar e desligar um efeito do patch, que o app aprende sozinho
>
> Basta tocar em "Aprender" e pisar no botão: não precisa saber nada de MIDI. A tela fica ligada no palco, mostra o patch atual em letras grandes e tem um monitor MIDI para conferir as mensagens.
>
> Requer um celular com suporte a USB OTG e a GT-1 ligada na fonte ou nas pilhas.
>
> App independente, sem ligação com a Roland/BOSS ou a M-Vave. BOSS e GT-1 são marcas dos seus donos.

## Cuidado com marcas

Não use o logotipo da BOSS nem "BOSS"/"GT-1" no nome ou no ícone do app. Na descrição, citar a compatibilidade ("funciona com a BOSS GT-1") é o caminho seguro.
