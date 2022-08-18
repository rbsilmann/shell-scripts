#!/bin/bash

# Todas as funções aqui desenvolvidas trabalham utilizando o retorno como método de validação do sucesso
# ou da falha de alguma função, leve isso em consideração para a implementação de novos recursos.

# Desenvolvido e testado para distribuições Linux RedHat-Based 8+.

function testeConexao()
{
    # O código realiza um teste simples de ping, caso o teste de ping falhe ele interrompe a execução e
    # verifica se o DNS está configurado.
    ping 8.8.8.8 -c4 &> /dev/null
    if [ $? -eq 0 ]
    then
        return 0
    else
        cat /etc/resolv.conf | grep nameserver | cut -d" " -f2 > /tmp/dns
        DNS=$(ls -l /tmp/dns | awk '{print $5}')
        echo "Falha na conexão. Verifique a rede."
        if [ $DNS -eq 0 ] 
        then
            echo "Dica: não identificamos o DNS configurado. Configure e tente novamente."
        fi
        return 1
    fi
}

function configurarHostname()
{
    # A função realiza a alteração do hostname da máquina desde que o nome inserido não tenha caracteres
    # especiais.
    read -p "Digite o nome que deseja colocar para o dispositivo: " NOMEMAQUINA
    if [[ $NOMEMAQUINA =~ ['!@/\#$%^&*()_+'] ]] 
    then
        return 1
    else
        hostnamectl set-hostname $NOMEMAQUINA
        return 0
    fi
}

function verificarUsuario()
{
    # Esse script foi desenvolvido para administradores de sistemas, por conta disso deve ser executado
    # apenas com o super usuário do sistema (root).
    if [ $UID -ne 0 ] 
    then
        echo "O script só pode ser executado com o super usuário (root)."
        return 1
    else
        return 0
    fi
}

function instalarUtilitarios()
{
    # Função que será responsável por gerir os pacotes que serão instalados.
    dnf update -y && \
    dnf install -y  mlocate \
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

function particoesSistema()
{
    # O código abaixo testa a existência de partições chamadas data e dados.
    # O retorno 0 corresponde a existência dessas partições, já o retorno 1 corresponde a ausência delas.
    if [ 1 -eq 1 ] 
    then
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
    fi
}

function instalarPostgres()
{
    # Instalação do PostgreSQL 12.
    dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm
    dnf -qy module disable postgresql
    dnf install -y  postgresql12-server \
                    postgresql12-contrib
    particoesSistema
    if [ $? -eq 0 ]
    then
        DIRETORIO=$(cat /tmp/particao)
        mkdir -p $DIRETORIO/pgsql/12/main
        chown -R postgres:postgres $DIRETORIO/pgsql
        chmod -R 770 $DIRETORIO/pgsql
        mkdir /etc/systemd/system/postgresql-12.service.d
        echo -e "[Service]\nEnvironment=PGDATA=$DIRETORIO/pgsql/12/main" | tee -a /etc/systemd/system/postgresql-12.service.d/override.conf
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

function menuInstalarPostgres()
{
    # Esse menu é chamado durante a instalação do PostgreSQL caso não encontre a partição /dados ou /data,
    # ele possibilita que seja personalizado o diretório de criação do cluster.
    clear
    echo -e "Partição data ou dados não encontrada.\n\n"
    echo "1. Instalação padrão do PostgreSQL;"
    echo "2. Instalar em /home;"
    echo "3. Personalizar um diretório na raiz;"
    echo "4. Sair."
    read -p "Selecione uma das opções acima: " OPC
    case $OPC in
        1) return 0
        ;;
        2)  mkdir -p /home/pgsql/12/main
            chown -R postgres:postgres /home/pgsql
            chmod -R 770 /home/pgsql
            mkdir /etc/systemd/system/postgresql-12.service.d
            echo -e "[Service]\nEnvironment=PGDATA=/home/pgsql/12/main" | tee -a /etc/systemd/system/postgresql-12.service.d/override.conf
            return 0
        ;;
        3)  read -p "Digite apenas o nome do diretório sem caracteres especiais: " DIRETORIO
            if [[ $DIRETORIO =~ ['!@/\#$%^&*()_+'] ]] 
            then
                echo "Nome inválido."
                sleep 5
                menuInstalarPostgres
            else
                mkdir -p $DIRETORIO/pgsql/12/main
                chown -R postgres:postgres $DIRETORIO/pgsql
                chmod -R 770 $DIRETORIO/pgsql
                echo -e "[Service]\nEnvironment=PGDATA=$DIRETORIO/pgsql/12/main" | tee -a /etc/systemd/system/postgresql-12.service.d/override.conf
                return 0
            fi
        ;;
        4)  return 1
            break
        ;;
        *)  echo "Opção inválida."
            sleep 5
            menuInstalarPostgres
    esac
}

function tunningConfiguracaoPostgres()
{
    # Função responsável por realizar o tunning das configurações do PostgreSQL com basendo-se no hardware.
    # Informações de hardware.
    TIPODISCO=$(cat /sys/block/sda/queue/rotational)
    CPUS=$(lscpu | grep 'CPU(s):' | head -n1 | awk '{print $2}')
    MEMORIACONVERTIDAKB=$(cat /proc/meminfo | grep MemTotal | grep -o '[0-9]*')
    # Configuração de parâmetros baseados nas recomendações da documentação.
    SHARED_BUFFERS=$(($MEMORIACONVERTIDAKB/8/4))
    CACHE_SIZE=$(($MEMORIACONVERTIDAKB/8/4*3))
    MAINTANANCE_MEM=$(($MEMORIACONVERTIDAKB/8/8))
    MAX_PARALLEL_WORKERS=$(($CPUS/2))
    # Parâmetros maleáveis de acordo com o tipo de hardware precisam da verificação abaixo para
    # que o tunning seja preciso.
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
    # Criação do arquivo de source.
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
    # Os comandos abaixo realizam a alteração através do metacomando "ALTER SYSTEM" do PostgreSQL.
    # Eles ficam disponíveis para serem consultados no arquivo postgresql.auto.conf ou até mesmo na
    # view especial do PostgreSQL pg_settings.
    # Caso seja necessário é possível desfazer as alterações utilizando o "ALTER SYSTEM RESET ALL".
    echo "Rodando alterações no banco de dados..."
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -c "ALTER SYSTEM SET shared_buffers = $SHARED_BUFFERS;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -c "ALTER SYSTEM SET effective_cache_size = $CACHE_SIZE;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -c "ALTER SYSTEM SET maintenance_work_mem = $MAINTANANCE_MEM;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -c "ALTER SYSTEM SET max_worker_processes = $CPUS;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -c "ALTER SYSTEM SET max_parallel_workers_per_gather = $MAX_PARALLEL_WORKERS;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -c "ALTER SYSTEM SET max_parallel_workers = $CPUS;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -c "ALTER SYSTEM SET max_parallel_maintenance_workers = $MAX_PARALLEL_WORKERS;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -c "ALTER SYSTEM SET effective_io_concurrency = $IO;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -c "ALTER SYSTEM SET random_page_cost = $PAGE_COST;"'
    runuser -l postgres -c '/usr/pgsql-12/bin/psql -c "ALTER SYSTEM SET listen_addresses = $(cat /tmp/alladdress);"'
    runuser -l postgres -c '/usr/pgsql-12/bin/psql -c "ALTER SYSTEM SET max_connections = 200;"'
    runuser -l postgres -c '/usr/pgsql-12/bin/psql -c "ALTER SYSTEM SET checkpoint_completion_target = 0.9;"'
    runuser -l postgres -c '/usr/pgsql-12/bin/psql -c "ALTER SYSTEM SET wal_buffers = 2048;"'
    runuser -l postgres -c '/usr/pgsql-12/bin/psql -c "ALTER SYSTEM SET default_statistics_target = 2000;"'
    runuser -l postgres -c '/usr/pgsql-12/bin/psql -c "ALTER SYSTEM SET work_mem = 10240;"'
    runuser -l postgres -c '/usr/pgsql-12/bin/psql -c "ALTER SYSTEM SET min_wal_size = 1024;"'
    runuser -l postgres -c '/usr/pgsql-12/bin/psql -c "ALTER SYSTEM SET max_wal_size = 4096;"'
    if [ $? -eq 0 ] 
    then
        return 0
    else
        return 1
    fi
    systemctl restart postgresql-12
}

function alterarHostBasedAuth()
{
    # Função responsável por identificar as redes da máquina e realizar a autorização no arquivo pg_hba.conf
    # utilizando o método md5.
    REDES=$(hostname -I | sed 's/ /\n/g' | wc -l | bc)
    CONTADOR=1
    if [ $REDES -gt 2 ]; then
        while [ $CONTADOR -lt $REDES ]; do
            IPADDRESS=$(hostname -I | sed 's/ /\n/g' | sed -n "$CONTADOR p")
		    echo -e "host\tall\t\tall\t\t$IPADDRESS/24\t\tmd5" >> $DIRETORIO/pgsql/12/main/pg_hba.conf
		    LAST_IP=$(tail -n1 $DIRETORIO/pgsql/12/main/pg_hba.conf | cut -d . -f 4)
		    ALTER_IP=$(echo -e "0/24\t\tmd5")
		    sed -i "s|$LAST_IP|$ALTER_IP|g" $DIRETORIO/pgsql/12/main/pg_hba.conf
		    CONTADOR=$(($CONTADOR+1))
        done
    else
	    IPADDRESS=$(hostname -I | sed 's/ /\n/g' | sed -n "$CONTADOR p")
	    echo -e "host\tall\t\tall\t\t$IPADDRESS/24\t\tmd5" >> $DIRETORIO/pgsql/12/main/pg_hba.conf
	    LAST_IP=$(tail -n1 $DIRETORIO/pgsql/12/main/pg_hba.conf | cut -d . -f 4)
	    ALTER_IP=$(echo -e "0/24\t\tmd5")
	    sed -i "s|$LAST_IP|$ALTER_IP|g" $DIRETORIO/pgsql/12/main/pg_hba.conf
    fi
}

function instalarMonitoramentoPostgres()
{
    # Instalação do pgBadger e da ferramenta para envio de e-mail, uma ferramenta de monitoramento pontual.
    # A instalação dessa ferramenta é opcional, por conta disso propositalmente o arquivo .variables_badger
    # deve ser preenchido manualmente.
    mkdir /pg_badger
    dnf update -y
    dnf install -y git
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

function configurarSamba()
{
    # Função responsável por realizar a criação do compartilhamento público e restringir o acesso
    # a pasta de backup somente para o usuário criado.
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

function configurarFirewall()
{
    # Configuração de firewall alterando o perfil para ambiente corporativo e adicionando os serviços: samba
    # e do PostgreSQL nas exceções
    echo -n "Configurando zona padrão: "
    firewall-cmd --set-default-zone=work
    sleep 2
    echo -n "Configurando serviço samba: "
    firewall-cmd --add-service=samba --permanent
    sleep 2
    echo -n "Configurando serviço PostgreSQL: "
    firewall-cmd --add-service=postgresql --permanent
    sleep 2
    echo -n "Recarregando firewalld: "
    firewall-cmd --reload
    sleep 2
    echo "Habilitando inicialização automática SMB e NMB: "
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

function boasVindas()
{
    # 01 - Boas-vindas.
    clear
    echo "Olá, bem vindo ao assistente de configuração."
    sleep 5
    echo "Esse assistente irá auxiliar na configuração de um ambiente funcional"
    echo "utilizando PostgreSQL (otimizando as configurações de acordo com o hardware)"
    echo "e configurando um compartilhamento samba utilizando controle de acesso."
    sleep 10
    # 01
    #
    # 02 - Validações iniciais.
    clear
    echo "Inicialmente vamos validar se há acesso com a internet..."
    sleep 5
    testeConexao
    if [ $? -eq 0 ] 
    then
        echo "Conexão com a internet: OK" > /tmp/relatorio_instalacao.txt
    else
        echo "Conexão com a internet: FALHOU" > /tmp/relatorio_instalacao.txt
    fi
    echo "Agora validaremos a permissão do usuário conectado..."
    verificarUsuario
    if [ $? -eq 0 ]
    then
        echo "Validação de usuário: OK" >> /tmp/relatorio_instalacao.txt
        sleep 5
    else
        echo "Validação de usuário: FALHOU" >> /tmp/relatorio_instalacao.txt
        sleep 5
        exit
    fi
    # 02
    #
    # 03 - Início da instalação
    configurarHostname
    if [ $? -eq 0 ]
    then
        echo "Configuração de hostname: OK" >> /tmp/relatorio_instalacao.txt
        sleep 5
    else
        echo "Configuração de hostname: FALHOU" >> /tmp/relatorio_instalacao.txt
        sleep 5
    fi
    clear
    echo "Iniciando a instalação dos componentes necessários..."
    sleep 5
    instalarUtilitarios
    if [ $? -eq 0 ]
    then
        echo "Instalação de pré-requisitos: OK" >> /tmp/relatorio_instalacao.txt
        sleep 5
    else
        echo "Instalação de pré-requisitos: FALHOU" >> /tmp/relatorio_instalacao.txt
        sleep 5
    fi
    # 03
    #
    # 04 - Início das instalações/configurações do PostgreSQL e samba.
    clear
    echo "Iniciando a instalação do PostgreSQL 12..."
    sleep 5
    instalarPostgres
    if [ $? -eq 0 ]
    then
        echo "Instalação do PostgreSQL: OK" >> /tmp/relatorio_instalacao.txt
        sleep 5
        tunningConfiguracaoPostgres
        if [ $? -eq 0 ]
        then
            echo "Tunning do PostgreSQL: OK" >> /tmp/relatorio_instalacao.txt
        else
            echo "Tunning do PostgreSQL: FALHOU" >> /tmp/relatorio_instalacao.txt
        fi
    else
        echo "Instalação do PostgreSQL: FALHOU" >> /tmp/relatorio_instalacao.txt
        sleep 5
    fi
    clear
    configurarSamba
    if [ $? -eq 0 ]
    then
        echo "Configuração do SAMBA: OK" >> /tmp/relatorio_instalacao.txt
        sleep 5
    else
        echo "Configuração do SAMBA: FALHOU" >> /tmp/relatorio_instalacao.txt
        sleep 5
    fi
    # 04
    # 05 - Ajustes finais.
    clear
    instalarMonitoramentoPostgres
    if [ $? -eq 0 ]
    then
        echo "Instalação do pgBadger: OK" >> /tmp/relatorio_instalacao.txt
        sleep 5
    else
        echo "Instalação do pgBadger: FALHOU" >> /tmp/relatorio_instalacao.txt
        sleep 5
    fi
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
    alterarHostBasedAuth
    if [ $? -eq 0 ]
    then
        echo "Configuração do pg_hba.conf: OK" >> /tmp/relatorio_instalacao.txt
        sleep 5
    else
        echo "Configuração do pg_hba.conf: FALHOU" >> /tmp/relatorio_instalacao.txt
        sleep 5
    fi
    # 05
}

boasVindas