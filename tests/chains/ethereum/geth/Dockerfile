FROM ethereum/client-go:v1.14.12

ARG CHAIN_ID

ADD geth.password /root/geth.password
ADD genesis-${CHAIN_ID}.json  /root/genesis.json
ADD privatekey  /root/privatekey
ADD run.sh  /run.sh

RUN /usr/local/bin/geth --datadir /root/.ethereum --state.scheme hash init /root/genesis.json

RUN /usr/local/bin/geth account import --password /root/geth.password /root/privatekey

EXPOSE 8545

ENTRYPOINT ["/run.sh"]
CMD ["--verbosity", "5", "--vmdebug"]
