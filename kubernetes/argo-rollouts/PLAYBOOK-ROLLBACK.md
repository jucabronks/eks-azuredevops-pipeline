# Playbook de Rollback - Argo Rollouts

## 1. Monitorando o Rollout
- Use o comando abaixo para acompanhar o progresso do rollout:
  ```sh
  kubectl argo rollouts get rollout projeto-vm-app -n dev --watch
  ```
- O rollout é considerado saudável quando o status for `Healthy`.

## 2. Rollback Automático
- O Argo Rollouts monitora a saúde dos pods durante o deploy.
- Se detectar falha (pods não prontos, probes falhando), ele reverte automaticamente para a versão anterior.
- O pipeline CI/CD também monitora e executa rollback se necessário.

## 3. Rollback Manual
- Se precisar reverter manualmente, use:
  ```sh
  kubectl argo rollouts undo projeto-vm-app -n dev
  ```
- Você pode ver o histórico de revisões com:
  ```sh
  kubectl argo rollouts history projeto-vm-app -n dev
  ```

## 4. Troubleshooting
- Verifique eventos e logs do rollout:
  ```sh
  kubectl describe rollout projeto-vm-app -n dev
  kubectl logs deployment/argo-rollouts -n argo-rollouts
  ```
- Cheque os pods e seus status:
  ```sh
  kubectl get pods -n dev
  kubectl describe pod <nome-do-pod> -n dev
  ```

## 5. Dicas
- Sempre monitore o rollout após deploys críticos.
- Em caso de dúvida, prefira reverter para a última versão estável.
- Consulte a [documentação oficial](https://argoproj.github.io/argo-rollouts/) para estratégias avançadas. 