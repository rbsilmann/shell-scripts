#!/bin/bash

# Variáveis de backup.
DIRETORIO="/vr/backup"
PORTA="8745"
DATA=$(date +%H%M%d%m%y)
NOME="dump_database_$DATA"

# Executando o backup e removendo arquivos com mais de 7 dias.
pg_dump -U postgres -p $PORTA -d vr -Fc > $DIRETORIO/$NOME.backup 2> $DIRETORIO/$NOME.log
if [ $? -ne 0 ] 
then
    echo "O backup nomeado $NOME não foi executado corretamente, verifique o arquivo de log." | tee -a $DIRETORIO/log_erro.txt
fi
find $DIRETORIO/* -name "$NOME" -mtime +7 -exec rm {} \;

# Ajustando permissão dos arquivos.
chmod 660 $DIRETORIO/*