# HANDOVER

## Status Atual

Estavamos saindo do zero para colocar no ar um backend de licenciamento e billing do `Stash` com Cloudflare Workers + D1 + Stripe. O backend foi implementado, validado localmente e colocado em producao.

Entregas concluidas nesta sessao:

- Worker Cloudflare em producao.
- Banco D1 de producao criado e migrado.
- Secrets principais do Worker configurados.
- Produtos e precos Stripe configurados, incluindo mensal e anual.
- Webhook Stripe criado e apontando para o Worker publicado.
- Documentacao operacional criada em `docs/production-setup.md`.

URL atual do Worker:

- `https://stash-licensing-prod.robsonferr.workers.dev`

Webhook Stripe atual:

- `https://stash-licensing-prod.robsonferr.workers.dev/stripe/webhook`

O proximo foco natural e integrar a pagina/web do `stash` e o aplicativo para fazer um teste E2E real de compra -> webhook -> ativacao -> refresh.

## Contexto Tecnico e Decisoes

Arquitetura adotada:

- **Cloudflare Workers** como backend HTTP stateless.
- **Cloudflare D1** como fonte de verdade para licencas, checkout e sincronizacao com Stripe.
- **Stripe** para checkout, subscriptions e billing portal.
- **Entitlements assinados** com chave privada Ed25519 no Worker e verificacao local no app com chave publica.

Decisoes importantes:

- O projeto ficou **prod-only** por enquanto. O `wrangler.toml` usa apenas `[env.prod]`.
- O binding do banco ficou como `DB` e o codigo usa `env.DB`.
- O roteamento publico atual do backend usa o dominio `workers.dev`; ainda **nao** foi adaptado para `/stash/api/*`.
- O endpoint de webhook em producao e `POST /stripe/webhook`.
- O app/site devem chamar diretamente os endpoints do Worker ate que exista proxy, rewrite ou dominio customizado.
- O codigo de configuracao (`src/config.ts`) exige todos os secrets de Stripe e URLs no startup das rotas principais.
- Mesmo usando so `monthly` na UX agora, os secrets `*_YEARLY` continuam obrigatorios no estado atual do codigo.
- Em codigo de runtime Worker, a orientacao registrada foi preferir APIs web/standard em vez de depender de `Buffer` quando possivel.

Contratos HTTP atuais do Worker:

- `GET /health`
  - Retorna algo como `{ "ok": true, "service": "stash-licensing" }`.

- `POST /checkout/session`
  - Body:
    ```json
    {
      "email": "cliente@exemplo.com",
      "plan": "pro",
      "interval": "monthly"
    }
    ```
  - Retorno:
    ```json
    {
      "checkout_url": "...",
      "checkout_session_id": "...",
      "license_id": "...",
      "license_key": "..."
    }
    ```

- `POST /licenses/activate`
  - Body:
    ```json
    {
      "email": "cliente@exemplo.com",
      "license_key": "...",
      "device_id": "device-unico",
      "device_label": "MacBook Pro"
    }
    ```

- `POST /licenses/refresh`
  - Body:
    ```json
    {
      "email": "cliente@exemplo.com",
      "license_key": "...",
      "device_id": "device-unico"
    }
    ```

- `POST /billing/portal`
  - Body com `email` e/ou `license_key`.
  - Retorna `billing_portal_url`.

## Registro de Erros e Correcoes

- **Wrangler nao encontrado / fluxo Cloudflare incompleto**
  - Foi resolvido adicionando `wrangler` em `devDependencies` e scripts em `package.json`.

- **Uso incorreto de `npm exec wrangler ... --env prod`**
  - O `npm exec` interpretava `--env` de forma errada.
  - Solucao: usar `npm exec -- wrangler ...` ou, preferencialmente, `npx wrangler ...`.

- **Configuracao misturada de dev/prod no `wrangler.toml`**
  - O arquivo foi limpo para um caminho `prod-only`.

- **Criacao do subdominio `workers.dev`**
  - Tentar nomes como `stash` falhou por indisponibilidade.
  - Tentar FQDN como `stash.simplificandoproduto.com.br` falhou por formato invalido.
  - O subdominio correto da conta foi registrado e o deploy final saiu em `robsonferr.workers.dev`.

- **VS Code acusando `Cannot find name 'Buffer'`**
  - Isso mostrou um desalinhamento entre expectativas Node e runtime Worker.
  - A convencao do repositorio foi atualizada para privilegiar APIs web-standard no runtime.

- **Minimo para deploy vs minimo para funcionamento real**
  - Descoberta importante: o Worker sobe e responde em `/health` mesmo sem todos os secrets.
  - Porem as rotas principais chamam `getConfig()` e exigem os secrets obrigatorios.

## Licoes Aprendidas e Gotchas

- O `workers.dev` usa o padrao:
  - `<worker-name>.<account-subdomain>.workers.dev`
- O `name` do worker em producao esta como `stash-licensing-prod`.
- O `<account-subdomain>` nao e livre por deploy; ele e registrado uma vez por conta Cloudflare.
- O backend **ainda nao** responde em `/stash/api/*`; hoje os paths validos sao os do Worker raiz:
  - `/checkout/session`
  - `/stripe/webhook`
  - `/licenses/activate`
  - `/licenses/refresh`
  - `/billing/portal`
- Se o site publico quiser usar `/stash/api/*`, sera necessario:
  - adaptar o codigo para esse prefixo, ou
  - configurar reverse proxy/rewrite no Cloudflare.
- `APP_SUCCESS_URL` e `APP_CANCEL_URL` sao URLs de redirecionamento do navegador apos checkout; nao precisam ser rotas do Worker.
- `LICENSE_PEPPER` deve ser estavel; rotacao sem plano invalida hashes de licenca existentes.
- A chave **privada** de entitlement fica apenas no Worker; a **publica** precisa ir para o app `stash` para verificacao local.
- Para testes E2E do app, o fluxo correto e:
  - criar checkout
  - concluir compra no Stripe
  - deixar o webhook sincronizar estado
  - ativar licenca no app
  - refrescar entitlement periodicamente

## Mapa de Arquivos

Arquivos principais criados ou modificados nesta sessao:

- `.github/copilot-instructions.md`
  - instrucoes especificas do repositorio e convencoes para futuras sessoes

- `package.json`
  - scripts de `lint`, `test`, `check`, `deploy`, `cf:*` e `d1:*`

- `wrangler.toml`
  - configuracao `prod-only`
  - binding D1 `DB`
  - Worker `stash-licensing-prod`

- `docs/production-setup.md`
  - guia operacional completo de producao

- `scripts/create-d1-database.sh`
  - padronizado para uso com `npx wrangler`

- `scripts/apply-migrations.sh`
  - padronizado para uso com `npx wrangler`

- `src/index.ts`
  - entrypoint do Worker e mapa de rotas

- `src/config.ts`
  - validacao e leitura dos secrets/vars obrigatorios

- `src/routes/checkout.ts`
  - criacao de checkout session

- `src/routes/stripe-webhook.ts`
  - sincronizacao Stripe -> D1

- `src/routes/activate-license.ts`
  - ativacao de licenca por dispositivo

- `src/routes/refresh-license.ts`
  - refresh do entitlement para dispositivo ativo

- `src/routes/billing-portal.ts`
  - geracao de link para portal de billing

- `src/db/schema.sql`
  - schema do D1 ja aplicado em producao

- `src/crypto/sign-entitlement.ts`
  - assinatura dos entitlements

## Proximos Passos Imediatos

- [ ] No agente do app/web, implementar a chamada `POST /checkout/session` ao clicar em comprar/assinar.
- [ ] Redirecionar o usuario para o `checkout_url` retornado pelo Worker.
- [ ] Definir no site as paginas finais de sucesso e cancelamento, se ainda estiverem temporarias.
- [ ] No aplicativo `stash`, implementar `POST /licenses/activate`.
- [ ] No aplicativo `stash`, implementar `POST /licenses/refresh`.
- [ ] No app `stash`, embutir a chave publica de entitlement para verificar a assinatura localmente.
- [ ] Fazer um teste E2E com compra real/controlada: checkout -> webhook -> ativacao -> refresh.
- [ ] Decidir se o backend vai continuar em `workers.dev` inicialmente ou se sera movido para um caminho publico como `/stash/api/*`.
- [ ] Se quiser expor em `/stash/api/*`, criar tarefa dedicada para adaptar rotas do Worker ou configurar proxy/rewrite.
