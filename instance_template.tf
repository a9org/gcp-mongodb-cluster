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
    ssh-keys       = "ubuntu:${var.ssh_public_key}"
    startup-script = <<-EOF
  #!/bin/bash
  set -e

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
      echo "Aguardando disco $disk_name ficar disponível... tentativa $attempt"
      sleep 5
      attempt=$((attempt + 1))
    done
    
    echo "Timeout esperando pelo disco $disk_name"
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

  # Configuração do MongoDB com bind_ip ajustado
  cat > /etc/mongod.conf <<-EOL
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
    authorization: disabled  # Inicialmente desabilitado para setup
  setParameter:
    maxIndexBuildMemoryUsageMegabytes: 1000
  EOL

  # Cria o arquivo de chave com conteúdo base64
  echo "${random_password.mongodb_keyfile_content.result}" | base64 > /etc/mongodb-keyfile
  chmod 600 /etc/mongodb-keyfile
  chown mongodb:mongodb /etc/mongodb-keyfile

  # Verificação do keyfile
  if [ ! -s /etc/mongodb-keyfile ]; then
    echo "ERRO: Arquivo keyfile está vazio!"
    exit 1
  fi

  echo "KeyFile criado com sucesso"
  ls -l /etc/mongodb-keyfile
  
  # Reinicia o MongoDB e verifica o status
  systemctl stop mongod || true
  sleep 5
  systemctl start mongod
  systemctl enable mongod

  # Função para verificar se o MongoDB está respondendo
  wait_for_mongodb() {
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
      if mongosh --quiet --eval "db.adminCommand('ping')" &>/dev/null; then
        echo "MongoDB está respondendo!"
        return 0
      fi
      echo "Tentativa $attempt: Aguardando MongoDB iniciar..."
      sleep 10
      attempt=$((attempt + 1))
    done
    
    echo "Timeout aguardando MongoDB iniciar"
    return 1
  }

  # Aguarda o MongoDB iniciar
  echo "Aguardando MongoDB iniciar..."
  if ! wait_for_mongodb; then
    echo "ERRO: MongoDB não iniciou corretamente"
    echo "=== Status do MongoDB ==="
    systemctl status mongod
    echo "=== Últimas 20 linhas do log ==="
    tail -n 20 /var/log/mongodb/mongod.log
    exit 1
  fi

  # Função para obter o timestamp de criação da instância
  get_instance_creation_timestamp() {
    curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/creation-timestamp" -H "Metadata-Flavor: Google"
  }

  # Função para encontrar outras instâncias do MIG
  find_mig_instances() {
    local project=$(curl -s "http://metadata.google.internal/computeMetadata/v1/project/project-id" -H "Metadata-Flavor: Google")
    local zone=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/zone" -H "Metadata-Flavor: Google" | cut -d/ -f4)
    local mig_name="${local.prefix_name}-mongodb-nodes"
    
    # Lista as instâncias do MIG
    instances=$(gcloud compute instance-groups managed list-instances $mig_name \
      --zone=$zone \
      --project=$project \
      --format="value(instance.scope(instances))")
    
    echo "$instances"
  }

  # Função para encontrar o primário existente
  find_primary() {
    local max_attempts=10
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
      echo "Tentativa $attempt de encontrar primário existente..."
      
      # Obter lista de instâncias do MIG
      local instances=$(find_mig_instances)
      
      for instance in $instances; do
        echo "Verificando $instance..."
        
        # Tenta conectar em cada instância
        if mongosh --host $instance --eval "rs.isMaster()" --quiet 2>/dev/null | grep -q '"ismaster" : true'; then
          echo "Primário encontrado: $instance"
          echo $instance
          return 0
        fi
      done
      
      attempt=$((attempt + 1))
      sleep 10
    done
    
    echo ""
    return 1
  }

  # Obtém o timestamp de criação desta instância
  CREATION_TIMESTAMP=$(get_instance_creation_timestamp)
  INSTANCE_NAME=$(hostname)
  echo "Esta instância ($INSTANCE_NAME) foi criada em: $CREATION_TIMESTAMP"

  # Aguarda um tempo aleatório entre 0-30 segundos para evitar corrida
  sleep $((RANDOM % 30))

  # Verifica se já existe um primário
  PRIMARY_HOST=$(find_primary)

  if [ -z "$PRIMARY_HOST" ]; then
    echo "Nenhum primário encontrado. Verificando se esta instância deve inicializar..."
    
    # Lista todas as instâncias e seus timestamps
    instances=$(find_mig_instances)
    oldest_instance=""
    oldest_timestamp="999999999999999999"
    
    for instance in $instances; do
      instance_timestamp=$(gcloud compute instances describe $instance --format="value(creationTimestamp)")
      if [[ $instance_timestamp < $oldest_timestamp ]]; then
        oldest_timestamp=$instance_timestamp
        oldest_instance=$instance
      fi
    done
    
    # Se esta for a instância mais antiga, inicializa o ReplicaSet
    if [[ "$INSTANCE_NAME" == "$oldest_instance" ]]; then
      echo "Esta é a instância mais antiga. Iniciando novo ReplicaSet..."
      
      # Inicializa o ReplicaSet
      mongosh --eval "
        rs.initiate({
          _id: 'rs0',
          members: [
            { _id: 0, host: '$(hostname -f):27017', priority: 2 }
          ]
        })
      "
      
      # Aguarda o ReplicaSet inicializar
      MAX_WAIT=60
      WAIT_COUNT=0
      while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
        if mongosh --eval "rs.status()" --quiet | grep -q '"stateStr" : "PRIMARY"'; then
          echo "ReplicaSet inicializado com sucesso"
          break
        fi
        echo "Aguardando ReplicaSet inicializar..."
        sleep 5
        WAIT_COUNT=$((WAIT_COUNT + 1))
      done

      # Configura o usuário admin no primário
      echo "Configurando usuário admin..."
      sleep 10  # Aguarda estabilização
      
      mongosh admin --eval "
        db.createUser({
          user: 'admin',
          pwd: '${random_password.mongodb.result}',
          roles: ['root']
        })
      "
    else
      echo "Esta não é a instância mais antiga. Aguardando..."
      exit 1
    fi
  else
    echo "Primário encontrado em $PRIMARY_HOST. Adicionando esta instância ao ReplicaSet..."
    
    # Tenta adicionar este nó ao ReplicaSet
    mongosh --host $PRIMARY_HOST --eval "
      rs.add('$(hostname -f):27017')
    "
  fi

  # Aguarda a configuração ser aplicada
  sleep 30

  # Verifica o status final
  echo "Status final do ReplicaSet:"
  mongosh --eval "rs.status()"

  # Log completion
  echo "Startup script completed successfully"
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
