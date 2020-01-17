#!/usr/bin/env bash

function info() {
    echo -e "************************************************************\n\033[1;33m${1}\033[m\n************************************************************"
}

orgs=$@
first_org=${1:-org1}

export DOMAIN=${DOMAIN:-example.com}
export SERVICE_CHANNEL=${SERVICE_CHANNEL:-common}

export LDAP_ENABLED=true
export LDAPADMIN_HTTPS=${LDAPADMIN_HTTPS:-true}

docker_compose_args=${DOCKER_COMPOSE_ARGS:-"-f docker-compose.yaml -f docker-compose-couchdb.yaml -f https/docker-compose-generate-tls-certs.yaml -f https/docker-compose-https-ports.yaml -f docker-compose-ldap.yaml"}
# -f environments/dev/docker-compose-debug.yaml -f https/docker-compose-generate-tls-certs-debug.yaml
: ${DOCKER_COMPOSE_ORDERER_ARGS:="-f docker-compose-orderer.yaml -f docker-compose-orderer-domain.yaml -f docker-compose-orderer-ports.yaml"}


info "Cleaning up"
./clean.sh all
unset ORG COMPOSE_PROJECT_NAME

export DOCKER_REGISTRY=docker.io
export FABRIC_VERSION=1.4.4
export FABRIC_STARTER_VERSION=baas-test

if [ "$DEPLOY_VERSION" == "Hyperledger Fabric 1.4.4-GOST-34" ]; then
    set -x
    export DOCKER_REGISTRY=registry.labdlt.ru
    export FABRIC_VERSION=latest
    export FABRIC_STARTER_VERSION=baas-test
    export AUTH_MODE=ADMIN
    export CRYPTO_ALGORITHM=GOST
    export SIGNATURE_HASH_FAMILY=SM3
    export DNS_USERNAME=admin
    export DNS_PASSWORD=${ENROLL_SECRET:-adminpw}
    set +x
fi

# Create orderer organization

#docker pull ${DOCKER_REGISTRY:-docker.io}/olegabu/fabric-tools-extended:${FABRIC_STARTER_VERSION:-latest}
#docker pull ${DOCKER_REGISTRY:-docker.io}/olegabu/fabric-starter-rest:${FABRIC_STARTER_VERSION:-latest}


source ${first_org}_env;

info "Creating orderer organization for $DOMAIN"

shopt -s nocasematch
if [ "${ORDERER_TYPE}" == "SOLO" ]; then
    WWW_PORT=${ORDERER_WWW_PORT} docker-compose -f docker-compose-orderer.yaml -f docker-compose-orderer-ports.yaml up -d
    #-f environments/dev/docker-compose-orderer-debug.yaml
else
    WWW_PORT=${ORDERER_WWW_PORT} DOCKER_COMPOSE_ORDERER_ARGS=${DOCKER_COMPOSE_ORDERER_ARGS} ./raft/1_raft-start-3-nodes.sh
fi

sleep 3

info "Create first organization ${first_org}"
echo "docker-compose ${docker_compose_args} up -d"
source ${first_org}_env;
COMPOSE_PROJECT_NAME=${first_org} docker-compose ${docker_compose_args} up -d

echo -e "\nWait post-install.${first_org}.${DOMAIN} to complete"
docker wait post-install.${first_org}.${DOMAIN}
for org in ${@:2}; do
    source ${org}_env
    info "      Creating member organization $ORG with api $API_PORT"
    echo "docker-compose ${docker_compose_args} up -d"
    COMPOSE_PROJECT_NAME=${org} docker-compose ${docker_compose_args} up -d
done

sleep 4
for org in "${@:2}"; do
    source ${org}_env
    orgPeer0Port=${PEER0_PORT}

    info "Adding $org to channel ${SERVICE_CHANNEL}"
    source ${first_org}_env;
    COMPOSE_PROJECT_NAME=$first_org ORG=$first_org ./channel-add-org.sh ${SERVICE_CHANNEL} ${org} ${orgPeer0Port}
done

