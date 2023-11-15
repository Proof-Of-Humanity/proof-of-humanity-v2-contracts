# Cross-chain Proof-of-Humanity

Smart contracts for the cross-chain version of Proof-of-Humanity

![image](https://user-images.githubusercontent.com/47434163/161445069-c6207d96-0477-47bb-b374-36828a7c150f.png)

### Install dependencies
```shell
yarn
```

### Deployment
Scripts to help with deployment are in `scripts/deploy` folder. You can run corresponding commands to deploy different contracts:
- `deploy-poh`: deploy ProofOfHumanity
- `deploy-extended`: deploy ProofOfHumanityExtended
- `deploy-ccpoh`: deploy CrossChainProofOfHumanity
- `deploy-gateway`: deploy cross-chain gateway
- `deploy-pohlegacy`: deploy legacy version of ProofOfHumanity (v1)

Note that variables are hardcoded in each script file and contract addresses (which are going to be used to connect contracts interacting with each other) are to be added in `scripts/consts.ts` file.

### Test contracts (will also compile them)
```shell
npx hardhat test
```

### Compile contracts
```shell
npx hardhat compile
```

Other hardhat commands can be searched in the hardhat documentation.

### Deploying contracts
