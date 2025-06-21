# 🚀 Guia de Primeira Execução - Projeto VM

Este guia te ensina como criar toda a infraestrutura do zero, desde a configuração inicial até o primeiro deploy funcionando. Ideal para quem está começando ou quer replicar o projeto em um novo ambiente.

---

## 📋 Pré-requisitos

### **Contas e Acesso**
- [ ] Conta GitHub (para repositório e CI/CD)
- [ ] Conta AWS, Azure ou GCP (escolha uma)
- [ ] Acesso de administrador na cloud escolhida
- [ ] Docker instalado localmente
- [ ] Git instalado localmente

### **Ferramentas Locais**
- [ ] **Terraform** (versão 1.12.2+)
- [ ] **kubectl** (versão 1.33+)
- [ ] **Docker** (versão 20.1.1+)
- [ ] **Git** (versão 2.49.0+)

---

## 🔧 Passo 1: Preparação do Ambiente Local

### **1.1 Instalar ferramentas necessárias**

#### **Terraform:**
```bash
# Linux/macOS
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install terraform

# macOS (via Homebrew)
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

#### **kubectl:**
```bash
# Linux
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# macOS
brew install kubectl
```

### **1.2 Clone o repositório**
```bash
git clone https://github.com/SEU_USUARIO/projeto-vm.git
cd projeto-vm
```

---

## ☁️ Passo 2: Configuração da Cloud (Escolha uma)

### **Opção A: AWS**
1. **Criar usuário IAM:**
   - Acesse o AWS Console → IAM
   - Crie um usuário com permissões de administrador
   - Gere Access Key e Secret Key
   - Anote as credenciais

2. **Configurar AWS CLI:**
   ```bash
   aws configure
   # Digite: Access Key, Secret Key, região (ex: us-east-1), formato (json)
   ```

### **Opção B: Azure**
1. **Criar Service Principal:**
   ```bash
   az login
   az ad sp create-for-rbac --name "projeto-vm-sp" --role contributor
   ```
   - Anote: clientId, clientSecret, subscriptionId, tenantId

2. **Configurar Azure CLI:**
   ```bash
   az account set --subscription <subscription-id>
   ```

### **Opção C: GCP**
1. **Criar Service Account:**
   - Acesse Google Cloud Console → IAM & Admin → Service Accounts
   - Crie uma service account com permissões de administrador
   - Baixe o arquivo JSON de credenciais

2. **Configurar GCP CLI:**
   ```bash
   gcloud auth activate-service-account --key-file=caminho/para/credenciais.json
   gcloud config set project SEU_PROJECT_ID
   ```

---

## 🔐 Passo 3: Configuração do GitHub

### **3.1 Criar repositório**
1. Acesse GitHub.com
2. Crie um novo repositório chamado `projeto-vm`
3. Faça push do código:
   ```bash
   git remote add origin https://github.com/SEU_USUARIO/projeto-vm.git
   git add .
   git commit -m "Initial commit"
   git push -u origin main
   ```

### **3.2 Configurar GitHub Secrets**
No seu repositório GitHub → Settings → Secrets and variables → Actions:

#### **Para AWS:**
- `AWS_ACCESS_KEY_ID`: Sua AWS Access Key
- `AWS_SECRET_ACCESS_KEY`: Sua AWS Secret Key

#### **Para Azure:**
- `AZURE_CREDENTIALS`: JSON com clientId, clientSecret, subscriptionId, tenantId

#### **Para GCP:**
- `GCP_SA_KEY`: Conteúdo do arquivo JSON da service account

#### **Para Docker Hub:**
- `DOCKER_USERNAME`: Seu usuário Docker Hub
- `DOCKER_PASSWORD`: Sua senha Docker Hub

#### **Para Slack (opcional):**
- `SLACK_WEBHOOK_URL`: URL do webhook do Slack

---

## 🏗️ Passo 4: Provisionamento da Infraestrutura

### **4.1 Configurar variáveis de ambiente**
```bash
# Copie o arquivo de exemplo
cp .env.example .env

# Edite com suas configurações
nano .env
```

### **4.2 Provisionar infraestrutura com Terraform**
```bash
# Entre no diretório Terraform
cd terraform/aws  # ou azure, ou gcp

# Inicialize o Terraform
terraform init

# Planeje a infraestrutura
terraform plan

# Aplique a infraestrutura
terraform apply
```

**O que será criado:**
- VPC/Network
- Cluster Kubernetes (EKS/AKS/GKE)
- Bucket S3 para backups (AWS)
- Storage Account para backups (Azure)
- Cloud Storage para backups (GCP)

### **4.3 Configurar kubectl**
```bash
# AWS
aws eks update-kubeconfig --region us-east-1 --name projeto-vm-dev

# Azure
az aks get-credentials --resource-group projeto-vm-dev-rg --name projeto-vm-dev

# GCP
gcloud container clusters get-credentials projeto-vm-dev --region us-central1
```

---

## 🔧 Passo 5: Instalação de Ferramentas no Cluster

### **5.1 Instalar Argo Rollouts**
```bash
# Execute o script de instalação
chmod +x kubernetes/argo-rollouts/script-instalacao.sh
./kubernetes/argo-rollouts/script-instalacao.sh
```

### **5.2 Instalar Velero**
```bash
# Crie o bucket S3 (AWS) ou configure storage (Azure/GCP)
# Siga o guia em kubernetes/velero/README.md
```

---

## 🚀 Passo 6: Primeiro Deploy

### **6.1 Aplicar recursos base**
```bash
# Crie os namespaces
kubectl create namespace projeto-vm-dev
kubectl create namespace projeto-vm-staging
kubectl create namespace projeto-vm-prod

# Aplique o Rollout da aplicação
kubectl apply -f kubernetes/argo-rollouts/rollout-projeto-vm-app.yaml
```

### **6.2 Executar deploy via pipeline**
1. Faça um push para a branch `develop`:
   ```bash
   git checkout -b develop
   git add .
   git commit -m "Primeiro deploy"
   git push origin develop
   ```

2. Acompanhe o pipeline no GitHub Actions

### **6.3 Monitorar o deploy**
```bash
# Acompanhe o rollout
kubectl argo rollouts get rollout projeto-vm-app -n projeto-vm-dev --watch

# Verifique os recursos
kubectl get pods -n projeto-vm-dev
kubectl get svc -n projeto-vm-dev
kubectl get ingress -n projeto-vm-dev
```

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

# Verifique se há backups recentes
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

Sua infraestrutura está funcionando! Agora você tem:
- ✅ Cluster Kubernetes provisionado
- ✅ Pipeline CI/CD automatizado
- ✅ Deploy canário com Argo Rollouts
- ✅ Backup automático com Velero
- ✅ Scan de vulnerabilidades com Trivy
- ✅ Rollback automático

---

## 🔧 Próximos Passos

1. **Personalizar a aplicação:**
   - Modifique `app.js` e `package.json`
   - Ajuste o `Dockerfile` se necessário

2. **Configurar observabilidade:**
   - Siga o guia em `docs/OBSERVABILITY.md`

3. **Configurar alertas:**
   - Configure notificações para o time

4. **Documentar para o time:**
   - Compartilhe este guia
   - Crie playbooks específicos

---

## 🆘 Troubleshooting

### **Problema: Pipeline falha**
- Verifique os GitHub Secrets
- Confirme se as credenciais cloud estão corretas
- Verifique os logs do GitHub Actions

### **Problema: Deploy não funciona**
- Verifique se o Argo Rollouts está instalado
- Confirme se a imagem Docker existe
- Verifique os logs dos pods

### **Problema: Backup não funciona**
- Verifique se o Velero está configurado
- Confirme as permissões na cloud
- Verifique os logs do Velero

---

**💡 Dica:** Se algo der errado, sempre consulte os logs e a documentação oficial dos serviços. Este guia é um ponto de partida!

**📞 Suporte:** Para dúvidas específicas, consulte a documentação oficial ou entre em contato com o time DevOps. 