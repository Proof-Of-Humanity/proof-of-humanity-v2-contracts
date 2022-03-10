import { expect } from "chai";
import { Contract, ContractReceipt } from "ethers";
import { ethers } from "hardhat";

export const expectRevert = async (promise: Promise<any>, expectedError: string) => {
  try {
    await promise;
    expect.fail("Expected an exception but none was received");
  } catch (err: any) {
    if (err.message.indexOf(expectedError) !== -1) return;
    const actualError = err.message.replace(
      /Returned error: VM Exception while processing transaction: (revert )?/,
      ""
    );
    expect(actualError).to.equal(expectedError, "Wrong kind of exception received");
  }
};

export const expectEvent = (tx: ContractReceipt, idx: number) => ({
  named: (eventName: string) => ({
    with(argsToCheck: Record<string, any>) {
      if (!Array.isArray(tx.events) || tx.events[idx].event !== eventName)
        return expect.fail(`The event '${eventName}' has not been created`);
      for (const arg in argsToCheck) {
        expect(tx.events[idx].args![arg], `The event '${eventName}' has wrong '${arg}'`).to.equal(argsToCheck[arg]);
      }
    },
  }),
});

export const getCurrentTimestamp = async () =>
  (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp;

export const increaseTime = async (amount: number) =>
  await ethers.provider.send("evm_mine", [(await getCurrentTimestamp()) + amount]);
// await ethers.provider.send("evm_increaseTime", [amount]);

export const checkContract =
  <C extends Contract, F extends keyof C["callStatic"]>(contract: C, method: F) =>
  (...args: Parameters<C[F]>) => ({
    async for(argsToCheck: Partial<Awaited<ReturnType<C[F]>>>) {
      const entity = await contract[method](...args);
      for (const arg in argsToCheck) {
        expect(entity[arg], `Calling '${method}' returned incorrect '${arg}' parameter`).to.equal(argsToCheck[arg]);
      }
    },
  });
