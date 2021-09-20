const Web3Utils = require('web3-utils');
const { accounts, contract, privateKeys } = require('@openzeppelin/test-environment');
const {
    time,
    constants,    // Common constants, like the zero address and largest integers
    expectEvent,  // Assertions for emitted events
    expectRevert, // Assertions for transactions that should fail
} = require('@openzeppelin/test-helpers');

const { assert, expect } = require('chai');
const { ZERO_ADDRESS } = constants;

// signatures
const { fromRpcSig } = require('ethereumjs-util');
const ethSigUtil = require('eth-sig-util');
const abi = require('ethereumjs-abi')

let gasUsage = [];
function logGas(event, name) {
    let gas = event.receipt.gasUsed
    gasUsage.push({ name: name, value: gas });
}

const UniqlyMarket = require.fromArtifact("UniqlyMarket");
const simpleNFT = require.fromArtifact("simpleNft");
const simpleErc20 = require.fromArtifact("simpleErc20");

describe("Market sigtest", function () {

    let market, nftToken1, payToken1;

    let [owner, publisher, user1, user2, user3] = accounts;
    let [ownerPriv, publisherPriv] = privateKeys;

    let startTime = Number();
    let day = Number(time.duration.days(1));
    let days2 = day * 2;
    let second = Number(time.duration.seconds(1));
    let week = Number(time.duration.days(7));
    let weeks2 = week * 2;
    let weeks4 = week * 4;
    let month = 30 * day;
    let months2 = 2 * month;

    before(async function () {
        market = await UniqlyMarket.new(weeks4, 60 * 15, { from: owner });

        payToken1 = await simpleErc20.new({ from: publisher })
        nftToken1 = await simpleNFT.new({ from: publisher })

        // mint and send tokens
        await nftToken1.mint("1", user1, "0"); // user1, 1 token, no royalties
        await payToken1.transfer(user2, "1000000", { from: publisher });

        // allow payment methods
        // function addPaymentToken(address token, uint256 marketFee)
        await market.addPaymentToken(payToken1.address, "5000", { from: owner }) // this have no fees
        // allow NTF tokens
        await market.addNftToken(nftToken1.address, { from: owner })

        startTime = Number(await time.latest())
    })

    describe('Sell and get fee', function () {

        it('do market sell', async function () {
            await nftToken1.setOperator(market.address, { from: user1 });
            await market.sell( nftToken1.address, payToken1.address, 0, 500, 1000, 1, startTime + week, {from:user1});
        })

        //function withdrawFee(address token,uint256 amount,bytes32 r,bytes32 s,uint8 v)
        //abi.encodePacked(msg.sender, token, amount, address(this))
        it('allows to withraw by signature', async function () {
            let feeCollected = await market.getFeeCollected(payToken1.address);
            let its10percent = new BN(feeCollected).div(new BN('10'));
            data = "0x" + abi.soliditySHA3(
                ["address", "address", "uint256", "address"],
                [user3, payToken1.address, its10percent, market.address]
            ).toString("hex");
            const signature = ethSigUtil.personalSign(ownerPriv, { data: data });
            const { v, r, s } = fromRpcSig(signature);
            ret = await market.withdrawFee(payToken1.address, its10percent, r, s, v, { from: user3 })
            logGas(ret, "market.withdrawFee");
            expect(await payToken1.balanceOf(user3)).to.eql(its10percent, "Not received?");
        })
    })

})