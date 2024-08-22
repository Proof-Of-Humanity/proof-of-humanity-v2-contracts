export interface AddressSet {
    POH: string;
    POH_Implementation: string;
    CROSS_CHAIN: string;
    CC_Implementation: string;
    GATEWAY: string;
}

export interface AddressSetFixed {
    LEGACY: string;
    MESSENGER: string;
    ARBITRATOR: string;
    W_NATIVE: string;
}

export interface InitParamSet {
    ARBITRATOR_EXTRA_DATA: string,
    REQUEST_BASE_DEPOSIT_MAINNET: bigint,
    REQUEST_BASE_DEPOSIT_SIDECHAIN: bigint,
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
