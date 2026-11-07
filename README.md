# Pedal Ponte: Chocolate Plus → BOSS GT-1 (Android / Flutter)

App Android que liga um pedal MIDI (como o **M-Vave Chocolate Plus**) à **BOSS GT-1**, usando o celular como ponte:

```
Chocolate Plus ──Bluetooth MIDI──▶ celular ──cabo USB OTG──▶ GT-1
```

Cada botão do pedal pode: ir para um patch, avançar ou voltar patch, alternar entre dois patches ou ligar e desligar um efeito.

## Por que precisa do app

A GT-1 **não** aceita Program Change nem Control Change, que são as mensagens que o pedal envia. Ela só obedece às mensagens SysEx da Roland, as mesmas do BOSS TONE STUDIO. A porta USB dela também não é "class compliant", então o Android não a reconhece como MIDI. O app fala direto com a interface USB da GT-1 e traduz os comandos do pedal.

## O que você precisa

- Celular Android 7 ou mais novo **com suporte a USB OTG** (quase todos os atuais têm)
- Cabo/adaptador **OTG** do celular para o cabo USB da GT-1
- GT-1 ligada com fonte ou pilhas (o celular não alimenta a GT-1)
- Chocolate Plus ligado. Não precisa parear nas configurações do Android: a conexão é feita dentro do app

## Como gerar o app sem instalar nada (GitHub)

1. Crie uma conta em github.com e um repositório **privado** (ex.: `pedal-ponte`).
2. Envie todos os arquivos desta pasta para o repositório. Na página do repositório: *Add file → Upload files* e arraste o conteúdo da pasta.
   A pasta `.github` é oculta em alguns computadores. Se ela não subir, crie os arquivos à mão em *Add file → Create new file*, com os nomes `.github/workflows/build.yml` e `.github/workflows/gerar-chave.yml`, e cole o conteúdo.
3. Vá em **Actions → Gerar app Android → Run workflow**. Em uns 10 minutos:
   - o **APK** aparece em **Releases** (lado direito da página do repositório), pronto para baixar no celular;
   - em Actions, o pacote **pedal-ponte** traz também o `app-release.aab`, que é o arquivo da Play Store (veja a parte da assinatura abaixo).

### Instalar no celular

1. No celular, abra o navegador, entre no GitHub com a sua conta e abra o repositório → **Releases**.
2. Toque em **app-release.apk** para baixar.
3. Abra o arquivo baixado. Se o Android pedir, permita **"Instalar apps desta fonte"** para o navegador.
4. Se o Play Protect avisar que o app é desconhecido, toque em **Mais detalhes → Instalar mesmo assim**. Isso acontece com qualquer app que ainda não está na loja.
5. Ligue a GT-1 no cabo OTG. O Android pergunta se quer abrir o Pedal Ponte: marque **"Sempre"**.

Quando o app estiver na Play Store, desinstale esta versão de teste antes de instalar a da loja, porque as assinaturas são diferentes.

### Assinatura (obrigatória para a Play Store)

1. **Actions → Gerar chave de assinatura → Run workflow** (uma vez só). Baixe o arquivo `chave-de-assinatura-GUARDE-BEM`.
2. Guarde essa pasta num lugar seguro, fora do GitHub.
3. No repositório, abra **Settings → Secrets and variables → Actions** e crie:
   - Secret `KEYSTORE_BASE64` = conteúdo de `KEYSTORE_BASE64.txt`
   - Secret `KEYSTORE_PASSWORD` = conteúdo de `KEYSTORE_PASSWORD.txt`
   - Na aba *Variables*, crie `APP_ID` com o ID definitivo do app, ex.: `br.com.seunome.pedalponte`. **Esse ID não pode mudar depois de publicado.**
4. Apague a execução que gerou a chave (Actions → menu ⋯ → *Delete workflow run*).
5. Rode **Gerar app Android** de novo. Agora o `.aab` sai assinado.

A cada nova versão, aumente o número em `pubspec.yaml` (`version: 1.0.1+2` — o número depois do `+` precisa sempre subir).

## Gerar no seu computador (opcional)

Com Flutter e Android Studio instalados:

```bash
flutter create --org app --project-name pontegt1 --platforms android .
dart run tools/preparar_android.dart br.com.seunome.pedalponte
flutter build apk --release      # para testar
flutter build appbundle --release # para a Play Store
```

Para assinar localmente, crie `android/key.properties` com `storeFile`, `storePassword`, `keyAlias` e `keyPassword`.

## Publicar na Play Store

Veja `docs/play-store.md`: lá estão o roteiro, os textos da loja e as respostas dos formulários.
A política de privacidade está pronta em `docs/privacidade.html`.

## Como o app funciona por dentro

| Parte | Arquivo |
|---|---|
| USB da GT-1 (pacotes USB-MIDI) e Bluetooth MIDI do pedal | `android/app/src/main/kotlin/app/pontegt1/MainActivity.kt` |
| Protocolo SysEx da GT-1 | `lib/gt1.dart` |
| Botões e ações | `lib/model.dart` |
| Telas | `lib/main.dart` |

Protocolo da GT-1 (endereços verificados pelo projeto open-source *Open GT-1 Web Editor*):

- Trocar patch: DT1 em `00 01 00 00` com 2 bytes (0–98 = U01–U99, 99–197 = P01–P99)
- Som em edição: `60 00 xx xx`; liga/desliga de efeito = 1 byte nesse bloco, descoberto pelo "Aprender efeito"
- Modo editor: DT1 `7F 00 00 01` = 1 ao conectar, 0 ao sair

## Se algo não funcionar

Abra o **Monitor MIDI** (ícone no topo), toque em copiar e mande o texto para quem estiver ajudando você. Ali aparece tudo o que o pedal envia e o que vai para a GT-1.

*App independente, sem ligação com a Roland/BOSS ou a M-Vave. BOSS e GT-1 são marcas dos seus donos.*
