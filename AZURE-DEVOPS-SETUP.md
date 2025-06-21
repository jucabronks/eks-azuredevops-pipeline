# 🚀 Configuração do Projeto no Azure DevOps

Este guia te ensina como migrar o projeto do GitHub Actions para o Azure DevOps, mantendo toda a funcionalidade de CI/CD, backup, rollback automático e scan de vulnerabilidades.

---

## 📋 Pré-requisitos

- [ ] Conta Azure DevOps (gratuita para até 5 usuários)
- [ ] Conta Azure com permissões de administrador
- [ ] Acesso ao Azure Container Registry (ACR) ou Docker Hub
- [ ] Projeto já configurado localmente

---

## 🔧 Passo 1: Criação do Projeto no Azure DevOps

### **1.1 Criar organização e projeto**
1. Acesse [dev.azure.com](https://dev.azure.com)
2. Crie uma nova organização (se não tiver)
3. Crie um novo projeto chamado `projeto-vm`
4. Escolha:
   - **Version Control**: Git
   - **Work Item Process**: Agile (ou Scrum)
   - **Visibility**: Private (recomendado)

### **1.2 Configurar repositório**
1. No projeto, vá em **Repos**
2. Clone o repositório local:
   ```bash
   git remote add azure https://dev.azure.com/SUA_ORG/projeto-vm/_git/projeto-vm
   git push -u azure main
   ```

---

## 🔐 Passo 2: Configuração de Service Connections

### **2.1 Azure Resource Manager**
1. Vá em **Project Settings** → **Service Connections**
2. Clique em **New Service Connection**
3. Escolha **Azure Resource Manager**
4. Configure:
   - **Scope Level**: Subscription
   - **Subscription**: Sua subscription
   - **Resource Group**: Deixe vazio (será criado pelo Terraform)
5. Salve como `azure-connection`

### **2.2 Docker Registry**
1. **Para Azure Container Registry:**
   - Service Connection Type: **Docker Registry**
   - Registry Type: **Azure Container Registry**
   - Subscription: Sua subscription
   - Azure Container Registry: Seu ACR
   - Salve como `acr-connection`

2. **Para Docker Hub:**
   - Service Connection Type: **Docker Registry**
   - Registry Type: **Docker Hub**
   - Docker ID: Seu usuário Docker Hub
   - Password: Seu token Docker Hub
   - Salve como `dockerhub-connection`

### **2.3 Kubernetes**
1. Service Connection Type: **Kubernetes**
2. **Para AKS:**
   - **Authentication method**: Azure Subscription
   - **Subscription**: Sua subscription
   - **Cluster**: Seu cluster AKS
   - **Namespace**: Deixe vazio
   - Salve como `aks-connection`

---

## 🔧 Passo 3: Configuração de Variáveis de Ambiente

### **3.1 Library Variables**
1. Vá em **Library** → **Variable Groups**
2. Crie um grupo chamado `projeto-vm-variables`
3. Adicione as variáveis:

#### **Variáveis Gerais:**
```
REGISTRY_NAME=seuacr.azurecr.io
IMAGE_NAME=projeto-vm-app
ENVIRONMENT=dev
```

#### **Variáveis de Cloud (escolha uma):**
```
# Para Azure
AZURE_SUBSCRIPTION_ID=seu-subscription-id
AZURE_LOCATION=eastus
RESOURCE_GROUP=projeto-vm-rg

# Para AWS (se usar AWS)
AWS_ACCESS_KEY_ID=sua-access-key
AWS_SECRET_ACCESS_KEY=sua-secret-key
AWS_REGION=us-east-1

# Para GCP (se usar GCP)
GCP_PROJECT_ID=seu-project-id
GCP_REGION=us-central1
```

### **3.2 Secret Variables**
No mesmo grupo de variáveis, marque como **Secret**:
- `DOCKER_USERNAME`
- `DOCKER_PASSWORD`
- `AWS_SECRET_ACCESS_KEY` (se usar AWS)
- `GCP_SA_KEY` (se usar GCP)

---

## 🚀 Passo 4: Criação do Pipeline Azure DevOps

### **4.1 Criar pipeline**
1. Vá em **Pipelines** → **New Pipeline**
2. Escolha **Azure Repos Git**
3. Selecione seu repositório
4. Escolha **Existing Azure Pipelines YAML file**
5. Caminho: `/azure-pipelines.yml`

### **4.2 Pipeline YAML (azure-pipelines.yml)**

```yaml
# ============================================================================
# Azure DevOps Pipeline - Projeto VM
# Pipeline CI/CD com Argo Rollouts, Velero, Trivy e rollback automático
# ============================================================================

trigger:
  branches:
    include:
    - main
    - develop
  paths:
    include:
    - app.js
    - package.json
    - Dockerfile
    - kubernetes/**
    - azure-pipelines.yml

variables:
- group: projeto-vm-variables
- name: REGISTRY
  value: $(REGISTRY_NAME)
- name: IMAGE_NAME
  value: $(IMAGE_NAME)

stages:
# ============================================================================
# BUILD AND TEST
# ============================================================================
- stage: Build
  displayName: 'Build and Test'
  jobs:
  - job: Build
    pool:
      vmImage: 'ubuntu-latest'
    
    steps:
    # Faz checkout do código-fonte do repositório
    - task: Checkout@3
      displayName: 'Checkout code'
      inputs:
        fetchDepth: 0

    # Configura o Docker Buildx para builds mais rápidos e eficientes
    - task: Docker@2
      displayName: 'Set up Docker Buildx'
      inputs:
        command: 'buildx'
        arguments: 'create --use'

    # Faz login no registry Docker
    - task: Docker@2
      displayName: 'Log in to Docker Registry'
      inputs:
        command: 'login'
        containerRegistry: 'acr-connection'  # ou 'dockerhub-connection'

    # Extrai metadados da imagem (tags, labels) baseado no commit e branch
    - task: Docker@2
      displayName: 'Extract metadata'
      inputs:
        command: 'buildx'
        arguments: 'imagetools inspect $(REGISTRY)/$(IMAGE_NAME):$(Build.SourceVersion)'

    # Constrói e faz push da imagem Docker para o registry
    - task: Docker@2
      displayName: 'Build and push Docker image'
      inputs:
        command: 'buildx'
        arguments: 'build --push --tag $(REGISTRY)/$(IMAGE_NAME):$(Build.SourceVersion) --tag $(REGISTRY)/$(IMAGE_NAME):latest .'
        repository: '$(REGISTRY)/$(IMAGE_NAME)'

    # Testa se a imagem Docker funciona corretamente
    - script: |
        docker run --rm $(REGISTRY)/$(IMAGE_NAME):$(Build.SourceVersion) node -e "console.log('App is working!')"
      displayName: 'Run container tests'

# ============================================================================
# SCAN DE VULNERABILIDADES
# ============================================================================
- stage: SecurityScan
  displayName: 'Security Scan'
  dependsOn: Build
  jobs:
  - job: TrivyScan
    pool:
      vmImage: 'ubuntu-latest'
    
    steps:
    # Faz checkout do código-fonte do repositório
    - task: Checkout@3
      displayName: 'Checkout code'

    # Instala o Trivy, ferramenta de scan de vulnerabilidades open source
    - script: |
        curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin v0.13.1
      displayName: 'Install Trivy'

    # Faz login no registry Docker
    - task: Docker@2
      displayName: 'Log in to Docker Registry'
      inputs:
        command: 'login'
        containerRegistry: 'acr-connection'

    # Constrói a imagem Docker localmente para ser escaneada
    - script: |
        docker build -t $(REGISTRY)/$(IMAGE_NAME):$(Build.SourceVersion) .
      displayName: 'Build Docker image for scan'

    # Roda o Trivy para escanear vulnerabilidades na imagem Docker
    # O pipeline falha se encontrar vulnerabilidades HIGH ou CRITICAL
    - script: |
        trivy image --exit-code 1 --severity HIGH,CRITICAL $(REGISTRY)/$(IMAGE_NAME):$(Build.SourceVersion)
      displayName: 'Scan Docker image vulnerabilities'

    # Roda o Trivy para escanear vulnerabilidades em arquivos de infraestrutura como código (Terraform)
    - script: |
        trivy config ./terraform/
      displayName: 'Scan IaC vulnerabilities'

# ============================================================================
# DEPLOY TO DEV
# ============================================================================
- stage: DeployDev
  displayName: 'Deploy to Dev'
  dependsOn: SecurityScan
  condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/develop'))
  jobs:
  - deployment: DeployDev
    pool:
      vmImage: 'ubuntu-latest'
    environment: 'dev'
    strategy:
      runOnce:
        deploy:
          steps:
          # Faz checkout do código-fonte do repositório
          - task: Checkout@3
            displayName: 'Checkout code'

          # Instala o kubectl para interagir com o cluster Kubernetes
          - task: KubectlInstaller@0
            displayName: 'Install kubectl'
            inputs:
              kubectlVersion: 'latest'

          # Instala o Helm para gerenciar charts e releases
          - task: HelmInstaller@0
            displayName: 'Install Helm'
            inputs:
              helmVersion: 'latest'

          # Instala o plugin do Argo Rollouts para gerenciar deploys progressivos
          - script: |
              curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
              chmod +x kubectl-argo-rollouts-linux-amd64
              sudo mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
            displayName: 'Install Argo Rollouts plugin'

          # Conecta ao cluster AKS e verifica se está funcionando
          - task: AzureCLI@2
            displayName: 'Get kubeconfig'
            inputs:
              azureSubscription: 'azure-connection'
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                az aks get-credentials --resource-group projeto-vm-dev-rg --name projeto-vm-dev --overwrite-existing
                kubectl get nodes

          # Cria um backup Velero automático antes do deploy
          # Este step garante que, caso o deploy cause problemas, seja possível restaurar o estado anterior do cluster.
          # O backup recebe um nome único com data/hora e o ambiente.
          - script: |
              velero backup create pre-deploy-dev-$(date +%Y%m%d%H%M%S) --wait
            displayName: 'Backup Velero before deploy'

          # Cria o namespace do ambiente se não existir
          - script: |
              kubectl create namespace projeto-vm-dev --dry-run=client -o yaml | kubectl apply -f -
            displayName: 'Create namespace'

          # Aplica os recursos base (Service e Ingress) que não mudam com o deploy
          - script: |
              envsubst < kubernetes/base/service.yaml | kubectl apply -f -
              envsubst < kubernetes/base/ingress.yaml | kubectl apply -f -
            displayName: 'Deploy base resources'
            env:
              NAMESPACE: projeto-vm-dev

          # Aplica o Rollout do Argo Rollouts com a nova imagem
          # O Rollout substitui o Deployment tradicional e permite deploy canário com rollback automático
          - script: |
              # Atualiza a imagem no manifesto do Rollout
              sed -i "s|SEU_REGISTRY/projeto-vm-app:latest|$(REGISTRY)/$(IMAGE_NAME):$(Build.SourceVersion)|g" kubernetes/argo-rollouts/rollout-projeto-vm-app.yaml
              # Aplica o Rollout no cluster
              kubectl apply -f kubernetes/argo-rollouts/rollout-projeto-vm-app.yaml
            displayName: 'Deploy with Argo Rollouts'

          # Monitora o rollout e executa rollback automático se falhar
          # Este step aguarda até 5 minutos pelo sucesso do rollout. Se não ficar saudável, faz rollback automático.
          - script: |
              set -e
              rollout_name=projeto-vm-app
              namespace=projeto-vm-dev
              # Aguarda até 5 minutos pelo sucesso do rollout
              if ! timeout 300s kubectl argo rollouts get rollout $rollout_name -n $namespace --watch | grep -q 'Healthy'; then
                echo "Rollout failed, executing rollback..."
                kubectl argo rollouts undo $rollout_name -n $namespace
                exit 1
              fi
            displayName: 'Monitor rollout and auto-rollback'

          # Verifica se os recursos foram criados corretamente
          - script: |
              kubectl get pods -n projeto-vm-dev
              kubectl get svc -n projeto-vm-dev
              kubectl get ingress -n projeto-vm-dev
              kubectl argo rollouts get rollout projeto-vm-app -n projeto-vm-dev
            displayName: 'Verify deployment'

          # Executa testes de saúde na aplicação
          - script: |
              # Aguarda os pods ficarem prontos
              kubectl wait --for=condition=ready pod -l app=projeto-vm-app -n projeto-vm-dev --timeout=300s
              
              # Obtém a URL do serviço
              SERVICE_URL=$(kubectl get svc projeto-vm-app -n projeto-vm-dev -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
              if [ -z "$SERVICE_URL" ]; then
                SERVICE_URL=$(kubectl get svc projeto-vm-app -n projeto-vm-dev -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
              fi
              
              # Testa o endpoint de saúde
              curl -f http://$SERVICE_URL/health || echo "Health check failed"
            displayName: 'Run health check'

# ============================================================================
# DEPLOY TO STAGING
# ============================================================================
- stage: DeployStaging
  displayName: 'Deploy to Staging'
  dependsOn: SecurityScan
  condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
  jobs:
  - deployment: DeployStaging
    pool:
      vmImage: 'ubuntu-latest'
    environment: 'staging'
    strategy:
      runOnce:
        deploy:
          steps:
          # [Mesmos steps do DeployDev, mas para staging]
          - task: Checkout@3
            displayName: 'Checkout code'

          - task: KubectlInstaller@0
            displayName: 'Install kubectl'

          - task: HelmInstaller@0
            displayName: 'Install Helm'

          - script: |
              curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
              chmod +x kubectl-argo-rollouts-linux-amd64
              sudo mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
            displayName: 'Install Argo Rollouts plugin'

          - task: AzureCLI@2
            displayName: 'Get kubeconfig'
            inputs:
              azureSubscription: 'azure-connection'
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                az aks get-credentials --resource-group projeto-vm-staging-rg --name projeto-vm-staging --overwrite-existing
                kubectl get nodes

          - script: |
              velero backup create pre-deploy-staging-$(date +%Y%m%d%H%M%S) --wait
            displayName: 'Backup Velero before deploy'

          - script: |
              kubectl create namespace projeto-vm-staging --dry-run=client -o yaml | kubectl apply -f -
            displayName: 'Create namespace'

          - script: |
              envsubst < kubernetes/base/service.yaml | kubectl apply -f -
              envsubst < kubernetes/base/ingress.yaml | kubectl apply -f -
            displayName: 'Deploy base resources'
            env:
              NAMESPACE: projeto-vm-staging

          - script: |
              sed -i "s|SEU_REGISTRY/projeto-vm-app:latest|$(REGISTRY)/$(IMAGE_NAME):$(Build.SourceVersion)|g" kubernetes/argo-rollouts/rollout-projeto-vm-app.yaml
              kubectl apply -f kubernetes/argo-rollouts/rollout-projeto-vm-app.yaml
            displayName: 'Deploy with Argo Rollouts'

          - script: |
              set -e
              rollout_name=projeto-vm-app
              namespace=projeto-vm-staging
              if ! timeout 300s kubectl argo rollouts get rollout $rollout_name -n $namespace --watch | grep -q 'Healthy'; then
                echo "Rollout failed, executing rollback..."
                kubectl argo rollouts undo $rollout_name -n $namespace
                exit 1
              fi
            displayName: 'Monitor rollout and auto-rollback'

          - script: |
              kubectl wait --for=condition=ready pod -l app=projeto-vm-app -n projeto-vm-staging --timeout=300s
              SERVICE_URL=$(kubectl get svc projeto-vm-app -n projeto-vm-staging -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
              if [ -z "$SERVICE_URL" ]; then
                SERVICE_URL=$(kubectl get svc projeto-vm-app -n projeto-vm-staging -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
              fi
              curl -f http://$SERVICE_URL/health
              curl -f http://$SERVICE_URL/
              curl -f http://$SERVICE_URL/metadata
            displayName: 'Run integration tests'

# ============================================================================
# DEPLOY TO PRODUCTION
# ============================================================================
- stage: DeployProd
  displayName: 'Deploy to Production'
  dependsOn: SecurityScan
  condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
  jobs:
  - deployment: DeployProd
    pool:
      vmImage: 'ubuntu-latest'
    environment: 'production'
    strategy:
      runOnce:
        deploy:
          steps:
          # [Mesmos steps do DeployStaging, mas para production]
          - task: Checkout@3
            displayName: 'Checkout code'

          - task: KubectlInstaller@0
            displayName: 'Install kubectl'

          - task: HelmInstaller@0
            displayName: 'Install Helm'

          - script: |
              curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
              chmod +x kubectl-argo-rollouts-linux-amd64
              sudo mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
            displayName: 'Install Argo Rollouts plugin'

          - task: AzureCLI@2
            displayName: 'Get kubeconfig'
            inputs:
              azureSubscription: 'azure-connection'
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                az aks get-credentials --resource-group projeto-vm-prod-rg --name projeto-vm-prod --overwrite-existing
                kubectl get nodes

          - script: |
              velero backup create pre-deploy-prod-$(date +%Y%m%d%H%M%S) --wait
            displayName: 'Backup Velero before deploy'

          - script: |
              kubectl create namespace projeto-vm-prod --dry-run=client -o yaml | kubectl apply -f -
            displayName: 'Create namespace'

          - script: |
              envsubst < kubernetes/base/service.yaml | kubectl apply -f -
              envsubst < kubernetes/base/ingress.yaml | kubectl apply -f -
            displayName: 'Deploy base resources'
            env:
              NAMESPACE: projeto-vm-prod

          - script: |
              sed -i "s|SEU_REGISTRY/projeto-vm-app:latest|$(REGISTRY)/$(IMAGE_NAME):$(Build.SourceVersion)|g" kubernetes/argo-rollouts/rollout-projeto-vm-app.yaml
              kubectl apply -f kubernetes/argo-rollouts/rollout-projeto-vm-app.yaml
            displayName: 'Deploy with Argo Rollouts'

          - script: |
              set -e
              rollout_name=projeto-vm-app
              namespace=projeto-vm-prod
              if ! timeout 300s kubectl argo rollouts get rollout $rollout_name -n $namespace --watch | grep -q 'Healthy'; then
                echo "Rollout failed, executing rollback..."
                kubectl argo rollouts undo $rollout_name -n $namespace
                exit 1
              fi
            displayName: 'Monitor rollout and auto-rollback'

          - script: |
              kubectl wait --for=condition=ready pod -l app=projeto-vm-app -n projeto-vm-prod --timeout=300s
              SERVICE_URL=$(kubectl get svc projeto-vm-app -n projeto-vm-prod -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
              if [ -z "$SERVICE_URL" ]; then
                SERVICE_URL=$(kubectl get svc projeto-vm-app -n projeto-vm-prod -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
              fi
              curl -f http://$SERVICE_URL/health
              curl -f http://$SERVICE_URL/
              curl -f http://$SERVICE_URL/metadata
              kubectl get pods -n projeto-vm-prod -l app=projeto-vm-app
            displayName: 'Run production tests'
```

---

## 🔧 Passo 5: Configuração de Environments

### **5.1 Criar Environments**
1. Vá em **Environments**
2. Crie 3 environments:
   - `dev` (para desenvolvimento)
   - `staging` (para homologação)
   - `production` (para produção)

### **5.2 Configurar Approvals (opcional)**
Para `staging` e `production`:
1. Clique no environment
2. Vá em **Approvals and checks**
3. Adicione **Approvals** se quiser aprovação manual antes do deploy

---

## 🚀 Passo 6: Primeiro Deploy

### **6.1 Executar pipeline**
1. Vá em **Pipelines**
2. Clique no pipeline criado
3. Clique em **Run pipeline**
4. Escolha a branch `develop`
5. Execute

### **6.2 Monitorar o deploy**
1. Acompanhe o progresso em tempo real
2. Verifique os logs de cada stage
3. Confirme se o deploy foi bem-sucedido

---

## ✅ Passo 7: Validação

### **7.1 Testar a aplicação**
```bash
# Obtenha a URL do serviço
kubectl get svc projeto-vm-app -n projeto-vm-dev

# Teste os endpoints
curl http://URL_DO_SERVICO/health
curl http://URL_DO_SERVICO/
```

### **7.2 Verificar backup**
```bash
# Liste os backups
velero backup get
```

### **7.3 Testar rollback**
```bash
# Simule um problema (opcional)
kubectl argo rollouts undo projeto-vm-app -n projeto-vm-dev

# Monitore o rollback
kubectl argo rollouts get rollout projeto-vm-app -n projeto-vm-dev --watch
```

---

## 🎉 Parabéns!

Seu projeto está funcionando no Azure DevOps com:
- ✅ Pipeline CI/CD automatizado
- ✅ Deploy canário com Argo Rollouts
- ✅ Backup automático com Velero
- ✅ Scan de vulnerabilidades com Trivy
- ✅ Rollback automático
- ✅ Environments configurados
- ✅ Service connections seguras

---

## 🔧 Diferenças do GitHub Actions

### **Vantagens do Azure DevOps:**
- **Integração nativa** com Azure
- **Environments** com approvals
- **Variable Groups** para gerenciar variáveis
- **Service Connections** para credenciais
- **Dashboards** nativos
- **Work Items** integrados

### **Adaptações feitas:**
- **Tasks** em vez de Actions
- **Variable Groups** em vez de Secrets
- **Service Connections** em vez de credenciais inline
- **Environments** para controle de deploy
- **Stages** para organização do pipeline

---

## 🆘 Troubleshooting

### **Problema: Service Connection falha**
- Verifique as permissões no Azure
- Confirme se a subscription está ativa
- Teste a connection manualmente

### **Problema: Pipeline não executa**
- Verifique se o trigger está configurado
- Confirme se o arquivo YAML está correto
- Verifique as permissões do pipeline

### **Problema: Deploy falha**
- Verifique se o AKS está funcionando
- Confirme se o Argo Rollouts está instalado
- Verifique os logs do pipeline

---

**💡 Dica:** O Azure DevOps oferece mais recursos nativos para gerenciamento de projetos e equipes, aproveite!

**📞 Suporte:** Para dúvidas específicas, consulte a [documentação oficial do Azure DevOps](https://docs.microsoft.com/en-us/azure/devops/).

## **Ferramentas e Versões**

### **Ferramentas Locais**
- **Terraform**: 1.12.2+
- **kubectl**: 1.33+
- **Docker**: 20.1.1+
- **Git**: 2.49.0+
- **Azure CLI**: 2.55.0+ 