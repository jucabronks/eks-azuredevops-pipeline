kubectl rollout undo deployment/eks-azuredevops-app 

- script: |
    kubectl rollout status deployment/eks-azuredevops-app --timeout=60s || \
    kubectl rollout undo deployment/eks-azuredevops-app
  displayName: 'Verificar rollout e fazer rollback se necessário' 

## Rollback Automático em Caso de Erro

O pipeline Azure DevOps está configurado para realizar rollback automático caso o deploy falhe:
- Após o deploy, o pipeline verifica o status do rollout do deployment.
- Se houver erro (ex: pods não sobem, healthcheck falha), executa automaticamente o rollback para a versão anterior estável.

### Como funciona
```yaml
- script: |
    kubectl rollout status deployment/eks-azuredevops-app --timeout=60s || \
    kubectl rollout undo deployment/eks-azuredevops-app
  displayName: 'Verificar rollout e fazer rollback se necessário'
```

### Como monitorar e auditar rollbacks
- O histórico de rollouts pode ser consultado com:
  ```sh
  kubectl rollout history deployment/eks-azuredevops-app
  ```
- Logs do pipeline Azure DevOps mostram quando um rollback foi executado.
- (Opcional) Adicione notificações (Teams, Slack, email) em caso de rollback usando tasks de notificação no pipeline.

### Sugestão: Rollout Progressivo e Rollback Avançado
Para ambientes críticos, considere ferramentas que fazem rollout progressivo e rollback automático baseado em métricas:
- **Argo Rollouts:** Deploys canário, blue/green, rollback automático por métricas (Prometheus, Datadog, etc).
  - [Argo Rollouts Docs](https://argoproj.github.io/argo-rollouts/)
- **Flagger:** Automação de rollout progressivo e rollback com análise de métricas.
  - [Flagger Docs](https://docs.flagger.app/)

Essas ferramentas integram com Prometheus, Grafana, Datadog e podem ser instaladas via Helm no EKS. 

- task: SendEmail@1
  condition: failed()
  inputs:
    To: 'seu@email.com'
    Subject: 'Erro/Rollback no deploy EKS'
    Body: 'O deploy falhou e um rollback foi executado. Verifique os logs do pipeline para detalhes.' 

- script: |
    curl -H 'Content-Type: application/json' -d '{"text":"[ALERTA] O deploy no EKS falhou e rollback foi executado!"}' https://seu_webhook_url
  displayName: 'Notificar Teams/Slack em caso de erro'
  condition: failed() 

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update 

helm upgrade --install argo-rollouts argo/argo-rollouts --namespace argo-rollouts --create-namespace 

kubectl get pods -n argo-rollouts 

kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/dashboard-install.yaml
kubectl port-forward -n argo-rollouts service/argo-rollouts-dashboard 3100:3100 

kubectl argo rollouts get rollout eks-azuredevops-app
kubectl argo rollouts promote eks-azuredevops-app 

kubectl apply -f k8s/rollout.yaml 

## Checklist para Substituição de Variáveis e Placeholders (Passo a Passo para Iniciantes)

Antes de rodar o pipeline e fazer o deploy, **você precisa substituir alguns valores de exemplo pelos dados do seu ambiente**. Siga este passo a passo:

### 1. Pipeline Azure DevOps (`pipelines/azure-pipelines.yml`)
- **`<seu_ecr_repo>`**: Nome do repositório ECR onde a imagem Docker será publicada.
  - Exemplo: `123456789012.dkr.ecr.us-east-1.amazonaws.com/eks-azuredevops-app`
  - Onde encontrar: Console AWS > ECR > Repositórios
- **`<seu_service_connection>`**: Nome da conexão de serviço AWS configurada no Azure DevOps.
  - Onde encontrar: Azure DevOps > Projeto > Project Settings > Service connections
- **`<seu_eks_cluster>`**: Nome do seu cluster EKS.
  - Onde encontrar: Console AWS > EKS > Clusters
- **`<seu_datadog_api_key>`**: Sua chave de API do Datadog.
  - Onde encontrar: Datadog > Integrations > APIs > API Keys
- **`https://seu_webhook_url`**: URL do webhook do Teams ou Slack para notificações.
  - Onde encontrar: Teams/Slack > Configurações de Webhook
- **`seu@email.com`**: Email para receber notificações de erro.
  - Onde encontrar: Seu email corporativo ou pessoal

### 2. Manifests Kubernetes (`k8s/deployment.yaml`, `k8s/rollout.yaml`)
- **`<seu_ecr_repo>:<tag>`**: Imagem Docker publicada no ECR.
  - Exemplo: `123456789012.dkr.ecr.us-east-1.amazonaws.com/eks-azuredevops-app:latest`
  - Dica: O pipeline já gera a tag automaticamente, mas confira se está igual ao pipeline.

### 3. Monitoramento (`k8s/datadog-values.yaml`)
- **`<DATADOG_API_KEY>`**: Substitua pela sua chave Datadog.

### 4. Infraestrutura (Terraform)
- **Variáveis do cluster**: Nome, região, roles, etc. Devem bater com o que está no pipeline e nos manifests.
  - Onde encontrar: Arquivos Terraform (`infra/` ou `terraform/`), console AWS

## Passo a Passo Resumido
1. **Clone o repositório**
2. **Substitua todos os valores acima nos arquivos indicados**
3. **Provisionar o EKS com Terraform** (se ainda não existir)
4. **Configure o Azure DevOps com as permissões e conexões necessárias**
5. **Execute o pipeline**
6. **Acompanhe o deploy, monitoramento e notificações**

> Se tiver dúvidas, consulte a documentação oficial de cada serviço ou peça ajuda para um colega mais experiente. Este projeto foi pensado para ser didático e seguro para iniciantes! 

## Como Colocar Toda a Infraestrutura no Azure DevOps (Passo a Passo para Iniciantes)

Siga este passo a passo para configurar e rodar toda a infraestrutura e deploy automatizado no Azure DevOps, mesmo sem experiência prévia:

### 1. Crie um Repositório no Azure DevOps
- Acesse [dev.azure.com](https://dev.azure.com)
- Crie um novo projeto (ex: `eks-azuredevops-pipeline`)
- Crie um novo repositório Git e faça o push do código do projeto (pasta `eks-azuredevops-pipeline/`)

### 2. Configure as Conexões de Serviço (Service Connections)
Essas conexões permitem que o pipeline acesse a AWS (ECR, EKS).

**A) AWS Service Connection**
1. No Azure DevOps, vá em **Project Settings > Service connections**.
2. Clique em **New service connection > AWS**.
3. Insira as credenciais de acesso (Access Key ID e Secret Access Key) de um usuário IAM com permissões para ECR, EKS e EC2.
4. Dê um nome fácil de lembrar (ex: `aws-eks-connection`).

### 3. Configure as Variáveis/Secrets no Azure DevOps
- Vá em **Pipelines > Library** e crie um grupo de variáveis chamado `secrets`.
- Adicione:
  - `DATADOG_API_KEY` (se for usar Datadog)
  - Outras chaves sensíveis, se necessário

### 4. Ajuste os Placeholders no Código
- No arquivo `pipelines/azure-pipelines.yml`, substitua:
  - `<seu_ecr_repo>` pelo seu repositório ECR
  - `<seu_service_connection>` pelo nome da conexão criada
  - `<seu_eks_cluster>` pelo nome do cluster EKS
  - `<seu_datadog_api_key>` pela variável de secret ou valor direto
  - `<seu_webhook_url>` pelo URL do Teams/Slack
  - `seu@email.com` pelo seu email

### 5. Crie o Pipeline no Azure DevOps
1. Vá em **Pipelines > Pipelines** e clique em **New Pipeline**.
2. Escolha o repositório criado.
3. Selecione a opção **YAML** e aponte para o arquivo `eks-azuredevops-pipeline/pipelines/azure-pipelines.yml`.
4. Salve e rode o pipeline.

### 6. Provisionar o EKS (se ainda não existir)
- Use o Terraform do projeto para criar o cluster EKS:
  ```sh
  cd eks-azuredevops-pipeline/infra/
  terraform init
  terraform apply
  ```
- Aguarde o cluster ser criado e anote o nome/endpoint.

### 7. Execute o Pipeline
- O pipeline irá:
  - Buildar a imagem Docker
  - Fazer push para o ECR
  - Deploy no EKS (Deployment/Rollout, Service, Ingress)
  - Instalar Prometheus, Grafana, Datadog via Helm
  - Verificar rollout e fazer rollback automático se necessário
  - Enviar notificações em caso de erro

### 8. Acompanhe o Deploy e Monitoramento
- Use o Azure DevOps para ver logs e status do pipeline.
- Acesse o Grafana, Prometheus e Datadog conforme instruções deste README.
- Teste o acesso ao app via Ingress (NGINX/ALB).

---

> **Dica:** Sempre valide se as permissões do IAM estão corretas. Se der erro, cheque os logs do pipeline e as notificações. Para dúvidas, consulte a documentação oficial ou peça ajuda para um colega. 

## **Como usar localmente (DEV)**
Se quiser rodar o app localmente com Docker:
```sh
cd eks-azuredevops-pipeline/app
docker build -t eks-azuredevops-app:dev .
docker run -p 3000:3000 eks-azuredevops-app:dev
```
Acesse em: [http://localhost:3000](http://localhost:3000)

## **Resumo**
- O projeto já está pronto para Docker, tanto para desenvolvimento local quanto para deploy em nuvem.
- Se quiser, posso adicionar um `docker-compose.yml` para facilitar ainda mais o uso local (inclusive com banco de dados local, se desejar).

**Quer que eu adicione um exemplo de banco de dados (DynamoDB, RDS ou local) ao Docker Compose e à infraestrutura?**  
Se sim, só avisar qual banco prefere! 

## Integração com DynamoDB (Ambiente DEV)

### 1. Provisionar a tabela DynamoDB
- O Terraform já cria a tabela `dev-app-data` automaticamente:
  ```sh
  cd infra/
  terraform init
  terraform apply
  ```

### 2. Configurar variáveis de ambiente
- No app Node.js, use:
  - `AWS_REGION=us-east-1`
  - `DYNAMODB_TABLE=dev-app-data`
- No Kubernetes, adicione essas variáveis no Deployment/Rollout se desejar usar em produção/dev cloud.

### 3. Testar integração Node.js
- O app expõe endpoints para CRUD simples:
  - `GET /items/:id` — Busca item pelo id
  - `POST /items` — Cria/atualiza item (JSON com campo `id` obrigatório)

**Exemplo de uso com curl:**
```sh
curl -X POST http://localhost:3000/items -H 'Content-Type: application/json' -d '{"id":"123","nome":"teste"}'
curl http://localhost:3000/items/123
```

### 4. Dicas para DEV
- O DynamoDB em modo `PAY_PER_REQUEST` não gera custo se não for usado.
- Para testar local, use as variáveis de ambiente no `.env` ou exporte antes de rodar o app.
- Para produção, use IAM Roles for Service Accounts (IRSA) para acesso seguro no EKS. 

## **Como Criar um Agente Linux Self-Hosted no Azure DevOps**

### **1. Pré-requisitos**
- Uma VM ou máquina Linux (pode ser local, cloud, WSL, etc).
- Docker instalado (opcional, mas recomendado para builds de container).

### **2. No Azure DevOps**
1. Vá em **Project Settings > Agent Pools**.
2. Clique em **Add pool** (ou use o pool "Default").
3. Clique no pool desejado e depois em **New agent**.
4. Selecione **Linux** e copie o script de instalação fornecido.

### **3. No seu Linux**
Execute os comandos abaixo (ajuste o diretório se quiser):

```sh
# Baixe o agente
mkdir myagent && cd myagent
wget https://vstsagentpackage.azureedge.net/agent/3.236.1/vsts-agent-linux-x64-3.236.1.tar.gz
tar zxvf vsts-agent-linux-x64-3.236.1.tar.gz

# Instale dependências
sudo apt-get install -y libssl-dev

# Configure o agente (siga as instruções, cole o token do Azure DevOps)
./config.sh

# Inicie o agente
./run.sh
```

> O Azure DevOps vai pedir a URL da sua organização, o nome do agente e um token de acesso (você gera na tela do Azure DevOps).

### **4. (Opcional) Rodar como serviço**
Para não precisar rodar manualmente toda vez:
```sh
sudo ./svc.sh install
sudo ./svc.sh start
```

---

## **Dicas**
- O agente aparecerá disponível no Azure DevOps em "Agent Pools".
- Você pode rodar builds ilimitados sem consumir os minutos gratuitos.
- Pode instalar Docker, Node.js, Terraform, etc, conforme sua necessidade.

---

Se quiser, posso te ajudar a:
- Gerar o PAT (Personal Access Token) para o agente
- Instalar dependências específicas (Docker, kubectl, etc)
- Automatizar o setup do agente

Só avisar se precisar de algum passo detalhado ou script pronto! 

## CI/CD no Azure DevOps: Passo a Passo Crucial para Iniciantes

### **Primeiro Passo Importante: Criar o Pipeline no Azure DevOps**
1. Acesse [dev.azure.com](https://dev.azure.com) e entre no seu projeto.
2. No menu lateral, clique em **Pipelines > Pipelines**.
3. Clique em **New Pipeline**.
4. Escolha **Azure Repos Git** e selecione o repositório do seu projeto.
5. Escolha a opção **YAML**.
6. Aponte para o arquivo `eks-azuredevops-pipeline/pipelines/azure-pipelines.yml`.
7. Clique em **Save and run** para salvar e rodar o pipeline.

### **Segundo Passo Importante: Configurar o Agente (Runner)**
- **Microsoft-hosted:**
  - Não precisa configurar nada, já vem pronto para uso (Linux, Windows, macOS).
  - Ideal para começar e testar rapidamente.
- **Self-hosted (Linux):**
  - Permite builds ilimitados e mais controle.
  - Veja o passo a passo abaixo para criar seu próprio agente Linux.

#### Como criar um agente Linux self-hosted
1. No Azure DevOps, vá em **Project Settings > Agent Pools**.
2. Clique em **Add pool** (ou use o pool "Default").
3. Clique no pool desejado e depois em **New agent**.
4. Selecione **Linux** e copie o script de instalação fornecido.
5. No seu Linux (VM, WSL, cloud, etc):
   ```sh
   mkdir myagent && cd myagent
   wget https://vstsagentpackage.azureedge.net/agent/3.236.1/vsts-agent-linux-x64-3.236.1.tar.gz
   tar zxvf vsts-agent-linux-x64-3.236.1.tar.gz
   sudo apt-get install -y libssl-dev
   ./config.sh  # Siga as instruções, cole o token do Azure DevOps
   ./run.sh     # Para rodar manualmente
   # (Opcional) Para rodar como serviço:
   sudo ./svc.sh install
   sudo ./svc.sh start
   ```
6. O agente aparecerá disponível no Azure DevOps em "Agent Pools".

### **Terceiro Passo Importante: Configurar Service Connections e Variáveis/Secrets**
- **Service Connection AWS:**
  1. No Azure DevOps, vá em **Project Settings > Service connections**.
  2. Clique em **New service connection > AWS**.
  3. Preencha com as credenciais IAM e salve.
- **Variáveis/Secrets:**
  1. Vá em **Pipelines > Library > + Variable group**.
  2. Adicione secrets como `DATADOG_API_KEY` e outras chaves necessárias.

### **Quarto Passo Importante: Ajustar Placeholders nos Arquivos**
- Edite os arquivos YAML e substitua todos os `<seu_ecr_repo>`, `<seu_service_connection>`, `<seu_eks_cluster>`, `<seu_datadog_api_key>`, `<seu_webhook_url>`, `seu@email.com` pelos valores reais do seu ambiente.

### **Quinto Passo Importante: Provisionar EKS e DynamoDB**
- Se ainda não existir, rode o Terraform:
  ```sh
  cd infra/
  terraform init
  terraform apply
  ```
- Aguarde a criação dos recursos.

### **Sexto Passo Importante: Executar e Acompanhar o Pipeline**
- Clique em **Run pipeline** para rodar o CI/CD.
- Acompanhe o progresso, logs e resultados na interface do Azure DevOps.
- Se der erro, clique no job para ver detalhes e mensagens de erro.

### **Dicas para troubleshooting**
- Verifique se todos os placeholders e variáveis estão corretos.
- Confira se o agente (Microsoft ou self-hosted) está online.
- Veja os logs detalhados do pipeline para identificar problemas.
- Consulte a documentação oficial do Azure DevOps para dúvidas específicas.

---

> Com essa ordem de passos, qualquer pessoa pode criar e rodar o CI/CD do projeto no Azure DevOps, mesmo sem experiência prévia! 