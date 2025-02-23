# Random MongoDB password
resource "random_password" "mongodb" {
  length           = 14
  special          = true
  override_special = "&8h8a9QogDb3y"
}

# Random MongoDB KeyFile com caracteres válidos
resource "random_password" "mongodb_keyfile_content" {
  length           = 756  # Tamanho recomendado pelo MongoDB
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

  # Configuração dos discos [mantido o código existente dos discos]
  # ... [código dos discos permanece o mesmo]

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

  # Obtém o nome da instância atual
  INSTANCE_NAME=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/name" -H "Metadata-Flavor: Google")
  INSTANCE_HOSTNAME=$(hostname -f)

  # Função para verificar se o ReplicaSet já está iniciado em algum nó
  check_replicaset_initialized() {
    mongosh --quiet --eval "rs.status()" &>/dev/null
    return $?
  }

  # Função para obter o status do ReplicaSet
  get_replicaset_status() {
    mongosh --quiet --eval "rs.status().ok" || echo "0"
  }

  # Função para tentar inicializar o ReplicaSet
  try_initialize_replicaset() {
    mongosh --eval "
      rs.initiate({
        _id: 'rs0',
        members: [{
          _id: 0,
          host: '$(hostname -f):27017',
          priority: 1
        }]
      })
    " || return 1
  }

  # Função para tentar adicionar o nó ao ReplicaSet
  try_add_to_replicaset() {
    local primary_host=$1
    mongosh --host $primary_host --eval "
      rs.add('$(hostname -f):27017')
    " || return 1
  }

  # Tenta inicializar ou juntar-se ao ReplicaSet
  MAX_ATTEMPTS=30
  ATTEMPT=1
  INITIALIZED=false

  while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    echo "Tentativa $ATTEMPT de configurar o ReplicaSet..."
    
    # Verifica se o ReplicaSet já está iniciado
    if ! check_replicaset_initialized; then
      echo "ReplicaSet não está iniciado. Tentando inicializar..."
      if try_initialize_replicaset; then
        sleep 10
        
        if [ "$(get_replicaset_status)" == "1" ]; then
          echo "ReplicaSet inicializado com sucesso"
          INITIALIZED=true
          break
        fi
      else
        echo "Falha ao inicializar ReplicaSet"
      fi
    else
      echo "ReplicaSet já está iniciado. Tentando adicionar este nó..."
      PRIMARY_HOST=$(mongosh --quiet --eval "rs.isMaster().primary" || echo "")
      
      if [ ! -z "$PRIMARY_HOST" ]; then
        if try_add_to_replicaset $PRIMARY_HOST; then
          sleep 10
          INITIALIZED=true
          break
        else
          echo "Falha ao adicionar nó ao ReplicaSet"
        fi
      fi
    fi
    
    echo "Tentativa $ATTEMPT falhou. Aguardando próxima tentativa..."
    ATTEMPT=$((ATTEMPT + 1))
    sleep 10
  done

  if [ "$INITIALIZED" = true ]; then
    echo "Nó configurado com sucesso no ReplicaSet"
    
    # Se este for o nó que inicializou o ReplicaSet, configura o usuário admin
    if [ "$(mongosh --quiet --eval "rs.isMaster().ismaster" || echo "false")" == "true" ]; then
      echo "Configurando usuário admin..."
      sleep 30  # Aguarda a estabilização do ReplicaSet
      
      mongosh admin --eval "
        db.createUser({
          user: 'admin',
          pwd: '${random_password.mongodb.result}',
          roles: ['root']
        })
      "
      
      # Habilita autenticação após criar o usuário
      sed -i 's/authorization: disabled/authorization: enabled/' /etc/mongod.conf
      systemctl restart mongod
    fi
  else
    echo "Falha ao configurar o ReplicaSet após $MAX_ATTEMPTS tentativas"
    echo "=== Status do MongoDB ==="
    systemctl status mongod
    echo "=== Últimas 20 linhas do log ==="
    tail -n 20 /var/log/mongodb/mongod.log
    exit 1
  fi

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
