# Proof-of-Humanity v2 - Contracts

### Main Contracts on Ethereum Mainnet and side chains (Gnosis)
- `ProofOfHumanity`: Main v2 contract deployed only on sidechains, gnosis in first time.
- `ProofOfHumanityExtended`: Main v2 contract deployed on ethereum mainnet only. It is similar to the `ProofOfHumanity` deployed on sidechains with the additional capability of integrating v1 profiles.


### Contracts on both Ethereum Mainnet and side chains (Gnosis)
- `CrossChainProofOfHumanity`: Crosschain capabilities for the main contracts.
- `AMBBridgeGateway`: Connects to the corresponding Arbitrary Message Bridge in this chain, to the CrossChainProofOfHumanity Proxy and to the foreign gateway contract (deployed on the side chain).
- `IBridgeGateway`: The gateway's interface.


### Other contracts on Ethereum Mainnet only
- `ForkModule`: Capable of marking v1 profiles (for removal, for instance) in order to modify their status without modifying the corresponding status on the v1 contract. In this manner, each side of the fork can have different considerations (and consequences) for the same action of a v1 profile.


### Other Contracts
- `ProofOfHumanityOld`: Legacy version of ProofOfHumanity (v1). Used for simulate the v1 contract (deployed on mainnet) on other chains (specially on testnets). Not used for the v2 launched version.


Other contracts in `libraries` and `interfaces` are also relevant for the launched version. 


### Schemma (revisited) of the smart contracts for the cross-chain version of Proof-of-Humanity

![image](https://user-images.githubusercontent.com/47434163/161445069-c6207d96-0477-47bb-b374-36828a7c150f.png)

