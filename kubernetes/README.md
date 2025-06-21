# Kubernetes - Deploy Multicloud

Este diretório contém tudo o que você precisa para rodar aplicações no Kubernetes, mesmo que nunca tenha usado antes!

## O que é Kubernetes?
Kubernetes é uma plataforma que automatiza o deploy, o gerenciamento e o scaling de aplicações em containers (como Docker) em qualquer nuvem (AWS, Azure, GCP, etc).

## Estrutura deste diretório

```
kubernetes/
├── base/           # Manifests YAML puros (Deployment, Service, Ingress, etc)
├── charts/         # Helm charts (modelos reutilizáveis de deploy)
└── README.md       # Este guia
```

## Como funciona o deploy?

1. **Containerize sua aplicação** (já temos um Dockerfile pronto!)
2. **Suba a imagem para um registry** (Docker Hub, ECR, GCR, etc)
3. **Use os manifests ou Helm charts** para criar os recursos no cluster Kubernetes

## O que são esses arquivos?
- **Deployment**: Garante que sua aplicação está sempre rodando (auto-recuperação)
- **Service**: Expõe sua aplicação para acesso interno ou externo
- **Ingress**: Permite acessar sua aplicação por um endereço amigável (URL)
- **Helm Chart**: Um "pacote" que facilita instalar e atualizar aplicações no Kubernetes

## Passo a passo para leigos

### 1. Deploy manual com YAML (base)

```bash
kubectl apply -f kubernetes/base/deployment.yaml
kubectl apply -f kubernetes/base/service.yaml
kubectl apply -f kubernetes/base/ingress.yaml
```

### 2. Deploy automatizado com Helm (charts)

```bash
# Instale o Helm se não tiver
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Instale o chart
helm install projeto-vm kubernetes/charts/projeto-vm-app \
  --set image.repository=SEU_REGISTRY/projeto-vm-app \
  --set image.tag=latest
```

### 3. Acesse sua aplicação
- Descubra o endereço com:
  ```bash
  kubectl get svc
  kubectl get ingress
  ```
- Acesse pelo navegador ou via curl:
  ```bash
  curl http://SEU_ENDERECO/
  curl http://SEU_ENDERECO/health
  ```

## Dicas para quem nunca usou
- Não precisa decorar comandos! Siga o passo a passo.
- Se der erro, leia a mensagem: geralmente ela explica o que falta.
- Kubernetes é poderoso, mas começa simples: um deploy, um service, um ingress.
- Use o Helm para facilitar upgrades e rollback.

## Próximos passos
- Aprenda a escalar: `kubectl scale deployment projeto-vm-app --replicas=3`
- Monitore com: `kubectl get pods -w`
- Explore o dashboard: `kubectl proxy` e acesse http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/

Se precisar de ajuda, consulte a documentação oficial ou peça suporte ao time DevOps! 