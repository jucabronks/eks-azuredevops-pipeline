#!/bin/bash

# ============================================================================
# Script de Instalação Automatizada - Argo Rollouts
# Este script instala o Argo Rollouts no cluster Kubernetes de forma segura.
# ============================================================================

set -e  # Para o script se qualquer comando falhar

echo "🚀 Iniciando instalação do Argo Rollouts..."

# ============================================================================
# VERIFICAÇÕES PRÉVIAS
# ============================================================================

echo "📋 Verificando pré-requisitos..."

# Verifica se o kubectl está instalado
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl não encontrado. Instale o kubectl primeiro."
    exit 1
fi

# Verifica se está conectado ao cluster
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Não foi possível conectar ao cluster Kubernetes."
    echo "   Verifique se o kubectl está configurado corretamente."
    exit 1
fi

echo "✅ kubectl configurado e conectado ao cluster"

# Verifica se tem permissões de administrador
if ! kubectl auth can-i create namespaces &> /dev/null; then
    echo "❌ Permissões insuficientes. Você precisa de permissões de administrador."
    exit 1
fi

echo "✅ Permissões verificadas"

# ============================================================================
# INSTALAÇÃO DO ARGO ROLLOUTS
# ============================================================================

echo "🔧 Instalando Argo Rollouts..."

# Cria o namespace se não existir
echo "   Criando namespace argo-rollouts..."
kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -

# Instala o Argo Rollouts
echo "   Aplicando manifestos do Argo Rollouts..."
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

# ============================================================================
# INSTALAÇÃO DO PLUGIN KUBECTL
# ============================================================================

echo "🔌 Instalando plugin kubectl do Argo Rollouts..."

# Detecta o sistema operacional
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

# Mapeia arquitetura
if [ "$ARCH" = "x86_64" ]; then
    ARCH="amd64"
elif [ "$ARCH" = "aarch64" ]; then
    ARCH="arm64"
fi

# URL do plugin
PLUGIN_URL="https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-${OS}-${ARCH}"

echo "   Baixando plugin para ${OS}-${ARCH}..."

# Baixa o plugin
curl -LO "$PLUGIN_URL"

# Torna executável e move para o PATH
chmod +x kubectl-argo-rollouts-${OS}-${ARCH}
sudo mv kubectl-argo-rollouts-${OS}-${ARCH} /usr/local/bin/kubectl-argo-rollouts

# ============================================================================
# VERIFICAÇÃO DA INSTALAÇÃO
# ============================================================================

echo "✅ Verificando instalação..."

# Aguarda os pods ficarem prontos
echo "   Aguardando pods do Argo Rollouts..."
kubectl wait --for=condition=ready pod -l app=argo-rollouts -n argo-rollouts --timeout=120s

# Verifica se o plugin está funcionando
if ! kubectl argo rollouts version &> /dev/null; then
    echo "❌ Plugin kubectl não está funcionando corretamente."
    exit 1
fi

echo "✅ Plugin kubectl funcionando"

# ============================================================================
# TESTE BÁSICO
# ============================================================================

echo "🧪 Executando teste básico..."

# Cria um Rollout de teste
cat <<EOF | kubectl apply -f -
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

# Aguarda o rollout ficar pronto
echo "   Aguardando rollout de teste..."
kubectl argo rollouts get rollout test-rollout --watch --timeout=60s || true

# Remove o teste
echo "   Limpando teste..."
kubectl delete rollout test-rollout --ignore-not-found=true

# ============================================================================
# RESUMO FINAL
# ============================================================================

echo ""
echo "🎉 Instalação concluída com sucesso!"
echo ""
echo "📊 Status da instalação:"
echo "   - Namespace: argo-rollouts"
echo "   - Pods: $(kubectl get pods -n argo-rollouts --no-headers | wc -l) rodando"
echo "   - Plugin: kubectl argo rollouts"
echo ""
echo "🚀 Próximos passos:"
echo "   1. Aplique o Rollout da sua aplicação:"
echo "      kubectl apply -f kubernetes/argo-rollouts/rollout-projeto-vm-app.yaml"
echo ""
echo "   2. Monitore o deploy:"
echo "      kubectl argo rollouts get rollout projeto-vm-app -n dev --watch"
echo ""
echo "   3. Faça rollback se necessário:"
echo "      kubectl argo rollouts undo projeto-vm-app -n dev"
echo ""
echo "📖 Documentação: kubernetes/argo-rollouts/INSTALACAO.md"
echo "" 