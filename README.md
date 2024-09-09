# Cross-chain Proof-of-Humanity

Smart contracts for the cross-chain version of Proof-of-Humanity

![image](https://user-images.githubusercontent.com/47434163/161445069-c6207d96-0477-47bb-b374-36828a7c150f.png)

### Install dependencies
```shell
yarn
```

### Deployment
Scripts to help with deployment are in `scripts/deploy` folder. You can run corresponding commands to deploy different contracts:
- `deploy-poh`: deploy ProofOfHumanity (on sidechain)
- `deploy-extended`: deploy ProofOfHumanityExtended (on mainnet for integration of v1 profiles)
- `deploy-ccpoh`: deploy CrossChainProofOfHumanity
- `deploy-gateway`: deploy cross-chain gateway
- `deploy-pohlegacy`: deploy legacy version of ProofOfHumanity (v1) (testnets only)

Note that variables are hardcoded in each script file and contract addresses (which are going to be used to connect contracts interacting with each other) are to be added in `scripts/consts/addresses/addresses-mainnets.ts` file.

### Compile contracts
```shell
yarn compile
```

Other hardhat commands can be searched in the hardhat documentation.


# Deployed contracts on mainnets (Ethereum and Gnosis) and guidance
### - ETHEREUM:

Running script `deploy-extended mainnet`, the main PoH contracts (proxy and implementation) are deployed on Ethereum mainnet. 
- POH (`ProofOfHumanityExtended.sol`): 0xbE9834097A4E97689d9B667441acafb456D0480A
- POH_Implementation: 0x9EcDfADA6376D221Ed1513c9F52cC44a39E89657

Running script `deploy-ccpoh mainnet`, the cross chain contracts (proxy and implementation) are deployed on Ethereum mainnet. 
- CROSS_CHAIN (`CrossChainProofOfHumanity.sol`): 0xa478095886659168E8812154fB0DE39F103E74b2
- CC_Implementation: 0x7BBf4551E1324CE7F87050377aE3EF645F08DBfd

Running script `deploy-gateway mainnet` will deploy the gateway on Ethereum mainnet necessary for interaction with the AMB Bridge.
- GATEWAY (`AMBBridgeGateway.sol`): 0xddafACf8B4a5087Fc89950FF7155c76145376c1e

The ForkModule allows to mark v1 profiles without affecting PoHv1. Should be deployed automatically. If it is needed (under failure when deploying POH), it can be deployed manually by running script `deploy-fork-manually mainnet`.
- FORK_MODULE (`ForkModule.sol`): 0x068a27Db9c3B8595D03be263d52c813cb2C99cCB

Others (no need to deploy manually):
- LEGACY: 0xC5E9dDebb09Cd64DfaCab4011A0D5cEDaf7c9BDb (ProofOfHumanity v1)
- PROXY_ADMIN: 0x546bd92b3cDbf2000746a513B96659c926445c50
- PROXY_ADMIN_CC: 0x91b3Cb9e5A276ede97C3EE6088d5956DD01BcaA2

### - GNOSIS:

Running script `deploy-poh gnosis`, the main PoH contracts (proxy and implementation) are deployed on Gnosis. 
- POH(`ProofOfHumanity.sol`): 0xa4AC94C4fa65Bb352eFa30e3408e64F72aC857bc
- POH_Implementation: 0x85B88E38FB6cbc8059009902F76C47f902373F52

Running script `deploy-ccpoh gnosis`, the cross chain contracts (proxy and implementation) are deployed on Gnosis. 
- CROSS_CHAIN (`CrossChainProofOfHumanity.sol`): 0x16044E1063C08670f8653055A786b7CC2034d2b0
- CC_Implementation: 0x20C27AB7863dC31CEaBd300Fa2787B723D490162

Running script `deploy-gateway gnosis` will deploy the gateway on Gnosis, necessary for interaction with the AMB Bridge deployed on Gnosis.
- GATEWAY (`AMBBridgeGateway.sol`): 0x6Ef5073d79c42531352d1bF5F584a7CBd270c6B1

Others (no need to deploy manually):
- PROXY_ADMIN: 0xdEF33793a7924f876b20BE435Da5C234CE60a437
- PROXY_ADMIN_CC: 0x35eC1E9abb85365520CA0F099859064CE1678094

For deploying, a correct order should be interpolating deployments between mainnet and gnosis, for instance: deploy Extended PoH on mainnet, PoH on gnosis, CCPoH on mainnet, CCPoH on gnosis, Gateway on mainnet, and Gateway on gnosis. After each script, it is required to progressively fill the corresponding addresses on `scripts/consts/addresses/addresses-mainnets.ts`. The last gateway's deployment should set the needed foreign gateway address, otherwise, it should be set manually.
