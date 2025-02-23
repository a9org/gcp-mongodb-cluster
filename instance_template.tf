# Random MongoDB password
resource "random_password" "mongodb" {
  length           = 14
  special          = true
  override_special = "&8h8a9QogDb3y"
}

# Random MongoDB KeyFile com caracteres válidos
resource "random_password" "mongodb_keyfile_content" {
  length           = 756 # Tamanho recomendado pelo MongoDB
  special          = true
  override_special = "=+.-_" # Apenas caracteres especiais aceitos pelo MongoDB
  min_lower        = 10
  min_upper        = 10
  min_numeric      = 10
  min_special      = 4
}

# Local KeyFile
resource "local_file" "mongodb_keyfile" {
  content  = base64encode(random_password.mongodb_keyfile_content.result)
  filename = "${path.module}/mongodb-keyfile"
}


# Instance Template
resource "google_compute_instance_template" "mongodb_template" {
  name        = "${local.prefix_name}-mongodb-template"
  description = "Template for MongoDB ReplicaSet instances"

  tags = ["${local.prefix_name}-mongodb-node"]

  machine_type = var.machine_type

  disk {
    source_image = "ubuntu-os-cloud/ubuntu-2004-lts"
    auto_delete  = true
    boot         = true
    disk_size_gb = 30
    disk_type    = "pd-ssd"
  }

  disk {
    auto_delete  = true
    boot         = false
    disk_size_gb = var.mongodb_data_disk_size
    disk_type    = "pd-ssd"
    device_name  = "mongodb-data"
    interface    = "SCSI"
  }

  disk {
    auto_delete  = true
    boot         = false
    disk_size_gb = var.mongodb_logs_disk_size
    disk_type    = "pd-ssd"
    device_name  = "mongodb-logs"
    interface    = "SCSI"
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork
  }

  metadata = {
    ssh-keys           = "ubuntu:${var.ssh_public_key}"
    creation-timestamp = formatdate("YYYY-MM-DD'T'HH:mm:ssZ", timestamp())
    startup-script     = <<-EOF
  #!/bin/bash
  set -e

  # Funções utilitárias
  log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> /var/log/mongodb/startup.log; echo "$1"; }

  # Instalação do MongoDB 6.0
  wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | apt-key add -
  echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list
  apt-get update
  apt-get install -y mongodb-org

  # Função para esperar disco ficar disponível
  wait_for_disk() {
    local disk_name=$1
    local max_attempts=60
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
      if [ -b "$disk_name" ]; then
        return 0
      fi
      sleep 5
      attempt=$((attempt + 1))
    done
    return 1
  }

  # Configuração dos discos
  DATA_DISK="/dev/sdb"
  LOGS_DISK="/dev/sdc"

  # Aguarda os discos ficarem disponíveis
  wait_for_disk $DATA_DISK
  wait_for_disk $LOGS_DISK

  # Disco de dados
  if [ -b "$DATA_DISK" ]; then
    echo "Formatando disco de dados..."
    mkfs.xfs $DATA_DISK
    mkdir -p /data/mongodb
    mount $DATA_DISK /data/mongodb
    echo "$DATA_DISK /data/mongodb xfs defaults,nofail 0 2" >> /etc/fstab
  else
    echo "ERRO: Disco de dados não encontrado!"
    exit 1
  fi

  # Disco de logs
  if [ -b "$LOGS_DISK" ]; then
    echo "Formatando disco de logs..."
    mkfs.xfs $LOGS_DISK
    mkdir -p /var/log/mongodb
    mount $LOGS_DISK /var/log/mongodb
    echo "$LOGS_DISK /var/log/mongodb xfs defaults,nofail 0 2" >> /etc/fstab
  else
    echo "ERRO: Disco de logs não encontrado!"
    exit 1
  fi

  # Ajuste das permissões
  chown -R mongodb:mongodb /data/mongodb
  chown -R mongodb:mongodb /var/log/mongodb
  chmod 755 /data/mongodb
  chmod 755 /var/log/mongodb

  # Configuração do MongoDB
  log "Criando configuração do MongoDB..."
  cat > /etc/mongod.conf <<EOL
  storage:
    dbPath: /data/mongodb
    journal:
      enabled: true
  systemLog:
    destination: file
    path: /var/log/mongodb/mongod.log
    logAppend: true
  net:
    port: 27017
    bindIp: 0.0.0.0
  replication:
    replSetName: "rs0"
  security:
    keyFile: /etc/mongodb-keyfile
    authorization: enabled
  EOL
  # Cria o arquivo de chave
  log "Criando keyfile..."
  echo "${random_password.mongodb_keyfile_content.result}" | base64 > /etc/mongodb-keyfile
  chmod 600 /etc/mongodb-keyfile
  chown mongodb:mongodb /etc/mongodb-keyfile
  # Inicia o MongoDB
  log "Iniciando MongoDB..."
  systemctl start mongod
  systemctl enable mongod

  # Aguarda o MongoDB iniciar (sem autenticação ainda)
  log "Aguardando MongoDB iniciar..."
  for i in {1..30}; do
    if mongosh --quiet --eval "db.adminCommand('ping')" &>/dev/null; then
      log "MongoDB iniciado com sucesso"
      break
    fi
    log "Tentativa \$i: Aguardando MongoDB..."
    sleep 5
  done

  # Verifica o status do serviço para depuração (linha corrigida)
  log "Status do serviço MongoDB:"
  systemctl status mongod >> /var/log/mongodb/startup.log 2>&1

  # Definir variáveis de autenticação
  MONGO_ADMIN_USER="admin"
  MONGO_ADMIN_PWD="${random_password.mongodb.result}"

  # Funções para configuração do ReplicaSet
  get_instance_metadata() {
    curl -s "http://metadata.google.internal/computeMetadata/v1/\$1" -H "Metadata-Flavor: Google"
  }

  get_mig_instances() {
    project=\$(get_instance_metadata "project/project-id")
    zone=\$(get_instance_metadata "instance/zone" | cut -d'/' -f4)
    mig_name="${local.prefix_name}-mongodb-nodes"
    gcloud compute instance-groups managed list-instances "\$mig_name" \
      --zone="\$zone" \
      --project="\$project" \
      --format="value(instance)" || echo ""
  }

  is_primary() {
    mongosh -u "\$MONGO_ADMIN_USER" -p "\$MONGO_ADMIN_PWD" --authenticationDatabase admin --quiet --eval "rs.isMaster().ismaster" 2>/dev/null | grep -q "true"
  }

  # Obtém informações da instância atual
  INSTANCE_NAME=\$(hostname -f)
  CREATION_TIMESTAMP=\$(get_instance_metadata "instance/attributes/creation-timestamp")
  log "Instância \$INSTANCE_NAME criada em \$CREATION_TIMESTAMP"

  # Lista todas as instâncias do MIG
  log "Buscando instâncias do MIG..."
  INSTANCES=\$(get_mig_instances)
  if [ -z "\$INSTANCES" ]; then
    log "Erro: Não foi possível listar instâncias do MIG"
    exit 1
  fi
  log "Instâncias encontradas: \$INSTANCES"

  # Determina a instância mais antiga (primário)
  OLDEST_INSTANCE=""
  OLDEST_TIMESTAMP="9999-12-31T23:59:59Z"
  for instance in \$INSTANCES; do
    instance_timestamp=\$(gcloud compute instances describe "\$instance" --zone="\$(get_instance_metadata "instance/zone" | cut -d'/' -f4)" --format="value(creationTimestamp)")
    if [ -n "\$instance_timestamp" ] && [[ "\$instance_timestamp" < "\$OLDEST_TIMESTAMP" ]]; then
      OLDEST_TIMESTAMP="\$instance_timestamp"
      OLDEST_INSTANCE="\$instance"
    fi
  done

  if [ -z "\$OLDEST_INSTANCE" ]; then
    log "Erro: Não foi possível determinar a instância mais antiga"
    exit 1
  fi
  log "Instância mais antiga (primário): \$OLDEST_INSTANCE"

  # Adiciona um atraso aleatório para evitar condições de corrida
  sleep \$((RANDOM % 10))

  if [ "\$INSTANCE_NAME" = "\$OLDEST_INSTANCE" ]; then
    log "Esta é a instância mais antiga. Iniciando ReplicaSet como primário..."
    
    # Inicializa o ReplicaSet com todas as instâncias (sem autenticação ainda)
    MEMBERS=""
    i=0
    for instance in \$INSTANCES; do
      MEMBERS="\$MEMBERS{ _id: \$i, host: '\$instance:27017'\$(if [ \$i -eq 0 ]; then echo ', priority: 2'; else echo ', priority: 1'; fi) },"
      i=\$((i + 1))
    done
    MEMBERS_JSON="[$(echo "\$MEMBERS" | sed 's/,$//')]"
    log "Configuração do ReplicaSet: \$MEMBERS_JSON"

    mongosh --eval "rs.initiate({ _id: 'rs0', members: \$MEMBERS_JSON })"
    
    # Aguarda o primário estar pronto (sem autenticação ainda)
    for i in {1..60}; do
      if mongosh --quiet --eval "rs.isMaster().ismaster" 2>/dev/null | grep -q "true"; then
        log "ReplicaSet iniciado com sucesso"
        mongosh admin --eval "db.createUser({ user: '\$MONGO_ADMIN_USER', pwd: '\$MONGO_ADMIN_PWD', roles: ['root'] })"
        log "Usuário admin criado"
        break
      fi
      log "Aguardando primário... tentativa \$i"
      sleep 5
    done
  else
    log "Esta não é a instância mais antiga. Tentando se juntar ao ReplicaSet..."
    
    # Aguarda o primário estar disponível e autenticado (aumentado para 120 tentativas)
    for i in {1..120}; do
      if mongosh --host "\$OLDEST_INSTANCE" -u "\$MONGO_ADMIN_USER" -p "\$MONGO_ADMIN_PWD" --authenticationDatabase admin --quiet --eval "rs.isMaster().ismaster" 2>/dev/null | grep -q "true"; then
        log "Primário encontrado em \$OLDEST_INSTANCE. Adicionando esta instância..."
        mongosh --host "\$OLDEST_INSTANCE" -u "\$MONGO_ADMIN_USER" -p "\$MONGO_ADMIN_PWD" --authenticationDatabase admin --eval "rs.add('\$INSTANCE_NAME:27017')"
        break
      fi
      log "Aguardando primário em \$OLDEST_INSTANCE... tentativa \$i"
      sleep 5
    done
  fi

  # Verifica o status final com autenticação
  log "Verificando status do ReplicaSet..."
  mongosh -u "\$MONGO_ADMIN_USER" -p "\$MONGO_ADMIN_PWD" --authenticationDatabase admin --eval "rs.status()" >> /var/log/mongodb/startup.log 2>&1

  log "Configuração concluída com sucesso"
  EOF
  }
  service_account {
    scopes = [
      "compute-ro",
      "storage-ro",
      "cloud-platform"
    ]
  }

  labels = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}
