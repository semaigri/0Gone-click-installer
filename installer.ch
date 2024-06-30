#!/bin/bash

# Update and install necessary packages
sudo apt update
sudo apt install curl git jq build-essential gcc unzip wget lz4 -y

# Install the latest GO
cd $HOME
ver="1.22.4"
wget "https://golang.org/dl/go$ver.linux-amd64.tar.gz"
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf "go$ver.linux-amd64.tar.gz"
rm "go$ver.linux-amd64.tar.gz"
echo "export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin" >> $HOME/.bash_profile
source $HOME/.bash_profile
go version

# Clone the 0G chain repository
git clone -b v0.2.3 https://github.com/0glabs/0g-chain.git
cd 0g-chain
make install
echo 'export PATH=$PATH:$(go env GOPATH)/bin' >> ~/.profile
source ~/.profile
0gchaind version

# Ask user for node name
read -p "Enter your node name: " MONIKER
echo "export MONIKER=\"$MONIKER\"" >> ~/.bash_profile
echo 'export CHAIN_ID="zgtendermint_16600-2"' >> ~/.bash_profile
echo 'export WALLET_NAME="wallet"' >> ~/.bash_profile
echo 'export RPC_PORT="26657"' >> ~/.bash_profile
source $HOME/.bash_profile

# Configure the node
cd $HOME
0gchaind config chain-id $CHAIN_ID
0gchaind config node tcp://localhost:$RPC_PORT
0gchaind config keyring-backend file
0gchaind init $MONIKER --chain-id $CHAIN_ID

# Download and replace genesis file
rm ~/.0gchain/config/genesis.json
wget -P ~/.0gchain/config https://github.com/0glabs/0g-chain/releases/download/v0.2.3/genesis.json
SEEDS="81987895a11f6689ada254c6b57932ab7ed909b6@54.241.167.190:26656,010fb4de28667725a4fef26cdc7f9452cc34b16d@54.176.175.48:26656,e9b4bc203197b62cc7e6a80a64742e752f4210d5@54.193.250.204:26656,68b9145889e7576b652ca68d985826abd46ad660@18.166.164.232:26656"
sed -i -e "s/^seeds *=.*/seeds = \"$SEEDS\"/" $HOME/.0gchain/config/config.toml
PEERS="6122859577a3465ba67065f3b63194cae67ef4c4@110.171.123.186:36656"
sed -i "s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" "$HOME/.0gchain/config/config.toml"

# Set environment variables
EXTERNAL_IP=$(wget -qO- eth0.me)
PROXY_APP_PORT=26658
P2P_PORT=26656
PPROF_PORT=6060
API_PORT=1317
GRPC_PORT=9090
GRPC_WEB_PORT=9091

# Update config.toml with ports and external IP
sed -i \
    -e "s/\(proxy_app = \"tcp:\/\/\)\([^:]*\):\([0-9]*\).*/\1\2:$PROXY_APP_PORT\"/" \
    -e "s/\(laddr = \"tcp:\/\/\)\([^:]*\):\([0-9]*\).*/\1\2:$RPC_PORT\"/" \
    -e "s/\(pprof_laddr = \"\)\([^:]*\):\([0-9]*\).*/\1localhost:$PPROF_PORT\"/" \
    -e "/\[p2p\]/,/^\[/{s/\(laddr = \"tcp:\/\/\)\([^:]*\):\([0-9]*\).*/\1\2:$P2P_PORT\"/}" \
    -e "/\[p2p\]/,/^\[/{s/\(external_address = \"\)\([^:]*\):\([0-9]*\).*/\1${EXTERNAL_IP}:$P2P_PORT\"/; t; s/\(external_address = \"\).*/\1${EXTERNAL_IP}:$P2P_PORT\"/}" \
    $HOME/.0gchain/config/config.toml

# Update app.toml with ports
sed -i \
    -e "/\[api\]/,/^\[/{s/\(address = \"tcp:\/\/\)\([^:]*\):\([0-9]*\)\(\".*\)/\1\2:$API_PORT\4/}" \
    -e "/\[grpc\]/,/^\[/{s/\(address = \"\)\([^:]*\):\([0-9]*\)\(\".*\)/\1\2:$GRPC_PORT\4/}" \
    -e "/\[grpc-web\]/,/^\[/{s/\(address = \"\)\([^:]*\):\([0-9]*\)\(\".*\)/\1\2:$GRPC_WEB_PORT\4/}" $HOME/.0gchain/config/app.toml

# Set pruning options
sed -i.bak -e "s/^pruning *=.*/pruning = \"custom\"/" $HOME/.0gchain/config/app.toml
sed -i.bak -e "s/^pruning-keep-recent *=.*/pruning-keep-recent = \"100\"/" $HOME/.0gchain/config/app.toml
sed -i.bak -e "s/^pruning-interval *=.*/pruning-interval = \"10\"/" $HOME/.0gchain/config/app.toml

# Set gas price
sed -i "s/^minimum-gas-prices *=.*/minimum-gas-prices = \"0ua0gi\"/" $HOME/.0gchain/config/app.toml

# Set indexer
sed -i "s/^indexer *=.*/indexer = \"kv\"/" $HOME/.0gchain/config/config.toml

# Set json-rpc options
sed -i \
    -e 's/address = "127.0.0.1:8545"/address = "0.0.0.0:8545"/' \
    -e 's|^api = ".*"|api = "eth,txpool,personal,net,debug,web3"|' \
    $HOME/.0gchain/config/app.toml

# Create and start the service
sudo tee /etc/systemd/system/0gd.service > /dev/null <<EOF
[Unit]
Description=OG Node
After=network.target

[Service]
User=$USER
Type=simple
ExecStart=$(which 0gchaind) start --json-rpc.api eth,txpool,personal,net,debug,web3 --home $HOME/.0gchain
Restart=on-failure
RestartSec=10
LimitNOFILE=65535
Environment="GOGC=900"
Environment="GOMEMLIMIT=40GB"

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start the service
sudo systemctl daemon-reload
sudo systemctl enable 0gd
sudo systemctl restart 0gd
sudo journalctl -u 0gd -f -o cat
