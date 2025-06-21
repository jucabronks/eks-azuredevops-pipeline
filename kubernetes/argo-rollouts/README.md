# Argo Rollouts - Deploys Progressivos e Rollback Inteligente

O [Argo Rollouts](https://argoproj.github.io/argo-rollouts/) é uma extensão do Kubernetes para deploys avançados, como canário e blue-green, com monitoramento de saúde e rollback automático.

## **Pré-requisitos**

- **kubectl** (versão 1.33+)
- **Argo Rollouts CLI** (versão 1.9.0+)
- Cluster Kubernetes funcionando

## Benefícios
- Deploys progressivos (canário, blue-green, experimentos)
- Rollback automático em caso de falha
- Dashboards e integração com Prometheus/Grafana
- Zero downtime e controle fino do rollout

## Estratégias suportadas
- RollingUpdate (padrão)
- Canary (canário)
- BlueGreen (azul-verde)
- Experiment

## Como usaremos no projeto
- Deploys de aplicação usando Rollout em vez de Deployment
- Rollback automático se health check falhar
- Monitoramento visual via Argo Rollouts Dashboard

## Estrutura deste diretório
- `install.yaml`: Instalação do Argo Rollouts no cluster
- `rollout-projeto-vm-app.yaml`: Exemplo de Rollout para sua aplicação
- `dashboard.yaml`: (Opcional) Instalação do dashboard web

## Links úteis
- [Documentação oficial](https://argoproj.github.io/argo-rollouts/)
- [Exemplo de Rollout](https://argoproj.github.io/argo-rollouts/features/canary/)
- [Dashboard](https://argoproj.github.io/argo-rollouts/features/dashboard/) 