# Helm Chart: projeto-vm-app

Este Helm chart facilita o deploy da aplicação Node.js de exemplo do projeto VM em qualquer cluster Kubernetes (AWS, Azure, GCP, local, etc).

## O que é Helm?
Helm é um "gerenciador de pacotes" para Kubernetes. Ele permite instalar, atualizar e remover aplicações de forma simples, usando comandos parecidos com o apt ou yum do Linux.

## Como usar este chart?

### 1. Pré-requisitos
- Ter um cluster Kubernetes funcionando (EKS, AKS, GKE, Minikube, etc)
- Ter o Helm instalado ([veja como instalar](https://helm.sh/docs/intro/install/))
- Ter a imagem Docker da aplicação publicada em um registry (Docker Hub, ECR, GCR, etc)

### 2. Instalar o chart

```bash
helm install projeto-vm kubernetes/charts/projeto-vm-app \
  --set image.repository=SEU_REGISTRY/projeto-vm-app \
  --set image.tag=latest
```

- Troque `SEU_REGISTRY` pelo endereço do seu Docker registry.
- O nome `projeto-vm` pode ser alterado para o nome que preferir.

### 3. Customizar valores
Você pode customizar qualquer valor do `values.yaml` usando `--set` ou criando um arquivo `meus-valores.yaml`:

```bash
helm install projeto-vm kubernetes/charts/projeto-vm-app -f meus-valores.yaml
```

Exemplo de customização:
```yaml
replicaCount: 3
image:
  repository: meu-registry/projeto-vm-app
  tag: v1.2.3
service:
  type: NodePort
  port: 8080
  targetPort: 3000
env:
  ENVIRONMENT: "staging"
```

### 4. Atualizar o deploy

```bash
helm upgrade projeto-vm kubernetes/charts/projeto-vm-app \
  --set image.tag=novo-tag
```

### 5. Remover o deploy

```bash
helm uninstall projeto-vm
```

## O que este chart instala?
- Deployment (replicas da aplicação)
- Service (exposição interna/externa)
- Ingress (opcional, para URL amigável)

## Dicas para leigos
- Não precisa entender todos os arquivos, basta seguir o passo a passo.
- Se der erro, leia a mensagem: geralmente ela explica o que falta.
- Você pode testar localmente com Minikube ou Kind antes de ir para a nuvem.
- O Helm facilita upgrades, rollback e gerenciamento de configurações.

## Documentação útil
- [Documentação oficial do Helm](https://helm.sh/docs/)
- [Documentação do Kubernetes](https://kubernetes.io/pt/docs/home/)
- [Guia de troubleshooting do Helm](https://helm.sh/docs/howto/charts_tips_and_tricks/)

Se precisar de ajuda, peça suporte ao time DevOps ou consulte a documentação acima! 