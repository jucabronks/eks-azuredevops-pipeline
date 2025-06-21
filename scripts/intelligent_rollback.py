#!/usr/bin/env python3
"""
Intelligent Rollback System
Uses ML/AI to automatically detect deployment failures and trigger rollbacks
"""

import os
import sys
import json
import time
import logging
import requests
import numpy as np
import pandas as pd
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
import argparse
from kubernetes import client, config
from kubernetes.client.rest import ApiException
import prometheus_client
from prometheus_client import CollectorRegistry, Gauge, push_to_gateway

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class IntelligentRollback:
    def __init__(self, config: Dict):
        self.config = config
        self.k8s_client = self._setup_kubernetes()
        self.prometheus_url = config.get('prometheus_url', 'http://prometheus-operated:9090')
        self.alertmanager_url = config.get('alertmanager_url', 'http://alertmanager-operated:9093')
        self.rollback_threshold = float(config.get('rollback_threshold', 0.8))
        self.health_check_timeout = int(config.get('health_check_timeout', 300))
        self.error_threshold = int(config.get('error_threshold', 5))
        
        # ML model for failure prediction
        self.failure_model = self._load_failure_model()
        
        # Metrics
        self.registry = CollectorRegistry()
        self.rollback_counter = Gauge('rollback_total', 'Total rollbacks performed', registry=self.registry)
        self.failure_prediction_accuracy = Gauge('failure_prediction_accuracy', 'ML model accuracy', registry=self.registry)
        
    def _setup_kubernetes(self) -> client.CoreV1Api:
        """Setup Kubernetes client"""
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()
        
        return client.CoreV1Api()
    
    def _load_failure_model(self):
        """Load ML model for failure prediction"""
        # In a real implementation, this would load a trained model
        # For now, we'll use a simple heuristic-based approach
        return {
            'type': 'heuristic',
            'version': '1.0',
            'parameters': {
                'error_rate_threshold': 0.1,
                'response_time_threshold': 2000,  # ms
                'memory_usage_threshold': 0.8,
                'cpu_usage_threshold': 0.8
            }
        }
    
    def predict_deployment_failure(self, deployment_name: str, namespace: str) -> Tuple[bool, float]:
        """
        Predict if a deployment is likely to fail using ML/AI
        
        Returns:
            Tuple[bool, float]: (will_fail, confidence)
        """
        try:
            # Collect metrics for the deployment
            metrics = self._collect_deployment_metrics(deployment_name, namespace)
            
            # Extract features for ML model
            features = self._extract_features(metrics)
            
            # Make prediction
            if self.failure_model['type'] == 'heuristic':
                prediction, confidence = self._heuristic_prediction(features)
            else:
                # In real implementation, use trained ML model
                prediction, confidence = self._ml_model_prediction(features)
            
            logger.info(f"Failure prediction for {deployment_name}: {prediction} (confidence: {confidence:.2f})")
            return prediction, confidence
            
        except Exception as e:
            logger.error(f"Error predicting deployment failure: {e}")
            return False, 0.0
    
    def _collect_deployment_metrics(self, deployment_name: str, namespace: str) -> Dict:
        """Collect metrics for the deployment"""
        metrics = {
            'error_rate': 0.0,
            'response_time': 0.0,
            'memory_usage': 0.0,
            'cpu_usage': 0.0,
            'pod_restarts': 0,
            'health_check_failures': 0
        }
        
        try:
            # Get pods for the deployment
            pods = self.k8s_client.list_namespaced_pod(
                namespace=namespace,
                label_selector=f"app={deployment_name}"
            )
            
            for pod in pods.items:
                # Get pod metrics
                pod_metrics = self._get_pod_metrics(pod.metadata.name, namespace)
                metrics['pod_restarts'] += pod.status.container_statuses[0].restart_count if pod.status.container_statuses else 0
                
                # Aggregate metrics
                for key in ['error_rate', 'response_time', 'memory_usage', 'cpu_usage']:
                    if key in pod_metrics:
                        metrics[key] = max(metrics[key], pod_metrics[key])
            
            # Get health check failures
            metrics['health_check_failures'] = self._get_health_check_failures(deployment_name, namespace)
            
        except Exception as e:
            logger.error(f"Error collecting metrics: {e}")
        
        return metrics
    
    def _get_pod_metrics(self, pod_name: str, namespace: str) -> Dict:
        """Get metrics for a specific pod"""
        metrics = {}
        
        try:
            # Query Prometheus for pod metrics
            prometheus_queries = {
                'error_rate': f'rate(http_requests_total{{pod="{pod_name}",status=~"5.."}}[5m])',
                'response_time': f'histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{{pod="{pod_name}"}}[5m]))',
                'memory_usage': f'container_memory_usage_bytes{{pod="{pod_name}"}} / container_spec_memory_limit_bytes{{pod="{pod_name}"}}',
                'cpu_usage': f'rate(container_cpu_usage_seconds_total{{pod="{pod_name}"}}[5m])'
            }
            
            for metric_name, query in prometheus_queries.items():
                response = requests.get(f"{self.prometheus_url}/api/v1/query", params={'query': query})
                if response.status_code == 200:
                    result = response.json()
                    if result['data']['result']:
                        value = float(result['data']['result'][0]['value'][1])
                        metrics[metric_name] = value
            
        except Exception as e:
            logger.error(f"Error getting pod metrics: {e}")
        
        return metrics
    
    def _get_health_check_failures(self, deployment_name: str, namespace: str) -> int:
        """Get number of health check failures"""
        try:
            # Query Prometheus for health check failures
            query = f'probe_failures_total{{job="kubernetes-pods",pod=~"{deployment_name}.*"}}'
            response = requests.get(f"{self.prometheus_url}/api/v1/query", params={'query': query})
            
            if response.status_code == 200:
                result = response.json()
                if result['data']['result']:
                    return int(float(result['data']['result'][0]['value'][1]))
            
        except Exception as e:
            logger.error(f"Error getting health check failures: {e}")
        
        return 0
    
    def _extract_features(self, metrics: Dict) -> np.ndarray:
        """Extract features for ML model"""
        features = [
            metrics.get('error_rate', 0.0),
            metrics.get('response_time', 0.0),
            metrics.get('memory_usage', 0.0),
            metrics.get('cpu_usage', 0.0),
            metrics.get('pod_restarts', 0),
            metrics.get('health_check_failures', 0)
        ]
        
        return np.array(features)
    
    def _heuristic_prediction(self, features: np.ndarray) -> Tuple[bool, float]:
        """Heuristic-based failure prediction"""
        error_rate, response_time, memory_usage, cpu_usage, pod_restarts, health_check_failures = features
        
        # Calculate failure score
        failure_score = 0.0
        
        # Error rate contribution
        if error_rate > self.failure_model['parameters']['error_rate_threshold']:
            failure_score += 0.3
        
        # Response time contribution
        if response_time > self.failure_model['parameters']['response_time_threshold']:
            failure_score += 0.2
        
        # Resource usage contribution
        if memory_usage > self.failure_model['parameters']['memory_usage_threshold']:
            failure_score += 0.2
        
        if cpu_usage > self.failure_model['parameters']['cpu_usage_threshold']:
            failure_score += 0.2
        
        # Pod restarts contribution
        if pod_restarts > 0:
            failure_score += min(0.1 * pod_restarts, 0.3)
        
        # Health check failures contribution
        if health_check_failures > 0:
            failure_score += min(0.1 * health_check_failures, 0.2)
        
        # Normalize to 0-1 range
        failure_score = min(failure_score, 1.0)
        
        # Predict failure if score exceeds threshold
        will_fail = failure_score > self.rollback_threshold
        confidence = failure_score
        
        return will_fail, confidence
    
    def _ml_model_prediction(self, features: np.ndarray) -> Tuple[bool, float]:
        """ML model-based failure prediction"""
        # In a real implementation, this would use a trained model
        # For now, return the heuristic prediction
        return self._heuristic_prediction(features)
    
    def should_rollback(self, deployment_name: str, namespace: str) -> bool:
        """Determine if a rollback should be performed"""
        try:
            # Check if deployment is healthy
            if self._is_deployment_healthy(deployment_name, namespace):
                return False
            
            # Predict failure
            will_fail, confidence = self.predict_deployment_failure(deployment_name, namespace)
            
            # Update metrics
            self.failure_prediction_accuracy.set(confidence)
            
            # Perform rollback if prediction is confident
            if will_fail and confidence > self.rollback_threshold:
                logger.warning(f"High confidence failure prediction for {deployment_name}: {confidence:.2f}")
                return True
            
            return False
            
        except Exception as e:
            logger.error(f"Error determining rollback: {e}")
            return False
    
    def _is_deployment_healthy(self, deployment_name: str, namespace: str) -> bool:
        """Check if deployment is healthy"""
        try:
            # Get deployment status
            apps_v1 = client.AppsV1Api()
            deployment = apps_v1.read_namespaced_deployment(deployment_name, namespace)
            
            # Check if all replicas are ready
            if deployment.status.ready_replicas != deployment.status.replicas:
                return False
            
            # Check if pods are healthy
            pods = self.k8s_client.list_namespaced_pod(
                namespace=namespace,
                label_selector=f"app={deployment_name}"
            )
            
            for pod in pods.items:
                if pod.status.phase != 'Running':
                    return False
                
                # Check container status
                for container in pod.status.container_statuses:
                    if not container.ready:
                        return False
            
            return True
            
        except Exception as e:
            logger.error(f"Error checking deployment health: {e}")
            return False
    
    def perform_rollback(self, deployment_name: str, namespace: str) -> bool:
        """Perform rollback to previous version"""
        try:
            logger.info(f"Performing rollback for {deployment_name} in {namespace}")
            
            # Get deployment
            apps_v1 = client.AppsV1Api()
            deployment = apps_v1.read_namespaced_deployment(deployment_name, namespace)
            
            # Check if there's a previous revision
            if not deployment.metadata.annotations or 'rollback.kubernetes.io/previous-revision' not in deployment.metadata.annotations:
                logger.warning(f"No previous revision found for {deployment_name}")
                return False
            
            # Get previous image tag
            previous_tag = deployment.metadata.annotations['rollback.kubernetes.io/previous-revision']
            
            # Update deployment to previous version
            deployment.spec.template.spec.containers[0].image = f"{deployment.spec.template.spec.containers[0].image.split(':')[0]}:{previous_tag}"
            
            # Apply the rollback
            apps_v1.patch_namespaced_deployment(
                name=deployment_name,
                namespace=namespace,
                body=deployment
            )
            
            # Update metrics
            self.rollback_counter.inc()
            
            # Send notification
            self._send_rollback_notification(deployment_name, namespace, previous_tag)
            
            logger.info(f"Rollback completed for {deployment_name} to version {previous_tag}")
            return True
            
        except Exception as e:
            logger.error(f"Error performing rollback: {e}")
            return False
    
    def _send_rollback_notification(self, deployment_name: str, namespace: str, previous_tag: str):
        """Send rollback notification"""
        try:
            # Send to AlertManager
            alert = {
                'labels': {
                    'alertname': 'DeploymentRollback',
                    'deployment': deployment_name,
                    'namespace': namespace,
                    'severity': 'warning'
                },
                'annotations': {
                    'summary': f'Automatic rollback performed for {deployment_name}',
                    'description': f'Deployment {deployment_name} in namespace {namespace} was automatically rolled back to version {previous_tag} due to detected issues.'
                }
            }
            
            response = requests.post(
                f"{self.alertmanager_url}/api/v1/alerts",
                json=[alert]
            )
            
            if response.status_code == 200:
                logger.info(f"Rollback notification sent for {deployment_name}")
            else:
                logger.warning(f"Failed to send rollback notification: {response.status_code}")
                
        except Exception as e:
            logger.error(f"Error sending rollback notification: {e}")
    
    def monitor_deployments(self, namespaces: List[str] = None):
        """Monitor deployments and perform rollbacks when needed"""
        if namespaces is None:
            namespaces = ['default']
        
        logger.info(f"Starting deployment monitoring for namespaces: {namespaces}")
        
        while True:
            try:
                for namespace in namespaces:
                    # Get all deployments in namespace
                    apps_v1 = client.AppsV1Api()
                    deployments = apps_v1.list_namespaced_deployment(namespace)
                    
                    for deployment in deployments.items:
                        deployment_name = deployment.metadata.name
                        
                        # Skip system deployments
                        if deployment_name.startswith('kube-') or deployment_name.startswith('system-'):
                            continue
                        
                        # Check if rollback is needed
                        if self.should_rollback(deployment_name, namespace):
                            logger.warning(f"Rollback needed for {deployment_name} in {namespace}")
                            
                            # Perform rollback
                            if self.perform_rollback(deployment_name, namespace):
                                logger.info(f"Rollback successful for {deployment_name}")
                            else:
                                logger.error(f"Rollback failed for {deployment_name}")
                
                # Push metrics to Prometheus
                try:
                    push_to_gateway('localhost:9091', job='intelligent-rollback', registry=self.registry)
                except Exception as e:
                    logger.warning(f"Failed to push metrics: {e}")
                
                # Wait before next check
                time.sleep(30)
                
            except Exception as e:
                logger.error(f"Error in deployment monitoring: {e}")
                time.sleep(60)

def main():
    parser = argparse.ArgumentParser(description='Intelligent Rollback System')
    parser.add_argument('--config', type=str, default='config.json', help='Configuration file')
    parser.add_argument('--namespaces', nargs='+', default=['default'], help='Namespaces to monitor')
    parser.add_argument('--once', action='store_true', help='Run once instead of continuously')
    
    args = parser.parse_args()
    
    # Load configuration
    try:
        with open(args.config, 'r') as f:
            config = json.load(f)
    except FileNotFoundError:
        config = {
            'prometheus_url': os.getenv('PROMETHEUS_URL', 'http://prometheus-operated:9090'),
            'alertmanager_url': os.getenv('ALERTMANAGER_URL', 'http://alertmanager-operated:9093'),
            'rollback_threshold': float(os.getenv('ROLLBACK_THRESHOLD', '0.8')),
            'health_check_timeout': int(os.getenv('HEALTH_CHECK_TIMEOUT', '300')),
            'error_threshold': int(os.getenv('ERROR_THRESHOLD', '5'))
        }
    
    # Create rollback system
    rollback_system = IntelligentRollback(config)
    
    if args.once:
        # Run once
        for namespace in args.namespaces:
            apps_v1 = client.AppsV1Api()
            deployments = apps_v1.list_namespaced_deployment(namespace)
            
            for deployment in deployments.items:
                if rollback_system.should_rollback(deployment.metadata.name, namespace):
                    rollback_system.perform_rollback(deployment.metadata.name, namespace)
    else:
        # Run continuously
        rollback_system.monitor_deployments(args.namespaces)

if __name__ == '__main__':
    main() 