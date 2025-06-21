[SERVICE]
    Flush        1
    Log_Level    info
    Parsers_File parsers.conf
    HTTP_Server  On
    HTTP_Listen  0.0.0.0
    HTTP_Port    2020

[INPUT]
    Name              tail
    Tag               kube.*
    Path              /var/log/containers/*.log
    Parser            docker
    DB                /var/log/flb_kube.db
    Skip_Long_Lines   On
    Refresh_Interval  10

[INPUT]
    Name              systemd
    Tag               host.*
    Systemd_Filter    _SYSTEMD_UNIT=kubelet.service
    Read_From_Tail    true
    Strip_Underscores true

[FILTER]
    Name                kubernetes
    Match               kube.*
    Kube_URL           https://kubernetes.default.svc:443
    Kube_CA_Path       /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    Kube_Token_Path    /var/run/secrets/kubernetes.io/serviceaccount/token
    Merge_Log          On
    Merge_Log_Key      log_processed
    K8S-Logging.Parser On
    K8S-Logging.Exclude On

[FILTER]
    Name   record_modifier
    Match  *
    Record environment ${environment}
    Record cluster_name ${cluster_name}
    Record cloud_provider ${cloud_provider}

%{ if cloud_provider == "aws" }
[OUTPUT]
    Name              cloudwatch
    Match             *
    region            ${aws_region}
    log_group_name    ${log_group}
    log_stream_prefix fluent-bit-
    auto_create_group true
    log_key           log
    log_format        json/emf
    role_arn          ${role_arn}
    net.connect_timeout 10
    net.keepalive     off
%{ endif }

%{ if cloud_provider == "azure" }
[OUTPUT]
    Name              azure
    Match             *
    Tenant_ID         ${tenant_id}
    Client_ID         ${client_id}
    Client_Secret     ${client_secret}
    Workspace_ID      ${workspace_id}
    Log_Type          ContainerLogs
    Time_Generated_Field @timestamp
%{ endif }

%{ if cloud_provider == "gcp" }
[OUTPUT]
    Name              stackdriver
    Match             *
    project_id        ${gcp_project}
    resource          k8s_container
    k8s_cluster_name  ${cluster_name}
    k8s_cluster_location ${gcp_region}
    severity_key      severity
    labels_key        labels
    metadata_keys     metadata
%{ endif }

%{ if enable_elasticsearch }
[OUTPUT]
    Name              es
    Match             *
    Host              elasticsearch-master
    Port              9200
    Index              fluent-bit
    Type              _doc
    Generate_ID       On
    Suppress_Type_Name On
    tls               Off
    HTTP_User         elastic
    HTTP_Passwd       ${elastic_password}
%{ endif } 