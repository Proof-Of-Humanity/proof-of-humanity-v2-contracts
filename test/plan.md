
Initialization

Claim

Vouching

Challenging

Renewing

Rewards



context("Challenging", function () {
beforeEach("Setup", async function () {
context("Claim request", function () {
it("should not allow challenging with reason none", async function () {
it("should not allow challenging if challenger has not paid cost", async function () {
context("Requester won", function () {
it("Should reset the request after requester won a challenge", async function () {
it("Should grant ownership after claim request passed with no challenges", async function () {
it("Should grant ownership after claim request passed but was challenged once", async function () {
it("Should grant ownership after claim requester won challenges for all reasons", async function () {
context("Challenger won", function () {
it("Should not allow executing request or challenging again if claim request lost challenge", async function () {
it("Should not grant ownership if requester lost challenge", async function () {
context("Revocation request", function () {
beforeEach("Setup", async function () {
it("should not allow challenging with reason", async function () {
context("Requester won", function () {
it("Should revoke soul after revocation request passed with no challenges", async function () {
context("Challenger won", function () {
it("Should not revoke soul after revocation request was challenged and challenger won", async function () {
context("Arbitrator rules", function () {});
context("Arbitrator refuses to rule", function () {});
context("Appeals", function () {});
context("Winner paid appeal, loser not", function () {});
context("Loser paid appeal, winner not", function () {});




context("Vouching", function () {
context("Changing state to pending", function () {
beforeEach("Setup", async function () {
context("Vanilla vouches", function () {
it("Should add vouch", async function () {
it("Should remove vouch", async function () {
it("Should revert when there are less vouches than required", async function () {
it("Should set correct values when there are exactly the number of vouches required", async function () {
it("Should set correct values when there are more vouches than necessary", async function () {
context("Invalid vouches", function () {
it("Should not allow human with no soul", async function () {
it("Should not allow human without soul and that is in vouching state for a valid soul", async function () {
it("Should not allow human with expired soul", async function () {
it("Should not allow human that is already vouching", async function () {
context("Signature vouches", function () {
it("Should revert when there are less vouches than required", async function () {
it("Should set correct values when there are exactly the number of vouches required", async function () {
it("Should set correct values when there are more vouches than necessary", async function () {
context("Invalid vouches", function () {
it("Should not allow human with no soul", async function () {
it("Should not allow human without soul and that is in vouching state for a valid soul", async function () {
it("Should not allow human with expired soul", async function () {
it("Should not allow human that is already vouching", async function () {
it("Should not allow expired vouch", async function () {
context("Mixed vouches", function () {
it("Should allow both vanilla and signature vouches", async function () {
it("Should not allow duplicated", async function () {
context("Processing vouches", function () {
beforeEach("Setup", async function () {
it("Should set parameters correctly for good vouchers", async function () {
it("Should penalize vouchers of request challenged for DoesNotExist", async function () {
it("Should not penalize vouchers of request challenged for IncorrectSubmission", async function () {
it("Should not allow bad voucher to win pending claim request", async function () {
