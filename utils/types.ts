import { BigNumberish } from "ethers";
import { Party, Reason, Status } from "./enums";

export interface DisputeData {
  challengeID?: BigNumberish;
  submissionID?: string;
}

export interface ArbitratorData {
  arbitrator?: string;
  metaEvidenceUpdates?: BigNumberish;
  arbitratorExtraData?: string;
}

export interface ChallengeInfo {
  lastRoundID?: number;
  challenger?: string;
  disputeID?: BigNumberish;
  ruling?: number;
  duplicateSubmissionChainID?: BigNumberish;
}

export interface RequestInfo {
  disputed?: boolean;
  resolved?: boolean;
  requesterLost?: boolean;
  currentReason?: Reason;
  nbParallelDisputes?: number;
  lastChallengeID?: number;
  arbitratorDataID?: number;
  requester?: string;
  ultimateChallenger?: string;
  usedReasons?: number;
}

export interface SubmissionInfo {
  status?: Status;
  submissionTime?: BigNumberish;
  registered?: boolean;
  hasVouched?: boolean;
  numberOfRequests?: BigNumberish;
}

export interface RoundInfo {
  appealed?: boolean;
  paidFeesForNone?: BigNumberish;
  paidFeesForRequester?: BigNumberish;
  paidFeesForChallenger?: BigNumberish;
  sideFunded?: Party;
  feeRewards?: BigNumberish;
}
