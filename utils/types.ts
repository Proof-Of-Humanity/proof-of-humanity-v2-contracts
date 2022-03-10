import { BigNumberish } from "ethers";
import { Party } from "./enums";

export interface RoundInfo {
  appealed?: boolean;
  paidFeesForNone?: BigNumberish;
  paidFeesForRequester?: BigNumberish;
  paidFeesForChallenger?: BigNumberish;
  sideFunded?: Party;
  feeRewards?: BigNumberish;
}
