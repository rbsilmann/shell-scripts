#!/bin/bash

# Desenvolvido e testado apenas para distribuições RHEL-Based (7+).

function SET()
{
    qtde=$(( ( `tput cols` - `echo -n $txt | wc -c` ) / 2 ))
    esp=$(for ((X=0;X<=qtde;X++)) { echo -n " " ; })
    echo -e "\033[1;$cor$esp$txt\033[0m\n"
}

function SETR()
{
    qtde=$(( ( `tput cols` - `echo -n $txt | wc -c` ) / 2 ))
    esp=$(for ((X=0;X<=qtde;X++)) { echo -n " " ; })
    echo -e -n "\n\033[1;$cor$esp$txt\033[0m"
}

function textoPreto()
{
    txt=$@;cor="30m";SET; 
}

function textoVermelho()
{
    txt=$@;cor="31m";SET; 
}

function textoVerde()
{
    txt=$@;cor="32m";SET; 
}

function textoAmarelo()
{
    txt=$@;cor="33m";SET; 
}

function textoAzul()
{
    txt=$@;cor="34m";SET; 
}

function textoPurpura()
{
    txt=$@;cor="35m";SET; 
}

function textoCiano()
{
    txt=$@;cor="36m";SET; 
}

function textoBranco()
{
    txt=$@;cor="37m";SET; 
}

function readBranco()
{
    txt=$@;cor="37m";SETR; 
}

# Função testarConexao é responsável por realizar um ping para o endereço "8.8.8.8".
function testarConexao()
{
    ping 8.8.8.8 -c2 &> /dev/null
    case $? in
        0)
            return 0
        ;;
        1)
            textoVermelho "Teste de conexão falhou. Endereço 8.8.8.8 não alcançado."
            cat /etc/resolv.conf | grep nameserver | cut -d" " -f2 > /tmp/dns
            DNS=$(ls -l /tmp/dns | awk '{print $5}')
            if [ $DNS -eq 0 ] 
            then
                textoBranco "Dica: não identificamos o DNS configurado. Configure e tente novamente."
                sleep 5
                rm -rf /tmp/dns
            fi
            textoBranco "Encerrando configuração, até logo!"
            sleep 5
            return 1
        ;;
        *)
            textoVermelho "Um retorno não catalogado ocorreu, contate o administrador: rafael.bardini@outlook.com"
            sleep 5
            return 1
        ;;
    esac
}

# Função verificarUsuario é responsável por validar o UID do usuário, sendo necessário ser 0 (root).
function verificarUsuario()
{
    if [ $UID -eq 0 ]
    then
        return 0
    else
        textoVermelho "O script só deve ser executado com o usuário root. Encerrando configuração."
        return 1
    fi
}

# Função configurarHostname é responsável por realizar a alteração do hostname, é necessário
# que o nome informado não possua caracteres especiais, sendo eles: "!@/\#$%^&*()_+".
function configurarHostname()
{
    readBranco "Digite o nome que deseja colocar para o dispositivo: "
    read NOMEMAQUINA
    if [[ $NOMEMAQUINA =~ ['!@/\#$%^&*()_+'] ]] 
    then
        return 1
    else
        hostnamectl set-hostname $NOMEMAQUINA
        return 0
    fi
}

# Função definirGerenciadorPacotes realiza a coleta da versão para definir se o gerenciador
# de pacotes que será utilizado é yum ou dnf.
function definirGerenciadorPacotes()
{
    VERSAO=$(cat /etc/os-release | grep VERSION_ID | cut -d'"' -f2 | cut -d'.' -f1)
    case $VERSAO in
        7)
            GERENCIADOR=yum
            return 0
        ;;
        8)
            GERENCIADOR=dnf
            return 0
        ;;
        9)
            GERENCIADOR=dnf
            return 0
        ;;
        *)
            textoVermelho "Não foi possível definir a versão utilizando o arquivo /etc/os-release."
            textoBranco "Dica: verifique se a versão que está entre as versões compatíveis: RHEL (7, 8, 9) | CentOS (7, 8 e 9) | RockyLinux (7, 8 e 9)"
            return 1
    esac
    
}

# Função instalarUtilitarios realiza a instalação de ferramentas úteis para o servidor, ela
# só deve ser executada desde que a validação feita pela função definirGerenciadorPacotes tenha
# sido bem sucedida.
function instalarUtilitarios()
{
    $GERENCIADOR update -y && \
    $GERENCIADOR install -y mlocate \
                            curl \
                            bc \
                            vim \
                            samba \
                            cifs-utils \
                            sysstat \
                            perl \
                            firewalld
    if [ $? -eq 0 ]
    then
        return 0
    else
        return 1
    fi
}

# Função verificarParticao realiza a validação da existência de partições nomeadas
# /data ou /dados criadas geralmente na instalação.
function verificarParticao()
{
    df -h | grep /dados | awk '{print $6}' > /tmp/particao
    PARTICAO=$(ls -l /tmp/particao | awk '{print $5}')
    if [ $PARTICAO -gt 0 ] 
    then
        return 0
    elif [ $PARTICAO -eq 0 ]
    then
        df -h | grep /data | awk '{print $6}' > /tmp/particao
        PARTICAO=$(ls -l /tmp/particao | awk '{print $5}')
        if [ $PARTICAO -gt 0 ]
        then
            return 0
        else
            return 1
        fi
    fi
}

# Função instalarPostgres utiliza informações obtidas através da função definirGerenciadorPacotes,
# logo só deve ser chamada caso tenha obtido um retorno bem sucedido da mesma.
function instalarPostgres()
{
    $GERENCIADOR install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-$VERSAO-x86_64/pgdg-redhat-repo-latest.noarch.rpm
    if [ $VERSAO -gt 7 ]
    then
        $GERENCIADOR -qy module disable postgresql  
    fi
    $GERENCIADOR install -y postgresql12-server \
                            postgresql12-contrib
    verificarParticao
    if [ $? -eq 0 ]
    then
        DIRETORIO=$(cat /tmp/particao)
        mkdir -p $DIRETORIO/pgsql/12/main
        chown -R postgres:postgres $DIRETORIO/pgsql
        chmod -R 770 $DIRETORIO/pgsql
        mkdir -p /etc/systemd/system/postgresql-12.service.d
        echo -e "[Service]\nEnvironment=PGDATA=$DIRETORIO/pgsql/12/main" | tee -a /etc/systemd/system/postgresql-12.service.d/override.conf
        clear
        textoAzul "Inicializando o banco de dados..."
        sleep 5
        /usr/pgsql-12/bin/postgresql-12-setup initdb
        systemctl enable --now postgresql-12
        return 0
    else
        menuInstalarPostgres
        if [ $? -eq 0 ] 
        then
            /usr/pgsql-12/bin/postgresql-12-setup initdb
            systemctl enable --now postgresql-12
            return 0
        else
            return 1
        fi
    fi
}

# Função menuInstalarPostgres é chamada caso não seja identificada a existência de "/data" ou "/dados".
function menuInstalarPostgres()
{
    textoVermelho "Partição data / dados não encontrada."
    textoBranco "1. Instalação padrão PostgreSQL (/var);"
    textoBranco "2. Instalação na raiz de usuários (/home);"
    textoBranco "3. Personalizar partição/diretório na raiz;"
    textoBranco "4. Sair."
    readBranco "Selecione uma das opções acima: "
    read OPC
    case $OPC in
        1)
            return 0
        ;;
        2)
            mkdir -p /home/pgsql/12/main
            chown -R postgres:postgres /home/pgsql
            chmod -R 770 /home/pgsql
            mkdir -p /etc/systemd/system/postgresql-12.service.d
            echo -e "[Service]\nEnvironment=PGDATA=/home/pgsql/12/main" | tee -a /etc/systemd/system/postgresql-12.service.d/override.conf
            clear
            return 0
        ;;
        3)
            readBranco "Digite apenas o nome da partição/diretório na raiz sem caracteres especiais: "
            read DIRETORIO
            if [[ $DIRETORIO =~ ['!@/\#$%^&*()_+'] ]] 
            then
                textoVermelho "Nome inválido."
                sleep 5
                menuInstalarPostgres
            else
                DIRETORIO=/$DIRETORIO
                mkdir -p $DIRETORIO/pgsql/12/main
                chown -R postgres:postgres $DIRETORIO/pgsql
                chmod -R 770 $DIRETORIO/pgsql
                echo -e "[Service]\nEnvironment=PGDATA=$DIRETORIO/pgsql/12/main" | tee -a /etc/systemd/system/postgresql-12.service.d/override.conf
                clear
                return 0
            fi
        ;;
        4)
            return 1
        ;;
        *)
            textoVermelho "Opção inválida."
            sleep 5
            menuInstalarPostgres
    esac
}

# Função tunningConfiguracaoPostgres realiza as alterações de tunning baseadas no hardware encontrado.
function tunningConfiguracaoPostgres()
{
    PORTA=$1
    TIPODISCO=$(cat /sys/block/sda/queue/rotational)
    CPUS=$(lscpu | grep 'CPU(s):' | head -n1 | awk '{print $2}')
    MEMORIACONVERTIDAKB=$(cat /proc/meminfo | grep MemTotal | grep -o '[0-9]*')
    SHARED_BUFFERS=$(($MEMORIACONVERTIDAKB/8/4))
    CACHE_SIZE=$(($MEMORIACONVERTIDAKB/8/4*3))
    MAINTANANCE_MEM=$(($MEMORIACONVERTIDAKB/8/8))
    MAX_PARALLEL_WORKERS=$(($CPUS/2))
    if [ $MAX_PARALLEL_WORKERS > 4 ] 
    then
        MAX_PARALLEL_WORKERS=4
    fi
    if [ $TIPODISCO -eq 1 ] 
    then
        IO=2
        PAGE_COST=4
    else
        IO=200
        PAGE_COST=1.1
    fi
    echo "PORTA=$PORTA" | tee -a /tmp/infotunning
    echo "TIPODISCO=$TIPODISCO" | tee -a /tmp/infotunning
    echo "CPUS=$CPUS" | tee -a /tmp/infotunning
    echo "MEMORIACONVERTIDAKB=$MEMORIACONVERTIDAKB" | tee -a /tmp/infotunning
    echo "SHARED_BUFFERS=$SHARED_BUFFERS" | tee -a /tmp/infotunning
    echo "CACHE_SIZE=$CACHE_SIZE" | tee -a /tmp/infotunning
    echo "MAINTANANCE_MEM=$MAINTANANCE_MEM" | tee -a /tmp/infotunning
    echo "MAX_PARALLEL_WORKERS=$MAX_PARALLEL_WORKERS" | tee -a /tmp/infotunning
    echo "IO=$IO" | tee -a /tmp/infotunning
    echo "PAGE_COST=$PAGE_COST" | tee -a /tmp/infotunning
    echo '"*"' > /tmp/alladdress
    clear
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET shared_buffers = $SHARED_BUFFERS;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET effective_cache_size = $CACHE_SIZE;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET maintenance_work_mem = $MAINTANANCE_MEM;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET max_worker_processes = $CPUS;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET max_parallel_workers_per_gather = $MAX_PARALLEL_WORKERS;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET max_parallel_workers = $CPUS;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET max_parallel_maintenance_workers = $MAX_PARALLEL_WORKERS;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET effective_io_concurrency = $IO;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET random_page_cost = $PAGE_COST;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET listen_addresses = $(cat /tmp/alladdress);"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET max_connections = 200;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET checkpoint_completion_target = 0.9;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET wal_buffers = 2048;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET default_statistics_target = 2000;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET work_mem = 10240;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET min_wal_size = 1024;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET max_wal_size = 4096;"'
    if [ $? -eq 0 ] 
    then
        return 0
    else
        return 1
    fi
    systemctl restart postgresql-12
}

# Função alterarHostBasedAuth é responsável por realizar a alteração no arquivo "pg_hba.conf" com a rede 
# identificada, o padrão é adicionar o barramento "/16".
function alterarHostBasedAuth()
{
    PORTA=$1
    echo "PORTA=$PORTA" | tee -a /tmp/porta
    clear
    DIRETORIODATA=$(runuser -l postgres -c 'source /tmp/porta && /usr/pgsql-12/bin/psql -p $PORTA -c "SELECT setting FROM pg_settings"' | grep pg_hba.conf)
    REDES=$(hostname -I | sed 's/ /\n/g' | grep -v ":" | wc -l | bc)
    CONTADOR=1
    if [ $REDES -gt 2 ]; then
        while [ $CONTADOR -lt $REDES ]; do
            IPADDRESS=$(hostname -I | sed 's/ /\n/g' | sed -n "$CONTADOR p")
		    echo -e "host\tall\t\tall\t\t$IPADDRESS/16\t\tmd5" >> $DIRETORIODATA
		    LAST_IP=$(tail -n1 $DIRETORIODATA | cut -d . -f 4)
		    ALTER_IP=$(echo -e "0/16\t\tmd5")
		    sed -i "s|$LAST_IP|$ALTER_IP|g" $DIRETORIODATA
		    CONTADOR=$(($CONTADOR+1))
        done
    else
	    IPADDRESS=$(hostname -I | sed 's/ /\n/g' | sed -n "$CONTADOR p")
	    echo -e "host\tall\t\tall\t\t$IPADDRESS/16\t\tmd5" >> $DIRETORIODATA
	    LAST_IP=$(tail -n1 $DIRETORIODATA | cut -d . -f 4)
	    ALTER_IP=$(echo -e "0/16\t\tmd5")
	    sed -i "s|$LAST_IP|$ALTER_IP|g" $DIRETORIODATA
    fi
}

# Função instalarMonitoramentoPostgres é responsável por realizar o download do binário já compilado
# do pgBadger (log analyzer).
function instalarMonitoramentoPostgres()
{
    mkdir /pg_badger
    $GERENCIADOR update -y
    $GERENCIADOR install -y git
    curl https://storage.googleapis.com/linux-pdv/vrserver/centos/bin/pgbadger -o /pg_badger/pgbadger
    if [ $? -eq 0 ] 
    then
        return 0
    else
        return 1
    fi
    chown -R root:postgres /pg_badger
    chmod -R 770 /pg_badger
    git clone https://github.com/rbsilmann/pg-badger.git /pg_badger
}

# Função configurarSamba adiciona um usuário e um grupo de segurança para realizar o compartilhamento
# public e a sub-pasta backup protegida com usuário e senha.
function configurarSamba()
{
    PADRAOBACKUP=B4ckup@Software
    groupadd vrsamba
    useradd vrsoftware
    usermod -aG vrsamba vrsoftware
    usermod -p $(openssl passwd -1 $PADRAOBACKUP) vrsoftware
    mkdir -p /vr/backup
    chgrp vrsamba /vr/backup
    chmod 777 /vr
    chmod 770 /vr/backup
    chcon -t samba_share_t -R /vr
    mv /etc/samba/smb.conf /etc/samba/smb.conf.backup
    curl https://storage.googleapis.com/linux-pdv/vrserver/centos/files/smb.conf -o /etc/samba/smb.conf
    if [ $? -eq 0 ] 
    then
        return 0
    else
        return 1
    fi
}

# Função configurarFirewall realiza a alteração para o perfil "work" e adiciona os serviços necessários
# nas exceções de firewall.
function configurarFirewall()
{
    textoCiano "Configurando zona padrão: "
    firewall-cmd --set-default-zone=work
    sleep 2
    textoCiano "Configurando serviço SSH: "
    firewall-cmd --add-service=ssh --permanent
    sleep 2
    textoCiano "Configurando serviço Cockpit: "
    firewall-cmd --add-service=cockpit --permanent
    sleep 2
    textoCiano "Configurando serviço samba: "
    firewall-cmd --add-service=samba --permanent
    sleep 2
    textoCiano "Configurando serviço PostgreSQL: "
    firewall-cmd --add-service=postgresql --permanent
    sleep 2
    textoCiano "Recarregando firewalld: "
    firewall-cmd --reload
    sleep 2
    textoCiano "Habilitando inicialização automática SMB e NMB: "
    sleep 2
    systemctl enable smb nmb firewalld
    systemctl restart smb nmb firewalld
    if [ $? -eq 0 ] 
    then
        return 0
    else
        return 1
    fi
}

# Função alterarPorta é responsável por modificar o arquivo "postgresql.conf" alterando o valor default
# para 8745, essa alteração não é feita via ALTER SYSTEM para que seja fácil identificar a porta em que
# o banco de dados está rodando pelo arquivo padrão.
function alterarPorta()
{
    PORTA=$1
    DIRETORIODATA=$(runuser -l postgres -c 'source /tmp/porta && /usr/pgsql-12/bin/psql -p $PORTA -c "SELECT setting FROM pg_settings"' | grep postgresql.conf)
    sed -i "/#port/s/5432/$PORTA/g" $DIRETORIODATA
    sed -i "/#port/s/#port/port/g" $DIRETORIODATA
    if [ $? -eq 0 ] 
    then
        return 0
    else
        return 1
    fi
    systemctl restart postgresql-12
}

# Função criarRoles cria alguns objetos no banco de dados.
function criarRoles()
{
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "CREATE DATABASE vr;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "CREATE ROLE pgsql LOGIN SUPERUSER INHERIT CREATEDB CREATEROLE REPLICATION;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "CREATE USER arcos;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "CREATE USER arquitetura;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "CREATE USER desenvolvimento;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "CREATE USER implantacao;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "CREATE USER mercafacil;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "CREATE USER mixfiscal;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "CREATE USER pagpouco;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "CREATE USER projeto;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "CREATE USER suporte;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "CREATE USER vr;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "CREATE USER yandeh;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "CREATE USER smarket;"'
    if [ $? -eq 0 ] 
    then
        return 0
    else
        return 1
    fi
}

# Função instalacaoPadrao realiza é chamada no menu de opções através da opção 1.
# Nessa função o espaçamento entre as linhas refere-se aos blocos lógicos.
function instalacaoPadrao()
{
    clear
    textoAmarelo "Olá, bem-vindo ao assistente de configuração!"
    sleep 5
    textoBranco "O assistente se encarregará de auxiliar nas seguintes configurações:"
    textoBranco "- Instalação/configuração do SGBD PostgreSQL e pgBadger"
    textoBranco "- Instalação/configuração do samba"
    textoBranco "- Instalação de utilitários básicos"
    textoBranco "- Liberações de firewall"
    sleep 10
    #
    clear
    textoAzul "Inicialmente vamos validar se há acesso com a internet, beleza?"
    sleep 2
    testarConexao
    if [ $? -eq 0 ] 
    then
        textoVerde "Tudo certo com a sua conexão! =D"
        echo "Conexão com a internet (ping 8.8.8.8): OK" > /tmp/relatorio_instalacao.txt
    else
        echo "Conexão com a internet (ping 8.8.8.8): FALHOU" > /tmp/relatorio_instalacao.txt
    fi
    textoAzul "Agora validaremos a permissão do usuário conectado."
    sleep 5
    verificarUsuario
    if [ $? -eq 0 ]
    then
        textoVerde "Tudo certo também com o seu usuário! =)"
        echo "Validação de usuário (root): OK" >> /tmp/relatorio_instalacao.txt
        sleep 5
    else
        echo "Validação de usuário (root): FALHOU" >> /tmp/relatorio_instalacao.txt
        sleep 5
        exit
    fi
    configurarHostname
    if [ $? -eq 0 ]
    then
        textoVerde "Hostname configurado com sucesso!"
        echo "Configuração de hostname: OK" >> /tmp/relatorio_instalacao.txt
        sleep 5
    else
        textoVermelho "Falha ao configurar o novo hostname. Caracteres especiais identificados."
        echo "Configuração de hostname: FALHOU" >> /tmp/relatorio_instalacao.txt
        sleep 5
    fi
    #
    clear
    textoAzul "Iniciando a instalação dos componentes necessários."
    sleep 5
    definirGerenciadorPacotes
    if [ $? -eq 0 ]
    then
        textoVerde "Sistema operacional compatível com o script!"
        echo "Sistema operacional compatível: OK" >> /tmp/relatorio_instalacao.txt
        sleep 5
    else
        echo "Sistema operacional compatível: FALHOU" >> /tmp/relatorio_instalacao.txt
        sleep 5
        exit
    fi
    instalarUtilitarios
    if [ $? -eq 0 ]
    then
        echo "Instalação de pré-requisitos: OK" >> /tmp/relatorio_instalacao.txt
        sleep 5
    else
        echo "Instalação de pré-requisitos: FALHOU" >> /tmp/relatorio_instalacao.txt
        sleep 5
    fi
    #
    clear
    textoAzul "Iniciando a instalação do PostgreSQL 12..."
    sleep 5
    instalarPostgres
    if [ $? -eq 0 ]
    then
        echo ""
        textoVerde "Instalação do PostgreSQL realizada corretamente."
        echo "Instalação do PostgreSQL: OK" >> /tmp/relatorio_instalacao.txt
        sleep 5
        clear
        textoAzul "Aguarde enquanto ajustamos o tunning."
        sleep 5
        tunningConfiguracaoPostgres 5432
        if [ $? -eq 0 ]
        then
            echo "Tunning do PostgreSQL: OK" >> /tmp/relatorio_instalacao.txt
        else
            echo "Tunning do PostgreSQL: FALHOU" >> /tmp/relatorio_instalacao.txt
        fi
        clear
        textoAzul "Criando database inicial e roles..."
        criarRoles
        if [ $? -eq 0 ]
        then
            echo "Criação de database e roles: OK" >> /tmp/relatorio_instalacao.txt
        else
            echo "Criação de database e roles: FALHOU" >> /tmp/relatorio_instalacao.txt
        fi
        sleep 5
        clear
    else
        echo "Instalação do PostgreSQL: FALHOU" >> /tmp/relatorio_instalacao.txt
        sleep 5
    fi
    configurarSamba
    if [ $? -eq 0 ]
    then
        echo "Configuração do SAMBA: OK" >> /tmp/relatorio_instalacao.txt
        sleep 5
    else
        echo "Configuração do SAMBA: FALHOU" >> /tmp/relatorio_instalacao.txt
        sleep 5
    fi
    #
    instalarMonitoramentoPostgres
    if [ $? -eq 0 ]
    then
        echo "Instalação do pgBadger: OK" >> /tmp/relatorio_instalacao.txt
        sleep 5
    else
        echo "Instalação do pgBadger: FALHOU" >> /tmp/relatorio_instalacao.txt
        sleep 5
    fi
    #
    clear
    configurarFirewall
    if [ $? -eq 0 ]
    then
        echo "Configuração de firewall: OK" >> /tmp/relatorio_instalacao.txt
        sleep 5
    else
        echo "Configuração de firewall: FALHOU" >> /tmp/relatorio_instalacao.txt
        sleep 5
    fi
    #
    alterarHostBasedAuth 5432
    if [ $? -eq 0 ]
    then
        echo "Configuração do pg_hba.conf: OK" >> /tmp/relatorio_instalacao.txt
        sleep 5
    else
        echo "Configuração do pg_hba.conf: FALHOU" >> /tmp/relatorio_instalacao.txt
        sleep 5
    fi
    alterarPorta 8745
    if [ $? -eq 0 ]
    then
        echo "Configuração da porta: OK" >> /tmp/relatorio_instalacao.txt
        sleep 5
    else
        echo "Configuração do porta: FALHOU" >> /tmp/relatorio_instalacao.txt
        sleep 5
    fi
}

# Função menuConfiguracao é responsável por centralizar a chamada das funções dependendo da opção
# escolhida.
function menuConfiguracao()
{
    clear
    textoPreto "MENU"
    textoAzul "| 1. Instalação completa (PostgreSQL, Tunning, adição de liberações HBA, Samba);"
    textoCiano "| 2. PostgreSQL;"
    textoAmarelo "| 3. Tunning;"
    textoBranco "| 4. Liberações HBA;"
    textoPurpura "| 5. Instalação do Samba;"
    textoVermelho "| 6. Sair."
    readBranco "Selecione a opção desejada: "
    read MENU
    case $MENU in
        1)  clear
            instalacaoPadrao
            exit
        ;;
        2)  clear
            verificarUsuario
            if [ $? -ne 0 ] 
            then
                textoVermelho "É necessário que você execute essa função como root."
                sleep 5
                exit
            fi
            definirGerenciadorPacotes
            if [ $? -eq 0 ] 
            then
                clear
                instalarPostgres
                clear
                textoVerde "PostgreSQL instalado com sucesso! =)"
                sleep 5
            else
                clear
                textoVermelho "Falha ao instalar o PostgreSQL, não foi possível definir o gerenciador de pacotes."
                sleep 5
            fi
            menuConfiguracao
        ;;
        3)  clear
            verificarUsuario
            if [ $? -ne 0 ] 
            then
                textoVermelho "É necessário que você execute essa função como root."
                sleep 5
                exit
            fi
            readBranco "Informe a porta do banco de dados: "
            read PORTA
            tunningConfiguracaoPostgres $PORTA
            if [ $? -eq 0 ] 
            then
                textoVerde "Tunning realizado com sucesso."
                sleep 5
            else
                textoVermelho "Tunning falhou, verifique a porta informada! Porta informada: $PORTA"
                sleep 5
            fi
            menuConfiguracao
        ;;
        4)  clear
            verificarUsuario
            if [ $? -ne 0 ] 
            then
                textoVermelho "É necessário que você execute essa função como root."
                sleep 5
                exit
            fi
            readBranco "Informe a porta do banco de dados: "
            read PORTA
            alterarHostBasedAuth $PORTA
            if [ $? -ne 0 ] 
            then
                textoVermelho "Não foi possível adicionar informações no HBA, verifique a interface de rede."
                sleep 5
                exit
            else
                textoVerde "HBA configurado com sucesso, reinicie o serviço do PostgreSQL."
                sleep 5
            fi
            menuConfiguracao
        ;;
        5)  clear
            verificarUsuario
            if [ $? -ne 0 ] 
            then
                textoVermelho "É necessário que você execute essa função como root."
                sleep 5
                exit
            fi
            definirGerenciadorPacotes
            if [ $? -eq 0 ] 
            then
                clear
                instalarUtilitarios
                if [ $? -eq 0 ] 
                then
                    configurarSamba
                    configurarFirewall
                fi
            else
                clear
                textoVermelho "Falha ao instalar o samba, não foi possível definir o gerenciador de pacotes."
                sleep 5
            fi
            menuConfiguracao
        ;;
        6)  echo ""
            textoVermelho "Saindo do agente de configuração, até logo! =)"
            sleep 5
            exit
        ;;
        *)  clear
            textoVermelho "Opção inválida!!!"
            sleep 15
            menuConfiguracao
    esac
}

menuConfiguracao