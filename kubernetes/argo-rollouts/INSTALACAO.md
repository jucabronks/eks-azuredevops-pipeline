# Guia de Instalação - Argo Rollouts

Este guia te ensina como instalar o Argo Rollouts no seu cluster Kubernetes de forma simples e segura.

## 📋 Pré-requisitos

- Cluster Kubernetes funcionando (EKS, AKS, GKE ou local)
- `kubectl` configurado e conectado ao cluster
- Permissões de administrador no cluster
- Acesso à internet para baixar as imagens

## 🚀 Instalação Passo a Passo

### 1. **Verificar se o cluster está funcionando**

```bash
kubectl get nodes
```

**O que faz:** Verifica se o cluster está acessível e os nós estão prontos.

### 2. **Instalar o Argo Rollouts via kubectl**

```bash
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
```

**O que faz:** 
- Cria o namespace `argo-rollouts`
- Instala o controller do Argo Rollouts e suas dependências

### 3. **Instalar o plugin kubectl do Argo Rollouts (localmente)**

#### **Linux/macOS:**
```bash
curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
chmod +x kubectl-argo-rollouts-linux-amd64
sudo mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
```

#### **Windows:**
```powershell
# Baixe o arquivo .exe do GitHub e adicione ao PATH
```

**O que faz:** Instala o plugin que permite usar comandos como `kubectl argo rollouts get rollout`

### 4. **Verificar se a instalação foi bem-sucedida**

```bash
# Verifica se os pods do Argo Rollouts estão rodando
kubectl get pods -n argo-rollouts

# Verifica se o plugin está funcionando
kubectl argo rollouts version
```

**O que você deve ver:**
- Pods com status `Running`
- Versão do Argo Rollouts sendo exibida

## ✅ Verificação da Instalação

### **Teste básico:**

```bash
# Cria um Rollout de teste
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: test-rollout
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test
  template:
    metadata:
      labels:
        app: test
    spec:
      containers:
      - name: nginx
        image: nginx:latest
EOF

# Verifica o status
kubectl argo rollouts get rollout test-rollout

# Remove o teste
kubectl delete rollout test-rollout
```

## 🔧 Troubleshooting

### **Problema: Pods não ficam prontos**
```bash
# Verifica os logs do controller
kubectl logs -n argo-rollouts deployment/argo-rollouts

# Verifica eventos do namespace
kubectl get events -n argo-rollouts
```

### **Problema: Plugin não funciona**
```bash
# Verifica se o arquivo foi baixado corretamente
ls -la /usr/local/bin/kubectl-argo-rollouts

# Testa permissões
kubectl-argo-rollouts version
```

### **Problema: Permissões insuficientes**
```bash
# Verifica suas permissões
kubectl auth can-i create rollouts --all-namespaces
```

## 📚 Próximos Passos

1. **Aplicar o Rollout da sua aplicação:**
   ```bash
   kubectl apply -f kubernetes/argo-rollouts/rollout-projeto-vm-app.yaml
   ```

2. **Monitorar o deploy:**
   ```bash
   kubectl argo rollouts get rollout projeto-vm-app -n dev --watch
   ```

3. **Fazer rollback se necessário:**
   ```bash
   kubectl argo rollouts undo projeto-vm-app -n dev
   ```

## 🎯 Dicas Importantes

- **Sempre teste em ambiente de desenvolvimento primeiro**
- **Mantenha o Argo Rollouts atualizado**
- **Monitore os logs do controller em produção**
- **Configure alertas para falhas de rollout**

## 📖 Documentação Adicional

- [Documentação oficial](https://argoproj.github.io/argo-rollouts/)
- [Exemplos práticos](https://argoproj.github.io/argo-rollouts/features/canary/)
- [Troubleshooting](https://argoproj.github.io/argo-rollouts/troubleshooting/)

---

**🎉 Parabéns!** Seu Argo Rollouts está instalado e pronto para uso! 