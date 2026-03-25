# HANDOFF: `stash-licensing`

## Objetivo

Este handoff resume tudo o que foi decidido sobre o novo projeto privado `stash-licensing`.

O objetivo do projeto e criar o servico privado que vai controlar acesso pago ao Dashboard do Stash, substituindo o gate temporario em `UserDefaults` por um fluxo real de billing/licenciamento.

Este arquivo foi preparado para servir como contexto de partida de um novo agente dentro da pasta do novo projeto, onde serao feitos:

- `git init`
- configuracao do repositorio remoto
- scaffold inicial
- planejamento tecnico do MVP
- inicio da implementacao

---

## 1. Contexto do produto

O app `stash`:

- e um app macOS
- tem repositorio publico
- ja possui um Dashboard implementado
- hoje usa um gate local de plano apenas como MVP

Precisamos substituir esse gate local por uma solucao:

- simples
- segura o suficiente
- barata de operar
- compativel com distribuicao fora da App Store

---

## 2. Decisoes ja tomadas

### Distribuicao

- o app sera distribuido por **download direto / site / GitHub Releases**
- **nao** sera distribuido pela Mac App Store

### Billing

- o gateway escolhido e **Stripe**
- o modelo comercial escolhido e **assinatura recorrente**
- teremos cobranca **mensal e anual**

### Planos pagos no lancamento

Lancaremos com os dois planos e seus dois ciclos:

- `Pro Monthly`
- `Pro Yearly`
- `Premium Monthly`
- `Premium Yearly`

### Nome do repositorio privado

- nome escolhido: **`stash-licensing`**

### Hospedagem

- stack escolhida: **Cloudflare Workers + D1**

### Banco

- sim, teremos banco
- banco escolhido: **Cloudflare D1**

### Modelo de seguranca

- o app publico **nao** deve conter segredos
- o backend privado emite um **entitlement assinado**
- o app valida esse entitlement localmente com **chave publica**
- a **chave privada** de assinatura fica apenas no backend
- a `license key` e guardada no app em `Keychain`

### Posicionamento sobre repo publico

- o repo do app pode continuar publico
- o repo de billing/licenciamento precisa ser privado
- nao e necessario tornar o app fechado para viabilizar o modelo

---

## 3. Recomendacao arquitetural final

### Arquitetura escolhida

**Stripe + Cloudflare Worker + D1 + license key + entitlement assinado + Keychain no app**

### Componentes

#### App macOS (`stash`)

Responsavel por:

- abrir Checkout no browser
- pedir `email + license key`
- chamar ativacao
- chamar refresh de entitlement
- guardar entitlement no Keychain
- validar assinatura localmente com chave publica
- liberar ou bloquear o Dashboard

#### `stash-licensing` (repo privado)

Responsavel por:

- criar sessao de checkout
- receber webhooks do Stripe
- criar/atualizar licencas
- registrar ativacoes de device
- emitir entitlements assinados
- devolver link do Billing Portal

#### Stripe

Responsavel por:

- pagamento
- assinatura recorrente
- renovacao/cancelamento/inadimplencia
- Billing Portal

#### D1

Responsavel por:

- persistir licencas
- persistir ativacoes
- persistir idempotencia de webhooks
- persistir auditoria minima de entitlements

---

## 4. Por que essa arquitetura foi escolhida

### KISS

- evita auth completo
- evita painel admin no inicio
- evita infra pesada
- reaproveita Stripe, que ja e conhecido
- mantem a stack pequena

### Seguranca suficiente

- segredos fora do cliente
- app so recebe chave publica
- license key nao e armazenada em texto puro no backend
- webhooks do Stripe sao a base da verdade para o estado comercial

### Escalabilidade

Se crescer depois, da para adicionar:

- admin console
- suporte de devices
- antifraude
- observabilidade
- migracao para banco mais robusto, se necessario

---

## 5. Estrutura recomendada do repo `stash-licensing`

```text
stash-licensing/
  README.md
  package.json
  tsconfig.json
  wrangler.toml
  .dev.vars.example
  src/
    index.ts
    config.ts
    routes/
      checkout.ts
      stripe-webhook.ts
      activate-license.ts
      refresh-license.ts
      billing-portal.ts
    services/
      stripe.ts
      licensing.ts
      entitlements.ts
      device-activations.ts
      clock.ts
    db/
      schema.sql
      queries.ts
      mappers.ts
    crypto/
      sign-entitlement.ts
      hash-license-key.ts
      hash-device-id.ts
    types/
      api.ts
      billing.ts
      licensing.ts
    utils/
      http.ts
      validation.ts
      ids.ts
      logging.ts
  scripts/
    create-d1-database.sh
    apply-migrations.sh
  docs/
    stripe-price-map.md
    runbook-webhooks.md
    runbook-license-support.md
```

### Convencoes importantes

- `routes/` = camada HTTP fina
- `services/` = regra de negocio
- `db/` = SQL explicito e acesso ao D1
- `crypto/` = assinatura e hashing
- evitar frameworks pesados cedo demais
- evitar ORM complexo cedo demais

---

## 6. Ambientes

Criar pelo menos:

- `dev`
- `prod`

Cada ambiente deve ter:

- 1 Worker
- 1 banco D1
- 1 conjunto de secrets
- 1 ambiente Stripe correspondente

---

## 7. Secrets e configuracoes do Worker

### Secrets obrigatorios

- `STRIPE_SECRET_KEY`
- `STRIPE_WEBHOOK_SECRET`
- `STRIPE_PRICE_PRO_MONTHLY`
- `STRIPE_PRICE_PRO_YEARLY`
- `STRIPE_PRICE_PREMIUM_MONTHLY`
- `STRIPE_PRICE_PREMIUM_YEARLY`
- `ENTITLEMENT_PRIVATE_KEY`
- `LICENSE_PEPPER`
- `APP_SUCCESS_URL`
- `APP_CANCEL_URL`

### Configs opcionais

- `STRIPE_BILLING_PORTAL_CONFIGURATION_ID`
- `GRACE_PERIOD_DAYS`
- `ENTITLEMENT_TTL_DAYS`

### Binding D1

- `DB`

---

## 8. Modelo de dados D1 decidido

### Tabela `licenses`

Campos principais:

- `id`
- `license_key_hash`
- `customer_email`
- `stripe_customer_id`
- `stripe_subscription_id`
- `stripe_checkout_session_id`
- `plan`
- `status`
- `max_activations`
- `expires_at`
- `last_entitlement_issued_at`
- `created_at`
- `updated_at`

### Tabela `license_activations`

Campos principais:

- `id`
- `license_id`
- `device_id_hash`
- `device_label`
- `first_seen_at`
- `last_seen_at`
- `revoked_at`

### Tabela `stripe_events`

Campos principais:

- `id`
- `type`
- `received_at`
- `processed_at`
- `status`

### Tabela `entitlement_audit`

Campos principais:

- `id`
- `license_id`
- `status`
- `plan`
- `expires_at`
- `issued_at`

### Defaults operacionais decididos

- limite inicial de ativacoes: **2 devices**
- entitlement TTL: **7 dias**
- grace period: **7 dias**

---

## 9. Endpoints decididos

### `POST /checkout/session`

Cria Stripe Checkout Session.

Entrada esperada:

- `plan`
- `interval`
- `email` opcional

### `POST /stripe/webhook`

Recebe webhooks do Stripe com validacao de assinatura.

### `POST /licenses/activate`

Ativa uma licenca com:

- `email`
- `license_key`
- `device_id`
- `device_label` opcional

Retorna:

- plano
- status
- entitlement assinado

### `POST /licenses/refresh`

Atualiza entitlement para um device ja ativado.

### `POST /billing/portal`

Retorna URL do Billing Portal do Stripe.

---

## 10. Eventos Stripe que devem ser tratados

Eventos obrigatorios no MVP:

- `checkout.session.completed`
- `customer.subscription.created`
- `customer.subscription.updated`
- `customer.subscription.deleted`
- `invoice.paid`
- `invoice.payment_failed`

### Regras operacionais

- webhook precisa ser **idempotente**
- registrar `event_id` no banco
- mapear estado Stripe para estado interno da licenca

---

## 11. Modelo de license key e entitlement

### License key

Formato sugerido:

- `stash_XXXX-XXXX-XXXX-XXXX`

Regras:

- gerar com alta entropia
- **nao armazenar em texto puro**
- armazenar apenas hash com pepper do servidor

### Entitlement assinado

Payload sugerido:

```json
{
  "iss": "stash-licensing",
  "aud": "stash-macos-app",
  "license_id": "lic_xxx",
  "plan": "pro",
  "status": "active",
  "customer_email": "user@example.com",
  "device_id_hash": "dev_xxx",
  "issued_at": "2026-03-19T00:00:00Z",
  "expires_at": "2026-03-26T00:00:00Z",
  "grace_until": "2026-04-02T00:00:00Z"
}
```

Regras:

- assinatura assimetrica
- chave privada fica no backend
- chave publica fica no app

---

## 12. Fase 1 MVP decidida

### Objetivo

Entregar o minimo necessario para substituir o gate local do Dashboard.

### Entregas

#### 1. Bootstrap do repo

- criar repo privado
- configurar Worker em TypeScript
- configurar `wrangler.toml`
- configurar `dev` e `prod`
- criar `.dev.vars.example`

#### 2. Banco e migracoes

- criar schema D1
- criar scripts de bootstrap/migration
- validar schema localmente

#### 3. Stripe setup

- criar products/prices
- mapear os 4 `price_id`s
- implementar checkout

#### 4. Webhooks

- validar assinatura
- processar eventos
- salvar idempotencia

#### 5. Licenciamento

- gerar `license key`
- salvar hash
- criar licenca a partir de compra/assinatura

#### 6. Entitlement

- assinar entitlement
- armazenar auditoria minima

#### 7. API para o app

- `POST /checkout/session`
- `POST /licenses/activate`
- `POST /licenses/refresh`
- `POST /billing/portal`

### Fora da fase 1

- painel admin
- auth completo
- gestao self-service de devices
- antifraude avancado
- suporte interno sofisticado

---

## 13. Ordem recomendada de execucao no novo projeto

1. iniciar repo `stash-licensing`
2. configurar remoto
3. scaffold do Worker TypeScript
4. configurar `wrangler.toml`
5. configurar D1 `dev` e `prod`
6. criar schema SQL
7. implementar `POST /checkout/session`
8. implementar `POST /stripe/webhook`
9. implementar geracao e hash de `license key`
10. implementar assinatura de entitlement
11. implementar `POST /licenses/activate`
12. implementar `POST /licenses/refresh`
13. implementar `POST /billing/portal`
14. documentar setup local e secrets

---

## 14. Boundary de seguranca

### Pode ficar no repo publico do app

- UI de upgrade/ativacao
- URL da API
- chave publica
- gate local que valida entitlement
- integracao com Keychain

### Deve ficar no repo privado

- codigo do Worker
- integracao Stripe
- schema D1 e migracoes
- logica de hashing de `license key`
- logica de assinatura de entitlement
- secrets

### Nunca colocar no app

- `STRIPE_SECRET_KEY`
- `STRIPE_WEBHOOK_SECRET`
- `ENTITLEMENT_PRIVATE_KEY`
- `LICENSE_PEPPER`

---

## 15. Trade-offs aceitos

- como a feature premium roda localmente no app, sempre existira algum risco de bypass por engenharia reversa
- o objetivo aqui e impedir abuso casual/em massa, nao buscar protecao perfeita
- D1 foi escolhido por simplicidade, nao por ser o banco mais robusto possivel

---

## 16. Artefatos de referencia ja produzidos no repo atual

Se o novo agente quiser contexto extra, usar estes arquivos como referencia:

- `stash-docs/knowledge/architecture/stash-licensing-service-architecture.md`
- `stash-docs/knowledge/architecture/stash-licensing-d1-schema.md`
- `stash-docs/knowledge/architecture/stash-licensing-private-repo-structure.md`
- `stash-docs/knowledge/architecture/stash-licensing-phase-1-mvp.md`
- `stash-docs/knowledge/api-surface/stash-licensing-api-contracts.md`
- `stash-docs/knowledge/conventions/stash-licensing-boundaries-and-secrets.md`

---

## 17. O que o proximo agente deve fazer primeiro

Ao iniciar no novo projeto `stash-licensing`, o agente deve:

1. criar e organizar o repo
2. configurar stack `Cloudflare Workers + D1 + TypeScript`
3. planejar o scaffold inicial do codigo
4. definir os arquivos iniciais reais do projeto
5. preparar o backlog tecnico da fase 1
6. comecar a implementacao do bootstrap

---

## 18. Resumo executivo final

`stash-licensing` sera um repo privado em **Cloudflare Workers + D1**, usando **Stripe** para cobranca recorrente de `Pro` e `Premium`, com ciclos **mensal e anual**, ativacao por **email + license key**, e controle de acesso por **entitlement assinado** validado localmente pelo app.

Esse e o desenho aprovado para iniciar o novo projeto.
