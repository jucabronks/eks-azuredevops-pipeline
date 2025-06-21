# Velero Backup & Restore - Kubernetes

Este diretório contém manifestos do [Velero](https://velero.io/), uma ferramenta open source para backup e restore de recursos e volumes do Kubernetes.

## O que é o Velero?
- Permite fazer backup automático de Deployments, Services, ConfigMaps, Secrets, PVCs e volumes (EBS, etc).
- Suporta agendamento de backups, restore granular e integração com AWS S3, Azure Blob, GCP Storage.
- Essencial para Disaster Recovery e proteção de dados em clusters Kubernetes.

## Estrutura dos manifestos
- `velero-namespace.yaml`: Cria o namespace dedicado para o Velero.
- `velero-serviceaccount.yaml`: Cria a ServiceAccount e permissões necessárias.
- `velero-deployment.yaml`: Faz o deploy do Velero no cluster.
- `velero-schedule.yaml`: Exemplo de agendamento de backup automático.

Todos os manifestos possuem comentários didáticos explicando cada etapa.

## **Pré-requisitos**

- **kubectl** (versão 1.33+)
- **Velero CLI** (versão 1.13.0+)
- Cluster Kubernetes funcionando
- Bucket S3 configurado (para AWS)

---

> **Dica:**
> Para restaurar um backup, basta aplicar o manifesto de restore ou usar o CLI do Velero. 