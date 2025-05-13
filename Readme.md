# Readme
## Introduction

this is the blockchain network for my thesis application designed and inspired by Hyperledger Fabric [test-network](https://github.com/hyperledger/fabric-samples/tree/main/test-network)

> [!CAUTION]
> pleas check the [requirement](https://hyperledger-fabric.readthedocs.io/en/latest/prereqs.html) before setting up the network

* * *

## Network design:

<figure class="image"><img style="aspect-ratio:1334/483;" src="thesis network.svg" width="1334" height="483"></figure>

*   The Network consists of three organisations, each has two peers
    1.  Client Organisation
    2.  Law firm Organisation
    3.  Retail Organisation
*   One ordering service that uses RAFT but without BFT
*   Two channels:
    1.  LawfirmClientChannel: connects the Law firm Organisation with the Client Organisation
    2.  RetailClientChannel: connects the Retail Organisation with the Client Organisation
*   The chaincode will be deployed as a service, one chaincode per channel

* * *

## Setting up the network

1.  Clone the repository
    
    ```sh
    git clone https://github.com/rami-shalhoub/Thesis-Blockchain-network.git
    ```
2.  download the fabric components
    1.  change your directory to the repository directory and download the installation script
        
        ```sh
        curl -sSLO https://raw.githubusercontent.com/hyperledger/fabric/main/scripts/install-fabric.sh && chmod +x install-fabric.sh
        ```
    2.  install the necessary docker files and binaries
        
        ```sh
        ./install-fabric.sh --fabric-version 2.5.11 binary docker
        ```

> [!TIP]
> refer to the installation [documentation](https://hyperledger-fabric.readthedocs.io/en/latest/install.html) in case of any problem

3.  export the binary files to the PATH environment variable
    
    ```sh
    echo export PATH=path/to/repo/Thesis-Blockchain-network/bin:$PATH >> ~/.zshrc #~/.bashrc
    ```
4.  now you can start the network
    
    ```sh
    ./network.sh up
    ```

> [!TIP]
> you can print the help message
> 
> ```sh
> ./network.sh
> ```