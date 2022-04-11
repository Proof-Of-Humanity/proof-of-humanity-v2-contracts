// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

error POH_WrongStatus();
error POH_OnlyGovernorOrCrossChain();
error POH_NoReapplicationYet();
error POH_NoRemovalAfterRenewal();
error POH_SideMustBeFullyFunded();
error POH_SideAlreadyFunded();
error POH_RequesterNotFunded();
error POH_InvalidVoucherSignature();
error POH_NotEnoughVouches();
error POH_ReasonMustBeSpecified();
error POH_ReasonMustBeEmpty();
error POH_RequestIsDisputed();
error POH_ChallengeTimePassed();
error POH_ReasonAlreadyUsed();
error POH_ChallengeOutOfBounds();
error POH_NoDisputeToAppeal();
error POH_AppealPeriodOver();
error POH_AppealPeriodOverForLoser();
error POH_CantExecuteYet();
error POH_SubmissionMustBeResolved();
error POH_BeneficiaryMustNotBeZero();
error POH_IncorrectDurationsInputs();
error POH_FunctionCallFailed();
