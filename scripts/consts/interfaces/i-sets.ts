export interface AddressSet {
    POH: string;
    POH_Implementation: string;
    CROSS_CHAIN: string;
    CC_Implementation: string;
    GATEWAY: string;
    LEGACY: string;
    FORK_MODULE: string;
    PROXY_TOKEN: string;
}

export interface AddressSetFixed {
    MESSENGER: string;
    ARBITRATOR: string;
    W_NATIVE: string;
}

export interface InitSpecificParamSet {
    ARBITRATOR_EXTRA_DATA_MAINNET: string,
    ARBITRATOR_EXTRA_DATA_SIDECHAIN: string,
    REQUEST_BASE_DEPOSIT_MAINNET: bigint,
    REQUEST_BASE_DEPOSIT_SIDECHAIN: bigint,
}

export interface InitGeneralParamSet {
    HUMANITY_LIFESPAN: number,
    RENEWAL_DURATION: number,
    CHALLENGE_DURATION: number,
    FAILED_REV_COOL_DOWN: number,
    SHARED_MULTIPLIER: number,
    WINNER_MULTIPLIER: number,
    LOSER_MULTIPLIER: number,
    NB_VOUCHES: number,
    TRANSFER_COOLDOWN: number,
}
