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

### Deployed contracts on mainnets (Ethereum and Gnosis)
###- ETHEREUM:

Running script `deploy-extended mainnet`, the main PoH contracts (proxy and implementation) are deployed on Ethereum mainnet. 
- POH (`ProofOfHumanityExtended.sol`): 0x87c5c294C9d0ACa6b9b2835A99FE0c9A444Aacc1
- POH_Implementation: 0xF921b42B541bc53a07067B65207F879c9377bf7F

Running script `deploy-ccpoh mainnet`, the cross chain contracts (proxy and implementation) are deployed on Ethereum mainnet. 
- CROSS_CHAIN (`CrossChainProofOfHumanity.sol`): 0xD8D462ac9F3FAD77Af2ae2640fE7F591F1651A2C
- CC_Implementation: 0x064B1132D9A9c43Df269FeAD9e80c195Fb9cd916

Running script `deploy-gateway mainnet` will deploy the gateway on Ethereum mainnet necessary for interaction with the AMB Bridge.
- GATEWAY (`AMBBridgeGateway.sol`): 0x290e997D7c46BDFf666Ad38506fcFB3082180DF9

The ForkModule allows to mark v1 profiles without affecting PoHv1. Should be deployed automatically. If it is needed (under failure when deploying POH), it can be deployed manually by running script `deploy-fork-manually mainnet`.
- FORK_MODULE (`ForkModule.sol`): 0x116cB4077afbb9B5c7E0dCd5fc4Ce943Ab624dbF

Others (no need to deploy manually):
- LEGACY: 0xC5E9dDebb09Cd64DfaCab4011A0D5cEDaf7c9BDb (ProofOfHumanity v1)
- PROXY_ADMIN: 0xf57B69f71DD7499Ca30242390E655e8A6a93b51b
- PROXY_ADMIN_CC: 0xec729b0eCf7972236e8926DA4feAAF9BC8F55e65

###- GNOSIS:

Running script `deploy-poh gnosis`, the main PoH contracts (proxy and implementation) are deployed on Gnosis. 
- POH(`ProofOfHumanity.sol`): 0xECd1823b3087acEE3C77928b1959c08d31A8F20e
- POH_Implementation: 0x5efa99c7b0cc04893b2c5551437ff82b19e661c7

Running script `deploy-ccpoh gnosis`, the cross chain contracts (proxy and implementation) are deployed on Gnosis. 
- CROSS_CHAIN (`CrossChainProofOfHumanity.sol`): 0xF921b42B541bc53a07067B65207F879c9377bf7F
- CC_Implementation: 0xc664a8d43601109fc50f3bcf22f29e9119ab2f6d

Running script `deploy-gateway gnosis` will deploy the gateway on Gnosis, necessary for interaction with the AMB Bridge deployed on Gnosis.
- GATEWAY (`AMBBridgeGateway.sol`): 0xD8D462ac9F3FAD77Af2ae2640fE7F591F1651A2C

Others (no need to deploy manually):
- PROXY_ADMIN: 0x60BC555eb5a40b7f934A7345aFA3596Ddd388b2B
- PROXY_ADMIN_CC: 0x36dfBA40eD6DC28f26163548466170b39BE2916D

For deploying, a correct order should be interpolating deployments between mainnet and gnosis, for instance: deploy Extended PoH on mainnet, PoH on gnosis, CCPoH on mainnet, CCPoH on gnosis, Gateway on mainnet, and Gateway on gnosis. After each script, it is required to progressively fill the corresponding addresses on `scripts/consts/addresses/addresses-mainnets.ts`. The last gateway's deployment should set the needed foreign gateway address, otherwise, it should be set manually.
